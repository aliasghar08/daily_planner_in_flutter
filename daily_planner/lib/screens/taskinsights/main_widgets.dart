import 'package:daily_planner/widgets/charts/custom_charts.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MainWidgets {
  static Widget buildStreakChart(List<DateTime> stamps, Duration recurrence) {
    final now = DateTime.now();

    // Prepare labels for last 7 days
    final labels = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return DateFormat.E().format(day);
    });

    // Prepare completion data
    final data = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return stamps.any(
            (s) =>
                s.year == day.year && s.month == day.month && s.day == day.day,
          )
          ? 1.0
          : 0.0;
    });

    return CustomBarChart(
      barGroups: List.generate(7, (i) {
        return CustomBarGroupData(
          x: i,
          label: labels[i],
          barRods: [
            CustomBarRodData(
              toY: data[i],
              color: data[i] > 0 ? Colors.blue[300]! : Colors.grey[300]!,
              width: 20,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        );
      }),
    );
  }
}