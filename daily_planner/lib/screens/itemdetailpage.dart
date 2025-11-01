import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:daily_planner/utils/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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
  bool _notificationServiceInitialized = false;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  final notificationService = NotificationService();

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

    // Async setup after first frame to avoid blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeNotifications();
      await _checkNotificationChannel();
      await _loadTaskData();
      await _initializeNotificationService();
    });
  }

  // ✅ NEW: Helper function to format dates in "Saturday, 23rd August 2025" format
  String _formatDateTime(DateTime? date) {
    if (date == null) return "Not set";
    
    // Format: Saturday, 23rd August 2025 at 3:30 PM
    final daySuffix = _getDaySuffix(date.day);
    final dateFormat = DateFormat("EEEE, d'$daySuffix' MMMM yyyy 'at' h:mm a");
    return dateFormat.format(date);
  }

  // ✅ NEW: Helper function to get day suffix (st, nd, rd, th)
  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }

  // ✅ NEW: Helper function for shorter date format (for lists)
  String _formatShortDateTime(DateTime date) {
    final daySuffix = _getDaySuffix(date.day);
    final dateFormat = DateFormat("EEE, d'$daySuffix' MMM yyyy 'at' h:mm a");
    return dateFormat.format(date);
  }

  // MODIFIED: Initialize NotificationService only
  Future<void> _initializeNotificationService() async {
    try {
      await notificationService.initialize();
      setState(() {
        _notificationServiceInitialized = true;
      });
      debugPrint('NotificationService initialized successfully');
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Failed to initialize notifications: $e')),
      );
    }
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

      loadedStamps.sort((a, b) => b.compareTo(a));
      loadedNotifications.sort((a, b) => b.compareTo(a));

      setState(() {
        _currentCompletionStatus = loadedCompletionStatus;
        completedList = loadedStamps;
        notificationTimes = loadedNotifications;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading task data: $e");
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _initializeNotifications() async {
    try {
      tz.initializeTimeZones();

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      final iOSSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      await flutterLocalNotificationsPlugin.initialize(
        InitializationSettings(android: androidSettings, iOS: iOSSettings),
        onDidReceiveNotificationResponse:
            (details) => debugPrint('Notification tapped: ${details.payload}'),
      );

      if (Platform.isAndroid) await _requestAndroidPermissions();
    } catch (e) {
      debugPrint('Notification init error: $e');
    }
  }

  Future<void> _requestAndroidPermissions() async {
    final granted =
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
    debugPrint('Notification permission granted: $granted');
  }

  int generateNotificationId(String taskId, DateTime time) =>
      (taskId + time.toIso8601String()).hashCode.abs();

  // MODIFIED: Use NotificationService for hybrid notifications with clear feedback
Future<void> _triggerTestAlarm(int sec) async {
  try {
    // alarm will be triggered on scheduled time
    final scheduledTime = DateTime.now().add(Duration(seconds: sec));
    final scheduledTimeUtc = scheduledTime.toUtc();

    // Check if notification service is initialized
    if (!_notificationServiceInitialized) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Notifications not initialized yet. Please wait...'),
        ),
      );
      return;
    }

    // Get connectivity status for user feedback
    final connectivity = Connectivity();
    final results = await connectivity.checkConnectivity();
    final isOnline = results.any((result) => 
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet ||
        result == ConnectivityResult.vpn);

    // Use NotificationService for hybrid notifications (local + push based on connectivity)
    await notificationService.scheduleTaskNotification(
      taskId: widget.task.docId!,
      title: widget.task.title,
      body: "🔔 Reminder: ${widget.task.title}",
      scheduledTimeUtc: scheduledTimeUtc,
      payload: {
        'taskId': widget.task.docId!,
        'type': 'test_notification',
        'scheduledTime': scheduledTimeUtc.toIso8601String(),
      },
    );

    // Show specific feedback based on connectivity
    if (isOnline) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            "✅ Hybrid notification scheduled for $sec seconds!\n"
            "• Local notification (always works)\n"
            "• Push notification (sent to server)",
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            "📱 Local notification scheduled for $sec seconds!\n"
            "• Local notification (scheduled now)\n"
            "• Push notification (queued - will send when online)",
          ),
          backgroundColor: Colors.blue,
        ),
      );
    }

    debugPrint('Connectivity status: ${isOnline ? 'Online' : 'Offline'}');
    debugPrint('Notification scheduled for: $scheduledTime');

  } catch (e) {
    debugPrint('Error in test alarm: $e');
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text("❌ Failed to schedule notification: $e"),
        backgroundColor: Colors.red,
      ),
    );
  }
}
  // MODIFIED: Cancel all notifications using NotificationService
  Future<void> _cancelAllNotifications() async {
    try {
      if (_notificationServiceInitialized) {
        // Get all scheduled times for this task and cancel them
        final scheduledTimes = await notificationService.getScheduledTimesForDocument(widget.task.docId!);
        
        if (scheduledTimes.isNotEmpty) {
          await notificationService.cancelAllNotificationsForDocument(
            docId: widget.task.docId!,
            scheduledTimesUtc: scheduledTimes,
          );
        }
        
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text("All scheduled notifications canceled")),
        );
      } else {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text("Notification service not initialized")),
        );
      }
    } catch (e) {
      debugPrint('Error cancelling notifications: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text("Failed to cancel notifications: $e")),
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

  // ✅ NEW: Get task type display info
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

    // ✅ UPDATED: Use new date formatting functions
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
                                task.date == null && _getTaskTypeLabel() != 'One-Time Task'
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
                if (!_notificationServiceInitialized)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.orange[100],
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.orange[800]),
                        const SizedBox(width: 8),
                        const Text(
                          'Initializing notifications...',
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
                          style: const TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ✅ UPDATED: Date & Time Information with new formatting
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.date == null && _getTaskTypeLabel() != 'One-Time Task'
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
                              color: task.date == null ? Colors.grey : Colors.blue,
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
                                  fontStyle: task.date == null ? FontStyle.italic : FontStyle.normal,
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
                                  _currentCompletionStatus! ? "Completed" : "Pending",
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
                _buildNotificationTestButtons(),
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
                      title: Text(
                        _formatShortDateTime(date), // ✅ UPDATED: Use short format for lists
                      ),
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
                      leading: const Icon(Icons.notifications_active, color: Colors.blue),
                      title: Text(
                        _formatShortDateTime(date), // ✅ UPDATED: Use short format for lists
                      ),
                    ),
                  )
                  .toList(),
    ),
  );

  // MODIFIED: Updated button texts and handlers with better explanation
