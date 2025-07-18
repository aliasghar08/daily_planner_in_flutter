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

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _detailController = TextEditingController(text: widget.task.detail);
    _editNoteController = TextEditingController();
    _selectedDate = widget.task.date;
    _isCompleted = widget.task.isCompleted;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    _editNoteController.dispose();
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

  Future<void> _saveChanges() async {
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

    if (_selectedDate.isBefore(DateTime.now())) {
      _showSnackBar("⚠️ Please choose a future date and time.");
      return;
    }

    if (_isCompleted && _selectedDate.isAfter(DateTime.now())) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Mark as Completed?"),
          content: const Text(
            "This task is still scheduled for the future. Are you sure you want to mark it as completed?",
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
      if (confirm != true) return;
    }

    final updatedTask = widget.task.copyWith(
      title: newTitle,
      detail: _detailController.text.trim(),
      date: _selectedDate,
      isCompleted: _isCompleted,
      editHistory: [
        ...widget.task.editHistory,
        TaskEdit(
          timestamp: DateTime.now(),
          note: _editNoteController.text.trim().isEmpty
              ? null
              : _editNoteController.text.trim(),
        ),
      ],
    );

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(updatedTask.docId)
          .update(updatedTask.toMap());

      final int notificationId = updatedTask.id.hashCode & 0x7FFFFFFF;
      await NativeAlarmHelper.cancelAlarmById(notificationId);

      final DateTime notificationTime = updatedTask.date.subtract(
        const Duration(minutes: 15),
      );

      if (!updatedTask.isCompleted &&
          notificationTime.isAfter(DateTime.now())) {
        await NativeAlarmHelper.scheduleAlarmAtTime(
          id: updatedTask.id,
          title: 'Reminder: ${updatedTask.title}',
          body:
              '${updatedTask.title} is due at ${DateFormat.jm().format(updatedTask.date)}',
          dateTime: updatedTask.date,
        );

        _showSnackBar(
          "✅ Notification scheduled at ${DateFormat.yMd().add_jm().format(notificationTime)}",
        );
      } else if (updatedTask.isCompleted) {
        _showSnackBar(
          "✔️ Task marked as completed, no notification scheduled.",
        );
      } else {
        _showSnackBar("⏰ Too late to schedule notification.");
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint("❌ Error updating task: $e");
      _showSnackBar("❌ Failed to update task. Try again.");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String dateStr =
        DateFormat('EEE, MMM d, yyyy').format(_selectedDate);
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
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("Save Changes"),
                onPressed: _saveChanges,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
