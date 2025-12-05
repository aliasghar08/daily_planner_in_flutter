import 'dart:math';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

class HelperFunctions {
  static Map<String, int> calculateStreak(
    List<DateTime> stamps,
    Duration recurrence,
  ) {
    if (stamps.isEmpty) return {'current': 0, 'longest': 0};

    final normalizedStamps =
        stamps.map((d) => DateTime(d.year, d.month, d.day)).toList();
    normalizedStamps.sort();

    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);

    int currentStreak = 0;
    int longestStreak = 0;
    int tempStreak = 1;

    for (int i = 1; i < normalizedStamps.length; i++) {
      final prev = normalizedStamps[i - 1];
      final current = normalizedStamps[i];
      final diff = current.difference(prev).inDays;

      if (diff == recurrence.inDays) {
        tempStreak++;
      } else if (diff > recurrence.inDays) {
        longestStreak = max(longestStreak, tempStreak);
        tempStreak = 1;
      }
    }
    longestStreak = max(longestStreak, tempStreak);

    if (normalizedStamps.contains(todayNormalized)) {
      currentStreak = 1;
      DateTime checkDate = todayNormalized.subtract(recurrence);

      while (normalizedStamps.contains(checkDate)) {
        currentStreak++;
        checkDate = checkDate.subtract(recurrence);
      }
    } else if (normalizedStamps.isNotEmpty) {
      DateTime lastDate = normalizedStamps.last;
      DateTime checkDate = lastDate;
      currentStreak = 1;

      while (normalizedStamps.contains(checkDate.subtract(recurrence))) {
        currentStreak++;
        checkDate = checkDate.subtract(recurrence);
      }

      if (lastDate.difference(todayNormalized).inDays > recurrence.inDays) {
        currentStreak = 0;
      }
    }

