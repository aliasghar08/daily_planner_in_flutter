import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

enum TaskType { oneTime, daily, weekly, monthly }

// New enum for notification recurrence
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

extension TaskTypeExtension on TaskType {
  String get label {
    switch (this) {
      case TaskType.oneTime:
        return "One-Time";
      case TaskType.daily:
        return "Daily";
      case TaskType.weekly:
        return "Weekly";
      case TaskType.monthly:
        return "Monthly";
    }
  }

  IconData get icon {
    switch (this) {
      case TaskType.oneTime:
        return Icons.push_pin;
      case TaskType.daily:
        return Icons.loop;
      case TaskType.weekly:
        return Icons.calendar_today;
      case TaskType.monthly:
        return Icons.date_range;
    }
  }

  Color get color {
    switch (this) {
      case TaskType.oneTime:
        return Colors.blue;
      case TaskType.daily:
        return Colors.green;
      case TaskType.weekly:
        return Colors.orange;
      case TaskType.monthly:
        return Colors.purple;
    }
  }
}

class AddTaskPage extends StatefulWidget {
  const AddTaskPage({super.key});

  @override
  State<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends State<AddTaskPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();
  DateTime? _selectedDate;
  TaskType _selectedType = TaskType.oneTime;
  bool _isCompleted = false;
  bool _isSaving = false;
  bool _hasEndDate = true;
  List<DateTime> _notificationTimes = []; // For single notifications only
  bool _nativeAlarmInitialized = false;

  // New variables for recurring notifications
  NotificationRecurrence _notificationRecurrence = NotificationRecurrence.none;
  TimeOfDay _recurringTime = const TimeOfDay(hour: 21, minute: 0); // Default 9 PM
  Map<String, bool> _selectedDays = {
    '1': false, // Monday
    '2': false, // Tuesday
    '3': false, // Wednesday
    '4': false, // Thursday
    '5': false, // Friday
    '6': false, // Saturday
    '7': false, // Sunday
  };
  bool _showCustomDays = false;

  @override
  void initState() {
    super.initState();
    _checkNativeAlarmInitialization();
  }

