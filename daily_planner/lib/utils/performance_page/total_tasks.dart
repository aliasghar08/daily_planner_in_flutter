import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class TotalTasks extends StatefulWidget {
  const TotalTasks({super.key});

  @override
  State<TotalTasks> createState() => _AdvancedPerformancePageState();
}

class _AdvancedPerformancePageState extends State<TotalTasks> {
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
    user = FirebaseAuth.instance.currentUser;
    if (user != null) fetchTaskStats(user!);
  }

  Future<void> fetchTaskStats(User user) async {
    setState(() => isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .orderBy('date')
          .get();

      final tasks = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      rawTasks = tasks;
      processStats();
    } catch (e) {
      debugPrint("🔥 Error fetching stats: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void processStats() {
    final now = DateTime.now();

    final cleanedTasks = rawTasks.where((task) {
      if (task['isCompleted'] == true) {
        return task.containsKey('completedAt') && task['completedAt'] != null;
      }
      return true;
    }).toList();

    totalTasks = cleanedTasks.length;
    completedTasks =
        cleanedTasks.where((task) => task['isCompleted'] == true).length;
    completionRate = totalTasks > 0 ? completedTasks / totalTasks : 0;

    overdueTasks = cleanedTasks.where((task) {
      final taskDate = task['date'] is Timestamp
          ? (task['date'] as Timestamp).toDate()
          : DateTime.tryParse(task['date'].toString());

      return taskDate != null &&
          taskDate.isBefore(now) &&
          task['isCompleted'] != true;
    }).length;

    rawTasks = cleanedTasks;
    calculateStreaks();
    calculate7DayBarChartData();
  }

  void calculateStreaks() {
    final completedDates = rawTasks
        .where((task) =>
            task['isCompleted'] == true &&
            task['completedAt'] != null &&
            task['completedAt'] is Timestamp)
        .map((task) => (task['completedAt'] as Timestamp).toDate().toLocal())
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet();

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    int streak = 0;
    for (int i = 0; ; i++) {
      final day = todayDate.subtract(Duration(days: i));
      if (completedDates.contains(day)) {
        streak++;
      } else {
        break;
      }
    }

    currentStreak = streak;

    final sortedDates = completedDates.toList()..sort();
    int maxStreak = 1;
    int tempStreak = 1;

    for (int i = 1; i < sortedDates.length; i++) {
      if (sortedDates[i].difference(sortedDates[i - 1]).inDays == 1) {
        tempStreak++;
        maxStreak = maxStreak < tempStreak ? tempStreak : maxStreak;
      } else if (sortedDates[i] != sortedDates[i - 1]) {
        tempStreak = 1;
      }
    }

    longestStreak = maxStreak;
  }

  void calculate7DayBarChartData() {
    final now = DateTime.now();
    completedLast7Days.clear();

    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final key = formatDateKey(day);
      completedLast7Days[key] = 0;
    }

    for (var task in rawTasks) {
      if (task['isCompleted'] == true &&
          task['completedAt'] != null &&
          task['completedAt'] is Timestamp) {
        final completedDate =
            (task['completedAt'] as Timestamp).toDate().toLocal();
        final onlyDate = DateTime(
          completedDate.year,
          completedDate.month,
          completedDate.day,
        );
        final key = formatDateKey(onlyDate);

        if (completedLast7Days.containsKey(key)) {
          completedLast7Days[key] = completedLast7Days[key]! + 1;
        }
      }
    }
  }

  List<PieChartSectionData> generatePieChartData(int completed, int total) {
    final theme = Theme.of(context);
    final completedColor = Colors.green;
    final incompleteColor = Colors.red;

    final int safeTotal = total < completed ? completed : total;
    final int incomplete = safeTotal - completed;

    final double completedPercent =
        safeTotal == 0 ? 0 : (completed / safeTotal) * 100;
    final double incompletePercent =
        safeTotal == 0 ? 0 : (incomplete / safeTotal) * 100;

    return [
      PieChartSectionData(
        value: completedPercent,
        color: completedColor,
        title: '${completedPercent.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      PieChartSectionData(
        value: incompletePercent,
        color: incompleteColor,
        title: '${incompletePercent.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.white,
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
    final barColor = Colors.blueAccent;

    return Scaffold(
      appBar: AppBar(title: Text("Total Tasks Performance",), centerTitle: true,),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                buildStatCard("📋 Total Tasks", totalTasks.toString(), theme),
                buildStatCard("✅ Completed", completedTasks.toString(), theme),
                buildStatCard("📊 Completion Rate",
                    "${(completionRate * 100).toStringAsFixed(1)}%", theme),
                buildStatCard("🔥 Current Streak", "$currentStreak days", theme),
                buildStatCard("🏆 Longest Streak", "$longestStreak days", theme),
                buildStatCard("⚠️ Overdue Tasks", overdueTasks.toString(), theme),
                const SizedBox(height: 20),
                Text("📈 Task Completion Pie Chart",
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                totalTasks == 0
                    ? const Center(child: Text("No data for pie chart"))
                    : SizedBox(
                        height: 200,
                        child: PieChart(
                          PieChartData(
                            sections: generatePieChartData(
                                completedTasks, totalTasks),
                            centerSpaceRadius: 40,
                            sectionsSpace: 2,
                            pieTouchData: PieTouchData(enabled: true),
                          ),
                        ),
                      ),
                const SizedBox(height: 20),
                Text("Completed Tasks (Last 7 Days)",
                    style: theme.textTheme.titleMedium),
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
                              if (index < 0 || index > 6) {
                                return const SizedBox.shrink();
                              }
                              final date = DateTime.now()
                                  .subtract(Duration(days: 6 - index));
                              final weekday = _getWeekdayAbbreviation(
                                  date.weekday);
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(weekday,
                                    style: theme.textTheme.bodySmall),
                              );
                            },
                          ),
                        ),
                        leftTitles:
                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles:
                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles:
                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(7, (index) {
                        final date = DateTime.now()
                            .subtract(Duration(days: 6 - index));
                        final key = formatDateKey(date);
                        final count = completedLast7Days[key] ?? 0;
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: count.toDouble(),
                              width: 20,
                              color: barColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 23),
              ],
            ),
    );
  }

  Widget buildStatCard(String label, String value, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: theme.cardColor,
      child: ListTile(
        leading: Icon(Icons.analytics),
        title: Text(label, style: theme.textTheme.bodyLarge),
        trailing: Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ),
    );
  }
}