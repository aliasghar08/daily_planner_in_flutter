import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class DailyTasksStats extends StatefulWidget {
  const DailyTasksStats({super.key});

  @override
  State<DailyTasksStats> createState() => _DailyTasksStatsState();
}

class _DailyTasksStatsState extends State<DailyTasksStats> {
  User? user;
  bool isLoading = true;
  List<Map<String, dynamic>> rawTasks = [];

  int totalTasks = 0;
  int completedTasks = 0;
  double completionRate = 0;
  int currentStreak = 0;
  int longestStreak = 0;
  int overdueTasks = 0;

  Map<String, int> completedLast7Days = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await fetchTaskStats(user!);
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    });
  }

  Future<void> fetchTaskStats(User user) async {
    setState(() => isLoading = true);
    try {
      final now = DateTime.now();
      final oneYearAgo = DateTime(now.year - 1, now.month, now.day);

      final snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('tasks')
              .where('taskType', isEqualTo: 'DailyTask')
              .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        print('📄 ${doc.id} → taskType: ${data['taskType']}');
      }

      final filteredTasks =
          snapshot.docs.where((doc) {
            final data = doc.data();
            return data.containsKey('taskType') &&
                data['taskType'] == 'DailyTask';
          }).toList();

      final tasks =
          filteredTasks.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();

      debugPrint("✅ Fetched ${tasks.length} daily tasks");

      setState(() {
        rawTasks = tasks;
        processStats();
      });
    } catch (e) {
      debugPrint("🔥 Error fetching daily task stats: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void processStats() {
    if (rawTasks.isEmpty) {
      debugPrint("📭 No tasks to process");
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Filter only DailyTasks
    final dailyTasks =
        rawTasks.where((task) => task['taskType'] == 'DailyTask').toList();

    // Only count DailyTasks that exist (regardless of completion)
    totalTasks = dailyTasks.length;

    // final attemptedTasks =
    //     dailyTasks.where((task) {
    //       return task.containsKey('completionStamps') &&
    //           (task['completionStamps'] as List).isNotEmpty;
    //     }).toList();

    // final attemptedTasks =
    //     dailyTasks.where((task) {
    //       final hasStamps =
    //           task['completionStamps'] is List &&
    //           (task['completionStamps'] as List).isNotEmpty;
    //       final hasCompletedAt = task['completedAt'] is Timestamp;
    //       return hasStamps || hasCompletedAt;
    //     }).toList();

    final attemptedTasks = dailyTasks.where((task) {
  return task['completedAt'] != null;
}).toList();


    totalTasks = dailyTasks.length;

    completedTasks =
        attemptedTasks
            .length; // since we're only counting those with completionStamps

    completionRate = totalTasks > 0 ? completedTasks / totalTasks : 0;

    // Count overdue DailyTasks (task date < today and no completionStamps)
    overdueTasks =
        dailyTasks.where((task) {
          final taskDate = task['date'];
          if (taskDate is! Timestamp) return false;

          final date = taskDate.toDate();
          final taskDay = DateTime(date.year, date.month, date.day);

          final isIncomplete =
              !(task.containsKey('completionStamps') &&
                  (task['completionStamps'] as List).isNotEmpty);

          return taskDay.isBefore(today) && isIncomplete;
        }).length;

    calculateStreaks(today);
    calculate7DayBarChartData(today);
  }

  void calculateStreaks(DateTime today) {
    final completedDates = <DateTime>{};

    for (final task in rawTasks) {
      if (task['completionStamps'] != null &&
          task['completionStamps'] is List) {
        final stamps = task['completionStamps'] as List;
        for (var stamp in stamps) {
          if (stamp is Timestamp) {
            final completedDate = stamp.toDate();
            completedDates.add(
              DateTime(
                completedDate.year,
                completedDate.month,
                completedDate.day,
              ),
            );
          }
        }
      }
    }

    int streak = 0;
    DateTime currentDay = today;
    while (completedDates.contains(currentDay)) {
      streak++;
      currentDay = currentDay.subtract(const Duration(days: 1));
    }
    currentStreak = streak;

    final sortedDates = completedDates.toList()..sort();
    int maxStreak = 0;

    if (sortedDates.isNotEmpty) {
      int currentStreakCount = 1;
      maxStreak = 1;

      for (int i = 1; i < sortedDates.length; i++) {
        final difference = sortedDates[i].difference(sortedDates[i - 1]).inDays;
        if (difference == 1) {
          currentStreakCount++;
          if (currentStreakCount > maxStreak) maxStreak = currentStreakCount;
        } else if (difference > 1) {
          currentStreakCount = 1;
        }
      }
    }

    longestStreak = maxStreak;
  }

  void calculate7DayBarChartData(DateTime today) {
    completedLast7Days.clear();

    for (int i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final key = formatDateKey(day);
      completedLast7Days[key] = 0;
    }

    for (var task in rawTasks) {
      if (task['completionStamps'] != null &&
          task['completionStamps'] is List) {
        final stamps = task['completionStamps'] as List;
        for (var stamp in stamps) {
          if (stamp is Timestamp) {
            final completedDate = stamp.toDate();
            final taskDay = DateTime(
              completedDate.year,
              completedDate.month,
              completedDate.day,
            );
            final key = formatDateKey(taskDay);

            if (completedLast7Days.containsKey(key)) {
              completedLast7Days[key] = completedLast7Days[key]! + 1;
            }
          }
        }
      }
    }
  }

  List<PieChartSectionData> generatePieChartData(int completed, int total) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (total == 0) {
      return [
        PieChartSectionData(
          value: 100,
          color: colorScheme.secondary,
          title: 'No data',
          radius: 60,
          titleStyle: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSecondary,
          ),
        ),
      ];
    }

    final int incomplete = total - completed;
    final double completedPercent = (completed / total) * 100;
    final double incompletePercent = (incomplete / total) * 100;

    return [
      PieChartSectionData(
        value: completedPercent,
        color: Colors.green,
        title: '${completedPercent.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onPrimary,
        ),
      ),
      PieChartSectionData(
        value: incompletePercent,
        color: Colors.red,
        title: '${incompletePercent.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onError,
        ),
      ),
    ];
  }

  String formatDateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  String _getWeekdayAbbreviation(int weekday) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: Text("Daily Tasks Performance"), centerTitle: true),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  buildStatCard("📋 Daily Tasks", totalTasks.toString()),
                  buildStatCard("✅ Completed", completedTasks.toString()),
                  buildStatCard(
                    "📊 Completion Rate",
                    totalTasks > 0
                        ? "${(completionRate * 100).toStringAsFixed(1)}%"
                        : "0%",
                  ),
                  buildStatCard("🔥 Current Streak", "$currentStreak days"),
                  buildStatCard("🏆 Longest Streak", "$longestStreak days"),
                  buildStatCard("⚠️ Overdue Tasks", overdueTasks.toString()),
                  const SizedBox(height: 20),
                  Text(
                    "📈 Daily Task Completion",
                    style: textStyle.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sections: generatePieChartData(
                          completedTasks,
                          totalTasks,
                        ),
                        centerSpaceRadius: 40,
                        sectionsSpace: 2,
                        pieTouchData: PieTouchData(enabled: true),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Completed Daily Tasks (Last 7 Days)",
                    style: textStyle.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 250,
                    child: BarChart(
                      BarChartData(
                        gridData: const FlGridData(show: false),
                        alignment: BarChartAlignment.spaceAround,
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index > 6)
                                  return const SizedBox();
                                final date = DateTime.now().subtract(
                                  Duration(days: 6 - index),
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _getWeekdayAbbreviation(date.weekday),
                                    style: textStyle.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(7, (index) {
                          final date = DateTime.now().subtract(
                            Duration(days: 6 - index),
                          );
                          final key = formatDateKey(date);
                          final count = completedLast7Days[key] ?? 0;
                          return BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: count.toDouble(),
                                width: 20,
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                  SizedBox(height: 23),
                ],
              ),
    );
  }

  Widget buildStatCard(String label, String value) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(Icons.analytics),
        title: Text(label, style: theme.textTheme.bodyLarge),
        trailing: Text(value, style: theme.textTheme.titleMedium),
      ),
    );
  }
}
