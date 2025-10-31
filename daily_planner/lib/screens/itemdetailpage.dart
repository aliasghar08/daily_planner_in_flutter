import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:daily_planner/utils/push_notifications.dart';
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
  late PushNotifications _pushNotifications;

  List<DateTime> completedList = [];
  List<DateTime> notificationTimes = [];
  bool? _currentCompletionStatus;
  bool _isLoading = true;
  bool _pushNotificationsInitialized = false;
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
    _pushNotifications = PushNotifications();
    _currentCompletionStatus = widget.task.isCompleted;

    // Async setup after first frame to avoid blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeNotifications();
      await _checkNotificationChannel();
      await _loadTaskData();
      await _initializePushNotifications();
    });
  }

  // NEW: Initialize PushNotifications
  Future<void> _initializePushNotifications() async {
    try {
      await _pushNotifications.initialize();
      setState(() {
        _pushNotificationsInitialized = true;
      });
      debugPrint('PushNotifications initialized successfully');
    } catch (e) {
      debugPrint('Error initializing PushNotifications: $e');
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
          .get(
            const GetOptions(source: Source.serverAndCache),
          );

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

  Future<void> _scheduleNativeAndLocalAlarm({
    required Duration delay,
    required String title,
    required String body,
  }) async {
    try {
      // Check if push notifications are initialized
      if (!_pushNotificationsInitialized) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Notifications not initialized yet. Please wait...')),
        );
        return;
      }

      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      final scheduledTime = DateTime.now().add(delay);

      // Use PushNotifications
      await _pushNotifications.scheduleNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        payload: body,
        channelId: "daily_planner_channel",
      );

      // Also schedule with local notifications for redundancy
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        NotificationDetails(android: _androidDetails),
       // uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exact,
      );

      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text("Alarm scheduled in ${delay.inSeconds} seconds"),
        ),
      );
    } catch (e) {
      debugPrint('Error scheduling alarm/notification: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text("Failed to schedule: $e")),
      );
    }
  }

  Future<void> _triggerTestAlarm() async {
    try {
      // Check if push notifications are initialized
      if (!_pushNotificationsInitialized) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Notifications not initialized yet. Please wait...')),
        );
        return;
      }  

      int notId = generateNotificationId(widget.task.docId  as String, DateTime.now());
      
      // Test immediate notification first
      await _pushNotifications.showNotification(
        title: "Test Started",
        body: "This is an immediate test notification!",
        payload: "test_started", id: notId,
      );

      // Then schedule one for 2 seconds
      final scheduledTime = DateTime.now().add(const Duration(seconds: 2));
      notId = generateNotificationId(widget.task.docId as String, DateTime.now());
      await _pushNotifications.scheduleNotification(
        title: "🔔 Test Alarm",
        body: "You tapped the test button!",
        scheduledTime: scheduledTime,
        payload: "test_alarm",
        channelId: "daily_planner_channel", id: notId,
      );

      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text("Test notifications sent! Check for immediate one and one in 2 seconds.")),
      );
    } catch (e) {
      debugPrint('Error in test alarm: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text("Something went wrong: $e")),
      );
    }
  }

  Future<void> _cancelAllNotifications() async {
    try {
      if (_pushNotificationsInitialized) {
        await _pushNotifications.cancelAllNotifications();
      }
      await flutterLocalNotificationsPlugin.cancelAll();
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text("All scheduled notifications canceled")),
      );
    } catch (e) {
      debugPrint('Error cancelling notifications: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text("Failed to cancel notifications: $e")),
      );
    }
  }

  // ... rest of your existing methods (_toggleCompletion, _isSameDay, etc.) remain the same
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
      completedList = currentStamps.map((ts) => ts.toDate()).toList()
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

  @override
  Widget build(BuildContext context) {
    final task = widget.task;

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final formattedDate = DateFormat('MMM d, yyyy').format(task.date);
    final formattedTime = TimeOfDay.fromDateTime(task.date).format(context);
    final lastCompleted = completedList.isNotEmpty ? completedList.first : null;

    return ScaffoldMessenger(
      key: scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text("Task Detail")),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Add initialization status indicator
                if (!_pushNotificationsInitialized)
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
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.calendar_today),
                    const SizedBox(width: 8),
                    Text("Date: $formattedDate"),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time),
                    const SizedBox(width: 8),
                    Text("Time: $formattedTime"),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.history),
                    const SizedBox(width: 8),
                    Text(
                      "Created on: ${DateFormat('MMM d, yyyy • h:mm a').format(task.createdAt)}",
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.flag),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _toggleCompletion(!(_currentCompletionStatus ?? false)),
                      child: Chip(
                        label: Text(
                          _currentCompletionStatus! ? "Completed" : "Pending",
                        ),
                        backgroundColor: _currentCompletionStatus! ? Colors.green : Colors.red,
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
                      Text(
                        task.taskType != 'oneTime'
                            ? "Last Completed: ${DateFormat('MMM d, yyyy • h:mm a').format(lastCompleted)}"
                            : "Completed At: ${DateFormat('MMM d, yyyy • h:mm a').format(lastCompleted)}",
                      ),
                    ],
                  ),
                ],
                if (task.taskType != 'oneTime') ...[
                  _buildCompletionTimesExpansion(),
                ],
                const SizedBox(height: 24),
                _buildNotificationTimesExpansion(),
                const Divider(),
                _buildNotificationTestButtons(),
                const Divider(),
                _buildEditHistory(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ... rest of your widget methods (_buildCompletionTimesExpansion, etc.) remain the same
  Widget _buildCompletionTimesExpansion() => ExpansionTile(
    leading: const Icon(Icons.list_alt),
    title: const Text("See All Completion Times"),
    children: completedList.isEmpty
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
                leading: const Icon(Icons.check),
                title: Text(
                  DateFormat('MMM d, yyyy • h:mm a').format(date),
                ),
              ),
            )
            .toList(),
  );

  Widget _buildNotificationTimesExpansion() => ExpansionTile(
    leading: const Icon(Icons.notifications),
    title: const Text("See All Notification Times"),
    children: notificationTimes.isEmpty
        ? [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  "No Notification Times available",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ]
        : notificationTimes
            .map(
              (date) => ListTile(
                leading: const Icon(Icons.check),
                title: Text(
                  DateFormat('MMM d, yyyy • h:mm a').format(date),
                ),
              ),
            )
            .toList(),
  );

  Widget _buildNotificationTestButtons() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "🔔 Notification Test Buttons",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      // Add initialization status to button
      ElevatedButton(
        onPressed: _pushNotificationsInitialized ? _triggerTestAlarm : null,
        child: Text(_pushNotificationsInitialized 
            ? "Test Alarm (2 seconds)" 
            : "Initializing..."),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _pushNotificationsInitialized 
            ? () => _scheduleNativeAndLocalAlarm(
                  delay: const Duration(seconds: 10),
                  title: "⏰ Scheduled Alarm",
                  body: "This alarm is scheduled for 10 seconds later!",
                )
            : null,
        child: Text(_pushNotificationsInitialized 
            ? "Schedule Alarm (10 seconds)" 
            : "Initializing..."),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _pushNotificationsInitialized 
            ? () => _scheduleNativeAndLocalAlarm(
                  delay: const Duration(minutes: 1),
                  title: "⏰ Scheduled Alarm",
                  body: "This alarm is scheduled for 1 minute later!",
                )
            : null,
        child: Text(_pushNotificationsInitialized 
            ? "Schedule Alarm (1 min)" 
            : "Initializing..."),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        onPressed: _pushNotificationsInitialized ? _cancelAllNotifications : null,
        child: Text(_pushNotificationsInitialized 
            ? "Cancel All Scheduled Notifications" 
            : "Initializing..."),
      ),
    ],
  );

  Widget _buildEditHistory() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 32),
      const Text(
        "📜 Edit History",
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      if (widget.task.editHistory.isEmpty)
        const Text("No edits made yet.", style: TextStyle(fontSize: 16))
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.task.editHistory.map((edit) {
            final formattedEditTime = DateFormat(
              'MMM d, yyyy • h:mm a',
            ).format(edit.timestamp);
            return ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(formattedEditTime),
              subtitle: edit.note != null && edit.note!.isNotEmpty
                  ? Text(edit.note!)
                  : const Text("No note"),
              contentPadding: EdgeInsets.zero,
            );
          }).toList(),
        ),
    ],
  );
}