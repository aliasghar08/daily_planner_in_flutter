import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class AnalyticsPage extends StatefulWidget {
  final Task task;

  const AnalyticsPage({super.key, required this.task});

  @override
  _AnalyticsPageState createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late Future<DocumentSnapshot> _taskDataFuture;

  @override
  void initState() {
    super.initState();
    _taskDataFuture = _fetchTaskData();
  }

  Future<DocumentSnapshot> _fetchTaskData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not logged in');

    return await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .doc(widget.task.docId)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Analytics: ${widget.task.title}"),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _taskDataFuture = _fetchTaskData();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _taskDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    "Loading analytics...",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Error loading data',
                    style: TextStyle(fontSize: 18, color: Colors.red),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _taskDataFuture = _fetchTaskData();
                      });
                    },
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.find_in_page, color: Colors.blue, size: 48),
                  SizedBox(height: 16),
                  Text('Task data not found', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text(
                    'No analytics available for this task',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final taskData = snapshot.data!.data() as Map<String, dynamic>;
          final stamps = _parseCompletionStamps(taskData['completionStamps']);
          final notificationTimes =
              taskData['notificationTimes'] != null
                  ? _parseNotificationTimes(taskData['notificationTimes'])
                  : <DateTime>[];

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Existing analytics content
                  _buildTaskAnalytics(context, taskData),

                  // Add chart section header
                  if (stamps.isNotEmpty || notificationTimes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.insights,
                            color: Theme.of(context).primaryColor,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Visual Insights',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Daily Task Charts
                  if (widget.task.taskType == 'DailyTask' && stamps.isNotEmpty)
                    Column(
                      children: [
                        _buildAnalyticsCard(
                          title: "Weekly Completion",
                          children: [
                            SizedBox(
                              height: 220,
                              child: _buildStreakChart(
                                stamps,
                                Duration(days: 1),
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              "Last 7 days completion status",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        if (notificationTimes.isNotEmpty) ...[
                          _buildAnalyticsCard(
                            title: "Today's Notifications",
                            children: [
                              SizedBox(
                                height: 220,
                                child: _buildPendingNotificationsChart(
                                  notificationTimes,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Pending (blue) vs Sent (green) notifications",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 12),
                              Text(
                                "Upcoming Notifications:",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              _buildNotificationTimesList(
                                context,
                                notificationTimes,
                              ),
                            ],
                          ),
                        ],

                        if (notificationTimes.isNotEmpty)
                          _buildAnalyticsCard(
                            title: "Notification Time Distribution",
                            children: [
                              // Convert DateTime to TimeOfDay for the chart
                              SizedBox(
                                height: 220,
                                child: _buildTimeDistributionChart(
                                  notificationTimes
                                      .map((dt) => TimeOfDay.fromDateTime(dt))
                                      .toList(),
                                ),
                              ),
                              SizedBox(height: 8),

                              Text(
                                "Notification Time Distribution",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                children: [
                                  _buildLegendItem(
                                    Colors.blue,
                                    "Morning (6AM-12PM)",
                                  ),
                                  const SizedBox(width: 8),
                                  _buildLegendItem(
                                    Colors.orange,
                                    "Afternoon (12PM-6PM)",
                                  ),
                                  const SizedBox(width: 8),
                                  _buildLegendItem(
                                    Colors.purple,
                                    "Evening (6PM-12AM)",
                                  ),
                                  const SizedBox(width: 8),
                                  _buildLegendItem(
                                    Colors.grey,
                                    "Night (12AM-6AM)",
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),

                  // Weekly Task Charts
                  if (widget.task.taskType == 'WeeklyTask' && stamps.isNotEmpty)
                    _buildAnalyticsCard(
                      title: "Monthly Completion Trend",
                      children: [
                        SizedBox(
                          height: 220,
                          child: _buildMonthlyTrendChart(stamps),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Completion pattern over last 6 months",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),

                  // Monthly Task Charts
                  if (widget.task.taskType == 'MonthlyTask' &&
                      stamps.isNotEmpty)
                    _buildAnalyticsCard(
                      title: "Yearly Performance",
                      children: [
                        SizedBox(
                          height: 220,
                          child: _buildMonthlyTrendChart(stamps),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Monthly completion history",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

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

  List<TimeOfDay> _convertToTimeOfDay(List<DateTime> dateTimes) {
    return dateTimes.map((dt) => TimeOfDay.fromDateTime(dt)).toList();
  }

  List<String> _getTimeDistributionList(List<TimeOfDay> times) {
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

  Widget _buildNotificationTimesList(
    BuildContext context,
    List<dynamic> rawNotificationTimes, // Accept dynamic list from Firestore
  ) {
    // Convert rawNotificationTimes to proper List<DateTime>
    final notificationTimes =
        rawNotificationTimes.map<DateTime>((e) {
          if (e is DateTime) {
            return e;
          } else if (e is Timestamp) {
            return e.toDate();
          } else if (e is Map<String, dynamic>) {
            // Web Firestore returns {_seconds, _nanoseconds}
            return DateTime.fromMillisecondsSinceEpoch(
              (e['_seconds'] ?? 0) * 1000 +
                  ((e['_nanoseconds'] ?? 0) ~/ 1000000),
            );
          } else {
            debugPrint('Unknown notification time format: $e');
            return DateTime.now(); // fallback to prevent crash
          }
        }).toList();

    // Filter only upcoming notifications
    final upcomingTimes =
        notificationTimes.where((dt) => dt.isAfter(DateTime.now())).toList();

    if (upcomingTimes.isEmpty) {
      return const Text('None', style: TextStyle(color: Colors.grey));
    }

    // Remove exact duplicates and sort ascending
    final uniqueTimes = upcomingTimes.toSet().toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final dt in uniqueTimes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              // Show full date + time with day of week
              DateFormat('EEEE, MMM d, y – hh:mm a').format(dt),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.blue,
              ),
            ),
          ),
      ],
    );
  }

  String _getNextOccurrenceText(TimeOfDay time) {
    final now = DateTime.now();
    DateTime next = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (next.isBefore(now)) {
      next = next.add(Duration(days: 1));
    }

    return DateFormat('EEEE, MMMM d, y').format(next);
  }

  String _formatFullDateWithDay(DateTime date, TimeOfDay time) {
    // Create a DateTime object using the current date and the notification time
    final dateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    return DateFormat('EEEE, MMMM d, y').format(dateTime);
  }

  Widget _buildTimeDistributionChart(List<TimeOfDay> times) {
    if (times.isEmpty) return SizedBox.shrink();

    final morning = times.where((t) => t.hour >= 6 && t.hour < 12).length;
    final afternoon = times.where((t) => t.hour >= 12 && t.hour < 18).length;
    final evening = times.where((t) => t.hour >= 18 && t.hour < 24).length;
    final night = times.where((t) => t.hour >= 0 && t.hour < 6).length;

    final total = times.length.toDouble();
    final sections = [
      PieChartSectionData(
        value: morning / total * 100,
        color: Colors.blue,
        title: '${(morning / total * 100).round()}%',
        radius: 40,
      ),
      PieChartSectionData(
        value: afternoon / total * 100,
        color: Colors.orange,
        title: '${(afternoon / total * 100).round()}%',
        radius: 40,
      ),
      PieChartSectionData(
        value: evening / total * 100,
        color: Colors.purple,
        title: '${(evening / total * 100).round()}%',
        radius: 40,
      ),
      PieChartSectionData(
        value: night / total * 100,
        color: Colors.grey,
        title: '${(night / total * 100).round()}%',
        radius: 40,
      ),
    ];

    return PieChart(PieChartData(sections: sections, centerSpaceRadius: 30));
  }

  Widget _buildMonthlyTrendChart(List<DateTime> stamps) {
    if (stamps.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final months = List.generate(6, (i) {
      final date = DateTime(now.year, now.month - 5 + i);
      return DateFormat.MMM().format(date);
    });

    // Group stamps by month
    final monthlyCounts = <int, int>{};
    for (final stamp in stamps) {
      final monthKey = stamp.year * 100 + stamp.month;
      monthlyCounts[monthKey] = (monthlyCounts[monthKey] ?? 0) + 1;
    }

    // Prepare chart data for last 6 months
    final chartData = List.generate(6, (i) {
      final date = DateTime(now.year, now.month - 5 + i);
      final monthKey = date.year * 100 + date.month;
      return monthlyCounts[monthKey]?.toDouble() ?? 0.0;
    });

    // Find max value for scaling
    final maxValue = chartData.reduce(max) * 1.2;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxValue > 0 ? maxValue : 5, // Ensure chart has some height
        barGroups: List.generate(6, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: chartData[i],
                color: _getChartColor(chartData[i]),
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
                    months[value.toInt()],
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                );
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxValue > 10 ? 2 : 1,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                );
              },
              reservedSize: 28,
            ),
          ),
          rightTitles: AxisTitles(),
          topTitles: AxisTitles(),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxValue > 10 ? 2 : 1,
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Color _getChartColor(double value) {
    if (value == 0) return Colors.grey.withOpacity(0.3);
    if (value < 3) return Colors.orange.shade300;
    if (value < 6) return Colors.blue.shade300;
    return Colors.blue.shade300;
  }

  Widget _buildTaskAnalytics(
    BuildContext context,
    Map<String, dynamic> taskData,
  ) {
    if (widget.task.taskType == 'DailyTask') {
      return _buildDailyTaskAnalytics(context, taskData);
    } else if (widget.task.taskType == 'WeeklyTask') {
      return _buildWeeklyTaskAnalytics(context, taskData);
    } else if (widget.task.taskType == 'MonthlyTask') {
      return _buildMonthlyTaskAnalytics(context, taskData);
    } else {
      return _buildOneTimeTaskAnalytics(context, taskData);
    }
  }

  // Widget _buildOneTimeTaskAnalytics(
  //   BuildContext context,
  //   Map<String, dynamic> taskData,
  // ) {
  //   final createdAt = (taskData['createdAt'] as Timestamp).toDate();
  //   final completedAt =
  //       taskData['completedAt'] != null
  //           ? (taskData['completedAt'] as Timestamp).toDate()
  //           : null;

  //   // FIX: Handle null case for daysToComplete
  //   final daysToComplete =
  //       completedAt != null ? completedAt.difference(createdAt).inDays : null;

  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       _buildAnalyticsCard(
  //         title: "Task Overview",
  //         children: [
  //           _buildInfoRow("Type", "One-time"),
  //           _buildInfoRow("Created", DateFormat.yMMMd().format(createdAt)),
  //           _buildInfoRow(
  //             "Status",
  //             completedAt != null ? "Completed" : "Pending",
  //           ),
  //           if (completedAt != null) ...[
  //             _buildInfoRow(
  //               "Completed",
  //               DateFormat.yMMMd().format(completedAt),
  //             ),
  //             _buildInfoRow(
  //               "Time to Complete",
  //               daysToComplete == 0 ? "Same day" : "$daysToComplete days",
  //             ),
  //           ],
  //         ],
  //       ),

  //       if (taskData['notificationTimes'] != null)
  //         _buildAnalyticsCard(
  //           title: "Schedule",
  //           children: [
  //             _buildInfoRow(
  //               "Notification Times",
  //               _formatNotificationTimes(
  //                 context,
  //                 _parseNotificationTimes(taskData['notificationTimes']),
  //               ),
  //             ),
  //           ],
  //         ),
  //     ],
  //   );
  // }

//  Widget _buildOneTimeTaskAnalytics(
//   BuildContext context,
//   Map<String, dynamic> taskData,
// ) {
//   final createdAt = (taskData['createdAt'] as Timestamp).toDate();
//   final completedAt =
//       taskData['completedAt'] != null
//           ? (taskData['completedAt'] as Timestamp).toDate()
//           : null;

//   final daysToComplete =
//       completedAt != null ? completedAt.difference(createdAt).inDays : null;

//   return Column(
//     crossAxisAlignment: CrossAxisAlignment.start,
//     children: [
//       _buildAnalyticsCard(
//         title: "Task Overview",
//         children: [
//           _buildInfoRow("Type", "One-time"),
//           _buildInfoRow("Created", DateFormat.yMMMd().format(createdAt)),
//           _buildInfoRow(
//             "Status",
//             completedAt != null ? "Completed" : "Pending",
//           ),
//           if (completedAt != null) ...[
//             _buildInfoRow(
//               "Completed",
//               DateFormat.yMMMd().format(completedAt),
//             ),
//             _buildInfoRow(
//               "Time to Complete",
//               daysToComplete == 0 ? "Same day" : "$daysToComplete days",
//             ),
//           ],
//         ],
//       ),

//       if (taskData['notificationTimes'] != null)
//         _buildAnalyticsCard(
//           title: "Schedule",
//           children: [
//             Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   "Notification Times",
//                   style: TextStyle(
//                     fontWeight: FontWeight.bold,
//                     fontSize: 16, // Match your existing style
//                   ),
//                 ),
//                 SizedBox(height: 8),
//                 // Safe parsing with error handling
//                 ..._buildNotificationTimesListforOneTimeTask(context, taskData['notificationTimes']),
//               ],
//             ),
//           ],
//         ),
//     ],
//   );
// }

Widget _buildOneTimeTaskAnalytics(
  BuildContext context,
  Map<String, dynamic> taskData,
) {
  final createdAt = (taskData['createdAt'] as Timestamp).toDate();
  final completedAt =
      taskData['completedAt'] != null
          ? (taskData['completedAt'] as Timestamp).toDate()
          : null;

  final daysToComplete =
      completedAt != null ? completedAt.difference(createdAt).inDays : null;

       final notificationTimes =
        taskData['notificationTimes'] != null
            ? _parseNotificationTimes(taskData['notificationTimes'])
            : null;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildAnalyticsCard(
        title: "Task Overview",
        children: [
          _buildInfoRow("Type", "One-time"),
          _buildInfoRow("Created", DateFormat.yMMMd().format(createdAt)),
          _buildInfoRow(
            "Status",
            completedAt != null ? "Completed" : "Pending",
          ),
          if (completedAt != null) ...[
            _buildInfoRow(
              "Completed",
              DateFormat.yMMMd().format(completedAt),
            ),
            _buildInfoRow(
              "Time to Complete",
              daysToComplete == 0 ? "Same day" : "$daysToComplete days",
            ),
          ],
        ],
      ),

      if (taskData['notificationTimes'] != null)
        _buildAnalyticsCard(
          title: "Schedule",
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Notification Times",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                // Use the function that handles DateTime objects
                _buildNotificationTimesList(context, notificationTimes!),
              ],
            ),
          ],
        ),
    ],
  );
}

// Helper method to safely build notification times list
List<Widget> _buildNotificationTimesListforOneTimeTask(BuildContext context, dynamic notificationTimes) {
  try {
    final times = _parseNotificationTimes(notificationTimes);
    if (times.isEmpty) {
      return [Text("No notification times", style: TextStyle(color: Colors.grey))];
    }
    
    return times.map((time) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          _formatTimeOfDay(context, time as TimeOfDay),
          style: TextStyle(
            fontSize: 14, // Match your existing style
          ),
        ),
      );
    }).toList();
  } catch (e) {
    // Fallback if there's any parsing error
    return [
      Text(
        "Error displaying times",
        style: TextStyle(color: Colors.red),
      )
    ];
  }
}

// Safe time formatting method
String _formatTimeOfDay(BuildContext context, TimeOfDay time) {
  try {
    final materialLocalizations = MaterialLocalizations.of(context);
    return materialLocalizations.formatTimeOfDay(time);
  } catch (e) {
    // Fallback format
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }
}

  Widget _buildDailyTaskAnalytics(
    BuildContext context,
    Map<String, dynamic> taskData,
  ) {
    final stamps = _parseCompletionStamps(taskData['completionStamps']);
    final totalCompletions = stamps.length;
    final today = DateTime.now();
    final last7Days = today.subtract(const Duration(days: 7));
    final last30Days = today.subtract(const Duration(days: 30));

    final last7Count = stamps.where((d) => d.isAfter(last7Days)).length;
    final last30Count = stamps.where((d) => d.isAfter(last30Days)).length;

    final streakInfo = _calculateStreak(stamps, Duration(days: 1));
    final currentStreak = streakInfo['current'] as int;
    final longestStreak = streakInfo['longest'] as int;

    final notificationTimes =
        taskData['notificationTimes'] != null
            ? _parseNotificationTimes(taskData['notificationTimes'])
            : null;

    final timeStats = _calculateTimeStats(context, stamps, notificationTimes!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnalyticsCard(
          title: "Completion Insights",
          children: [
            _buildInfoRow("Total Completions", "$totalCompletions times"),
            _buildInfoRow(
              "Current Streak",
              "$currentStreak days",
              good: currentStreak >= 3,
            ),
            _buildInfoRow("Longest Streak", "$longestStreak days"),
            _buildInfoRow(
              "Last 7 Days",
              "$last7Count/7 days",
              good: last7Count >= 5,
            ),
            _buildInfoRow(
              "Last 30 Days",
              "$last30Count/30 days",
              good: last30Count >= 20,
            ),
            _buildInfoRow(
              "Completion Rate",
              "${((last30Count / 30) * 100).toStringAsFixed(1)}%",
            ),
          ],
        ),

        _buildAnalyticsCard(
          title: "Time Performance",
          children: [
            if (timeStats['average'] != null)
              _buildInfoRow(
                "Avg Completion Time",
                timeStats['average'] as String,
              ),
            if (notificationTimes.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                "Scheduled Times:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              _buildNotificationTimesList(context, notificationTimes),
            ],
            if (timeStats['onTimeRate'] != null)
              _buildInfoRow(
                "On Time Rate",
                "${timeStats['onTimeRate']}%",
                good: (timeStats['onTimeRate'] as int) >= 70,
              ),
            if (timeStats['consistency'] != null)
              _buildInfoRow(
                "Time Consistency",
                "${(timeStats['consistency'] as double).toStringAsFixed(1)}%",
                good: (timeStats['consistency'] as double) >= 80,
              ),
          ],
        ),

        if (notificationTimes.isNotEmpty)
          _buildAnalyticsCard(
            title: "Notification Patterns",
            children: [
              _buildInfoRow(
                "Most Common Time",
                _formatTimeOfDay(
                  context,
                  _findMostCommonTime(notificationTimes),
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Time Distribution:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              ..._getTimeDistributionList(
                _convertToTimeOfDay(notificationTimes),
              ).map(
                (part) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(part, style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),

        if (stamps.isNotEmpty)
          _buildAnalyticsCard(
            title: "Recent Activity",
            children: [
              _buildInfoRow(
                "Last Completed",
                DateFormat.yMMMd().format(stamps.last),
              ),
              _buildInfoRow("Most Active Day", _findMostActiveDay(stamps)),
            ],
          ),
      ],
    );
  }

  Widget _buildWeeklyTaskAnalytics(
    BuildContext context,
    Map<String, dynamic> taskData,
  ) {
    final stamps = _parseCompletionStamps(taskData['completionStamps']);
    final totalCompletions = stamps.length;
    final now = DateTime.now();
    final last4Weeks = now.subtract(const Duration(days: 28));

    final last4WeeksCount = stamps.where((d) => d.isAfter(last4Weeks)).length;

    final streakInfo = _calculateWeeklyStreak(stamps);
    final currentStreak = streakInfo['current'] as int;
    final longestStreak = streakInfo['longest'] as int;

    final notificationTimes =
        taskData['notificationTimes'] != null
            ? _parseNotificationTimes(taskData['notificationTimes'])
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnalyticsCard(
          title: "Completion Insights",
          children: [
            _buildInfoRow("Total Completions", "$totalCompletions weeks"),
            _buildInfoRow(
              "Current Streak",
              "$currentStreak weeks",
              good: currentStreak >= 3,
            ),
            _buildInfoRow("Longest Streak", "$longestStreak weeks"),
            _buildInfoRow(
              "Last 4 Weeks",
              "$last4WeeksCount/4 weeks",
              good: last4WeeksCount >= 3,
            ),
            _buildInfoRow(
              "Completion Rate",
              "${((last4WeeksCount / 4) * 100).toStringAsFixed(1)}%",
            ),
          ],
        ),

        if (notificationTimes != null && notificationTimes.isNotEmpty)
          _buildAnalyticsCard(
            title: "Notification Schedule",
            children: [
              Text(
                "Notification Times:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              _buildNotificationTimesList(context, notificationTimes),
              SizedBox(height: 8),
              _buildInfoRow(
                "Most Common Time",
                _formatTimeOfDay(
                  context,
                  _findMostCommonTime(notificationTimes),
                ),
              ),
            ],
          ),

        _buildAnalyticsCard(
          title: "Performance Trends",
          children: [
            _buildInfoRow("Most Active Month", _findMostActiveMonth(stamps)),
            _buildInfoRow(
              "Quarterly Consistency",
              "${_calculateQuarterlyConsistency(stamps).toStringAsFixed(1)}%",
            ),
          ],
        ),

        if (stamps.isNotEmpty)
          _buildAnalyticsCard(
            title: "Recent Activity",
            children: [
              _buildInfoRow(
                "Last Completed",
                DateFormat.yMMMd().format(stamps.last),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildMonthlyTaskAnalytics(
    BuildContext context,
    Map<String, dynamic> taskData,
  ) {
    final stamps = _parseCompletionStamps(taskData['completionStamps']);
    final totalCompletions = stamps.length;
    final now = DateTime.now();
    final currentYear = now.year;

    final yearlyCompletions = stamps.where((d) => d.year == currentYear).length;

    final streakInfo = _calculateMonthlyStreak(stamps);
    final currentStreak = streakInfo['current'] as int;
    final longestStreak = streakInfo['longest'] as int;

    final notificationTimes =
        taskData['notificationTimes'] != null
            ? _parseNotificationTimes(taskData['notificationTimes'])
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnalyticsCard(
          title: "Completion Insights",
          children: [
            _buildInfoRow("Total Completions", "$totalCompletions months"),
            _buildInfoRow(
              "Current Streak",
              "$currentStreak months",
              good: currentStreak >= 3,
            ),
            _buildInfoRow("Longest Streak", "$longestStreak months"),
            _buildInfoRow(
              "This Year",
              "$yearlyCompletions/${now.month} months",
              good: yearlyCompletions >= (now.month * 0.8).round(),
            ),
            _buildInfoRow(
              "Completion Rate",
              "${((yearlyCompletions / now.month) * 100).toStringAsFixed(1)}%",
            ),
          ],
        ),

        if (notificationTimes != null && notificationTimes.isNotEmpty)
          _buildAnalyticsCard(
            title: "Notification Schedule",
            children: [
              Text(
                "Notification Times:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              _buildNotificationTimesList(context, notificationTimes),
              SizedBox(height: 8),
              _buildInfoRow(
                "Most Common Time",
                _formatTimeOfDay(
                  context,
                  _findMostCommonTime(notificationTimes),
                ),
              ),
            ],
          ),

        _buildAnalyticsCard(
          title: "Long-Term Trends",
          children: [
            _buildInfoRow("Most Active Year", _findMostActiveYear(stamps)),
            _buildInfoRow(
              "Annual Consistency",
              "${_calculateAnnualConsistency(stamps).toStringAsFixed(1)}%",
            ),
          ],
        ),

        if (stamps.isNotEmpty)
          _buildAnalyticsCard(
            title: "Recent Activity",
            children: [
              _buildInfoRow(
                "Last Completed",
                DateFormat.yMMMd().format(stamps.last),
              ),
            ],
          ),
      ],
    );
  }

  List<DateTime> _parseCompletionStamps(dynamic stampsData) {
    if (stampsData == null) return [];

    if (stampsData is List) {
      return stampsData.map((stamp) {
        if (stamp is Timestamp) return stamp.toDate();
        if (stamp is DateTime) return stamp;
        if (stamp is String) return DateTime.parse(stamp);
        throw Exception('Invalid completion stamp format: $stamp');
      }).toList();
    }

    return [];
  }

  List<DateTime> _parseNotificationTimes(dynamic timesData) {
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

  Map<String, int> _calculateWeeklyStreak(List<DateTime> stamps) {
    if (stamps.isEmpty) return {'current': 0, 'longest': 0};

    stamps.sort();
    final weeks = stamps.map((d) => _getWeekNumber(d)).toSet();

    int currentStreak = 0;
    int longestStreak = 0;
    int tempStreak = 0;

    final currentWeek = _getWeekNumber(DateTime.now());

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

  Map<String, int> _calculateMonthlyStreak(List<DateTime> stamps) {
    if (stamps.isEmpty) return {'current': 0, 'longest': 0};

    stamps.sort();
    final months = stamps.map((d) => DateTime(d.year, d.month)).toSet();

    int currentStreak = 0;
    int longestStreak = 0;
    int tempStreak = 0;

    final now = DateTime.now();
    DateTime currentMonth = DateTime(now.year, now.month);

    while (months.contains(currentMonth)) {
      currentStreak++;
      tempStreak++;
      if (tempStreak > longestStreak) longestStreak = tempStreak;

      currentMonth = DateTime(currentMonth.year, currentMonth.month - 1);
    }

    return {'current': currentStreak, 'longest': longestStreak};
  }

  int _getWeekNumber(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final weekNum = ((day.weekday + 7 - day.weekday) % 7 + day.day) ~/ 7 + 1;
    return weekNum;
  }

  Map<String, int> _calculateStreak(
    List<DateTime> stamps,
    Duration recurrence,
  ) {
    if (stamps.isEmpty) return {'current': 0, 'longest': 0};

    // Normalize all dates to midnight (remove time component)
    final normalizedStamps =
        stamps.map((d) => DateTime(d.year, d.month, d.day)).toList();
    normalizedStamps.sort();

    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);

    int currentStreak = 0;
    int longestStreak = 0;
    int tempStreak = 1; // Start with 1 for the first date

    // 1. Calculate longest streak first
    for (int i = 1; i < normalizedStamps.length; i++) {
      final prev = normalizedStamps[i - 1];
      final current = normalizedStamps[i];
      final diff = current.difference(prev).inDays;

      if (diff == recurrence.inDays) {
        // Perfect continuation
        tempStreak++;
      } else if (diff > recurrence.inDays) {
        // Gap detected
        longestStreak = max(longestStreak, tempStreak);
        tempStreak = 1; // Reset
      }
      // If diff < recurrence.inDays, it's multiple completions in same period
    }
    longestStreak = max(longestStreak, tempStreak); // Final check

    // 2. Calculate current streak (working backwards from today)
    if (normalizedStamps.contains(todayNormalized)) {
      // Task completed today - count backwards
      currentStreak = 1;
      DateTime checkDate = todayNormalized.subtract(recurrence);

      while (normalizedStamps.contains(checkDate)) {
        currentStreak++;
        checkDate = checkDate.subtract(recurrence);
      }
    }
    else {
      // Task NOT completed today
      final yesterdayNormalized = todayNormalized.subtract(Duration(days: 1));
      
      if (normalizedStamps.contains(yesterdayNormalized)) {
        // Task completed yesterday but not today - count backwards from yesterday
        currentStreak = 1;
        DateTime checkDate = yesterdayNormalized.subtract(recurrence);

        while (normalizedStamps.contains(checkDate)) {
          currentStreak++;
          checkDate = checkDate.subtract(recurrence);
        }
      } else {
        // Task not completed today OR yesterday - streak is broken
        currentStreak = 0;
      }
    }

    return {'current': currentStreak, 'longest': longestStreak};
  }

  Map<String, dynamic> _calculateTimeStats(
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
          notificationTimes
              .map((time) => time.hour * 60 + time.minute)
              .toList();

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
      'average': '${_formatTimeOfDay(context, avgTime)} ± 15 min',
      'onTimeRate':
          notificationTimes.isNotEmpty
              ? ((onTimeCount / stamps.length) * 100).round()
              : null,
      'consistency': consistency,
    };
  }

  TimeOfDay _findMostCommonTime(List<DateTime> times) {
    if (times.isEmpty) {
      return const TimeOfDay(hour: 12, minute: 0); // Default noon
    }

    // Count by hour and minute
    final timeCounts = <TimeOfDay, int>{};
    for (final time in times) {
      final timeOfDay = TimeOfDay.fromDateTime(time);
      timeCounts.update(timeOfDay, (count) => count + 1, ifAbsent: () => 1);
    }

    // Handle ties by choosing the earliest time
    final maxCount = timeCounts.values.reduce(max);
    final mostCommonTimes =
        timeCounts.entries
            .where((e) => e.value == maxCount)
            .map((e) => e.key)
            .toList()
          ..sort(
            (a, b) =>
                a.hour != b.hour
                    ? a.hour.compareTo(b.hour)
                    : a.minute.compareTo(b.minute),
          );

    return mostCommonTimes.first;
  }

  String _analyzeTimeDistribution(List<TimeOfDay> times) {
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

  String _findMostActiveDay(List<DateTime> stamps) {
    if (stamps.isEmpty) return 'N/A';

    final dayCounts = List.filled(7, 0);
    for (final stamp in stamps) {
      dayCounts[stamp.weekday % 7]++;
    }

    final maxIndex = dayCounts.indexOf(dayCounts.reduce(max));
    return DateFormat.EEEE().format(DateTime(2023, 1, maxIndex + 1));
  }

  String _findMostActiveMonth(List<DateTime> stamps) {
    if (stamps.isEmpty) return 'N/A';

    final monthCounts = List.filled(12, 0);
    for (final stamp in stamps) {
      monthCounts[stamp.month - 1]++;
    }

    final maxIndex = monthCounts.indexOf(monthCounts.reduce(max));
    return DateFormat.MMMM().format(DateTime(2023, maxIndex + 1));
  }

  String _findMostActiveYear(List<DateTime> stamps) {
    if (stamps.isEmpty) return 'N/A';

    final yearCounts = <int, int>{};
    for (final stamp in stamps) {
      yearCounts[stamp.year] = (yearCounts[stamp.year] ?? 0) + 1;
    }

    final maxYear =
        yearCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    return '$maxYear (${yearCounts[maxYear]} times)';
  }

  double _calculateQuarterlyConsistency(List<DateTime> stamps) {
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

  double _calculateAnnualConsistency(List<DateTime> stamps) {
    if (stamps.isEmpty) return 0;

    final now = DateTime.now();
    final years = stamps.map((s) => s.year).toSet();
    final taskAge = now.year - stamps.first.year + 1;

    return (years.length / taskAge) * 100;
  }

  // String _formatTimeOfDay(BuildContext context, TimeOfDay time) {
  //   final now = DateTime.now();
  //   final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  //   return DateFormat.jm().format(dt);
  // }

  String _formatNotificationTimes(BuildContext context, List<DateTime> times) {
    if (times.isEmpty) return 'None';

    final formattedTimes = times
        .map((time) => DateFormat.jm().format(time))
        .toSet() // Remove duplicates
        .toList()
        .join(', ');

    return formattedTimes;
  }

  Widget _buildAnalyticsCard({
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
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool? good}) {
    Color? color;
    if (good != null) {
      color = good ? Colors.green : Colors.orange;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingNotificationsChart(List<DateTime> notificationTimes) {
    print(notificationTimes);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Ensure it's a proper List<DateTime>
    final times = notificationTimes.whereType<DateTime>().toList();

    // Separate pending and sent notifications
    final pending = times.where((dt) => dt.isAfter(now)).toList();
    final sent = times.where((dt) => !dt.isAfter(now)).toList();

    // Create hourly bins (0 → 23 hours of today)
    final hourlyBins = List.generate(
      24,
      (hour) => DateTime(today.year, today.month, today.day, hour),
    );

    // Prepare chart data
    final bars =
        hourlyBins.map((hour) {
          final nextHour = hour.add(const Duration(hours: 1));

          final pendingCount =
              pending
                  .where((dt) => !dt.isBefore(hour) && dt.isBefore(nextHour))
                  .length;
          final sentCount =
              sent
                  .where((dt) => !dt.isBefore(hour) && dt.isBefore(nextHour))
                  .length;

          debugPrint(
            "Hour ${hour.hour}: sent=$sentCount, pending=$pendingCount (total=${sentCount + pendingCount})",
          );

          return BarChartGroupData(
            x: hour.hour,
            barRods: [
              BarChartRodData(
                toY: sentCount.toDouble(),
                color: Colors.green,
                width: 12,
                borderRadius: BorderRadius.zero,
              ),
              BarChartRodData(
                toY: pendingCount.toDouble(),
                color: Colors.blue,
                width: 12,
                borderRadius: BorderRadius.zero,
              ),
            ],
          );
        }).toList();

    // Determine max Y value dynamically
    final maxY = bars
        .map(
          (barGroup) => barGroup.barRods
              .map((rod) => rod.toY)
              .reduce((a, b) => a > b ? a : b),
        )
        .fold<double>(0, (prev, curr) => prev > curr ? prev : curr);

    // Adaptive interval for left axis (as double)
    final interval = max((maxY / 4).ceilToDouble(), 1.0);

    return BarChart(
      BarChartData(
        barGroups: bars,
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 3, // Show every 3 hours
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
              interval: interval, // ✅ Now a double
              getTitlesWidget: (value, meta) {
                return Text(value.toInt().toString());
              },
              reservedSize: 28,
            ),
          ),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
        ),
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        alignment: BarChartAlignment.spaceAround,
        maxY: max(maxY * 1.2, 4), // 20% padding, minimum 4
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  DateTime _getNextOccurrence(DateTime notificationTime) {
    final now = DateTime.now();
    final time = TimeOfDay.fromDateTime(notificationTime);
    DateTime next = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (next.isBefore(now)) {
      next = next.add(Duration(days: 1));
    }

    return next;
  }
}
