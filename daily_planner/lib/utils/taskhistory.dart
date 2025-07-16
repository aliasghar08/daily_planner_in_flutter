import 'package:daily_planner/utils/catalog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TaskHistoryWidget extends StatelessWidget {
  final Task task;

  const TaskHistoryWidget({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final creation = DateFormat('MMM d, yyyy – h:mm a').format(task.createdAt);
    final daysAgo = DateTime.now().difference(task.createdAt).inDays;
    final editHistory = task.editHistory;
    final editCount = editHistory.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.blueGrey.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("📅 Created: $creation"),
            Text("✏️ Edited: $editCount time${editCount == 1 ? '' : 's'}"),
            Text("⏳ $daysAgo days ago"),
            const SizedBox(height: 10),
            if (editHistory.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("🕒 Edit History:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...editHistory.map((edit) {
                    final formatted = DateFormat('MMM d, yyyy – h:mm a').format(edit.timestamp);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text("• $formatted${edit.note != null ? " — ${edit.note}" : ""}"),
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
