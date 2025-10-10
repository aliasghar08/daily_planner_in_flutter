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

  final ValueNotifier<DateTime> _selectedDateNotifier = ValueNotifier(DateTime.now());
  final ValueNotifier<bool> _isCompletedNotifier = ValueNotifier(false);
  final ValueNotifier<List<DateTime>> _notificationTimesNotifier = ValueNotifier([]);

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _detailController = TextEditingController(text: widget.task.detail);
    _editNoteController = TextEditingController();

    _selectedDateNotifier.value = widget.task.date;
    _isCompletedNotifier.value = widget.task.isCompleted;

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
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateNotifier.value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateNotifier.value),
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

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: _selectedDateNotifier.value,
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
    if (newTime.isAfter(_selectedDateNotifier.value)) {
      _showSnackBar("❌ Notification must be before task time");
      return;
    }
    if (_notificationTimesNotifier.value.any((t) => t.isAtSameMomentAs(newTime))) {
      _showSnackBar("❌ Notification already added");
      return;
    }

    _notificationTimesNotifier.value = [..._notificationTimesNotifier.value, newTime]..sort();
  }

  void removeNotificationTime(DateTime time) {
    _notificationTimesNotifier.value =
        _notificationTimesNotifier.value.where((t) => t != time).toList();
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isSameWeek(DateTime a, DateTime b) =>
      a.subtract(Duration(days: a.weekday - 1)).difference(b.subtract(Duration(days: b.weekday - 1))).inDays == 0;
  bool _isSameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

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
      final selectedDate = _selectedDateNotifier.value;
      List<DateTime> finalTimes = [..._notificationTimesNotifier.value];

      // Add fallback notification if none
      if (!isCompleted && finalTimes.isEmpty) {
        final fallback = selectedDate.subtract(const Duration(minutes: 15));
        if (fallback.isAfter(now)) finalTimes.add(fallback);
      }

      // Prepare Alarm IDs
      final oldTimes = widget.task.notificationTimes ?? [];
      final oldIds = {for (var t in oldTimes) generateNotificationId(widget.task.docId!, t)};
      final newIds = {for (var t in finalTimes) generateNotificationId(widget.task.docId!, t)};

      // Cancel and schedule alarms
      final cancelFutures = oldIds.difference(newIds).map(NativeAlarmHelper.cancelAlarmById);
      final scheduleFutures = finalTimes
          .where((t) => t.isAfter(now) && !oldTimes.any((o) => o.isAtSameMomentAs(t)))
          .map((t) => NativeAlarmHelper.scheduleAlarmAtTime(
                id: generateNotificationId(widget.task.docId!, t),
                title: 'Reminder: $newTitle',
                body: '$newTitle is due at ${DateFormat.jm().format(selectedDate)}',
                dateTime: t,
              ));

      await Future.wait([...cancelFutures, ...scheduleFutures]);

      // Prepare Firestore update
      final updateData = <String, dynamic>{
        'title': newTitle,
        'detail': _detailController.text.trim(),
        'date': Timestamp.fromDate(selectedDate.toUtc()),
        'isCompleted': isCompleted,
        'notificationTimes': finalTimes.map((dt) => Timestamp.fromDate(dt.toUtc())).toList(),
        'editHistory': FieldValue.arrayUnion([
          {
            'timestamp': Timestamp.now(),
            'note': _editNoteController.text.trim().isEmpty
                ? null
                : _editNoteController.text.trim(),
          }
        ]),
      };

      // Task Type Info
      if (widget.task is DailyTask) updateData['taskType'] = 'DailyTask';
      if (widget.task is WeeklyTask) updateData['taskType'] = 'WeeklyTask';
      if (widget.task is MonthlyTask) {
        updateData['taskType'] = 'MonthlyTask';
        updateData['dayOfMonth'] = (widget.task as MonthlyTask).dayOfMonth;
      }

      // Completion Stamps
      final currentStamps = widget.task.completionStamps ?? [];
      final nowStamp = Timestamp.fromDate(now.toUtc());

      if (widget.task.taskType == 'oneTime') {
        updateData['completionStamps'] = isCompleted ? [nowStamp] : [];
      } else if (widget.task.taskType != null) {
        final stampsInPeriod = currentStamps.where((ts) {
          final dt = ts.toDate().toLocal();
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
      _showSnackBar("❌ Failed to update task: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: message.contains("❌") ? Colors.red : Colors.green,
      ));
  }

  String _getTaskTypeLabel() {
    final taskType = widget.task.taskType;
    switch (taskType) {
      case 'oneTime':
        return 'One-Time Task';
      case 'daily':
        return 'Daily Task';
      case 'weekly':
        return 'Weekly Task';
      case 'monthly':
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
      case 'daily':
        return Icons.loop;
      case 'weekly':
        return Icons.calendar_today;
      case 'monthly':
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
      case 'daily':
        return Colors.green;
      case 'weekly':
        return Colors.orange;
      case 'monthly':
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
                        child: Icon(_getTaskTypeIcon(), color: _getTaskTypeColor()),
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

              // Date & Time Selection
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Date & Time",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder<DateTime>(
                        valueListenable: _selectedDateNotifier,
                        builder: (context, date, _) {
                          return Row(
                            children: [
                              Expanded(
                                child: _buildInfoChip(
                                  Icons.calendar_today,
                                  DateFormat('EEE, MMM d, yyyy').format(date),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildInfoChip(
                                  Icons.access_time,
                                  DateFormat('h:mm a').format(date),
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
                          label: const Text("Change Date & Time"),
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
                            isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isCompleted ? Colors.green : Colors.grey,
                            size: 28,
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Mark as completed",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
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
                                  physics: times.length > 3 ? null : const NeverScrollableScrollPhysics(),
                                  itemCount: times.length,
                                  itemBuilder: (_, index) {
                                    final time = times[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      elevation: 1,
                                      child: ListTile(
                                        leading: Icon(Icons.notifications_active, color: _getTaskTypeColor()),
                                        title: Text(
                                          DateFormat('MMM d, yyyy').format(time),
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        subtitle: Text(DateFormat('h:mm a').format(time)),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => removeNotificationTime(time),
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
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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