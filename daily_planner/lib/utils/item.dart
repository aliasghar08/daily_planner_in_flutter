import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/providers/task_provider.dart';
import 'package:daily_planner/screens/itemdetailedit.dart';
import 'package:daily_planner/screens/itemdetailpage.dart';
import 'package:daily_planner/screens/taskInsights.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daily_planner/services/custom_state_management.dart';
import 'package:daily_planner/services/native_share_service.dart';

class ItemWidget extends StatefulWidget {
  final Task item;
  final VoidCallback? onEditDone;
  final String searchQuery;
  final VoidCallback? onTaskStatusChanged;

  const ItemWidget({
    super.key,
    required this.item,
    this.onEditDone,
    this.searchQuery = '',
    this.onTaskStatusChanged,
  });

  @override
  State<ItemWidget> createState() => _ItemWidgetState();
}

class _ItemWidgetState extends State<ItemWidget> {
  bool _isChecked = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _isChecked = widget.item.isCompleted;
  }

  @override
  void didUpdateWidget(ItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.isCompleted != widget.item.isCompleted ||
        oldWidget.item.docId != widget.item.docId) {
      _isChecked = widget.item.isCompleted;
    }
  }

  int get notificationId {
    if (widget.item.docId == null) {
      return widget.item.title.hashCode & 0x7FFFFFFF;
    }
    return widget.item.docId!.hashCode & 0x7FFFFFFF;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _weekNumber(DateTime d) {
    final startOfYear = DateTime(d.year, 1, 1);
    final dayOfYear = d.toLocal().difference(startOfYear).inDays + 1;
    return ((dayOfYear - d.weekday + 10) / 7).floor();
  }

  bool _isSameWeek(DateTime date1, DateTime date2) {
    final d1 = date1.toLocal();
    final d2 = date2.toLocal();
    return d1.year == d2.year && _weekNumber(d1) == _weekNumber(d2);
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  Future<void> _toggleCompleted() async {
    if (_isProcessing) return;

    final newStatus = !_isChecked;

    if (!newStatus) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Undo Completed Task?'),
            content: const Text('Are you sure you want to mark this task as incomplete?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      );

      if (confirm != true) {
        return;
      }
    }

    final previousStatus = _isChecked;

    // Optimistic UI update
    setState(() {
      _isChecked = newStatus;
      _isProcessing = true;
    });

    final now = DateTime.now();
    final docId = widget.item.docId;

    if (docId != null) {
      context.read<TaskProvider>().updateTaskOptimistically(
        docId,
        newStatus,
        newStatus ? now : null,
      );
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || docId == null) throw Exception("User or Task not found");

      final taskRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(docId);

      // Use cache-first read so this works offline.
      // Falls back gracefully if the document isn't cached yet.
      Map<String, dynamic>? currentData;
      try {
        final snapshot = await taskRef.get(const GetOptions(source: Source.cache));
        currentData = snapshot.data();
      } catch (_) {
        // Cache miss (first install or cache cleared) — proceed without stamps.
        debugPrint('item.dart: cache miss for task $docId, proceeding without stamps');
      }

      List<Timestamp> updatedStamps = [];

      if (currentData != null && currentData['completionStamps'] != null) {
        updatedStamps = (currentData['completionStamps'] as List).map((e) {
          if (e is Timestamp) return e;
          if (e is int) return Timestamp.fromMillisecondsSinceEpoch(e);
          if (e is String) return Timestamp.fromDate(DateTime.parse(e));
          if (e is DateTime) return Timestamp.fromDate(e);
          return Timestamp.now();
        }).toList();
      }

      final Map<String, dynamic> updateData = {'isCompleted': newStatus};

      if (newStatus) {
        final ts = Timestamp.fromDate(now);
        final taskType = widget.item.taskType.toLowerCase();
        bool shouldAddStamp = true;

        if (taskType != 'onetime') {
          shouldAddStamp = !updatedStamps.any((stamp) {
            final date = stamp.toDate();
            if (taskType == 'dailytask') return _isSameDay(date, now);
            if (taskType == 'weeklytask') return _isSameWeek(date, now);
            if (taskType == 'monthlytask') return _isSameMonth(date, now);
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
        final taskType = widget.item.taskType.toLowerCase();
        updatedStamps = updatedStamps.where((stamp) {
          final date = stamp.toDate();
          if (taskType == 'onetime') return false;
          if (taskType == 'dailytask') return !_isSameDay(date, now);
          if (taskType == 'weeklytask') return !_isSameWeek(date, now);
          if (taskType == 'monthlytask') return !_isSameMonth(date, now);
          return true;
        }).toList();

        updateData['completedAt'] = null;
        updateData['completionStamps'] = updatedStamps;

        if (widget.item.date != null && widget.item.date!.isAfter(DateTime.now())) {
          await NativeAlarmHelper.scheduleAlarmAtTime(
            id: notificationId,
            title: widget.item.title,
            body: widget.item.detail,
            dateTime: widget.item.date!,
          );
        }
      }

      await taskRef.update(updateData);
      widget.item.isCompleted = newStatus;
      widget.item.completedAt = newStatus ? now : null;

      widget.onTaskStatusChanged?.call();
    } catch (e) {
      debugPrint('Error toggling task completion: $e');
      if (mounted) {
        setState(() {
          _isChecked = previousStatus;
        });
        if (docId != null) {
          context.read<TaskProvider>().updateTaskOptimistically(
            docId,
            previousStatus,
            previousStatus ? now : null,
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update task: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text("Delete Task"),
          ],
        ),
        content: Text("Are you sure you want to delete '${task.title}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || task.docId == null) return;

      await NativeAlarmHelper.cancelAlarmsForTask(task.docId!);
      await NativeAlarmHelper.cancelAlarmById(notificationId);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(task.docId)
          .delete();

      if (mounted) {
        context.read<TaskProvider>().deleteTaskOptimistically(task.docId!);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Task deleted successfully"),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onEditDone?.call();
        widget.onTaskStatusChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete: $e")),
        );
      }
    }
  }

  TextSpan _highlightSearchText(String text, String query, TextStyle defaultStyle) {
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
            color: const Color(0xFF2563EB),
            backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
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

  Color _getTaskTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'dailytask':
        return const Color(0xFF3B82F6); // Blue
      case 'weeklytask':
        return const Color(0xFF10B981); // Emerald
      case 'monthlytask':
        return const Color(0xFF8B5CF6); // Purple
      default:
        return const Color(0xFF64748B); // Slate
    }
  }

  String _getTaskTypeLabel(String? type) {
    switch (type?.toLowerCase()) {
      case 'dailytask':
        return 'Daily';
      case 'weeklytask':
        return 'Weekly';
      case 'monthlytask':
        return 'Monthly';
      default:
        return 'One-Time';
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOverdue = task.date != null &&
        task.date!.isBefore(DateTime.now()) &&
        !_isChecked;

    final typeColor = _getTaskTypeColor(task.taskType);
    final typeLabel = _getTaskTypeLabel(task.taskType);

    final titleStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      decoration: _isChecked ? TextDecoration.lineThrough : null,
      color: _isChecked
          ? (isDark ? Colors.grey.shade500 : Colors.grey.shade400)
          : (isDark ? Colors.white : const Color(0xFF0F172A)),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isChecked
              ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
              : isOverdue
                  ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isOverdue ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ItemDetailPage(task: task)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Left Accent Bar
                Container(
                  width: 4,
                  height: 48,
                  margin: const EdgeInsets.only(right: 12, top: 2),
                  decoration: BoxDecoration(
                    color: _isChecked ? Colors.grey.shade400 : typeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // 2. Interactive Checkbox
                GestureDetector(
                  onTap: _toggleCompleted,
                  child: Container(
                    margin: const EdgeInsets.only(right: 12, top: 4),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _isChecked
                          ? const Color(0xFF10B981)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isChecked
                            ? const Color(0xFF10B981)
                            : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                        width: 2,
                      ),
                    ),
                    child: _isChecked
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),

                // 3. Main Content (Title, Detail, Metadata Chips)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      RichText(
                        text: _highlightSearchText(
                          task.title,
                          widget.searchQuery,
                          titleStyle,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Optional Detail Preview
                      if (task.detail.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.detail.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Badges Row
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Frequency Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  task.taskType.toLowerCase() == 'dailytask'
                                      ? Icons.repeat
                                      : task.taskType.toLowerCase() == 'weeklytask'
                                          ? Icons.calendar_view_week
                                          : task.taskType.toLowerCase() == 'monthlytask'
                                              ? Icons.calendar_month
                                              : Icons.push_pin_outlined,
                                  size: 11,
                                  color: typeColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  typeLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: typeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Date / Time Badge
                          if (task.date != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isOverdue
                                    ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isOverdue
                                        ? Icons.error_outline
                                        : Icons.access_time_rounded,
                                    size: 11,
                                    color: isOverdue
                                        ? const Color(0xFFEF4444)
                                        : (isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isOverdue
                                        ? "Overdue • ${DateFormat('MMM d, h:mm a').format(task.date!)}"
                                        : DateFormat('MMM d, h:mm a').format(task.date!),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isOverdue ? FontWeight.bold : FontWeight.w500,
                                      color: isOverdue
                                          ? const Color(0xFFEF4444)
                                          : (isDark
                                              ? Colors.grey.shade300
                                              : Colors.grey.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 4. Quick Action Popup Menu
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) {
                    if (value == 'edit') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => EditTaskPage(task: task)),
                      ).then((_) {
                        widget.onEditDone?.call();
                        widget.onTaskStatusChanged?.call();
                      });
                    } else if (value == 'delete') {
                      _deleteTask(task);
                    } else if (value == 'share') {
                      NativeShareService.share(
                        task.detail.trim().isNotEmpty
                            ? "${task.title}\n\n${task.detail}"
                            : task.title,
                      );
                    } else if (value == 'details') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ItemDetailPage(task: task)),
                      );
                    } else if (value == 'analytics') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AnalyticsPage(task: task)),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'details',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Details'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'analytics',
                      child: Row(
                        children: [
                          Icon(Icons.insights, size: 18),
                          SizedBox(width: 8),
                          Text('Analytics'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Share'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