    return {'current': currentStreak, 'longest': longestStreak};
  }

  static Map<String, dynamic> calculateTimeStats(
    BuildContext context,
    List<DateTime> stamps,
    List<DateTime> notificationTimes,
  ) {
    if (stamps.isEmpty) return {};

    final totalMinutes = stamps.fold(
      0,
      (sum, stamp) => sum + stamp.hour * 60 + stamp.minute,
    );
    final avgMinutes = totalMinutes ~/ stamps.length;
    final avgTime = TimeOfDay(hour: avgMinutes ~/ 60, minute: avgMinutes % 60);

    int onTimeCount = 0;
    if (notificationTimes.isNotEmpty) {
      final scheduledMinutesList =
          notificationTimes.map((time) => time.hour * 60 + time.minute).toList();

      for (final stamp in stamps) {
        final stampMinutes = stamp.hour * 60 + stamp.minute;
        for (final scheduledMinutes in scheduledMinutesList) {
          if ((stampMinutes - scheduledMinutes).abs() <= 60) {
            onTimeCount++;
            break;
          }
        }
      }
    }

    double totalVariance = 0;
    for (final stamp in stamps) {
      final stampMinutes = stamp.hour * 60 + stamp.minute;
      totalVariance += pow(stampMinutes - avgMinutes, 2);
    }
    final timeDeviation = sqrt(totalVariance / stamps.length);
    final consistency = 100 - (timeDeviation / 60).clamp(0, 100);

    return {
      'average': '${formatTimeOfDay(context, avgTime)} ± 15 min',
      'onTimeRate':
          notificationTimes.isNotEmpty ? ((onTimeCount / stamps.length) * 100).round() : null,
      'consistency': consistency,
    };
  }

  static List<TimeOfDay> convertToTimeOfDay(List<DateTime> dateTimes) {
    return dateTimes.map((dt) => TimeOfDay.fromDateTime(dt)).toList();
  }

  static String analyzeTimeDistribution(List<TimeOfDay> times) {
    final morning = times.where((t) => t.hour >= 6 && t.hour < 12).length;
    final afternoon = times.where((t) => t.hour >= 12 && t.hour < 18).length;
    final evening = times.where((t) => t.hour >= 18 && t.hour < 24).length;
    final night = times.where((t) => t.hour >= 0 && t.hour < 6).length;

    final total = times.length.toDouble();
    return 'Morning ${(morning / total * 100).round()}%, '
        'Afternoon ${(afternoon / total * 100).round()}%, '
        'Evening ${(evening / total * 100).round()}%, '
        'Night ${(night / total * 100).round()}%';
  }

  static String findMostActiveDay(List<DateTime> stamps) {
    if (stamps.isEmpty) return 'N/A';

    final dayCounts = List.filled(7, 0);
    for (final stamp in stamps) {
      dayCounts[stamp.weekday % 7]++;
    }

    final maxIndex = dayCounts.indexOf(dayCounts.reduce(max));
    return DateFormat.EEEE().format(DateTime(2023, 1, maxIndex + 1));
  }

  static String findMostActiveMonth(List<DateTime> stamps) {
    if (stamps.isEmpty) return 'N/A';

    final monthCounts = List.filled(12, 0);
    for (final stamp in stamps) {
      monthCounts[stamp.month - 1]++;
    }

    final maxIndex = monthCounts.indexOf(monthCounts.reduce(max));
    return DateFormat.MMMM().format(DateTime(2023, maxIndex + 1));
  }

  static String findMostActiveYear(List<DateTime> stamps) {
    if (stamps.isEmpty) return 'N/A';

    final yearCounts = <int, int>{};
    for (final stamp in stamps) {
      yearCounts[stamp.year] = (yearCounts[stamp.year] ?? 0) + 1;
    }

    final maxYear =
        yearCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    return '$maxYear (${yearCounts[maxYear]} times)';
  }

  static double calculateQuarterlyConsistency(List<DateTime> stamps) {
    if (stamps.isEmpty) return 0;

    final now = DateTime.now();
    final quarters = <int, int>{};
    int maxPossible = 0;

    for (int i = 0; i < 4; i++) {
      final quarterStart = DateTime(now.year, i * 3 + 1);
      if (quarterStart.isBefore(now)) {
        maxPossible++;
        quarters[i] = 0;
      }
    }

    for (final stamp in stamps) {
      final quarter = ((stamp.month - 1) ~/ 3);
      if (quarters.containsKey(quarter)) {
        quarters[quarter] = (quarters[quarter] ?? 0) + 1;
      }
    }

    final completed = quarters.values.where((v) => v > 0).length;
    return (completed / maxPossible) * 100;
  }

  static double calculateAnnualConsistency(List<DateTime> stamps) {
    if (stamps.isEmpty) return 0;

    final now = DateTime.now();
    final years = stamps.map((s) => s.year).toSet();
    final taskAge = now.year - stamps.first.year + 1;

    return (years.length / taskAge) * 100;
  }

  static String formatTimeOfDay(BuildContext context, TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat.jm().format(dt);
  }

  static String formatNotificationTimes(BuildContext context, List<DateTime> times) {
    if (times.isEmpty) return 'None';

    final formattedTimes = times
        .map((time) => DateFormat.jm().format(time))
        .toSet()
        .toList()
        .join(', ');

    return formattedTimes;
  }

  static Widget buildAnalyticsCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  static Widget buildInfoRow(String label, String value, {bool? good}) {
    Color? color;
    if (good != null) color = good ? Colors.green : Colors.orange;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  static Widget buildPendingNotificationsChart(List<DateTime> notificationTimes) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final times = notificationTimes.whereType<DateTime>().toList();
    final pending = times.where((dt) => dt.isAfter(now)).toList();
    final sent = times.where((dt) => !dt.isAfter(now)).toList();

    final hourlyBins = List.generate(
      24,
      (hour) => DateTime(today.year, today.month, today.day, hour),
    );

    final bars = hourlyBins.map((hour) {
      final nextHour = hour.add(const Duration(hours: 1));
      final pendingCount = pending.where((dt) => !dt.isBefore(hour) && dt.isBefore(nextHour)).length;
      final sentCount = sent.where((dt) => !dt.isBefore(hour) && dt.isBefore(nextHour)).length;

      return BarChartGroupData(
        x: hour.hour,
        barRods: [
          BarChartRodData(toY: sentCount.toDouble(), color: Colors.green, width: 12),
          BarChartRodData(toY: pendingCount.toDouble(), color: Colors.blue, width: 12),
        ],
      );
    }).toList();

    final maxY = bars
        .map((barGroup) => barGroup.barRods.map((rod) => rod.toY).reduce(max))
        .fold<double>(0, (prev, curr) => prev > curr ? prev : curr);

    final interval = max((maxY / 4).ceilToDouble(), 1.0);

    return BarChart(
      BarChartData(
        barGroups: bars,
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 3,
              getTitlesWidget: (value, meta) {
                final hour = value.toInt();
                switch (hour) {
                  case 0:
                    return const Text("12AM", style: TextStyle(fontSize: 10));
                  case 3:
                    return const Text("3AM", style: TextStyle(fontSize: 10));
                  case 6:
                    return const Text("6AM", style: TextStyle(fontSize: 10));
                  case 9:
                    return const Text("9AM", style: TextStyle(fontSize: 10));
                  case 12:
                    return const Text("12PM", style: TextStyle(fontSize: 10));
                  case 15:
                    return const Text("3PM", style: TextStyle(fontSize: 10));
                  case 18:
                    return const Text("6PM", style: TextStyle(fontSize: 10));
                  case 21:
                    return const Text("9PM", style: TextStyle(fontSize: 10));
                  default:
                    return const SizedBox.shrink();
                }
              },
              reservedSize: 36,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString()),
              reservedSize: 28,
            ),
          ),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
        ),
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        alignment: BarChartAlignment.spaceAround,
        maxY: max(maxY * 1.2, 4),
      ),
    );
  }

  static Widget buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  static DateTime getNextOccurrence(DateTime notificationTime) {
    final now = DateTime.now();
    final time = TimeOfDay.fromDateTime(notificationTime);
    DateTime next = DateTime(now.year, now.month, now.day, time.hour, time.minute);

    if (next.isBefore(now)) next = next.add(const Duration(days: 1));

    return next;
  }

  static List<String> getTimeDistributionList(List<TimeOfDay> times) {
    final morning = times.where((t) => t.hour >= 6 && t.hour < 12).length;
    final afternoon = times.where((t) => t.hour >= 12 && t.hour < 18).length;
    final evening = times.where((t) => t.hour >= 18 && t.hour < 24).length;
    final night = times.where((t) => t.hour >= 0 && t.hour < 6).length;

    final total = times.length.toDouble();
    return [
      'Morning: ${(morning / total * 100).round()}%',
      'Afternoon: ${(afternoon / total * 100).round()}%',
      'Evening: ${(evening / total * 100).round()}%',
      'Night: ${(night / total * 100).round()}%',
    ];
  }

  static String formatFullDateWithDay(DateTime date, TimeOfDay time) {
    final dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    return DateFormat('EEEE, MMMM d, y').format(dateTime);
  }

  static Color getChartColor(double value) {
    if (value == 0) return Colors.grey.withOpacity(0.3);
    if (value < 3) return Colors.orange.shade300;
    if (value < 6) return Colors.blue.shade300;
    return Colors.blue.shade300;
  }

  static List<DateTime> parseNotificationTimes(dynamic timesData) {
    if (timesData == null) return [];
    if (timesData is List) {
      return timesData.map((time) {
        if (time is Timestamp) return time.toDate();
        if (time is DateTime) return time;
        if (time is String) return DateTime.parse(time);
        throw Exception('Invalid notification time format: $time');
      }).toList();
    }
    return [];
  }

  static Map<String, int> calculateWeeklyStreak(List<DateTime> stamps) {
    if (stamps.isEmpty) return {'current': 0, 'longest': 0};

    stamps.sort();
    final weeks = stamps.map((d) => getWeekNumber(d)).toSet();

    int currentStreak = 0;
    int longestStreak = 0;
    int tempStreak = 0;

    final currentWeek = getWeekNumber(DateTime.now());

    for (int week = currentWeek; week >= 1; week--) {
      if (weeks.contains(week)) {
        currentStreak++;
        tempStreak++;
        if (tempStreak > longestStreak) longestStreak = tempStreak;
      } else {
        break;
      }
    }

    return {'current': currentStreak, 'longest': longestStreak};
  }

  static int getWeekNumber(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final weekNum = ((day.weekday + 7 - day.weekday) % 7 + day.day) ~/ 7 + 1;
    return weekNum;
  }

  static TimeOfDay findMostCommonTime(List<DateTime> times) {
    if (times.isEmpty) return const TimeOfDay(hour: 12, minute: 0);

    final timeCounts = <TimeOfDay, int>{};
    for (final time in times) {
      final timeOfDay = TimeOfDay.fromDateTime(time);
      timeCounts.update(timeOfDay, (count) => count + 1, ifAbsent: () => 1);
    }

    final maxCount = timeCounts.values.reduce(max);
    final mostCommonTimes =
        timeCounts.entries.where((e) => e.value == maxCount).map((e) => e.key).toList()
          ..sort((a, b) => a.hour != b.hour ? a.hour.compareTo(b.hour) : a.minute.compareTo(b.minute));

    return mostCommonTimes.first;
  }
}
