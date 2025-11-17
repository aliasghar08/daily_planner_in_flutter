import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/screens/itemdetailedit.dart';
import 'package:daily_planner/screens/itemdetailpage.dart';
import 'package:daily_planner/screens/taskInsights.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:daily_planner/utils/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class ItemWidget extends StatefulWidget {
  final Task item;
  final VoidCallback? onEditDone;
  final String searchQuery;
  final VoidCallback? onTaskStatusChanged; // NEW: Callback for status changes

  const ItemWidget({
    super.key,
    required this.item,
    this.onEditDone,
    this.searchQuery = '',
    this.onTaskStatusChanged, // NEW: Added callback parameter
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
    _initializeTask();
  }

  @override
  void didUpdateWidget(ItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh when the task data changes from parent
    if (oldWidget.item.docId != widget.item.docId ||
        oldWidget.item.isCompleted != widget.item.isCompleted) {
      _initializeTask();
    }
  }

  void _initializeTask() {
    try {
      print('Initializing task: ${widget.item.title}');
      print('Task type: ${widget.item.taskType}');
      print('Task date: ${widget.item.date}');
      print('Task docId: ${widget.item.docId}');
      print('Task isCompleted: ${widget.item.isCompleted}');

      isChecked = widget.item.isCompleted ?? false;

      loadCompletionStamps(widget.item).then((loadedList) {
        if (mounted) {
          setState(() {
            completedList = loadedList;
          });
        }
      });
    } catch (e) {
      print('Error initializing task: $e');
      isChecked = false;
      completedList = [];
    }
  }

  int get notificationId {
    if (widget.item.docId == null) {
      return widget.item.title.hashCode & 0x7FFFFFFF;
    }
    return widget.item.docId!.hashCode & 0x7FFFFFFF;
  }

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
      isChecked = newStatus ?? false;
      widget.item.isCompleted = newStatus ?? false;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("User not logged in");
      if (widget.item.docId == null) throw Exception("Task has no document ID");

      final taskRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(widget.item.docId);

      final now = DateTime.now();

      final snapshot = await taskRef.get();
      final currentData = snapshot.data();
      List<Timestamp> updatedStamps = [];

      if (currentData != null && currentData['completionStamps'] != null) {
        updatedStamps =
            (currentData['completionStamps'] as List).map((e) {
              if (e is Timestamp) return e;
              if (e is int) return Timestamp.fromMillisecondsSinceEpoch(e);
              if (e is String) return Timestamp.fromDate(DateTime.parse(e));
              if (e is DateTime) return Timestamp.fromDate(e);
              return Timestamp.now();
            }).toList();
      }

      Map<String, dynamic> updateData = {'isCompleted': newStatus};

      if (newStatus == true) {
        final ts = Timestamp.fromDate(now);

        bool shouldAddStamp = true;
        final taskType = widget.item.taskType?.toLowerCase();
        if (taskType != 'onetime') {
          shouldAddStamp =
              !updatedStamps.any((stamp) {
                final date = stamp.toDate();
                if (taskType == 'dailytask') {
                  return _isSameDay(date, now);
                } else if (taskType == 'weeklytask') {
                  return _isSameWeek(date, now);
                } else if (taskType == 'monthlytask') {
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
        final taskType = widget.item.taskType?.toLowerCase();
        updatedStamps =
            updatedStamps.where((stamp) {
              final date = stamp.toDate();

              if (taskType == 'onetime') {
                return false;
              } else if (taskType == 'dailytask') {
                return !_isSameDay(date, now);
              } else if (taskType == 'weeklytask') {
                return !_isSameWeek(date, now);
              } else if (taskType == 'monthlytask') {
                return !_isSameMonth(date, now);
              }
              return true;
            }).toList();

        updateData['completedAt'] = null;
        updateData['completionStamps'] = updatedStamps;

        if (widget.item.date != null) {
          if (widget.item.date!.isAfter(DateTime.now())) {
            await NativeAlarmHelper.scheduleAlarmAtTime(
              id: notificationId,
              title: widget.item.title,
              body: widget.item.detail,
              dateTime: widget.item.date!,
            );
          }
        }
      }

      // Update Firestore
      await taskRef.update(updateData);

      // Update local object
      final updatedDates = updatedStamps.map((ts) => ts.toDate()).toList();
      if (widget.item is DailyTask) {
        (widget.item as DailyTask).completionStamps
          ..clear()
          ..addAll(updatedDates);
      } else if (widget.item is WeeklyTask) {
        (widget.item as WeeklyTask).completionStamps
          ..clear()
          ..addAll(updatedDates);
      } else if (widget.item is MonthlyTask) {
        (widget.item as MonthlyTask).completionStamps
          ..clear()
          ..addAll(updatedDates);
      }

      // Update local state
      if (mounted) {
        setState(() {
          completedList = updatedDates;
        });
      }

      widget.item.completedAt = newStatus == true ? now : null;

      // NEW: Call all refresh callbacks
      widget.onEditDone?.call();
      widget.onTaskStatusChanged
          ?.call(); // NEW: Call the status change callback
    } catch (e) {
      print('Error changing completion status: $e');
      if (mounted) {
        setState(() {
          isChecked = previousStatus;
          widget.item.isCompleted = previousStatus ?? false;
        });
      }
      _showSnackbar("❌ Failed to update task: ${e.toString()}");
    }
  }

  // String generateNotificationId(String taskId, DateTime time) {
  //   return (taskId + time.toIso8601String()).hashCode.abs().toString();
  // }

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
      builder:
          (context) => AlertDialog(
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
      if (task.notificationTimes != null &&
          task.notificationTimes!.isNotEmpty) {
        for (final time in task.notificationTimes!) {
          final id = generateNotificationId(task.docId!, task.date!);
          await NativeAlarmHelper.cancelAlarmById(id);
        }
      } else {
        if (task.date != null) {
          final fallbackId = generateNotificationId(task.docId!, task.date!);
          await NativeAlarmHelper.cancelAlarmById(fallbackId);
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(task.docId)
          .delete();

      if (mounted) Navigator.of(context).pop();
      _showSnackbar("🗑️ Task deleted successfully");

      // NEW: Call all refresh callbacks
      widget.onEditDone?.call();
      widget.onTaskStatusChanged?.call();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showSnackbar("❌ Failed to delete task: ${e.toString()}");
      debugPrint("Error deleting task: $e");
    }
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  TextSpan _highlightSearchText(String text, String query) {
    final defaultStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

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
      if (uid == null || task.docId == null) {
        debugPrint("Missing UID or docId for task: ${task.title}");
        return completedList;
      }

      final taskRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(task.docId);

      final snapshot = await taskRef.get();
      if (!snapshot.exists) {
        debugPrint("Task document doesn't exist: ${task.docId}");
        return completedList;
      }

      final data = snapshot.data();
      if (data != null && data['completionStamps'] != null) {
        final List<dynamic> stamps = data['completionStamps'];
        completedList =
            stamps.map((stamp) {
              if (stamp is Timestamp) return stamp.toDate();
              if (stamp is int)
                return DateTime.fromMillisecondsSinceEpoch(stamp);
              if (stamp is String) return DateTime.parse(stamp);
              if (stamp is DateTime) return stamp;
              return DateTime.now();
            }).toList();

        debugPrint(
          "Loaded ${completedList.length} completion stamps for task: ${task.title}",
        );
      }
    } catch (e) {
      debugPrint(
        "❌ Error loading completion stamps for task ${task.title}: $e",
      );
    }

    return completedList;
  }

  @override
  Widget build(BuildContext context) {
    try {
      final task = widget.item;

      print('Building ItemWidget for: ${task.title}');
      print('Task type: ${task.taskType}');
      print('Date: ${task.date}');
      print('isCompleted: ${task.isCompleted}');

      final isOverdue =
          task.date != null &&
          task.date!.isBefore(DateTime.now()) &&
          !(task.isCompleted ?? false);
      final textColor = isOverdue ? Colors.red : null;

      return Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(task: task),
              ),
            );
          },
          leading: IconButton(
            icon: Icon(
              (isChecked ?? false)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: (isChecked ?? false) ? Colors.green : Colors.grey,
              size: 28,
            ),
            onPressed: () => changeCompleted(!(isChecked ?? false)),
          ),
          title: RichText(
            text: _highlightSearchText(task.title, widget.searchQuery),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (task.date != null)
                Text(
                  DateFormat.yMd().add_jm().format(task.date!),
                  style: TextStyle(color: textColor, fontSize: 12),
                ),
              if (buildExtraInfo(task) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: buildExtraInfo(task)!,
                ),
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
                ).then((_) {
                  // NEW: Refresh after editing
                  widget.onEditDone?.call();
                  widget.onTaskStatusChanged?.call();
                });
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
            itemBuilder:
                (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('✏️ Edit')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('🗑️ Delete'),
                  ),
                  const PopupMenuItem(value: 'share', child: Text('📤 Share')),
                  const PopupMenuItem(
                    value: 'Analytics',
                    child: Text("📈 Analytics"),
                  ),
                  const PopupMenuItem(
                    value: 'details',
                    child: Text('📄 Details'),
                  ),
                ],
          ),
        ),
      );
    } catch (e, stackTrace) {
      print('Error building ItemWidget: $e');
      print('Stack trace: $stackTrace');

      return Card(
        color: Colors.red[100],
        child: ListTile(
          leading: const Icon(Icons.error, color: Colors.red),
          title: Text('Error loading: ${widget.item.title}'),
          subtitle: Text('Type: ${widget.item.taskType}'),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ),
      );
    }
  }

  Widget? buildExtraInfo(Task task) {
    final taskType = task.taskType?.toLowerCase();
    print('buildExtraInfo - taskType: $taskType');

    if (taskType == 'dailytask') {
      return Text(
        "Repeats daily",
        style: TextStyle(
          color: Colors.blue[700],
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );
    } else if (taskType == 'weeklytask') {
      return Text(
        "Repeats weekly",
        style: TextStyle(
          color: Colors.green[700],
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );
    } else if (taskType == 'monthlytask') {
      return Text(
        "Repeats monthly",
        style: TextStyle(
          color: Colors.orange[700],
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );
    } else if (taskType == 'onetime') {
      return null;
    }

    return Text(
      "Task type: $taskType",
      style: const TextStyle(color: Colors.grey, fontSize: 12),
    );
  }
}
