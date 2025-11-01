import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/push_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:intl/intl.dart';

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

  final ValueNotifier<DateTime?> _selectedDateNotifier = ValueNotifier<DateTime?>(null); // ✅ Made nullable
  final ValueNotifier<bool> _isCompletedNotifier = ValueNotifier(false);
  final ValueNotifier<List<DateTime>> _notificationTimesNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _hasEndDateNotifier = ValueNotifier(true); // ✅ New: Toggle for end date

  bool _isSaving = false;
  late List<DateTime> _oldNotificationTimes;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _detailController = TextEditingController(text: widget.task.detail);
    _editNoteController = TextEditingController();

    _selectedDateNotifier.value = widget.task.date; // ✅ Can be null now
    _isCompletedNotifier.value = widget.task.isCompleted;
    _oldNotificationTimes = widget.task.notificationTimes ?? [];
    
    // ✅ Initialize hasEndDate based on whether task has a date
    _hasEndDateNotifier.value = widget.task.date != null;

    loadNotificationTimes(widget.task).then((times) {
      _notificationTimesNotifier.value = times;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    _editNoteController.dispose();
    _selectedDateNotifier.dispose();
    _isCompletedNotifier.dispose();
    _notificationTimesNotifier.dispose();
    _hasEndDateNotifier.dispose(); // ✅ Dispose the new notifier
    super.dispose();
  }

  int generateNotificationId(String taskId, DateTime time) =>
      (taskId + time.toIso8601String()).hashCode.abs();

  Future<List<DateTime>> loadNotificationTimes(Task task) async {
    List<DateTime> notificationTimes = [];
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return notificationTimes;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(task.docId)
          .get();

      final data = snapshot.data();
      if (data != null && data['notificationTimes'] != null) {
        final List<dynamic> rawList = data['notificationTimes'];
        notificationTimes = rawList
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

  Future<void> _pickNotificationTime() async {
    final now = DateTime.now();
    final taskDate = _selectedDateNotifier.value;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: taskDate ?? DateTime(2100), // ✅ Handle null task date
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
    
    // ✅ Only check against task date if it exists
    if (taskDate != null && newTime.isAfter(taskDate)) {
      _showSnackBar("❌ Notification must be before task time");
      return;
    }
    
    if (_notificationTimesNotifier.value.any((t) => t.isAtSameMomentAs(newTime))) {
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
    return taskType == 'DailyTask' || taskType == 'WeeklyTask' || taskType == 'MonthlyTask';
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
      final selectedDate = hasEndDate ? _selectedDateNotifier.value : null; // ✅ Can be null
      List<DateTime> finalTimes = [..._notificationTimesNotifier.value];

      // Add fallback notification if none and task has end date
      if (!isCompleted && finalTimes.isEmpty && selectedDate != null) {
        final fallback = selectedDate.subtract(const Duration(minutes: 15));
        if (fallback.isAfter(now)) finalTimes.add(fallback);
      }

      // Prepare Alarm IDs
      final oldIds = {
        for (var t in _oldNotificationTimes)
          generateNotificationId(widget.task.docId!, t),
      };
      final newIds = {
        for (var t in finalTimes)
          generateNotificationId(widget.task.docId!, t),
      };

      // Cancel removed notifications
      final removedIds = oldIds.difference(newIds);
      for (final id in removedIds) {
        await PushNotifications().cancelNotification(id);
      }

      // Schedule new notifications
      for (final time in finalTimes) {
        if (time.isAfter(now) &&
            !_oldNotificationTimes.any((oldTime) => oldTime.isAtSameMomentAs(time))) {
          await PushNotifications().scheduleNotification(
            id: generateNotificationId(widget.task.docId!, time),
            title: 'Reminder: $newTitle',
            body: selectedDate != null 
                ? '$newTitle is due at ${DateFormat.jm().format(selectedDate)}'
                : '$newTitle reminder', // ✅ Different body for no end date
            scheduledTime: time,
            payload: selectedDate != null
                ? "This notification is due at ${DateFormat.jm().format(selectedDate)}"
                : "This is a reminder for your recurring task",
          );
        }
      }

      // Prepare Firestore update
      final updateData = <String, dynamic>{
        'title': newTitle,
        'detail': _detailController.text.trim(),
        'isCompleted': isCompleted,
        'notificationTimes':
            finalTimes.map((dt) => Timestamp.fromDate(dt.toUtc())).toList(),
      };

      // ✅ Only add date if it exists
      if (selectedDate != null) {
        updateData['date'] = Timestamp.fromDate(selectedDate.toUtc());
      } else {
        updateData['date'] = null; // ✅ Explicitly set to null for no end date
      }

      // Add edit history if there's a note
      final editNote = _editNoteController.text.trim();
      if (editNote.isNotEmpty) {
        updateData['editHistory'] = FieldValue.arrayUnion([
          {
            'timestamp': Timestamp.now(),
            'note': editNote,
          },
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
        final stampsInPeriod = currentStamps.where((ts) {
          final dt = ts.toLocal();
          if (widget.task.taskType == 'DailyTask') return _isSameDay(dt, now);
          if (widget.task.taskType == 'WeeklyTask') return _isSameWeek(dt, now);
          if (widget.task.taskType == 'MonthlyTask') return _isSameMonth(dt, now);
          return false;
        }).toList();

        if (isCompleted && stampsInPeriod.isEmpty) {
          updateData['completionStamps'] = FieldValue.arrayUnion([nowStamp]);
        } else if (!isCompleted && stampsInPeriod.isNotEmpty) {
          updateData['completionStamps'] = FieldValue.arrayRemove(stampsInPeriod);
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(widget.task.docId)
          .update(updateData);

      _showSnackBar("✅ Task updated successfully!");
      if (mounted) Navigator.pop(context, true);
    } catch (e, stack) {
      debugPrint("❌ Error updating task: $e\n$stack");
      _showSnackBar("❌ Failed to update task: ${e.toString()}");
    } finally {
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

              // ✅ NEW: End Date Toggle for recurring tasks
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
                              builder: (_, hasEndDate, __) => Icon(
                                hasEndDate ? Icons.event_available : Icons.event_busy,
                                color: hasEndDate ? Colors.green : Colors.grey,
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
                              builder: (_, value, __) => Switch(
                                value: value,
                                onChanged: (val) {
                                  _hasEndDateNotifier.value = val;
                                  if (!val) {
                                    // When disabling end date, clear the date
                                    _selectedDateNotifier.value = null;
                                  } else {
                                    // When enabling end date, set to current date if null
                                    _selectedDateNotifier.value ??= DateTime.now();
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
                                          ? DateFormat('EEE, MMM d, yyyy').format(date)
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
                                padding: const EdgeInsets.symmetric(vertical: 12),
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
                        builder: (_, value, __) => Switch(
                          value: value,
                          onChanged: (val) => _isCompletedNotifier.value = val,
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
                      ValueListenableBuilder<List<DateTime>>(
                        valueListenable: _notificationTimesNotifier,
                        builder: (_, times, __) {
                          if (times.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: Text(
                                  "No notifications set",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: [
                              SizedBox(
                                height: times.length > 3 ? 200 : null,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  physics: times.length > 3
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
                                          onPressed: () =>
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
                        },
                      ),
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