import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/screens/itemdetailedit.dart';
import 'package:daily_planner/screens/itemdetailpage.dart';
import 'package:daily_planner/screens/taskInsights.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class ItemWidget extends StatefulWidget {
  final Task item;
  final VoidCallback? onEditDone;
  final String searchQuery;

  const ItemWidget({
    super.key,
    required this.item,
    this.onEditDone,
    this.searchQuery = '',
  });

  @override
  State<ItemWidget> createState() => _ItemWidgetState();
}

class _ItemWidgetState extends State<ItemWidget> {
  bool? isChecked;
  List<DateTime> completedList = [];

  @override
  void initState() {
    super.initState();
    isChecked = widget.item.isCompleted;

    loadCompletionStamps(widget.item).then((loadedList) {
      setState(() {
        completedList = loadedList;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final taskType = widget.item.taskType;

      if (taskType != 'oneTime') {
        if (taskType == "DailyTask") {
          await resetDaily(widget.item, completedList);
        } else if (taskType == 'WeeklyTask') {
          await resetWeekly(widget.item, completedList);
        } else if (taskType == 'MonthlyTask') {
          await resetMonthly(widget.item, completedList);
        }
        setState(() {});
      }
    });
  }

  int get notificationId => widget.item.id.hashCode & 0x7FFFFFFF;

  // Helper functions for period comparisons
  bool _isSameDay(DateTime a, DateTime b) {
    final aUtc = DateTime.utc(a.year, a.month, a.day);
    final bUtc = DateTime.utc(b.year, b.month, b.day);
    return aUtc == bUtc;
  }

  int _weekNumber(DateTime d) {
    final startOfYear = DateTime(d.year, 1, 1);
    final dayOfYear = d.toLocal().difference(startOfYear).inDays + 1;
    return ((dayOfYear - d.weekday + 10) / 7).floor();
  }

  bool _isSameWeek(DateTime date1, DateTime date2) {
    date1 = date1.toLocal();
    date2 = date2.toLocal();
    return date1.year == date2.year && _weekNumber(date1) == _weekNumber(date2);
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  Future<void> changeCompleted(bool? newStatus) async {
    final previousStatus = isChecked;

    setState(() {
      isChecked = newStatus;
      widget.item.isCompleted = newStatus!;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("User not logged in");

      final taskRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(widget.item.docId);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final snapshot = await taskRef.get();
      final currentData = snapshot.data();
      List<Timestamp> updatedStamps = [];

      if (currentData != null && currentData['completionStamps'] != null) {
        updatedStamps = (currentData['completionStamps'] as List).map((e) {
          if (e is Timestamp) return e;
          if (e is int) return Timestamp.fromMillisecondsSinceEpoch(e);
          if (e is String) return Timestamp.fromDate(DateTime.parse(e));
          if (e is DateTime) return Timestamp.fromDate(e);
          throw Exception("Invalid completion stamp: $e");
        }).toList();
      }

      Map<String, dynamic> updateData = {'isCompleted': newStatus};

      if (newStatus == true) {
        final ts = Timestamp.fromDate(now);

        // For repeating tasks, only add if no stamp exists in current period
        bool shouldAddStamp = true;
        if (widget.item.taskType != 'oneTime') {
          shouldAddStamp = !updatedStamps.any((stamp) {
            final date = stamp.toDate();
            if (widget.item.taskType == 'DailyTask') {
              return _isSameDay(date, now);
            } else if (widget.item.taskType == 'WeeklyTask') {
              return _isSameWeek(date, now);
            } else if (widget.item.taskType == 'MonthlyTask') {
              return _isSameMonth(date, now);
            }
            return false;
          });
        }

        if (shouldAddStamp) {
          updatedStamps.add(ts);
          updateData['completedAt'] = ts;
          updateData['completionStamps'] = updatedStamps;
        }

        await NativeAlarmHelper.cancelAlarmById(notificationId);
      } else {
        // Remove ALL stamps in current period
        updatedStamps = updatedStamps.where((stamp) {
          final date = stamp.toDate();

          if (widget.item.taskType == 'oneTime') {
            return false; // Remove all for one-time tasks
          } else if (widget.item.taskType == 'DailyTask') {
            return !_isSameDay(date, now);
          } else if (widget.item.taskType == 'WeeklyTask') {
            return !_isSameWeek(date, now);
          } else if (widget.item.taskType == 'MonthlyTask') {
            return !_isSameMonth(date, now);
          }
          return true;
        }).toList();

        updateData['completedAt'] = null;
        updateData['completionStamps'] = updatedStamps;

        if (widget.item.date.isAfter(DateTime.now())) {
          await NativeAlarmHelper.scheduleAlarmAtTime(
            id: notificationId,
            title: widget.item.title,
            body: widget.item.detail,
            dateTime: widget.item.date,
          );
        }
      }

      // Update Firestore
      await taskRef.update(updateData);

      // Update local object
      if (widget.item is DailyTask) {
        (widget.item as DailyTask).completionStamps
          ..clear()
          ..addAll(updatedStamps.map((ts) => ts.toDate()));
      } else if (widget.item is WeeklyTask) {
        (widget.item as WeeklyTask).completionStamps
          ..clear()
          ..addAll(updatedStamps.map((ts) => ts.toDate()));
      } else if (widget.item is MonthlyTask) {
        (widget.item as MonthlyTask).completionStamps
          ..clear()
          ..addAll(updatedStamps.map((ts) => ts.toDate()));
      }

      // Update local state
      setState(() {
        completedList = updatedStamps.map((ts) => ts.toDate()).toList();
      });

      widget.item.completedAt = newStatus == true ? now : null;
      widget.onEditDone?.call();
    } catch (e) {
      setState(() {
        isChecked = previousStatus;
        widget.item.isCompleted = previousStatus!;
      });
      _showSnackbar("❌ Failed to update task: ${e.toString()}");
    }
  }

  int generateNotificationId(String taskId, DateTime time) {
    return (taskId + time.toIso8601String()).hashCode.abs();
  }

  Future<void> deleteTask(Task task) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || task.docId == null) {
      _showSnackbar("❌ Cannot delete: Missing user or task ID.");
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Deletion"),
        content: const Text("Are you sure you want to delete this task?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Cancel all notifications - FIXED: Use docId instead of task.id
      if (task.notificationTimes != null && task.notificationTimes!.isNotEmpty) {
        for (final time in task.notificationTimes!) {
          final id = generateNotificationId(task.docId!, time);
          await NativeAlarmHelper.cancelAlarmById(id);
        }
      } else {
        // Use docId for fallback ID generation
        final fallbackId = generateNotificationId(task.docId!, task.date);
        await NativeAlarmHelper.cancelAlarmById(fallbackId);
      }

      // Delete from Firestore :cite[1]:cite[3]
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(task.docId)
          .delete();

      if (mounted) Navigator.of(context).pop();
      _showSnackbar("🗑️ Task deleted successfully");
      widget.onEditDone?.call();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showSnackbar("❌ Failed to delete task: ${e.toString()}");
      debugPrint("Error deleting task: $e");
    }
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  TextSpan _highlightSearchText(String text, String query) {
    final defaultStyle = DefaultTextStyle.of(context).style;

    if (query.isEmpty) return TextSpan(text: text, style: defaultStyle);

    final matches = RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).allMatches(text);
    if (matches.isEmpty) return TextSpan(text: text, style: defaultStyle);

    final List<TextSpan> spans = [];
    int lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: defaultStyle,
          ),
        );
      }

      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: defaultStyle.copyWith(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(
        TextSpan(text: text.substring(lastMatchEnd), style: defaultStyle),
      );
    }

    return TextSpan(children: spans);
  }

