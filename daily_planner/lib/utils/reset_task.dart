import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

Future<void> resetAllTasksIfNeeded() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final taskCollection = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('tasks');

  try {
    // Try to get data from cache first (works offline)
    final snapshot = await taskCollection.get(const GetOptions(source: Source.cache));
    
    // Process task reset with cached data
    await _processTaskReset(snapshot, taskCollection);
    
    // Try to get server data in background and process if different
    try {
      final serverSnapshot = await taskCollection.get(const GetOptions(source: Source.server));
      if (serverSnapshot.docs.length != snapshot.docs.length) {
        await _processTaskReset(serverSnapshot, taskCollection);
      }
    } catch (e) {
      debugPrint("Server reset check failed (offline): $e");
      // Continue with cached data - this is normal in offline mode
    }
  } catch (e) {
    debugPrint("Error resetting tasks (cache unavailable): $e");
    // If cache is not available, try server but don't block
    _tryServerResetInBackground(taskCollection);
  }
}

Future<void> _processTaskReset(QuerySnapshot snapshot, CollectionReference taskCollection) async {
  final now = DateTime.now();
  
  for (final doc in snapshot.docs) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) continue;

    try {
      Task task = parseTaskFromMap(data, docId: doc.id);
      Map<String, dynamic> updates = {};

      if (task is DailyTask && task.shouldResetToday()) {
        if (_shouldSkipResetDueToRecentCompletion(task.completedAt, now)) {
          continue;
        }
        updates = _prepareResetUpdates(task);
      } else if (task is WeeklyTask && task.shouldResetThisWeek()) {
        if (_shouldSkipResetDueToRecentCompletion(task.completedAt, now)) {
          continue;
        }
        updates = _prepareResetUpdates(task);
      } else if (task is MonthlyTask && task.shouldResetThisMonth()) {
        if (_shouldSkipResetDueToRecentCompletion(task.completedAt, now)) {
          continue;
        }
        updates = _prepareResetUpdates(task);
      }

      if (updates.isNotEmpty) {
        // Use set with merge: true to avoid overwriting other fields
        await doc.reference.set(updates, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error processing task ${doc.id}: $e");
    }
  }
}

bool _shouldSkipResetDueToRecentCompletion(DateTime? completedAt, DateTime now) {
  if (completedAt == null) return false;
  
  // Convert both times to UTC for comparison
  final completedAtUtc = completedAt.toUtc();
  final nowUtc = now.toUtc();
  
  return completedAtUtc.day == nowUtc.day &&
         completedAtUtc.month == nowUtc.month &&
         completedAtUtc.year == nowUtc.year;
}

Map<String, dynamic> _prepareResetUpdates(Task task) {
  final updates = <String, dynamic>{
    'isCompleted': false,
    'completedAt': null,
  };

  // Preserve completion stamps
  if (task.completedAt != null &&
      !task.completionStamps!.any((ts) => ts.isAtSameMomentAs(task.completedAt!))) {
    final updatedStamps = [...?task.completionStamps, task.completedAt!];
    updates['completionStamps'] = updatedStamps.map((dt) => dt.toIso8601String()).toList();
  }

  return updates;
}

void _tryServerResetInBackground(CollectionReference taskCollection) {
  // This runs in background and won't block the app startup
  taskCollection.get(const GetOptions(source: Source.server)).then((serverSnapshot) {
    _processTaskReset(serverSnapshot, taskCollection);
  }).catchError((e) {
    debugPrint("Background server reset failed: $e");
  });
}