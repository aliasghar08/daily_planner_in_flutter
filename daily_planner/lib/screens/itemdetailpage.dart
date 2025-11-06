import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:daily_planner/utils/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

class ItemDetailPage extends StatefulWidget {
  final Task task;

  const ItemDetailPage({super.key, required this.task});

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  List<DateTime> completedList = [];
  List<DateTime> notificationTimes = [];
  bool? _currentCompletionStatus;
  bool _isLoading = true;
  bool _nativeAlarmInitialized = false;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  final AndroidNotificationDetails _androidDetails =
      const AndroidNotificationDetails(
        'daily_planner_channel',
        'Daily Planner Notifications',
        importance: Importance.max,
        priority: Priority.high,
        channelDescription: 'Channel for task reminders',
        playSound: true,
        enableLights: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
      );

  @override
  void initState() {
    super.initState();
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    _currentCompletionStatus = widget.task.isCompleted;

    // Initialize NativeAlarmHelper and load data
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeNativeAlarmHelper();
      await _checkNotificationChannel();
      await _loadTaskData();
    });
  }

  Future<void> _initializeNativeAlarmHelper() async {
    try {
      await NativeAlarmHelper.initialize();
      setState(() {
        _nativeAlarmInitialized = true;
      });
      debugPrint('✅ NativeAlarmHelper initialized successfully');
    } catch (e) {
      debugPrint('❌ NativeAlarmHelper initialization failed: $e');
      setState(() {
        _nativeAlarmInitialized = false;
      });
    }
  }

  // ✅ Helper function to format dates in "Saturday, 23rd August 2025" format
  String _formatDateTime(DateTime? date) {
    if (date == null) return "Not set";

    // Format: Saturday, 23rd August 2025 at 3:30 PM
    final daySuffix = _getDaySuffix(date.day);
    final dateFormat = DateFormat("EEEE, d'$daySuffix' MMMM yyyy 'at' h:mm a");
    return dateFormat.format(date);
  }

  // ✅ Helper function to get day suffix (st, nd, rd, th)
  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  // ✅ Helper function for shorter date format (for lists)
  String _formatShortDateTime(DateTime date) {
    final daySuffix = _getDaySuffix(date.day);
    final dateFormat = DateFormat("EEE, d'$daySuffix' MMM yyyy 'at' h:mm a");
    return dateFormat.format(date);
  }

  Future<void> _loadTaskData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(widget.task.docId)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!doc.exists) return;

      final data = doc.data()!;
      final loadedCompletionStatus = data['isCompleted'] ?? false;

      final loadedStamps =
          (data['completionStamps'] as List<dynamic>?)
              ?.whereType<Timestamp>()
              .map((ts) => ts.toDate())
              .toList() ??
          [];
      final loadedNotifications =
          (data['notificationTimes'] as List<dynamic>?)
              ?.whereType<Timestamp>()
              .map((ts) => ts.toDate())
              .toList() ??
          [];

      // ✅ Load edit history from Firestore
      final loadedEditHistory =
          (data['editHistory'] as List<dynamic>?)
              ?.map((editMap) => _parseEditHistory(editMap))
              .whereType<TaskEdit>()
              .toList() ??
          [];

      loadedStamps.sort((a, b) => b.compareTo(a));
      loadedNotifications.sort((a, b) => b.compareTo(a));
      loadedEditHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _currentCompletionStatus = loadedCompletionStatus;
        completedList = loadedStamps;
        notificationTimes = loadedNotifications;
        // ✅ Update the task with loaded edit history
        widget.task.editHistory = loadedEditHistory;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading task data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ ADD: Helper function to parse EditHistory from Firestore data
  TaskEdit? _parseEditHistory(dynamic editMap) {
    try {
      if (editMap is Map<String, dynamic>) {
        final timestamp = editMap['timestamp'] as Timestamp?;
        final note = editMap['note'] as String?;

        if (timestamp != null) {
          return TaskEdit(timestamp: timestamp.toDate(), note: note);
        }
      }
      return null;
    } catch (e) {
      debugPrint("Error parsing edit history: $e");
      return null;
    }
  }

  @override
  void didUpdateWidget(ItemDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.docId != widget.task.docId) _loadTaskData();
  }

  Future<void> _checkNotificationChannel() async {
    if (!Platform.isAndroid) return;
    final androidImpl =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    final channels = await androidImpl?.getNotificationChannels();
    if (channels == null || channels.isEmpty)
      await _createNotificationChannel();
  }

  Future<void> _createNotificationChannel() async {
    if (!Platform.isAndroid) return;
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            _androidDetails.channelId,
            _androidDetails.channelName,
            description: _androidDetails.channelDescription,
            importance: _androidDetails.importance,
            playSound: _androidDetails.playSound,
            enableVibration: _androidDetails.enableVibration,
            enableLights: _androidDetails.enableLights,
          ),
        );
  }

  // ✅ UPDATED: Use NativeAlarmHelper for notifications
  Future<void> _triggerTestAlarm(int seconds) async {
    try {
      final scheduledTime = DateTime.now().add(Duration(seconds: seconds));

      // Check if native alarm system is initialized
      if (!_nativeAlarmInitialized) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Alarm system not initialized yet. Please wait...'),
          ),
        );
        return;
      }

      // Get connectivity status for user feedback
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      final isOnline = results.any(
        (result) =>
            result == ConnectivityResult.wifi ||
            result == ConnectivityResult.mobile ||
            result == ConnectivityResult.ethernet ||
            result == ConnectivityResult.vpn,
      );

      // Use NativeAlarmHelper to schedule the alarm
      await NativeAlarmHelper.scheduleHybridAlarm(
        id: _generateAlarmId(widget.task.docId!, scheduledTime),
        title: "🚨 ALARM: ${widget.task.title}",
        body: "Tap to view task details",
        dateTime: scheduledTime,
        payload: {
          'taskId': widget.task.docId,
          'type': 'task_reminder',
          'taskTitle': widget.task.title,
          'dueDate': widget.task.date?.toIso8601String(),
        },
      );

      // Show specific feedback based on connectivity and system
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            "✅ Hybrid alarm scheduled for $seconds seconds!\n"
            "• Native Android Alarm (most reliable)\n"
            "• Fallback to local notifications\n"
            "• ${isOnline ? 'Online - push capable' : 'Offline - local only'}",
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      debugPrint('Native alarm scheduled for: $scheduledTime');
      debugPrint('Connectivity status: ${isOnline ? 'Online' : 'Offline'}');
    } catch (e) {
      debugPrint('Error in test alarm: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text("❌ Failed to schedule alarm: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ✅ UPDATED: Generate unique alarm ID
  int _generateAlarmId(String taskId, DateTime time) {
    return (taskId + time.millisecondsSinceEpoch.toString()).hashCode.abs() %
        1000000;
  }

  // ✅ UPDATED: Cancel alarms using NativeAlarmHelper
  Future<void> _cancelAllNotifications() async {
    try {
      if (_nativeAlarmInitialized) {
        // Cancel all potential alarms for this task
        // Since we don't store all alarm IDs, we'll cancel by known patterns
        // or cancel all and reschedule if needed

        // For now, cancel any alarms that might be scheduled in the near future
        final now = DateTime.now();
        final futureCutoff = now.add(const Duration(days: 30));

        // Generate possible alarm IDs for the near future and cancel them
        for (int i = 0; i < 100; i++) {
          final testTime = now.add(Duration(hours: i));
          final alarmId = _generateAlarmId(widget.task.docId!, testTime);
          await NativeAlarmHelper.cancelAlarmById(alarmId);
        }

        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text("All scheduled alarms canceled for this task"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text("Alarm system not initialized"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error cancelling alarms: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text("Failed to cancel alarms: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ✅ UPDATED: Test immediate notification using NativeAlarmHelper
  Future<void> _testImmediateNotification() async {
    try {
      await NativeAlarmHelper.showNow(
        id: _generateAlarmId(widget.task.docId!, DateTime.now()),
        title: "🔔 TEST: ${widget.task.title}",
        body: "This is a test notification with alarm behavior",
      );

      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text("✅ Test notification shown with alarm behavior"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Error showing immediate notification: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text("❌ Failed to show test notification: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleCompletion(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.task.docId == null) return;

    final now = DateTime.now();
    final nowStamp = Timestamp.fromDate(now.toUtc());

    final currentStamps = List<Timestamp>.from(
      widget.task.completionStamps ?? [],
    );

    if (value) {
      bool exists = currentStamps.any((ts) {
        final dt = ts.toDate().toLocal();
        if (widget.task.taskType == 'DailyTask') return _isSameDay(dt, now);
        if (widget.task.taskType == 'WeeklyTask') return _isSameWeek(dt, now);
        if (widget.task.taskType == 'MonthlyTask') return _isSameMonth(dt, now);
        return false;
      });

      if (!exists) currentStamps.add(nowStamp);
    } else {
      currentStamps.removeWhere((ts) {
        final dt = ts.toDate().toLocal();
        if (widget.task.taskType == 'DailyTask') return _isSameDay(dt, now);
        if (widget.task.taskType == 'WeeklyTask') return _isSameWeek(dt, now);
        if (widget.task.taskType == 'MonthlyTask') return _isSameMonth(dt, now);
        return false;
      });
    }

    setState(() {
      _currentCompletionStatus = value;
      completedList =
          currentStamps.map((ts) => ts.toDate()).toList()
            ..sort((a, b) => b.compareTo(a));
    });

    Navigator.pop(context);

    final updateData = <String, dynamic>{
      'isCompleted': value,
      'completionStamps': currentStamps,
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(widget.task.docId)
          .set(updateData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to update Firestore: $e');
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isSameWeek(DateTime a, DateTime b) =>
      a.year == b.year && (a.weekday - b.weekday).abs() < 7;

  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  // ✅ Get task type display info
  String _getTaskTypeLabel() {
    final taskType = widget.task.taskType;
    switch (taskType) {
      case 'oneTime':
        return 'One-Time Task';
      case 'DailyTask':
        return 'Daily Task';
      case 'WeeklyTask':
        return 'Weekly Task';
      case 'MonthlyTask':
        return 'Monthly Task';
      default:
        return 'Task';
    }
  }

  IconData _getTaskTypeIcon() {
    final taskType = widget.task.taskType;
    switch (taskType) {
      case 'oneTime':
        return Icons.push_pin;
      case 'DailyTask':
        return Icons.loop;
      case 'WeeklyTask':
        return Icons.calendar_today;
      case 'MonthlyTask':
        return Icons.date_range;
      default:
        return Icons.task;
    }
  }

  Color _getTaskTypeColor() {
    final taskType = widget.task.taskType;
    switch (taskType) {
      case 'oneTime':
        return Colors.blue;
      case 'DailyTask':
        return Colors.green;
      case 'WeeklyTask':
        return Colors.orange;
      case 'MonthlyTask':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // ✅ Use new date formatting functions
    final formattedDeadline = _formatDateTime(task.date);
    final formattedCreatedAt = _formatDateTime(task.createdAt);
    final lastCompleted = completedList.isNotEmpty ? completedList.first : null;

    return ScaffoldMessenger(
      key: scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Task Detail"),
          backgroundColor: _getTaskTypeColor().withOpacity(0.1),
          foregroundColor: _getTaskTypeColor(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task Type Header
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _getTaskTypeColor().withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _getTaskTypeIcon(),
                            color: _getTaskTypeColor(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getTaskTypeLabel(),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _getTaskTypeColor(),
                                ),
                              ),
                              Text(
                                task.date == null &&
                                        _getTaskTypeLabel() != 'One-Time Task'
                                    ? "Continues indefinitely"
                                    : "Created ${_formatShortDateTime(task.createdAt)}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Add initialization status indicator
                if (!_nativeAlarmInitialized)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.orange[100],
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.orange[800]),
                        const SizedBox(width: 8),
                        const Text(
                          'Initializing alarm system...',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ],
                    ),
                  ),

                // Task Title and Details
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          task.detail.isNotEmpty ? task.detail : "No details.",
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ✅ Date & Time Information with new formatting
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.date == null &&
                                  _getTaskTypeLabel() != 'One-Time Task'
                              ? "Recurring Schedule"
                              : "Deadline",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color:
                                  task.date == null ? Colors.grey : Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                task.date == null
                                    ? (_getTaskTypeLabel() != 'One-Time Task'
                                        ? "Recurs indefinitely"
                                        : "No deadline set")
                                    : formattedDeadline,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontStyle:
                                      task.date == null
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.history, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Created on: $formattedCreatedAt",
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Completion Status
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Completion Status",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.flag),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap:
                                  () => _toggleCompletion(
                                    !(_currentCompletionStatus ?? false),
                                  ),
                              child: Chip(
                                label: Text(
                                  _currentCompletionStatus!
                                      ? "Completed"
                                      : "Pending",
                                ),
                                backgroundColor:
                                    _currentCompletionStatus!
                                        ? Colors.green
                                        : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        if (lastCompleted != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.check_circle_outline),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  task.taskType != 'oneTime'
                                      ? "Last Completed: ${_formatDateTime(lastCompleted)}"
                                      : "Completed At: ${_formatDateTime(lastCompleted)}",
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                if (task.taskType != 'oneTime') ...[
                  const SizedBox(height: 16),
                  _buildCompletionTimesExpansion(),
                ],
                const SizedBox(height: 16),
                _buildNotificationTimesExpansion(),
                const SizedBox(height: 16),
                _buildAlarmTestButtons(),
                const SizedBox(height: 16),
                _buildEditHistory(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionTimesExpansion() => Card(
    elevation: 2,
    child: ExpansionTile(
      leading: const Icon(Icons.list_alt),
      title: const Text("Completion History"),
      children:
          completedList.isEmpty
              ? [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      "No completion times available",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ]
              : completedList
                  .map(
                    (date) => ListTile(
                      leading: const Icon(Icons.check, color: Colors.green),
                      title: Text(_formatShortDateTime(date)),
                    ),
                  )
                  .toList(),
    ),
  );

  Widget _buildNotificationTimesExpansion() => Card(
    elevation: 2,
    child: ExpansionTile(
      leading: const Icon(Icons.notifications),
      title: const Text("Scheduled Notifications"),
      children:
          notificationTimes.isEmpty
              ? [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      "No notifications scheduled",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ]
              : notificationTimes
                  .map(
                    (date) => ListTile(
                      leading: const Icon(
                        Icons.notifications_active,
                        color: Colors.blue,
                      ),
                      title: Text(_formatShortDateTime(date)),
                    ),
                  )
                  .toList(),
    ),
  );

  // ✅ UPDATED: Alarm test buttons using NativeAlarmHelper
  Widget _buildAlarmTestButtons() => Card(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "⏰ Native Alarm System",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[100]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "How it works:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 4),
                _buildFeatureRow(
                  "📱 Native Android Alarm",
                  "Uses AlarmManager - most reliable",
                ),
                _buildFeatureRow(
                  "🔄 Automatic Fallback",
                  "Falls back to local notifications",
                ),
                _buildFeatureRow(
                  "🔔 Alarm Behavior",
                  "Persistent notifications with actions",
                ),
                _buildFeatureRow(
                  "⚡ Exact Timing",
                  "Uses exact alarms for precision",
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Immediate test notification
          ElevatedButton(
            onPressed:
                _nativeAlarmInitialized ? _testImmediateNotification : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(
              _nativeAlarmInitialized
                  ? "Test Immediate Alarm Notification"
                  : "Initializing...",
            ),
          ),
          const SizedBox(height: 8),

          // Scheduled alarm tests
          ElevatedButton(
            onPressed:
                _nativeAlarmInitialized ? () => _triggerTestAlarm(2) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(
              _nativeAlarmInitialized
                  ? "Test Alarm (2 seconds)"
                  : "Initializing...",
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed:
                _nativeAlarmInitialized ? () => _triggerTestAlarm(10) : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(
              _nativeAlarmInitialized
                  ? "Test Alarm (10 seconds)"
                  : "Initializing...",
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed:
                _nativeAlarmInitialized ? () => _triggerTestAlarm(60) : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(
              _nativeAlarmInitialized
                  ? "Test Alarm (1 minute)"
                  : "Initializing...",
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
            onPressed: _nativeAlarmInitialized ? _cancelAllNotifications : null,
            child: Text(
              _nativeAlarmInitialized
                  ? "Cancel All Alarms for This Task"
                  : "Initializing...",
            ),
          ),
        ],
      ),
    ),
  );

  // Helper widget for feature list
  Widget _buildFeatureRow(String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildEditHistory() => Card(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "📜 Edit History",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (widget.task.editHistory.isEmpty)
            const Text(
              "No edits made yet.",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:
                  widget.task.editHistory.map((edit) {
                    final formattedEditTime = _formatShortDateTime(
                      edit.timestamp,
                    );
                    return ListTile(
                      leading: const Icon(Icons.edit_note),
                      title: Text(formattedEditTime),
                      subtitle:
                          edit.note != null && edit.note!.isNotEmpty
                              ? Text(edit.note!)
                              : const Text("No note"),
                      contentPadding: EdgeInsets.zero,
                    );
                  }).toList(),
            ),
        ],
      ),
    ),
  );
}
