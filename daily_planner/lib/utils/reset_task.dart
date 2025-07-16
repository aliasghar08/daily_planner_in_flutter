import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> resetAllTasksIfNeeded() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final taskCollection = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('tasks');

  final snapshot = await taskCollection.get();

  for (final doc in snapshot.docs) {
    final data = doc.data();
    Task task = parseTaskFromMap(data, docId: doc.id);

    Map<String, dynamic> updates = {};

    if (task is DailyTask && task.shouldResetToday()) {
      // 👇 Check if task was completed today; if yes, skip resetting
      if (task.completedAt != null &&
          task.completedAt!.day == DateTime.now().day &&
          task.completedAt!.month == DateTime.now().month &&
          task.completedAt!.year == DateTime.now().year) {
        continue; // Don't reset
        
      }
      print(task.shouldResetToday());

      // ✅ Preserve completedAt before reset
      if (task.completedAt != null &&
          !task.completionStamps.any(
            (ts) => ts.isAtSameMomentAs(task.completedAt!),
          )) {
        task.completionStamps.add(task.completedAt!);
        updates['completionStamps'] =
            task.completionStamps.map((dt) => dt.toIso8601String()).toList();
      }
      updates['isCompleted'] = false;
      updates['completedAt'] = null;
    } else if (task is WeeklyTask && task.shouldResetThisWeek()) {
      // 👇 Check if task was completed this week; if yes, skip resetting
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      if (task.completedAt != null &&
          task.completedAt!.isAfter(startOfWeek) &&
          task.completedAt!.isBefore(endOfWeek.add(const Duration(days: 1)))) {
        continue;
      }

      if (task.completedAt != null &&
          !task.completionStamps.any(
            (ts) => ts.isAtSameMomentAs(task.completedAt!),
          )) {
        task.completionStamps.add(task.completedAt!);
        updates['completionStamps'] =
            task.completionStamps.map((dt) => dt.toIso8601String()).toList();
      }
      updates['isCompleted'] = false;
      updates['completedAt'] = null;
    } else if (task is MonthlyTask && task.shouldResetThisMonth()) {
      // 👇 Check if task was completed this month; if yes, skip resetting
      final now = DateTime.now();
      if (task.completedAt != null &&
          task.completedAt!.month == now.month &&
          task.completedAt!.year == now.year) {
        continue;
      }

      if (task.completedAt != null &&
          !task.completionStamps.any(
            (ts) => ts.isAtSameMomentAs(task.completedAt!),
          )) {
        task.completionStamps.add(task.completedAt!);
        updates['completionStamps'] =
            task.completionStamps.map((dt) => dt.toIso8601String()).toList();
      }
      updates['isCompleted'] = false;
      updates['completedAt'] = null;
    }

    if (updates.isNotEmpty) {
      await doc.reference.update(updates);
    }
  }
}