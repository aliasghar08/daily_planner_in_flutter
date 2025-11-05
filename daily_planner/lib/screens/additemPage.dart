import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:daily_planner/main.dart';
import 'package:daily_planner/utils/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:intl/intl.dart';

enum TaskType { oneTime, daily, weekly, monthly }

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
  DateTime? _selectedDate; // ✅ Made nullable
  TaskType _selectedType = TaskType.oneTime;
  bool _isCompleted = false;
  bool _isSaving = false;
  bool _hasEndDate = true; // ✅ New: Toggle for end date
  List<DateTime> _notificationTimes = [];

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

  String formatDate(DateTime? date) => date != null ? DateFormat.yMMMd().format(date) : "Not set";
  String formatTime(DateTime? date) => date != null ? DateFormat.jm().format(date) : "Not set";

  // ✅ Check if task type supports no end date
  bool get _supportsNoEndDate {
    return _selectedType == TaskType.daily || 
           _selectedType == TaskType.weekly || 
           _selectedType == TaskType.monthly;
  }

  // ✅ Check if task type requires end date
  bool get _requiresEndDate {
    return _selectedType == TaskType.oneTime;
  }

  // 🚀 OPTIMIZED: Schedule notifications asynchronously without blocking UI
  Future<void> _scheduleNotifications(String taskId, String title, DateTime? taskDate) async {
    final now = DateTime.now();
    int scheduledCount = 0;

    // Schedule notifications asynchronously without waiting for each one
    final notificationFutures = _notificationTimes.where((notificationTime) => 
      notificationTime.isAfter(now)
    ).map((notificationTime) async {
      try {
        final notificationTimeUtc = notificationTime.toUtc();
        
        await NotificationService().scheduleTaskNotification(
          context: context, 
          taskId: taskId,
          title: 'Task Reminder: $title',
          body: taskDate != null 
              ? '$title is due at ${DateFormat.jm().format(taskDate)}'
              : '$title reminder',
          scheduledTimeUtc: notificationTimeUtc,
          payload: {
            'taskId': taskId,
            'type': 'task_reminder',
            'taskTitle': title,
            'dueDate': taskDate?.toIso8601String(),
          },
          isAlarm: true,
        );
        
        scheduledCount++;
        debugPrint("✅ Scheduled notification for: $notificationTime");
      } catch (e) {
        debugPrint("❌ Failed to schedule notification: $e");
      }
    }).toList();

    // Wait for all notifications to be scheduled, but don't block the main task creation
    if (notificationFutures.isNotEmpty) {
      await Future.wait(notificationFutures);
    }

    // Show success message only if we actually scheduled something
    if (scheduledCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ $scheduledCount notification(s) scheduled."),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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

    // ✅ Validation for one-time tasks (require end date)
    if (_requiresEndDate && _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ One-time tasks require an end date."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // ✅ Validation for date if set
    if (_selectedDate != null && _selectedDate!.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Please choose a future date and time."),
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
      final newTaskRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc();

      Task newTask;

      // ✅ Use _hasEndDate for recurring tasks to determine if date should be null
      final DateTime? taskDate = _requiresEndDate ? _selectedDate : (_hasEndDate ? _selectedDate : null);

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
            notificationTimes: _notificationTimes,
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
            notificationTimes: _notificationTimes,
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
            notificationTimes: _notificationTimes,
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
            notificationTimes: _notificationTimes,
          );
          break;
      }

      debugPrint("Creating task of type: ${_selectedType.name} - ${newTask.runtimeType}");

      // 🚀 FIRST: Save the task to Firestore immediately
      await newTaskRef.set(newTask.toMap());
      debugPrint("✅ Task '$title' successfully added to Firestore");

      // 🚀 SECOND: Show immediate success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Task '$title' added successfully!"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 🚀 THIRD: Navigate back immediately without waiting for notifications
      if (mounted) {
        Navigator.pop(context, true);
      }

      // 🚀 FOURTH: Schedule notifications in the background (after navigation)
      if (_notificationTimes.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scheduleNotifications(newTaskRef.id, title, taskDate);
        });
      }

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
    // 🚀 REMOVED: Don't set _isSaving to false here since we navigated away
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
                        items: TaskType.values.map((type) {
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
                              _hasEndDate ? Icons.event_available : Icons.event_busy,
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
                            label: Text(_requiresEndDate 
                                ? "Change Date & Time" 
                                : "Set End Date & Time"),
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

              // Notifications Section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Notifications",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                          children: _notificationTimes.map((time) {
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
                          label: const Text("Add Notification"),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

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