import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> simulateYesterdayCompletion(String taskId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final doc = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('tasks')
      .doc(taskId);

  await doc.update({
    'completedAt': DateTime.now().subtract(Duration(days: 1)).toIso8601String(),
    'isCompleted': true,
  });
}
