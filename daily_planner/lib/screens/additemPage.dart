import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
}

class AddTaskPage extends StatefulWidget {
  const AddTaskPage({super.key});

  @override
  State<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends State<AddTaskPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TaskType _selectedType = TaskType.oneTime;
  bool _isCompleted = false;
  bool _isSaving = false;
  List<DateTime> _notificationTimes = [];

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
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

  String formatDate(DateTime date) => DateFormat.yMMMd().format(date);
  String formatTime(DateTime date) => DateFormat.jm().format(date);

  // Generate unique notification ID based on task ID and notification time
  int _generateNotificationId(String taskId, DateTime notificationTime) {
    // return (taskId.hashCode + notificationTime.toIso8601String()).abs();
    return (taskId + notificationTime.toIso8601String()).hashCode.abs();
  }

  Future<void> _addTask() async {
    final title = _titleController.text.trim();
    final detail = _detailController.text.trim();
    final now = DateTime.now();

    if (title.isEmpty) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Title cannot be empty.")),
      );
      return;
    }

    if (_selectedDate.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Please choose a future date and time."),
        ),
      );
      return;
    }

    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ No internet connection. Please try again later."),
          ),
        );
        return;
      }

      if (_isCompleted && _selectedDate.isAfter(now)) {
        final confirm = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text("Mark as Completed?"),
                content: const Text(
                  "This task is set in the future. Are you sure you want to mark it as completed?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("No"),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("Yes"),
                  ),
                ],
              ),
        );
        if (confirm != true) {
          setState(() {
            _isSaving = false;
          });
          return;
        }
      }

      // final uid = FirebaseAuth.instance.currentUser!.uid;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ You must be logged in to add tasks."),
          ),
        );
        setState(() {
          _isSaving = false;
        });
        return;
      }
      final uid = user.uid;

      final newTaskRef =
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('tasks')
              .doc();

      final taskId = now.millisecondsSinceEpoch;
      final notificationId = taskId % 100000;

      Task newTask;

      switch (_selectedType) {
        case TaskType.oneTime:
          newTask = Task(
            docId: newTaskRef.id,
            id: taskId,
            title: title,
            detail: detail,
            date: _selectedDate,
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
            id: taskId,
            title: title,
            detail: detail,
            date: _selectedDate,
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
            id: taskId,
            title: title,
            detail: detail,
            date: _selectedDate,
            isCompleted: _isCompleted,
            createdAt: now,
            completedAt: _isCompleted ? now : null,
            completionStamps: _isCompleted ? [now] : [],
            notificationTimes: _notificationTimes,
          );
          break;

        case TaskType.monthly:
          final dayOfMonth = _selectedDate.day;
          newTask = MonthlyTask(
            docId: newTaskRef.id,
            id: taskId,
            title: title,
            detail: detail,
            date: _selectedDate,
            isCompleted: _isCompleted,
            createdAt: now,
            completedAt: _isCompleted ? now : null,
            dayOfMonth: dayOfMonth,
            completionStamps: _isCompleted ? [now] : [],
            notificationTimes:
                _notificationTimes, // Fixed typo in parameter name
          );
          break;
      }

      await newTaskRef.set(newTask.toMap());

      if (!_isCompleted) {
        if (_notificationTimes.isEmpty) {
          final fallbackTime = newTask.date.subtract(
            const Duration(minutes: 15),
          );
          if (fallbackTime.isAfter(now)) {
            final fallbackId = _generateNotificationId(
              newTaskRef.id,
              fallbackTime,
            );
            await NativeAlarmHelper.scheduleAlarmAtTime(
              id: fallbackId,
              title: 'Upcoming Task',
              body:
                  '${newTask.title} is due at ${DateFormat.jm().format(newTask.date)}',
              dateTime: fallbackTime,
            );

            _notificationTimes.add(fallbackTime);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "✅ Notification scheduled at ${DateFormat.yMd().add_jm().format(fallbackTime)} (ID: $fallbackId)",
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "ℹ️ Default notification time too close. No notification scheduled.",
                ),
              ),
            );
          }
        } else {
          int scheduledCount = 0;
          for (final notiTime in _notificationTimes) {
            if (notiTime.isAfter(now)) {
              final notiId = _generateNotificationId(newTaskRef.id, notiTime);
              await NativeAlarmHelper.scheduleAlarmAtTime(
                id: notiId,
                title: 'Task Reminder',
                body:
                    '${newTask.title} is due at ${DateFormat.jm().format(newTask.date)}',
                dateTime: notiTime,
              );
              scheduledCount++;
            }
          }

          if (scheduledCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("✅ $scheduledCount notification(s) scheduled."),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("ℹ️ No future notifications scheduled."),
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "ℹ️ Task is marked completed. No notification scheduled.",
            ),
          ),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Task '${newTask.title}' added.")),
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e, stack) {
      debugPrint("❌ Error adding task: $e");
      debugPrint("Stack trace:\n$stack");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Failed to add task. Please try again."),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _pickNotificationTime() async {
    final now = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now,
      lastDate: _selectedDate,
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
        ),
      );
      return;
    }

    if (newNotificationTime.isAfter(_selectedDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Notification time must be before task time."),
        ),
      );
      return;
    }

    // Check for duplicate notification times
    if (_notificationTimes.any(
      (time) => time.isAtSameMomentAs(newNotificationTime),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ This notification time is already added."),
        ),
      );
      return;
    }

    setState(() {
      _notificationTimes.add(newNotificationTime);
      _notificationTimes.sort();
    });
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = formatDate(_selectedDate);
    final formattedTime = formatTime(_selectedDate);

    return Scaffold(
      appBar: AppBar(title: const Text("Add Task")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: "Title"),
              ),
              TextField(
                controller: _detailController,
                decoration: const InputDecoration(labelText: "Detail"),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskType>(
                value: _selectedType,
                decoration: const InputDecoration(labelText: "Task Type"),
                items:
                    TaskType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      );
                    }).toList(),
                onChanged: (type) {
                  if (type != null) {
                    setState(() {
                      _selectedType = type;
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              if (_selectedType == TaskType.weekly)
                const Text("📆 This task will repeat weekly."),
              if (_selectedType == TaskType.monthly)
                const Text("📅 This task will repeat monthly."),
              if (_selectedType == TaskType.daily)
                const Text("🔁 This task will repeat daily."),
              if (_selectedType == TaskType.oneTime)
                const Text("📌 This task will occur only once."),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(child: Text("Date: $formattedDate")),
                  Expanded(child: Text("Time: $formattedTime")),
                  TextButton(
                    onPressed: _pickDateTime,
                    child: const Text("Change"),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Row(
                children: [
                  const Text("🔔 Notifications:"),
                  TextButton(
                    onPressed: _pickNotificationTime,
                    child: const Text("Add Notification Time"),
                  ),
                ],
              ),
              if (_notificationTimes.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      _notificationTimes.map((time) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            "• ${DateFormat.yMd().add_jm().format(time)}",
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _notificationTimes.remove(time);
                              });
                            },
                          ),
                        );
                      }).toList(),
                ),

              SwitchListTile(
                title: const Text("Completed"),
                value: _isCompleted,
                onChanged: (val) {
                  setState(() {
                    _isCompleted = val;
                  });
                },
              ),
              const SizedBox(height: 20),
              _isSaving
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("Add Task"),
                    onPressed: _addTask,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
