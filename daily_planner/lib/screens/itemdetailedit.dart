import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:intl/intl.dart';

// Add this enum (same as in AddTaskPage)
enum NotificationRecurrence { none, daily, weekly, monthly, custom }

extension NotificationRecurrenceExtension on NotificationRecurrence {
  String get label {
    switch (this) {
      case NotificationRecurrence.none:
        return "Once";
      case NotificationRecurrence.daily:
        return "Daily";
      case NotificationRecurrence.weekly:
        return "Weekly";
      case NotificationRecurrence.monthly:
        return "Monthly";
      case NotificationRecurrence.custom:
        return "Custom Days";
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationRecurrence.none:
        return Icons.notifications_none;
      case NotificationRecurrence.daily:
        return Icons.repeat;
      case NotificationRecurrence.weekly:
        return Icons.calendar_today;
      case NotificationRecurrence.monthly:
        return Icons.date_range;
      case NotificationRecurrence.custom:
        return Icons.settings;
    }
  }

  Color get color {
    switch (this) {
      case NotificationRecurrence.none:
        return Colors.grey;
      case NotificationRecurrence.daily:
        return Colors.blue;
      case NotificationRecurrence.weekly:
        return Colors.green;
      case NotificationRecurrence.monthly:
        return Colors.orange;
      case NotificationRecurrence.custom:
        return Colors.purple;
    }
  }
}

class EditTaskPage extends StatefulWidget {
  final Task task;
  const EditTaskPage({super.key, required this.task});

  @override
  State<EditTaskPage> createState() => _EditTaskPageState();
}

class _EditTaskPageState extends State<EditTaskPage> {
  late TextEditingController _titleController;
  late TextEditingController _detailController;
  late TextEditingController _editNoteController;

  final ValueNotifier<DateTime?> _selectedDateNotifier =
      ValueNotifier<DateTime?>(null);
  final ValueNotifier<bool> _isCompletedNotifier = ValueNotifier(false);
  final ValueNotifier<List<DateTime>> _notificationTimesNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> _hasEndDateNotifier = ValueNotifier(true);

  // New variables for recurring notifications
  final ValueNotifier<NotificationRecurrence> _notificationRecurrenceNotifier =
      ValueNotifier(NotificationRecurrence.none);
  final ValueNotifier<TimeOfDay> _recurringTimeNotifier = ValueNotifier(
    const TimeOfDay(hour: 21, minute: 0),
  );
  final ValueNotifier<Map<String, bool>> _selectedDaysNotifier = ValueNotifier({
    '1': false, // Monday
    '2': false, // Tuesday
    '3': false, // Wednesday
    '4': false, // Thursday
    '5': false, // Friday
    '6': false, // Saturday
    '7': false, // Sunday
  });
  final ValueNotifier<bool> _showCustomDaysNotifier = ValueNotifier(false);

  bool _isSaving = false;
  late List<DateTime> _oldNotificationTimes;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _detailController = TextEditingController(text: widget.task.detail);
    _editNoteController = TextEditingController();

    _selectedDateNotifier.value = widget.task.date;
    _isCompletedNotifier.value = widget.task.isCompleted;
    _oldNotificationTimes = widget.task.notificationTimes ?? [];

    _hasEndDateNotifier.value = widget.task.date != null;

    // Load notification recurrence info from task
    _loadNotificationRecurrenceInfo();

