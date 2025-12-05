import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class main_widgets {
  Widget _buildStreakChart(List<DateTime> stamps, Duration recurrence) {
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

    return BarChart(
      BarChartData(
        barGroups: List.generate(7, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: data[i],
                color: data[i] > 0 ? Colors.blue[300] : Colors.grey[300],
                width: 20,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    labels[value.toInt()],
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                );
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
   

   

}