Widget _buildNotificationTestButtons() => Card(
  elevation: 2,
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "🔔 Smart Notification System",
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
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              const SizedBox(height: 4),
              _buildFeatureRow("📱 Local Notification", "Always scheduled - works offline"),
              _buildFeatureRow("🌐 Push Notification", "Sent to server when online"),
              _buildFeatureRow("⏰ Queued Notifications", "Auto-send when connection returns"),
              _buildFeatureRow("🔄 Cross-Device Sync", "Push notifications sync across devices"),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _notificationServiceInitialized 
              ? () => _triggerTestAlarm(2)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
          ),
          child: Text(
            _notificationServiceInitialized
                ? "Test Smart Notification (2 seconds)"
                : "Initializing...",
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _notificationServiceInitialized 
              ? () => _triggerTestAlarm(10)
              : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: Text(
            _notificationServiceInitialized
                ? "Test Smart Notification (10 seconds)"
                : "Initializing...",
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _notificationServiceInitialized 
              ? () => _triggerTestAlarm(60)
              : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: Text(
            _notificationServiceInitialized
                ? "Test Smart Notification (1 minute)"
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
          onPressed: _notificationServiceInitialized ? _cancelAllNotifications : null,
          child: Text(
            _notificationServiceInitialized
                ? "Cancel All Notifications for This Task"
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
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
            const Text("No edits made yet.", style: TextStyle(fontSize: 16, color: Colors.grey))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:
                  widget.task.editHistory.map((edit) {
                    final formattedEditTime = _formatShortDateTime(edit.timestamp); // ✅ UPDATED
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