  Future<List<DateTime>> loadCompletionStamps(Task task) async {
    List<DateTime> completedList = [];

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return completedList;

      final taskRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(task.docId);

      final snapshot = await taskRef.get();
      if (!snapshot.exists) return completedList;

      final data = snapshot.data();
      if (data != null && data['completionStamps'] != null) {
        final List<dynamic> stamps = data['completionStamps'];
        completedList =
            stamps.whereType<Timestamp>().map((ts) => ts.toDate()).toList();
      }
    } catch (e) {
      debugPrint("❌ Error loading completion stamps: $e");
    }

    return completedList;
  }

  Future<void> resetDaily(Task task, List<DateTime> timestamps) async {
    if (!task.isCompleted) return;

    final nowUtc = DateTime.now().toUtc();
    final todayUtc = DateTime(nowUtc.year, nowUtc.month, nowUtc.day);

    final hasCompletedToday = timestamps.any((timestamp) {
      final tsUtc = timestamp.toUtc();
      return _isSameDay(tsUtc, todayUtc);
    });

    if (!hasCompletedToday) {
      task.isCompleted = false;
    }
  }

  Future<void> resetWeekly(Task task, List<DateTime> timestamps) async {
    if (!task.isCompleted) return;

    final nowUtc = DateTime.now().toUtc();

    final hasCompletedThisWeek = timestamps.any((timestamp) {
      final tsUtc = timestamp.toUtc();
      return _isSameWeek(tsUtc, nowUtc);
    });

    if (!hasCompletedThisWeek) {
      task.isCompleted = false;
    }
  }

  Future<void> resetMonthly(Task task, List<DateTime> timestamps) async {
    if (!task.isCompleted) return;

    final nowUtc = DateTime.now().toUtc();

    final hasCompletedThisMonth = timestamps.any((timestamp) {
      final tsUtc = timestamp.toUtc();
      return _isSameMonth(tsUtc, nowUtc);
    });

    if (!hasCompletedThisMonth) {
      task.isCompleted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.item;
    final isOverdue = task.date.isBefore(DateTime.now()) && !task.isCompleted;
    final textColor = isOverdue ? Colors.red : null;

    return Card(
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ItemDetailPage(task: task)),
          );
        },
        leading: IconButton(
          icon: Icon(
            (isChecked ?? false)
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: (isChecked ?? false) ? Colors.green : Colors.grey,
          ),
          onPressed: () => changeCompleted(!(isChecked ?? false)),
        ),

        title: RichText(
          text: _highlightSearchText(task.title, widget.searchQuery),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat.yMd().add_jm().format(task.date),
              style: TextStyle(color: textColor),
            ),
            if (buildExtraInfo(task) != null) buildExtraInfo(task)!,
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditTaskPage(task: task),
                ),
              ).then((_) => widget.onEditDone?.call());
            } else if (value == 'delete') {
              deleteTask(task);
            } else if (value == 'share') {
              Share.share("${task.title}\n\n${task.detail}");
            } else if (value == 'details') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ItemDetailPage(task: task),
                ),
              );
            } else if (value == 'Analytics') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AnalyticsPage(task: task)),
              );
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('✏️ Edit')),
            const PopupMenuItem(value: 'delete', child: Text('🗑️ Delete')),
            const PopupMenuItem(value: 'share', child: Text('📤 Share')),
            const PopupMenuItem(
              value: 'Analytics',
              child: Text(" Analytics"),
            ),
            const PopupMenuItem(
              value: 'details',
              child: Text('📄 Details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget? buildExtraInfo(Task task) {
    if (task is DailyTask) {
      return Text("Repeats every ${task.intervalDays} day(s)");
    } else if (task is WeeklyTask) {
      return Text("Repeats weekly");
    } else if (task is MonthlyTask) {
      return Text("Repeats monthly");
    }
    return null;
  }
}
