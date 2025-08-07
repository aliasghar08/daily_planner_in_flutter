import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class AnalyticsPage extends StatefulWidget {
  final Task task;

  const AnalyticsPage({Key? key, required this.task}) : super(key: key);

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
      appBar: AppBar(title: Text("Analytics: ${widget.task.title}")),
      body: FutureBuilder<DocumentSnapshot>(
        future: _taskDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text('Task data not found'));
          }

          final taskData = snapshot.data!.data() as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: _buildTaskAnalytics(context, taskData),
            ),
          );
        },
      ),
    );
  }

  List<String> _getTimeDistributionList(List<TimeOfDay> times) {
    final morning = times.where((t) => t.hour >= 6 && t.hour < 12).length;
    final afternoon = times.where((t) => t.hour >= 12 && t.hour < 18).length;
    final evening = times.where((t) => t.hour >= 18 && t.hour < 24).length;
    final night = times.where((t) => t.hour >= 0 && t.hour < 6).length;
    
    final total = times.length.toDouble();
    return [
      'Morning: ${(morning/total*100).round()}%',
      'Afternoon: ${(afternoon/total*100).round()}%',
      'Evening: ${(evening/total*100).round()}%',
      'Night: ${(night/total*100).round()}%',
    ];
  }
 
   Widget _buildNotificationTimesList(BuildContext context, List<TimeOfDay> times) {
    if (times.isEmpty) return Text('None', style: TextStyle(color: Colors.grey));
    
    // Remove duplicates while preserving order
    final uniqueTimes = times.fold<List<TimeOfDay>>([], (list, time) {
      if (!list.any((t) => t.hour == time.hour && t.minute == time.minute)) {
        list.add(time);
      }
      return list;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final time in uniqueTimes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(
              _formatTimeOfDay(context, time),
              style: TextStyle(fontSize: 14),
            ),
          ),
      ],
    );
  }
  

  Widget _buildTaskAnalytics(BuildContext context, Map<String, dynamic> taskData) {
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

  Widget _buildOneTimeTaskAnalytics(BuildContext context, Map<String, dynamic> taskData) {
    final createdAt = (taskData['createdAt'] as Timestamp).toDate();
    final completedAt = taskData['completedAt'] != null 
        ? (taskData['completedAt'] as Timestamp).toDate()
        : null;
    
    final daysToComplete = completedAt != null
        ? completedAt.difference(createdAt).inDays
        : null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnalyticsCard(
          title: "Task Overview",
          children: [
            _buildInfoRow("Type", "One-time"),
            _buildInfoRow("Created", DateFormat.yMMMd().format(createdAt)),
            _buildInfoRow("Status", completedAt != null 
                ? "Completed" 
                : "Pending"),
            if (completedAt != null) ...[
              _buildInfoRow("Completed", DateFormat.yMMMd().format(completedAt)),
              _buildInfoRow("Time to Complete", 
                  daysToComplete == 0 ? "Same day" : "$daysToComplete days"),
            ],
          ],
        ),
        
        if (taskData['notificationTimes'] != null) 
          _buildAnalyticsCard(
            title: "Schedule",
            children: [
              _buildInfoRow("Notification Times", 
                  _formatNotificationTimes(context, _parseNotificationTimes(taskData['notificationTimes']))),
            ],
          ),
      ],
    );
  }

  Widget _buildDailyTaskAnalytics(BuildContext context, Map<String, dynamic> taskData) {
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
    
    final notificationTimes = taskData['notificationTimes'] != null 
        ? _parseNotificationTimes(taskData['notificationTimes'])
        : null;
    
    final timeStats = _calculateTimeStats(
      context, 
      stamps, 
      notificationTimes
    );
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnalyticsCard(
          title: "Completion Insights",
          children: [
            _buildInfoRow("Total Completions", "$totalCompletions times"),
            _buildInfoRow("Current Streak", "$currentStreak days", 
                good: currentStreak >= 3),
            _buildInfoRow("Longest Streak", "$longestStreak days"),
            _buildInfoRow("Last 7 Days", "$last7Count/7 days", 
                good: last7Count >= 5),
            _buildInfoRow("Last 30 Days", "$last30Count/30 days", 
                good: last30Count >= 20),
            _buildInfoRow("Completion Rate", 
                "${((last30Count / 30) * 100).toStringAsFixed(1)}%"),
          ],
        ),
        
        _buildAnalyticsCard(
          title: "Time Performance",
          children: [
            if (timeStats['average'] != null)
              _buildInfoRow("Avg Completion Time", timeStats['average'] as String),
            if (notificationTimes != null && notificationTimes.isNotEmpty) ...[
              SizedBox(height: 8),
              Text("Scheduled Times:", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              _buildNotificationTimesList(context, notificationTimes),
            ],
            if (timeStats['onTimeRate'] != null)
              _buildInfoRow("On Time Rate", "${timeStats['onTimeRate']}%", 
                  good: (timeStats['onTimeRate'] as int) >= 70),
            if (timeStats['consistency'] != null)
              _buildInfoRow("Time Consistency", 
                  "${(timeStats['consistency'] as double).toStringAsFixed(1)}%", 
                  good: (timeStats['consistency'] as double) >= 80),
          ],
        ),
        
        if (notificationTimes != null && notificationTimes.isNotEmpty)
          _buildAnalyticsCard(
            title: "Notification Patterns",
            children: [
              _buildInfoRow("Most Common Time", 
                  _formatTimeOfDay(context, _findMostCommonTime(notificationTimes))),
              SizedBox(height: 8),
              Text("Time Distribution:", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              ..._getTimeDistributionList(notificationTimes).map((part) => 
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(part, style: TextStyle(fontSize: 14)),
                )
              ).toList(),
            ],
          ),
        
        if (stamps.isNotEmpty)
          _buildAnalyticsCard(
            title: "Recent Activity",
            children: [
              _buildInfoRow("Last Completed", DateFormat.yMMMd().format(stamps.last)),
              _buildInfoRow("Most Active Day", _findMostActiveDay(stamps)),
            ],
          ),
      ],
    );
  }

  Widget _buildWeeklyTaskAnalytics(BuildContext context, Map<String, dynamic> taskData) {
    final stamps = _parseCompletionStamps(taskData['completionStamps']);
    final totalCompletions = stamps.length;
    final now = DateTime.now();
    final last4Weeks = now.subtract(const Duration(days: 28));
    
    final last4WeeksCount = stamps.where((d) => d.isAfter(last4Weeks)).length;
    
    final streakInfo = _calculateWeeklyStreak(stamps);
    final currentStreak = streakInfo['current'] as int;
    final longestStreak = streakInfo['longest'] as int;
    
    final notificationTimes = taskData['notificationTimes'] != null 
        ? _parseNotificationTimes(taskData['notificationTimes'])
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnalyticsCard(
          title: "Completion Insights",
          children: [
            _buildInfoRow("Total Completions", "$totalCompletions weeks"),
            _buildInfoRow("Current Streak", "$currentStreak weeks", 
                good: currentStreak >= 3),
            _buildInfoRow("Longest Streak", "$longestStreak weeks"),
            _buildInfoRow("Last 4 Weeks", "$last4WeeksCount/4 weeks", 
                good: last4WeeksCount >= 3),
            _buildInfoRow("Completion Rate", 
                "${((last4WeeksCount / 4) * 100).toStringAsFixed(1)}%"),
          ],
        ),
        
        if (notificationTimes != null && notificationTimes.isNotEmpty)
          _buildAnalyticsCard(
            title: "Notification Schedule",
            children: [
              Text("Notification Times:", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              _buildNotificationTimesList(context, notificationTimes),
              SizedBox(height: 8),
              _buildInfoRow("Most Common Time", 
                  _formatTimeOfDay(context, _findMostCommonTime(notificationTimes))),
            ],
          ),
        
        _buildAnalyticsCard(
          title: "Performance Trends",
          children: [
            _buildInfoRow("Most Active Month", _findMostActiveMonth(stamps)),
            _buildInfoRow("Quarterly Consistency", 
                "${_calculateQuarterlyConsistency(stamps).toStringAsFixed(1)}%"),
          ],
        ),
        
        if (stamps.isNotEmpty)
          _buildAnalyticsCard(
            title: "Recent Activity",
            children: [
              _buildInfoRow("Last Completed", DateFormat.yMMMd().format(stamps.last)),
            ],
          ),
      ],
    );
  }

  Widget _buildMonthlyTaskAnalytics(BuildContext context, Map<String, dynamic> taskData) {
    final stamps = _parseCompletionStamps(taskData['completionStamps']);
    final totalCompletions = stamps.length;
    final now = DateTime.now();
    final currentYear = now.year;
    
    final yearlyCompletions = stamps
        .where((d) => d.year == currentYear)
        .length;
    
    final streakInfo = _calculateMonthlyStreak(stamps);
    final currentStreak = streakInfo['current'] as int;
    final longestStreak = streakInfo['longest'] as int;
    
    final notificationTimes = taskData['notificationTimes'] != null 
        ? _parseNotificationTimes(taskData['notificationTimes'])
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnalyticsCard(
          title: "Completion Insights",
          children: [
            _buildInfoRow("Total Completions", "$totalCompletions months"),
            _buildInfoRow("Current Streak", "$currentStreak months", 
                good: currentStreak >= 3),
            _buildInfoRow("Longest Streak", "$longestStreak months"),
            _buildInfoRow("This Year", "$yearlyCompletions/${now.month} months", 
                good: yearlyCompletions >= (now.month * 0.8).round()),
            _buildInfoRow("Completion Rate", 
                "${((yearlyCompletions / now.month) * 100).toStringAsFixed(1)}%"),
          ],
        ),
        
        if (notificationTimes != null && notificationTimes.isNotEmpty)
          _buildAnalyticsCard(
            title: "Notification Schedule",
            children: [
              Text("Notification Times:", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              _buildNotificationTimesList(context, notificationTimes),
              SizedBox(height: 8),
              _buildInfoRow("Most Common Time", 
                  _formatTimeOfDay(context, _findMostCommonTime(notificationTimes))),
            ],
          ),
        
        _buildAnalyticsCard(
          title: "Long-Term Trends",
          children: [
            _buildInfoRow("Most Active Year", _findMostActiveYear(stamps)),
            _buildInfoRow("Annual Consistency", 
                "${_calculateAnnualConsistency(stamps).toStringAsFixed(1)}%"),
          ],
        ),
        
        if (stamps.isNotEmpty)
          _buildAnalyticsCard(
            title: "Recent Activity",
            children: [
              _buildInfoRow("Last Completed", DateFormat.yMMMd().format(stamps.last)),
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

  List<TimeOfDay> _parseNotificationTimes(dynamic timesData) {
    if (timesData == null) return [];
    
    if (timesData is List) {
      return timesData.map((time) {
        if (time is Timestamp) {
          final dt = time.toDate();
          return TimeOfDay(hour: dt.hour, minute: dt.minute);
        }
        if (time is String) {
          // Handle string format if needed
          final parts = time.split(':');
          return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
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

  Map<String, dynamic> _calculateStreak(
    List<DateTime> stamps, 
    Duration recurrence
  ) {
    if (stamps.isEmpty) return {'current': 0, 'longest': 0};
    
    stamps.sort();
    final dates = stamps.map((d) => DateTime(d.year, d.month, d.day)).toSet();
    
    int currentStreak = 0;
    int longestStreak = 0;
    int tempStreak = 0;
    final today = DateTime.now();
    
    DateTime? prev;
    for (final date in stamps) {
      if (prev == null) {
        tempStreak = 1;
      } else {
        final diff = date.difference(prev);
        tempStreak = (diff.inDays ~/ recurrence.inDays) == 1 
            ? tempStreak + 1 
            : 1;
      }
      if (tempStreak > longestStreak) longestStreak = tempStreak;
      prev = date;
    }
    
    DateTime current = today;
    while (dates.contains(current)) {
      currentStreak++;
      current = current.subtract(recurrence);
    }
    
    return {'current': currentStreak, 'longest': longestStreak};
  }

  Map<String, dynamic> _calculateTimeStats(
    BuildContext context,
    List<DateTime> stamps, 
    List<TimeOfDay>? notificationTimes
  ) {
    if (stamps.isEmpty) return {};
    
    final totalMinutes = stamps.fold(0, (sum, stamp) => 
        sum + stamp.hour * 60 + stamp.minute);
    final avgMinutes = totalMinutes ~/ stamps.length;
    final avgTime = TimeOfDay(
      hour: avgMinutes ~/ 60,
      minute: avgMinutes % 60,
    );
    
    int onTimeCount = 0;
    if (notificationTimes != null && notificationTimes.isNotEmpty) {
      final scheduledMinutesList = notificationTimes
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
      'onTimeRate': notificationTimes != null && notificationTimes.isNotEmpty
          ? ((onTimeCount / stamps.length) * 100).round() 
          : null,
      'consistency': consistency,
    };
  }

  TimeOfDay _findMostCommonTime(List<TimeOfDay> times) {
    final timeCounts = <String, int>{};
    
    for (final time in times) {
      final key = '${time.hour}:${time.minute}';
      timeCounts[key] = (timeCounts[key] ?? 0) + 1;
    }
    
    final mostCommon = timeCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
    final parts = mostCommon.key.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _analyzeTimeDistribution(List<TimeOfDay> times) {
    final morning = times.where((t) => t.hour >= 6 && t.hour < 12).length;
    final afternoon = times.where((t) => t.hour >= 12 && t.hour < 18).length;
    final evening = times.where((t) => t.hour >= 18 && t.hour < 24).length;
    final night = times.where((t) => t.hour >= 0 && t.hour < 6).length;
    
    final total = times.length.toDouble();
    return 'Morning ${(morning/total*100).round()}%, '
           'Afternoon ${(afternoon/total*100).round()}%, '
           'Evening ${(evening/total*100).round()}%, '
           'Night ${(night/total*100).round()}%';
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
    
    final maxYear = yearCounts.entries
      .reduce((a, b) => a.value > b.value ? a : b)
      .key;
    
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

  String _formatTimeOfDay(BuildContext context, TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat.jm().format(dt);
  }

  String _formatNotificationTimes(BuildContext context, List<TimeOfDay> times) {
    if (times.isEmpty) return 'None';
    
    final formattedTimes = times
        .map((time) => _formatTimeOfDay(context, time))
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}