    loadNotificationTimes(widget.task).then((times) {
      _notificationTimesNotifier.value = times;
    });
  }

  void _loadNotificationRecurrenceInfo() {
    // ✅ FIXED: Use safe getters from Task model
    final recurrenceString = widget.task.safeNotificationRecurrence;

    // Convert string to enum
    final recurrence = NotificationRecurrence.values.firstWhere(
      (e) => e.name == recurrenceString,
      orElse: () => NotificationRecurrence.none,
    );
    _notificationRecurrenceNotifier.value = recurrence;

    // ✅ FIXED: Use safe getter for recurrence time
    final timeMap = widget.task.safeNotificationRecurrenceTime;
    _recurringTimeNotifier.value = TimeOfDay(
      hour: timeMap['hour'] ?? 21,
      minute: timeMap['minute'] ?? 0,
    );

    // ✅ FIXED: Use safe getter for selected days
    _selectedDaysNotifier.value = Map<String, bool>.from(
      widget.task.safeSelectedDays,
    );

    // Show custom days selector if needed
    _showCustomDaysNotifier.value =
        _notificationRecurrenceNotifier.value == NotificationRecurrence.custom;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    _editNoteController.dispose();
    _selectedDateNotifier.dispose();
    _isCompletedNotifier.dispose();
    _notificationTimesNotifier.dispose();
    _hasEndDateNotifier.dispose();
    _notificationRecurrenceNotifier.dispose();
    _recurringTimeNotifier.dispose();
    _selectedDaysNotifier.dispose();
    _showCustomDaysNotifier.dispose();
    super.dispose();
  }

  int generateNotificationId(String taskId, DateTime time) =>
      (taskId + time.toIso8601String()).hashCode.abs();

  Future<List<DateTime>> loadNotificationTimes(Task task) async {
    List<DateTime> notificationTimes = [];
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return notificationTimes;

      final snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('tasks')
              .doc(task.docId)
              .get();

      final data = snapshot.data();
      if (data != null && data['notificationTimes'] != null) {
        final List<dynamic> rawList = data['notificationTimes'];
        notificationTimes =
            rawList
                .whereType<Timestamp>()
                .map((ts) => ts.toDate().toLocal())
                .toList();
      }
    } catch (e) {
      debugPrint("Error loading Notification Times: $e");
    }
    return notificationTimes;
  }

  Future<void> _pickDateTime() async {
    final initialDate = _selectedDateNotifier.value ?? DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (pickedTime == null) return;

    _selectedDateNotifier.value = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<void> _pickRecurringTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _recurringTimeNotifier.value,
    );

    if (pickedTime != null) {
      _recurringTimeNotifier.value = pickedTime;
    }
  }

  Future<void> _pickNotificationTime() async {
    final now = DateTime.now();
    final taskDate = _selectedDateNotifier.value;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: taskDate ?? DateTime(2100),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (pickedTime == null) return;

    final newTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (newTime.isBefore(now)) {
      _showSnackBar("❌ Notification must be in the future");
      return;
    }

    if (taskDate != null && newTime.isAfter(taskDate)) {
      _showSnackBar("❌ Notification must be before task time");
      return;
    }

    if (_notificationTimesNotifier.value.any(
      (t) => t.isAtSameMomentAs(newTime),
    )) {
      _showSnackBar("❌ Notification already added");
      return;
    }

    _notificationTimesNotifier.value = [
      ..._notificationTimesNotifier.value,
      newTime,
    ]..sort();
  }

  void removeNotificationTime(DateTime time) {
    _notificationTimesNotifier.value =
        _notificationTimesNotifier.value.where((t) => t != time).toList();
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dateTime = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    return DateFormat.jm().format(dateTime);
  }

  String _getRecurrenceDescription() {
    if (_notificationRecurrenceNotifier.value == NotificationRecurrence.none) {
      return "Single Notifications";
    }

    final timeStr = " at ${_formatTimeOfDay(_recurringTimeNotifier.value)}";

    switch (_notificationRecurrenceNotifier.value) {
      case NotificationRecurrence.daily:
        return "Daily$timeStr";
      case NotificationRecurrence.weekly:
        final dayOfWeek = widget.task.date?.weekday ?? DateTime.now().weekday;
        final dayName = DateFormat('EEEE').format(DateTime(2024, 1, dayOfWeek));
        return "Every $dayName$timeStr";
      case NotificationRecurrence.monthly:
        final dayOfMonth = widget.task.date?.day ?? DateTime.now().day;
        final suffix = _getDaySuffix(dayOfMonth);
        return "Monthly on ${dayOfMonth}$suffix$timeStr";
      case NotificationRecurrence.custom:
        if (_selectedDaysNotifier.value.values.any((v) => v)) {
          final selectedDayNames = _getSelectedDayNames();
          return "Custom: ${selectedDayNames.join(', ')}$timeStr";
        }
        return "Custom schedule";
      default:
        return "Single notifications";
    }
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  List<String> _getSelectedDayNames() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return _selectedDaysNotifier.value.entries
        .where((entry) => entry.value)
        .map((entry) {
          final index = int.tryParse(entry.key);
          return index != null && index >= 1 && index <= 7
              ? days[index - 1]
              : 'Day $entry.key';
        })
        .toList();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isSameWeek(DateTime a, DateTime b) =>
      a
          .subtract(Duration(days: a.weekday - 1))
          .difference(b.subtract(Duration(days: b.weekday - 1)))
          .inDays ==
      0;
  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  // ✅ Check if task type supports no end date
  bool get _supportsNoEndDate {
    final taskType = widget.task.taskType;
    return taskType == 'DailyTask' ||
        taskType == 'WeeklyTask' ||
        taskType == 'MonthlyTask';
  }

  // 🚀 NEW: Calculate next recurring notifications
  List<DateTime> _calculateNextRecurringNotifications(
    DateTime? taskDate,
    int count,
  ) {
    final now = DateTime.now();
    final List<DateTime> times = [];

    if (_notificationRecurrenceNotifier.value == NotificationRecurrence.none) {
      return times;
    }

    DateTime startDate = taskDate ?? now;
    if (taskDate != null && taskDate.isBefore(now)) {
      startDate = now;
    }

    DateTime baseTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      _recurringTimeNotifier.value.hour,
      _recurringTimeNotifier.value.minute,
    );

    if (baseTime.isBefore(now)) {
      baseTime = baseTime.add(const Duration(days: 1));
    }

    int scheduled = 0;
    DateTime currentTime = baseTime;

    while (scheduled < count) {
      if (taskDate != null && currentTime.isAfter(taskDate)) {
        break;
      }

      bool shouldSchedule = true;

      switch (_notificationRecurrenceNotifier.value) {
        case NotificationRecurrence.daily:
          break;

        case NotificationRecurrence.weekly:
          if (currentTime.weekday != startDate.weekday) {
            shouldSchedule = false;
            currentTime = currentTime.add(const Duration(days: 1));
            continue;
          }
          break;

        case NotificationRecurrence.monthly:
          if (currentTime.day != startDate.day) {
            shouldSchedule = false;
            currentTime = DateTime(
              currentTime.year,
              currentTime.month + 1,
              startDate.day,
              _recurringTimeNotifier.value.hour,
              _recurringTimeNotifier.value.minute,
            );
            continue;
          }
          break;

        case NotificationRecurrence.custom:
          final weekdayKey = currentTime.weekday.toString();
          final isSelected = _selectedDaysNotifier.value[weekdayKey] ?? false;
          if (!isSelected) {
            shouldSchedule = false;
            currentTime = currentTime.add(const Duration(days: 1));
            continue;
          }
          break;

        case NotificationRecurrence.none:
          shouldSchedule = false;
          break;
      }

      if (shouldSchedule) {
        times.add(currentTime);
        scheduled++;

        switch (_notificationRecurrenceNotifier.value) {
          case NotificationRecurrence.daily:
            currentTime = currentTime.add(const Duration(days: 1));
            break;
          case NotificationRecurrence.weekly:
            currentTime = currentTime.add(const Duration(days: 7));
            break;
          case NotificationRecurrence.monthly:
            currentTime = DateTime(
              currentTime.year,
              currentTime.month + 1,
              currentTime.day,
              _recurringTimeNotifier.value.hour,
              _recurringTimeNotifier.value.minute,
            );
            break;
          case NotificationRecurrence.custom:
            currentTime = currentTime.add(const Duration(days: 1));
            break;
          case NotificationRecurrence.none:
            break;
        }
      }
    }

    return times;
  }

  // 🚀 UPDATED: Handle notifications with recurring support
  Future<void> _handleNotifications(
    String taskId,
    String title,
    DateTime? selectedDate,
  ) async {
    final now = DateTime.now();

    // Cancel all existing notifications for this task
    for (final oldTime in _oldNotificationTimes) {
      try {
        await NativeAlarmHelper.cancelAlarmById(
          generateNotificationId(taskId, oldTime),
        );
      } catch (e) {
        debugPrint("Error cancelling old notification: $e");
      }
    }

    // Schedule new notifications based on type
    if (_notificationRecurrenceNotifier.value != NotificationRecurrence.none) {
      // Schedule recurring notifications
      final recurringTimes = _calculateNextRecurringNotifications(
        selectedDate,
        10,
      );

      for (final notificationTime in recurringTimes) {
        if (notificationTime.isAfter(now)) {
          try {
            await NativeAlarmHelper.scheduleHybridAlarm(
              id: generateNotificationId(taskId, notificationTime),
              title: 'Task Reminder: $title',
              body:
                  selectedDate != null
                      ? '$title is due at ${DateFormat.jm().format(selectedDate)}'
                      : '$title reminder',
              dateTime: notificationTime,
              payload: {
                'type': 'alarm',
                'taskId': taskId,
                'title': title,
                'body':
                    selectedDate != null
                        ? '$title is due at ${DateFormat.jm().format(selectedDate)}'
                        : '$title reminder',
                'recurrence': _notificationRecurrenceNotifier.value.name,
                'recurrenceTime': {
                  'hour': _recurringTimeNotifier.value.hour,
                  'minute': _recurringTimeNotifier.value.minute,
                },
                'selectedDays': _selectedDaysNotifier.value,
              },
            );
            debugPrint("✅ Recurring alarm scheduled for: $notificationTime");
          } catch (e) {
            debugPrint("❌ Failed to schedule recurring alarm: $e");
          }
        }
      }
    } else {
      // Schedule single notifications
      for (final notificationTime in _notificationTimesNotifier.value) {
        if (notificationTime.isAfter(now)) {
          try {
            await NativeAlarmHelper.scheduleHybridAlarm(
              id: generateNotificationId(taskId, notificationTime),
              title: 'Task Reminder: $title',
              body:
                  selectedDate != null
                      ? '$title is due at ${DateFormat.jm().format(selectedDate)}'
                      : '$title reminder',
              dateTime: notificationTime,
              payload: {
                'type': 'alarm',
                'taskId': taskId,
                'title': title,
                'body':
                    selectedDate != null
                        ? '$title is due at ${DateFormat.jm().format(selectedDate)}'
                        : '$title reminder',
              },
            );
            debugPrint("✅ Single alarm scheduled for: $notificationTime");
          } catch (e) {
            debugPrint("❌ Failed to schedule single alarm: $e");
          }
        }
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not signed in");
      if (widget.task.docId == null) throw Exception("Task ID not found");

      final now = DateTime.now();
      final newTitle = _titleController.text.trim();
      if (newTitle.isEmpty) throw Exception("Task title cannot be empty");

      final isCompleted = _isCompletedNotifier.value;
      final hasEndDate = _hasEndDateNotifier.value;
      final selectedDate = hasEndDate ? _selectedDateNotifier.value : null;

      // ✅ FIXED: Prepare Firestore update with safe defaults
      final updateData = <String, dynamic>{
        'title': newTitle,
        'detail': _detailController.text.trim(),
        'isCompleted': isCompleted,
        'notificationTimes':
            _notificationTimesNotifier.value
                .map((dt) => Timestamp.fromDate(dt.toUtc()))
                .toList(),
        // Add recurrence information - always include these fields
        'notificationRecurrence': _notificationRecurrenceNotifier.value.name,
        'notificationRecurrenceTime': {
          'hour': _recurringTimeNotifier.value.hour,
          'minute': _recurringTimeNotifier.value.minute,
        },
        'selectedDays': _selectedDaysNotifier.value,
      };

      // ✅ Only add date if it exists
      if (selectedDate != null) {
        updateData['date'] = Timestamp.fromDate(selectedDate.toUtc());
      } else {
        updateData['date'] = null;
      }

      // Add edit history if there's a note
      final editNote = _editNoteController.text.trim();
      if (editNote.isNotEmpty) {
        updateData['editHistory'] = FieldValue.arrayUnion([
          {'timestamp': Timestamp.now(), 'note': editNote},
        ]);
      }

      // Task Type Info
      if (widget.task.taskType == "DailyTask") {
        updateData['taskType'] = 'DailyTask';
      } else if (widget.task.taskType == "WeeklyTask") {
        updateData['taskType'] = 'WeeklyTask';
      } else if (widget.task.taskType == "MonthlyTask") {
        updateData['taskType'] = 'MonthlyTask';
        updateData['dayOfMonth'] = (widget.task as MonthlyTask).dayOfMonth;
      } else {
        updateData['taskType'] = 'oneTime';
      }

      // Completion Stamps
      final currentStamps = widget.task.completionStamps ?? [];
      final nowStamp = Timestamp.fromDate(now.toUtc());

      if (widget.task.taskType == 'oneTime') {
        updateData['completionStamps'] = isCompleted ? [nowStamp] : [];
      } else {
        final stampsInPeriod =
            currentStamps.where((ts) {
              final dt = ts.toLocal();
              if (widget.task.taskType == 'DailyTask')
                return _isSameDay(dt, now);
              if (widget.task.taskType == 'WeeklyTask')
                return _isSameWeek(dt, now);
              if (widget.task.taskType == 'MonthlyTask')
                return _isSameMonth(dt, now);
              return false;
            }).toList();

        if (isCompleted && stampsInPeriod.isEmpty) {
          updateData['completionStamps'] = FieldValue.arrayUnion([nowStamp]);
        } else if (!isCompleted && stampsInPeriod.isNotEmpty) {
          updateData['completionStamps'] = FieldValue.arrayRemove(
            stampsInPeriod,
          );
        }
      }

      // 🚀 FIRST: Save to Firestore immediately
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(widget.task.docId)
          .update(updateData);

      debugPrint("✅ Task '$newTitle' successfully updated in Firestore");

      // 🚀 SECOND: Show immediate success message
      _showSnackBar("✅ Task updated successfully!");

      // 🚀 THIRD: Navigate back immediately
      if (mounted) Navigator.pop(context, true);

      // 🚀 FOURTH: Handle notifications in background (after navigation)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotifications(widget.task.docId!, newTitle, selectedDate);
      });
    } catch (e, stack) {
      debugPrint("❌ Error updating task: $e\n$stack");
      _showSnackBar("❌ Failed to update task: ${e.toString()}");
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: message.contains("❌") ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  String _getTaskTypeLabel() {
    final taskType = widget.task.taskType;
    switch (taskType) {
      case 'oneTime':
        return 'One-Time Task';
      case 'DailyTask':
        return 'Daily Task';
      case 'WeeklyTask':
        return 'Weekly Task';
      case 'MonthlyTask':
        return 'Monthly Task';
      default:
        return 'Task';
    }
  }

  IconData _getTaskTypeIcon() {
    final taskType = widget.task.taskType;
    switch (taskType) {
      case 'oneTime':
        return Icons.push_pin;
      case 'DailyTask':
        return Icons.loop;
      case 'WeeklyTask':
        return Icons.calendar_today;
      case 'MonthlyTask':
        return Icons.date_range;
      default:
        return Icons.task;
    }
  }

  Color _getTaskTypeColor() {
    final taskType = widget.task.taskType;
    switch (taskType) {
      case 'oneTime':
        return Colors.blue;
      case 'DailyTask':
        return Colors.green;
      case 'WeeklyTask':
        return Colors.orange;
      case 'MonthlyTask':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // ✅ NEW: Build recurring notification section
  Widget _buildRecurringNotificationSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Notification Schedule",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),

            // Recurrence Type Selection
            ValueListenableBuilder<NotificationRecurrence>(
              valueListenable: _notificationRecurrenceNotifier,
              builder: (_, recurrence, __) {
                return DropdownButtonFormField<NotificationRecurrence>(
                  value: recurrence,
                  decoration: InputDecoration(
                    labelText: "How often?",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  items:
                      NotificationRecurrence.values.map((recurrence) {
                        return DropdownMenuItem(
                          value: recurrence,
                          child: Row(
                            children: [
                              Icon(
                                recurrence.icon,
                                color: recurrence.color,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                recurrence.label,
                                style: TextStyle(color: recurrence.color),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                  onChanged: (newRecurrence) {
                    if (newRecurrence != null) {
                      _notificationRecurrenceNotifier.value = newRecurrence;
                      _showCustomDaysNotifier.value =
                          newRecurrence == NotificationRecurrence.custom;
                      // Clear single notifications if switching to recurring
                      if (newRecurrence != NotificationRecurrence.none) {
                        _notificationTimesNotifier.value = [];
                      }
                    }
                  },
                );
              },
            ),

            const SizedBox(height: 16),

            // Time Picker for Recurring Notifications
            ValueListenableBuilder<NotificationRecurrence>(
              valueListenable: _notificationRecurrenceNotifier,
              builder: (_, recurrence, __) {
                if (recurrence == NotificationRecurrence.none) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Notification Time:",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<TimeOfDay>(
                      valueListenable: _recurringTimeNotifier,
                      builder: (_, time, __) {
                        return InkWell(
                          onTap: _pickRecurringTime,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _formatTimeOfDay(time),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const Spacer(),
                                const Icon(Icons.edit, color: Colors.grey),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Next 10 occurrences will be scheduled",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                );
              },
            ),

            // Custom Days Selector
            ValueListenableBuilder<bool>(
              valueListenable: _showCustomDaysNotifier,
              builder: (_, showCustomDays, __) {
                if (!showCustomDays) return const SizedBox.shrink();

                return Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildCustomDaysSelector(),
                  ],
                );
              },
            ),

            // Single Notifications (only when recurrence is "none")
            ValueListenableBuilder<NotificationRecurrence>(
              valueListenable: _notificationRecurrenceNotifier,
              builder: (_, recurrence, __) {
                if (recurrence != NotificationRecurrence.none) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      "Single Notifications:",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<List<DateTime>>(
                      valueListenable: _notificationTimesNotifier,
                      builder: (_, times, __) {
                        if (times.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              "No notifications added",
                              style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          );
                        } else {
                          return Column(
                            children: [
                              SizedBox(
                                height: times.length > 3 ? 200 : null,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      times.length > 3
                                          ? null
                                          : const NeverScrollableScrollPhysics(),
                                  itemCount: times.length,
                                  itemBuilder: (_, index) {
                                    final time = times[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      elevation: 1,
                                      child: ListTile(
                                        leading: Icon(
                                          Icons.notifications_active,
                                          color: _getTaskTypeColor(),
                                        ),
                                        title: Text(
                                          DateFormat(
                                            'MMM d, yyyy',
                                          ).format(time),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          DateFormat('h:mm a').format(time),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed:
                                              () =>
                                                  removeNotificationTime(time),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          );
                        }
                      },
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickNotificationTime,
                        icon: const Icon(Icons.add_alert),
                        label: const Text("Add Single Notification"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            // ✅ NEW: Show current recurrence description
            ValueListenableBuilder<NotificationRecurrence>(
              valueListenable: _notificationRecurrenceNotifier,
              builder: (_, recurrence, __) {
                if (recurrence == NotificationRecurrence.none) {
                  return const SizedBox.shrink();
                }

                return Column(
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: recurrence.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: recurrence.color.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            recurrence.icon,
                            color: recurrence.color,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _getRecurrenceDescription(),
                              style: TextStyle(
                                color: recurrence.color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ✅ NEW: Build custom days selector
  Widget _buildCustomDaysSelector() {
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Select days:",
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<Map<String, bool>>(
            valueListenable: _selectedDaysNotifier,
            builder: (_, selectedDays, __) {
              return Wrap(
                spacing: 8,
                children: List.generate(7, (index) {
                  final dayKey = (index + 1).toString();
                  final isSelected = selectedDays[dayKey] ?? false;

                  return FilterChip(
                    label: Text(days[index]),
                    selected: isSelected,
                    onSelected: (selected) {
                      final newMap = Map<String, bool>.from(selectedDays);
                      newMap[dayKey] = selected;
                      _selectedDaysNotifier.value = newMap;
                    },
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                    selectedColor: Theme.of(context).primaryColor,
                    checkmarkColor: Colors.white,
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<Map<String, bool>>(
            valueListenable: _selectedDaysNotifier,
            builder: (_, selectedDays, __) {
              final selectedDayNames = _getSelectedDayNames();
              return Text(
                selectedDayNames.isEmpty
                    ? "No days selected"
                    : "Selected: ${selectedDayNames.join(', ')}",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Edit Task",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Task Type Info
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _getTaskTypeColor().withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getTaskTypeIcon(),
                          color: _getTaskTypeColor(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getTaskTypeLabel(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _getTaskTypeColor(),
                              ),
                            ),
                            Text(
                              "Created ${DateFormat('MMM d, yyyy').format(widget.task.createdAt)}",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Task Details
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Task Details",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: "Title *",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.title),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _detailController,
                        decoration: InputDecoration(
                          labelText: "Description",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.description),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ✅ End Date Toggle for recurring tasks
              if (_supportsNoEndDate) ...[
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "End Date",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ValueListenableBuilder<bool>(
                              valueListenable: _hasEndDateNotifier,
                              builder:
                                  (_, hasEndDate, __) => Icon(
                                    hasEndDate
                                        ? Icons.event_available
                                        : Icons.event_busy,
                                    color:
                                        hasEndDate ? Colors.green : Colors.grey,
                                    size: 28,
                                  ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                "Set an end date",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            ValueListenableBuilder<bool>(
                              valueListenable: _hasEndDateNotifier,
                              builder:
                                  (_, value, __) => Switch(
                                    value: value,
                                    onChanged: (val) {
                                      _hasEndDateNotifier.value = val;
                                      if (!val) {
                                        _selectedDateNotifier.value = null;
                                      } else {
                                        _selectedDateNotifier.value ??=
                                            DateTime.now();
                                      }
                                    },
                                    activeColor: Colors.green,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: _hasEndDateNotifier,
                          builder: (_, hasEndDate, __) {
                            return Text(
                              hasEndDate
                                  ? "This task will end on the selected date"
                                  : "This task will continue indefinitely",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Date & Time Selection (only show if hasEndDate is true)
              ValueListenableBuilder<bool>(
                valueListenable: _hasEndDateNotifier,
                builder: (context, hasEndDate, _) {
                  if (!hasEndDate) return const SizedBox.shrink();

                  return Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "End Date & Time",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ValueListenableBuilder<DateTime?>(
                            valueListenable: _selectedDateNotifier,
                            builder: (context, date, _) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: _buildInfoChip(
                                      Icons.calendar_today,
                                      date != null
                                          ? DateFormat(
                                            'EEE, MMM d, yyyy',
                                          ).format(date)
                                          : "Not set",
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildInfoChip(
                                      Icons.access_time,
                                      date != null
                                          ? DateFormat('h:mm a').format(date)
                                          : "Not set",
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _pickDateTime,
                              icon: const Icon(Icons.edit_calendar),
                              label: const Text("Set End Date & Time"),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // ✅ NEW: Recurring Notifications Section
              _buildRecurringNotificationSection(),

              const SizedBox(height: 20),

              // Completion Status
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: _isCompletedNotifier,
                        builder: (_, isCompleted, __) {
                          return Icon(
                            isCompleted
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: isCompleted ? Colors.green : Colors.grey,
                            size: 28,
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Mark as completed",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: _isCompletedNotifier,
                        builder:
                            (_, value, __) => Switch(
                              value: value,
                              onChanged:
                                  (val) => _isCompletedNotifier.value = val,
                              activeColor: Colors.green,
                            ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Edit Note
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Edit Note (Optional)",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Why did you update this task?",
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _editNoteController,
                        decoration: InputDecoration(
                          hintText: "Add a note about this edit...",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.note),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ✅ NEW: Delete Recurring Notifications Button
              ValueListenableBuilder<NotificationRecurrence>(
                valueListenable: _notificationRecurrenceNotifier,
                builder: (_, recurrence, __) {
                  if (recurrence == NotificationRecurrence.none) {
                    return const SizedBox.shrink();
                  }

                  return Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Manage Recurring Notifications",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "You have ${_getRecurrenceDescription()} notifications set up.",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // Clear all recurring settings
                                _notificationRecurrenceNotifier.value =
                                    NotificationRecurrence.none;
                                _showCustomDaysNotifier.value = false;
                                _selectedDaysNotifier.value = {
                                  '1': false,
                                  '2': false,
                                  '3': false,
                                  '4': false,
                                  '5': false,
                                  '6': false,
                                  '7': false,
                                };
                                _showSnackBar(
                                  "✅ Recurring notifications removed",
                                );
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text(
                                "Remove Recurring Notifications",
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 30),

              // Save Button
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save, size: 24),
                      label: const Text(
                        "Save Changes",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _getTaskTypeColor(),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[800]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
