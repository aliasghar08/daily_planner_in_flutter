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

//   Future<void> _saveChanges() async {
//   if (_isSaving) return;
//   _isSaving = true;

//   try {
//     final user = FirebaseAuth.instance.currentUser;
//     if (user == null) throw Exception("User not signed in");
//     if (widget.task.docId == null) throw Exception("Task ID not found");

//     final now = DateTime.now();
//     final newTitle = _titleController.text.trim();
//     if (newTitle.isEmpty) throw Exception("Task title cannot be empty");

//     final isCompleted = _isCompletedNotifier.value;
//     final selectedDate = _selectedDateNotifier.value;
//     List<DateTime> finalTimes = [..._notificationTimesNotifier.value];

//     // Add fallback notification if none
//     if (!isCompleted && finalTimes.isEmpty) {
//       final fallback = selectedDate.subtract(const Duration(minutes: 15));
//       if (fallback.isAfter(now)) finalTimes.add(fallback);
//     }

//     // Prepare Alarm IDs
//     final oldTimes = widget.task.notificationTimes ?? [];
//     final oldIds = {for (var t in oldTimes) generateNotificationId(widget.task.docId!, t)};
//     final newIds = {for (var t in finalTimes) generateNotificationId(widget.task.docId!, t)};

//     // Cancel and schedule alarms in parallel
//     final cancelFutures = oldIds.difference(newIds).map(NativeAlarmHelper.cancelAlarmById);
//     final scheduleFutures = finalTimes
//         .where((t) => t.isAfter(now) && !oldTimes.any((o) => o.isAtSameMomentAs(t)))
//         .map((t) => NativeAlarmHelper.scheduleAlarmAtTime(
//               id: generateNotificationId(widget.task.docId!, t),
//               title: 'Reminder: $newTitle',
//               body: '$newTitle is due at ${DateFormat.jm().format(selectedDate)}',
//               dateTime: t,
//             ));

//     await Future.wait([...cancelFutures, ...scheduleFutures]);

//     // Prepare Firestore update
//     final updateData = <String, dynamic>{
//       'title': newTitle,
//       'detail': _detailController.text.trim(),
//       'date': Timestamp.fromDate(selectedDate.toUtc()),
//       'isCompleted': isCompleted,
//       'notificationTimes': finalTimes.map((dt) => Timestamp.fromDate(dt.toUtc())).toList(),
//       'editHistory': FieldValue.arrayUnion([
//         {
//           'timestamp': Timestamp.now(),
//           'note': _editNoteController.text.trim().isEmpty
//               ? null
//               : _editNoteController.text.trim(),
//         }
//       ]),
//     };

//     // Task Type Info
//     if (widget.task is DailyTask) updateData['taskType'] = 'DailyTask';
//     if (widget.task is WeeklyTask) updateData['taskType'] = 'WeeklyTask';
//     if (widget.task is MonthlyTask) {
//       updateData['taskType'] = 'MonthlyTask';
//       updateData['dayOfMonth'] = (widget.task as MonthlyTask).dayOfMonth;
//     }

//     // Completion Stamps
//     final currentStamps = widget.task.completionStamps ?? [];
//     final nowStamp = Timestamp.fromDate(now.toUtc());

//     if (widget.task.taskType == 'oneTime') {
//       updateData['completionStamps'] = isCompleted ? [nowStamp] : [];
//     } else if (widget.task.taskType != null) {
//       // Precompute stamps for current period
//       final stampsInPeriod = currentStamps.where((ts) {
//         final dt = ts.toDate().toLocal();
//         if (widget.task.taskType == 'DailyTask') return _isSameDay(dt, now);
//         if (widget.task.taskType == 'WeeklyTask') return _isSameWeek(dt, now);
//         if (widget.task.taskType == 'MonthlyTask') return _isSameMonth(dt, now);
//         return false;
//       }).toList();

//       if (isCompleted && stampsInPeriod.isEmpty) {
//         updateData['completionStamps'] = FieldValue.arrayUnion([nowStamp]);
//       } else if (!isCompleted && stampsInPeriod.isNotEmpty) {
//         updateData['completionStamps'] = FieldValue.arrayRemove(stampsInPeriod);
//       }
//     }

//     await FirebaseFirestore.instance
//         .collection('users')
//         .doc(user.uid)
//         .collection('tasks')
//         .doc(widget.task.docId)
//         .update(updateData);

//     _showSnackBar("✅ Task updated successfully!");
//     if (mounted) Navigator.pop(context, true);
//   } catch (e, stack) {
//     debugPrint("❌ Error updating task: $e\n$stack");
//     _showSnackBar("❌ Failed to update task: $e");
//   } finally {
//     _isSaving = false;
//   }
// }

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
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
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
                decoration: const InputDecoration(labelText: "Title *", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detailController,
                decoration: const InputDecoration(labelText: "Detail", border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<DateTime>(
                valueListenable: _selectedDateNotifier,
                builder: (context, date, _) {
                  final dateStr = DateFormat('EEE, MMM d, yyyy').format(date);
                  final timeStr = DateFormat('h:mm a').format(date);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Date: $dateStr"), Text("Time: $timeStr")]),
                      TextButton.icon(onPressed: _pickDateTime, icon: const Icon(Icons.calendar_today), label: const Text("Change")),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<bool>(
                valueListenable: _isCompletedNotifier,
                builder: (_, val, __) => SwitchListTile(
                  title: const Text("Mark as Completed"),
                  value: val,
                  onChanged: (v) => _isCompletedNotifier.value = v,
                ),
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
              ValueListenableBuilder<List<DateTime>>(
                valueListenable: _notificationTimesNotifier,
                builder: (_, times, __) => ExpansionTile(
                  leading: const Icon(Icons.notifications),
                  title: const Text("Notification Times"),
                  children: [
                    SizedBox(
                      height: times.length > 5 ? 200 : null,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: times.length,
                        itemBuilder: (_, index) {
                          final t = times[index];
                          return ListTile(
                            leading: const Icon(Icons.access_time),
                            title: Text(DateFormat('MMM d, yyyy • h:mm a').format(t)),
                            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => removeNotificationTime(t)),
                          );
                        },
                      ),
                    ),
                    TextButton.icon(onPressed: _pickNotificationTime, icon: const Icon(Icons.add), label: const Text("Add Notification Time")),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: _isSaving
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text("Save Changes"),
                        onPressed: _saveChanges,
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