  Future<void> _checkNativeAlarmInitialization() async {
    try {
      await NativeAlarmHelper.initialize();
      setState(() {
        _nativeAlarmInitialized = true;
      });
      debugPrint('✅ NativeAlarmHelper initialized in AddTaskPage');
    } catch (e) {
      debugPrint('❌ NativeAlarmHelper initialization failed: $e');
      setState(() {
        _nativeAlarmInitialized = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final initialDate = _selectedDate ?? DateTime.now();

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

    setState(() {
      _selectedDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickRecurringTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _recurringTime,
    );

    if (pickedTime != null) {
      setState(() {
        _recurringTime = pickedTime;
      });
    }
  }

  String formatDate(DateTime? date) =>
      date != null ? DateFormat.yMMMd().format(date) : "Not set";
  String formatTime(DateTime? date) =>
      date != null ? DateFormat.jm().format(date) : "Not set";

  String _formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dateTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat.jm().format(dateTime);
  }

  bool get _supportsNoEndDate {
    return _selectedType == TaskType.daily ||
        _selectedType == TaskType.weekly ||
        _selectedType == TaskType.monthly;
  }

  bool get _requiresEndDate {
    return _selectedType == TaskType.oneTime;
  }

  // ✅ NEW: Calculate recurring notification times dynamically (not stored)
  List<DateTime> _calculateNextRecurringNotifications(DateTime? taskDate, int count) {
    final now = DateTime.now();
    final List<DateTime> times = [];
    
    if (_notificationRecurrence == NotificationRecurrence.none) {
      return times;
    }

    // Start from tomorrow or task date
    DateTime startDate = taskDate ?? now;
    if (taskDate != null && taskDate.isBefore(now)) {
      startDate = now;
    }

    // Create base time with the selected recurring time
    DateTime baseTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      _recurringTime.hour,
      _recurringTime.minute,
    );

    // If base time is in the past, move to next day
    if (baseTime.isBefore(now)) {
      baseTime = baseTime.add(const Duration(days: 1));
    }

    int scheduled = 0;
    DateTime currentTime = baseTime;

    while (scheduled < count) {
      // Check if this time is before task end date (if exists)
      if (taskDate != null && currentTime.isAfter(taskDate)) {
        break;
      }

      // Apply recurrence pattern
      bool shouldSchedule = true;
      
      switch (_notificationRecurrence) {
        case NotificationRecurrence.daily:
          // Schedule every day
          break;
          
        case NotificationRecurrence.weekly:
          // Schedule weekly on the same weekday
          if (currentTime.weekday != startDate.weekday) {
            shouldSchedule = false;
            currentTime = currentTime.add(const Duration(days: 1));
            continue;
          }
          break;
          
        case NotificationRecurrence.monthly:
          // Schedule monthly on the same day
          if (currentTime.day != startDate.day) {
            shouldSchedule = false;
            currentTime = DateTime(
              currentTime.year,
              currentTime.month + 1,
              startDate.day,
              _recurringTime.hour,
              _recurringTime.minute,
            );
            continue;
          }
          break;
          
        case NotificationRecurrence.custom:
          // Schedule only on selected days
          if (!(_selectedDays[currentTime.weekday.toString()] ?? false)) {
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
        
        // Move to next occurrence based on pattern
        switch (_notificationRecurrence) {
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
              _recurringTime.hour,
              _recurringTime.minute,
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

  // ✅ UPDATED: Schedule notifications dynamically
  Future<void> _scheduleNotifications(
    String taskId,
    String title,
    DateTime? taskDate,
  ) async {
    final now = DateTime.now();
    int scheduledCount = 0;

    // For recurring notifications, calculate next occurrences and schedule them
    if (_notificationRecurrence != NotificationRecurrence.none) {
      // Calculate next 10 recurring notifications (or until task end date)
      final List<DateTime> recurringTimes = _calculateNextRecurringNotifications(taskDate, 10);
      
      debugPrint("📅 Will schedule ${recurringTimes.length} recurring notifications");
      
      for (final notificationTime in recurringTimes) {
        if (notificationTime.isAfter(now)) {
          try {
            await NativeAlarmHelper.scheduleHybridAlarm(
              id: _generateAlarmId(taskId, notificationTime),
              title: 'Task Reminder: $title',
              body: taskDate != null
                  ? '$title is due at ${DateFormat.jm().format(taskDate)}'
                  : '$title reminder',
              dateTime: notificationTime,
              payload: {
                'type': 'alarm',
                'alarmId': _generateAlarmId(taskId, notificationTime),
                'taskId': taskId,
                'title': title,
                'body': taskDate != null
                    ? '$title is due at ${DateFormat.jm().format(taskDate)}'
                    : '$title reminder',
                'recurrence': _notificationRecurrence.name,
                'recurrenceTime': {
                  'hour': _recurringTime.hour,
                  'minute': _recurringTime.minute,
                },
                'selectedDays': _selectedDays,
              },
            );
            scheduledCount++;
            debugPrint("✅ Recurring alarm scheduled for: $notificationTime");
          } catch (e) {
            debugPrint("❌ Failed to schedule recurring alarm: $e");
            // Fallback logic if needed
          }
        }
      }
    } else {
      // For single notifications, schedule only the stored times
      for (final notificationTime in _notificationTimes) {
        if (notificationTime.isAfter(now)) {
          try {
            await NativeAlarmHelper.scheduleHybridAlarm(
              id: _generateAlarmId(taskId, notificationTime),
              title: 'Task Reminder: $title',
              body: taskDate != null
                  ? '$title is due at ${DateFormat.jm().format(taskDate)}'
                  : '$title reminder',
              dateTime: notificationTime,
              payload: {
                'type': 'alarm',
                'alarmId': _generateAlarmId(taskId, notificationTime),
                'taskId': taskId,
                'title': title,
                'body': taskDate != null
                    ? '$title is due at ${DateFormat.jm().format(taskDate)}'
                    : '$title reminder',
              },
            );
            scheduledCount++;
            debugPrint("✅ Single alarm scheduled for: $notificationTime");
          } catch (e) {
            debugPrint("❌ Failed to schedule single alarm: $e");
          }
        }
      }
    }

    if (scheduledCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✅ $scheduledCount notification(s) scheduled",
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  int _generateAlarmId(String taskId, DateTime time) {
    // Combine taskId and timestamp for unique ID
    final combined = '${taskId}_${time.millisecondsSinceEpoch}';
    return combined.hashCode.abs() % 1000000;
  }

  Future<void> _addTask() async {
    final title = _titleController.text.trim();
    final detail = _detailController.text.trim();
    final now = DateTime.now();

    if (title.isEmpty) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Title cannot be empty."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_requiresEndDate && _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ One-time tasks require an end date."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedDate != null && _selectedDate!.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Please choose a future date and time."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate custom days selection
    if (_notificationRecurrence == NotificationRecurrence.custom &&
        !_selectedDays.values.any((selected) => selected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Please select at least one day for custom notifications."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ You must be logged in to add tasks."),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
        return;
      }

      final uid = user.uid;
      final newTaskRef =
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('tasks')
              .doc();

      Task newTask;

      final DateTime? taskDate =
          _requiresEndDate
              ? _selectedDate
              : (_hasEndDate ? _selectedDate : null);

      // 🚀 CRITICAL FIX: Don't store recurring notification times in Firestore
      // Only store single notification times, not recurring ones
      final List<DateTime> notificationTimesToStore = 
          _notificationRecurrence == NotificationRecurrence.none 
              ? _notificationTimes 
              : [];

      switch (_selectedType) {
        case TaskType.oneTime:
          newTask = Task(
            docId: newTaskRef.id,
            title: title,
            detail: detail,
            date: taskDate,
            isCompleted: _isCompleted,
            createdAt: now,
            completedAt: _isCompleted ? now : null,
            taskType: _selectedType.name,
            notificationTimes: notificationTimesToStore,
            // Store recurrence pattern only, not individual times
            notificationRecurrence: _notificationRecurrence.name,
            notificationRecurrenceTime: {
              'hour': _recurringTime.hour,
              'minute': _recurringTime.minute,
            },
            selectedDays: _selectedDays,
          );
          break;

        case TaskType.daily:
          newTask = DailyTask(
            docId: newTaskRef.id,
            title: title,
            detail: detail,
            date: taskDate,
            isCompleted: _isCompleted,
            createdAt: now,
            completedAt: _isCompleted ? now : null,
            completionStamps: _isCompleted ? [now] : [],
            notificationTimes: notificationTimesToStore,
            // Store recurrence pattern only, not individual times
            notificationRecurrence: _notificationRecurrence.name,
            notificationRecurrenceTime: {
              'hour': _recurringTime.hour,
              'minute': _recurringTime.minute,
            },
            selectedDays: _selectedDays,
          );
          break;

        case TaskType.weekly:
          newTask = WeeklyTask(
            docId: newTaskRef.id,
            title: title,
            detail: detail,
            date: taskDate,
            isCompleted: _isCompleted,
            createdAt: now,
            completedAt: _isCompleted ? now : null,
            completionStamps: _isCompleted ? [now] : [],
            notificationTimes: notificationTimesToStore,
            // Store recurrence pattern only, not individual times
            notificationRecurrence: _notificationRecurrence.name,
            notificationRecurrenceTime: {
              'hour': _recurringTime.hour,
              'minute': _recurringTime.minute,
            },
            selectedDays: _selectedDays,
          );
          break;

        case TaskType.monthly:
          final dayOfMonth = taskDate?.day ?? now.day;
          newTask = MonthlyTask(
            docId: newTaskRef.id,
            title: title,
            detail: detail,
            date: taskDate,
            isCompleted: _isCompleted,
            createdAt: now,
            completedAt: _isCompleted ? now : null,
            dayOfMonth: dayOfMonth,
            completionStamps: _isCompleted ? [now] : [],
            notificationTimes: notificationTimesToStore,
            // Store recurrence pattern only, not individual times
            notificationRecurrence: _notificationRecurrence.name,
            notificationRecurrenceTime: {
              'hour': _recurringTime.hour,
              'minute': _recurringTime.minute,
            },
            selectedDays: _selectedDays,
          );
          break;
      }

      debugPrint(
        "Creating task of type: ${_selectedType.name} - ${newTask.runtimeType}"
      );

      await newTaskRef.set(newTask.toMap());
      debugPrint("✅ Task '$title' successfully added to Firestore");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Task '$title' added successfully!"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }

      // Schedule notifications in background
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleNotifications(newTaskRef.id, title, taskDate);
      });
    } catch (e, stack) {
      debugPrint("❌ Error adding task: $e");
      debugPrint("Stack trace:\n$stack");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Failed to add task: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickNotificationTime() async {
    final now = DateTime.now();
    final taskDate = _selectedDate;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: taskDate ?? DateTime(2100),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (pickedTime == null) return;

    final newNotificationTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (newNotificationTime.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Notification time must be in the future."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (taskDate != null && newNotificationTime.isAfter(taskDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Notification time must be before task time."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_notificationTimes.any(
      (time) => time.isAtSameMomentAs(newNotificationTime),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ This notification time is already added."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _notificationTimes.add(newNotificationTime);
      _notificationTimes.sort();
    });
  }

  Widget _buildTaskTypeInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _selectedType.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _selectedType.color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(_selectedType.icon, color: _selectedType.color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getTaskTypeDescription(),
              style: TextStyle(
                color: _selectedType.color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getTaskTypeDescription() {
    switch (_selectedType) {
      case TaskType.oneTime:
        return "This task will occur only once and requires an end date";
      case TaskType.daily:
        return _hasEndDate
            ? "This task will repeat every day until the end date"
            : "This task will repeat every day indefinitely";
      case TaskType.weekly:
        return _hasEndDate
            ? "This task will repeat every week until the end date"
            : "This task will repeat every week indefinitely";
      case TaskType.monthly:
        return _hasEndDate
            ? "This task will repeat every month until the end date"
            : "This task will repeat every month indefinitely";
    }
  }

  String _getSelectedDaysText() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final selectedDayNames = _selectedDays.entries
        .where((entry) => entry.value)
        .map((entry) => days[int.parse(entry.key) - 1])
        .toList();
    
    return selectedDayNames.isEmpty ? "No days selected" : selectedDayNames.join(', ');
  }

  Widget _buildCustomDaysSelector() {
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
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
          Wrap(
            spacing: 8,
            children: List.generate(7, (index) {
              final dayKey = (index + 1).toString();
              final isSelected = _selectedDays[dayKey] ?? false;
              
              return FilterChip(
                label: Text(days[index]),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedDays[dayKey] = selected;
                  });
                },
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                ),
                selectedColor: Theme.of(context).primaryColor,
                checkmarkColor: Colors.white,
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            "Selected: ${_getSelectedDaysText()}",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

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
            DropdownButtonFormField<NotificationRecurrence>(
              value: _notificationRecurrence,
              decoration: InputDecoration(
                labelText: "How often?",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
              ),
              items: NotificationRecurrence.values.map((recurrence) {
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
              onChanged: (recurrence) {
                if (recurrence != null) {
                  setState(() {
                    _notificationRecurrence = recurrence;
                    _showCustomDays = recurrence == NotificationRecurrence.custom;
                    // Clear single notifications if switching to recurring
                    if (recurrence != NotificationRecurrence.none) {
                      _notificationTimes.clear();
                    }
                  });
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // Time Picker for Recurring Notifications
            if (_notificationRecurrence != NotificationRecurrence.none)
              Column(
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
                  InkWell(
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
                          const Icon(Icons.access_time, color: Colors.grey),
                          const SizedBox(width: 12),
                          Text(
                            _formatTimeOfDay(_recurringTime),
                            style: const TextStyle(fontSize: 16),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit, color: Colors.grey),
                        ],
                      ),
                    ),
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
              ),
            
            // Custom Days Selector
            if (_showCustomDays)
              Column(
                children: [
                  const SizedBox(height: 16),
                  _buildCustomDaysSelector(),
                ],
              ),
            
            // Single Notifications (only when recurrence is "none")
            if (_notificationRecurrence == NotificationRecurrence.none)
              Column(
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
                  if (_notificationTimes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        "No notifications added",
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          _notificationTimes.map((time) {
                            return Chip(
                              label: Text(
                                DateFormat.yMd().add_jm().format(time),
                              ),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () {
                                setState(() {
                                  _notificationTimes.remove(time);
                                });
                              },
                              backgroundColor: Colors.blue.withOpacity(0.1),
                            );
                          }).toList(),
                    ),
                  const SizedBox(height: 12),
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmSystemStatus() {
    if (_nativeAlarmInitialized) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[800], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "✅ Native Alarm System Active",
                style: TextStyle(
                  color: Colors.green[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange),
        ),
        child: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange[800], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "⚠️ Using Fallback Notification System",
                style: TextStyle(
                  color: Colors.orange[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = formatDate(_selectedDate);
    final formattedTime = formatTime(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Add New Task",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Alarm System Status
              _buildAlarmSystemStatus(),
              const SizedBox(height: 16),

              // Task Type Selection
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Task Type",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<TaskType>(
                        value: _selectedType,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                        ),
                        items:
                            TaskType.values.map((type) {
                              return DropdownMenuItem(
                                value: type,
                                child: Row(
                                  children: [
                                    Icon(
                                      type.icon,
                                      color: type.color,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      type.label,
                                      style: TextStyle(color: type.color),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                        onChanged: (type) {
                          if (type != null) {
                            setState(() {
                              _selectedType = type;
                              if (_supportsNoEndDate) {
                                _hasEndDate = true;
                              }
                              if (!_hasEndDate && _supportsNoEndDate) {
                                _selectedDate = null;
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildTaskTypeInfo(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

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
                            Icon(
                              _hasEndDate
                                  ? Icons.event_available
                                  : Icons.event_busy,
                              color: _hasEndDate ? Colors.green : Colors.grey,
                              size: 28,
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
                            Switch(
                              value: _hasEndDate,
                              onChanged: (val) {
                                setState(() {
                                  _hasEndDate = val;
                                  if (!val) {
                                    _selectedDate = null;
                                  } else {
                                    _selectedDate ??= DateTime.now();
                                  }
                                });
                              },
                              activeColor: Colors.green,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hasEndDate
                              ? "This task will end on the selected date"
                              : "This task will continue indefinitely",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

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
                          labelText: "Title",
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

              if (_requiresEndDate || _hasEndDate) ...[
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _requiresEndDate ? "Date & Time" : "End Date & Time",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoChip(
                                Icons.calendar_today,
                                formattedDate,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoChip(
                                Icons.access_time,
                                formattedTime,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _pickDateTime,
                            icon: const Icon(Icons.edit_calendar),
                            label: Text(
                              _requiresEndDate
                                  ? "Change Date & Time"
                                  : "Set End Date & Time",
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Recurring Notifications Section
              _buildRecurringNotificationSection(),

              const SizedBox(height: 20),

              // Completion Status
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        _isCompleted
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: _isCompleted ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Mark as completed",
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                      Switch(
                        value: _isCompleted,
                        onChanged: (val) {
                          setState(() {
                            _isCompleted = val;
                          });
                        },
                        activeColor: Colors.green,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Save Button
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_task, size: 24),
                      label: const Text(
                        "Add Task",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _addTask,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedType.color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
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