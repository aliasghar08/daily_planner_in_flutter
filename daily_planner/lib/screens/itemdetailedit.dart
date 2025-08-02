import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
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
  late DateTime _selectedDate;
  late bool _isCompleted;
  List<DateTime> _notiificationTimes = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _detailController = TextEditingController(text: widget.task.detail);
    _editNoteController = TextEditingController();
    _selectedDate = widget.task.date;
    _isCompleted = widget.task.isCompleted;

    loadNotificationTimes(widget.task).then((times) {
      setState(() {
        _notiificationTimes = times;
      });
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    _editNoteController.dispose();
    super.dispose();
  }

  // Generate unique notification ID based on task ID and notification time
  int generateNotificationId(String taskId, DateTime time) {
    //  return (taskId.hashCode + time.millisecondsSinceEpoch).hashCode.abs();
    return (taskId + time.toIso8601String()).hashCode.abs();
  }

  Future<List<DateTime>> loadNotificationTimes(Task task) async {
    List<DateTime> notificationTimes = [];

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("User not logged in");

      final taskRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(task.docId);

      final snapshot = await taskRef.get();
      final data = snapshot.data();

      if (data != null && data['notificationTimes'] != null) {
        final List<dynamic> rawList = data['notificationTimes'];
        notificationTimes =
            rawList.whereType<Timestamp>().map((ts) => ts.toDate()).toList();
      }
    } catch (e) {
      debugPrint("Error loading Notification Times: $e");
    }

    return notificationTimes;
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
      _showSnackBar("❌ Notification time must be in the future.");
      return;
    }

    if (newNotificationTime.isAfter(_selectedDate)) {
      _showSnackBar("❌ Notification time must be before task time.");
      return;
    }

    // Check for duplicate
    if (_notiificationTimes.any(
      (time) => time.isAtSameMomentAs(newNotificationTime),
    )) {
      _showSnackBar("❌ This notification time is already added.");
      return;
    }

    setState(() {
      _notiificationTimes.add(newNotificationTime);
      _notiificationTimes.sort();
    });
  }

  void removeNotificationTime(DateTime time) {
    setState(() {
      _notiificationTimes.remove(time);
    });
  }

  Future<void> _saveChanges() async {
  if (_isSaving) return;
  setState(() => _isSaving = true);

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("❌ User not signed in.");
      return;
    }

    if (widget.task.docId == null) {
      _showSnackBar("❌ Task ID not found.");
      return;
    }

    final String newTitle = _titleController.text.trim();
    if (newTitle.isEmpty) {
      _showSnackBar("⚠️ Task title cannot be empty.");
      return;
    }

    // Prepare notification times
    List<DateTime> finalNotificationTimes = List.from(_notiificationTimes);
    final now = DateTime.now();

    if (!_isCompleted && finalNotificationTimes.isEmpty) {
      final fallbackTime = _selectedDate.subtract(const Duration(minutes: 15));
      if (fallbackTime.isAfter(now)) {
        finalNotificationTimes.add(fallbackTime);
        finalNotificationTimes.sort();
      }
    }

    // Cancel all existing notifications
    for (final time in widget.task.notificationTimes) {
      final id = generateNotificationId(widget.task.docId!, time);
      await NativeAlarmHelper.cancelAlarmById(id);
    }

    // Schedule new notifications
    if (!_isCompleted) {
      for (final time in finalNotificationTimes) {
        if (time.isAfter(now)) {
          final id = generateNotificationId(widget.task.docId!, time);
          await NativeAlarmHelper.scheduleAlarmAtTime(
            id: id,
            title: 'Reminder: $newTitle',
            body: '$newTitle is due at ${DateFormat.jm().format(_selectedDate)}',
            dateTime: time,
          );
        }
      }
    }

    // Create update data with proper type conversions
    final updateData = {
      'title': newTitle,
      'detail': _detailController.text.trim(),
      'date': Timestamp.fromDate(_selectedDate),
      'isCompleted': _isCompleted,
      'notificationTimes': finalNotificationTimes.map((dt) => Timestamp.fromDate(dt)).toList(),
      'editHistory': FieldValue.arrayUnion([
        {
          'timestamp': Timestamp.now(),
          'note': _editNoteController.text.trim().isEmpty 
              ? null 
              : _editNoteController.text.trim(),
        }
      ]),
    };

    // Handle task type specific fields
    if (widget.task is DailyTask) {
      updateData['type'] = 'DailyTask';
      updateData['taskType'] = 'DailyTask';
    } 
    else if (widget.task is WeeklyTask) {
      updateData['type'] = 'WeeklyTask';
      updateData['taskType'] = 'WeeklyTask';
    }
    else if (widget.task is MonthlyTask) {
      updateData['type'] = 'MonthlyTask';
      updateData['taskType'] = 'MonthlyTask';
      updateData['dayOfMonth'] = (widget.task as MonthlyTask).dayOfMonth;
    }

    debugPrint("Updating task with data: $updateData");

    // Update Firestore document
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .doc(widget.task.docId)
        .update(updateData);

    _showSnackBar("✅ Task updated successfully!");
    if (mounted) Navigator.pop(context, true);

  } catch (e, stackTrace) {
    debugPrint("❌ Error updating task: $e");
    debugPrint("📌 Stack trace: $stackTrace");
    _showSnackBar("❌ Failed to update task: ${e.toString()}");
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final String dateStr = DateFormat('EEE, MMM d, yyyy').format(_selectedDate);
    final String timeStr = DateFormat('h:mm a').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(title: const Text("Edit Task")),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: "Title *",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detailController,
                decoration: const InputDecoration(
                  labelText: "Detail",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text("Date: $dateStr"), Text("Time: $timeStr")],
                  ),
                  TextButton.icon(
                    onPressed: _pickDateTime,
                    icon: const Icon(Icons.calendar_today),
                    label: const Text("Change"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text("Mark as Completed"),
                value: _isCompleted,
                onChanged: (val) => setState(() => _isCompleted = val),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _editNoteController,
                decoration: const InputDecoration(
                  labelText: "Edit Note (optional)",
                  border: OutlineInputBorder(),
                  hintText: "Why did you update this task?",
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              ExpansionTile(
                leading: const Icon(Icons.notifications),
                title: const Text("Notification Times"),
                children: [
                  ..._notiificationTimes.map((date) {
                    final id = generateNotificationId(widget.task.docId!, date);

                    return ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text(
                        DateFormat('MMM d, yyyy • h:mm a').format(date),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => removeNotificationTime(date),
                      ),
                    );
                  }).toList(),
                  TextButton.icon(
                    onPressed: _pickNotificationTime,
                    icon: const Icon(Icons.add),
                    label: const Text("Add Notification Time"),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              Center(
                child: _isSaving
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text("Save Changes"),
                      onPressed: _saveChanges,
                    ),
              ),
                  const SizedBox(height: 24,),
            ],
          ),
        ),
      ),
    );
  }
}
