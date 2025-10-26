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

  List<DateTime> completedList = [];
  List<DateTime> notificationTimes = [];
  bool? _currentCompletionStatus;
  bool _isLoading = true;
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

    // Async setup after first frame to avoid blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeNotifications();
      await _checkNotificationChannel();
      await _loadTaskData();
    });
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
          ); // <-- offline-safe

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
      loadedNotifications.sort((a, b) => b.compareTo(a)); // latest on top

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

  Future<void> _scheduleNativeAndLocalAlarm({
    required Duration delay,
    required String title,
    required String body,
  }) async {
    try {
      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      final scheduledTime = DateTime.now().add(delay);

      // if (!await NativeAlarmHelper.checkExactAlarmPermission()) {
      //   scaffoldMessengerKey.currentState?.showSnackBar(
      //     const SnackBar(content: Text("Please grant exact alarm permission first")),
      //   );
      //   return;
      // }

      // await NativeAlarmHelper.scheduleAlarmAtTime(
      //   id: id,
      //   dateTime: scheduledTime,
      //   title: title,
      //   body: body,
      // );

      await PushNotifications().scheduleNotification(
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        payload: body,
        channelId: "GENERAL_NOTIFICATIONS",
        channelName: "GENERAL NOTIFICATIONS",
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        NotificationDetails(android: _androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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

  Future<void> _triggerTestAlarm() async => _scheduleNativeAndLocalAlarm(
    delay: const Duration(seconds: 2),
    title: '🔔 Test Alarm',
    body: 'You tapped the test alarm button!',
  );

  Future<void> _cancelAllNotifications() async {
    try {
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

  // Future<void> _toggleCompletion(bool value) async {
  //   final user = FirebaseAuth.instance.currentUser;
  //   if (user == null || widget.task.docId == null) return;

  //   final now = DateTime.now();
  //   final nowStamp = Timestamp.fromDate(now.toUtc());

  //   final currentStamps = widget.task.completionStamps ?? [];

  //   final updateData = <String, dynamic>{'isCompleted': value};

  //   // Update completionStamps
  //   bool exists = currentStamps.any((ts) {
  //     final dt = ts.toDate().toLocal();
  //     if (widget.task.taskType == 'DailyTask') return _isSameDay(dt, now);
  //     if (widget.task.taskType == 'WeeklyTask') return _isSameWeek(dt, now);
  //     if (widget.task.taskType == 'MonthlyTask') return _isSameMonth(dt, now);
  //     return false;
  //   });

  //   if (value && !exists) updateData['completionStamps'] = FieldValue.arrayUnion([nowStamp]);
  //   if (!value && exists) {
  //     final toRemove = currentStamps.where((ts) {
  //       final dt = ts.toDate().toLocal();
  //       if (widget.task.taskType == 'DailyTask') return _isSameDay(dt, now);
  //       if (widget.task.taskType == 'WeeklyTask') return _isSameWeek(dt, now);
  //       if (widget.task.taskType == 'MonthlyTask') return _isSameMonth(dt, now);
  //       return false;
  //     }).toList();
  //     updateData['completionStamps'] = FieldValue.arrayRemove(toRemove);
  //   }

  //   await FirebaseFirestore.instance
  //       .collection('users')
  //       .doc(user.uid)
  //       .collection('tasks')
  //       .doc(widget.task.docId)
  //       .update(updateData);

  //   setState(() => _currentCompletionStatus = value);
  // }

  Future<void> _toggleCompletion(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.task.docId == null) return;

    final now = DateTime.now();
    final nowStamp = Timestamp.fromDate(now.toUtc());

    // Create a mutable copy of completionStamps
    final currentStamps = List<Timestamp>.from(
      widget.task.completionStamps ?? [],
    );

    if (value) {
      // Add today’s completion if not already present
      bool exists = currentStamps.any((ts) {
        final dt = ts.toDate().toLocal();
        if (widget.task.taskType == 'DailyTask') return _isSameDay(dt, now);
        if (widget.task.taskType == 'WeeklyTask') return _isSameWeek(dt, now);
        if (widget.task.taskType == 'MonthlyTask') return _isSameMonth(dt, now);
        return false;
      });

      if (!exists) currentStamps.add(nowStamp);
    } else {
      // Remove today’s completion
      currentStamps.removeWhere((ts) {
        final dt = ts.toDate().toLocal();
        if (widget.task.taskType == 'DailyTask') return _isSameDay(dt, now);
        if (widget.task.taskType == 'WeeklyTask') return _isSameWeek(dt, now);
        if (widget.task.taskType == 'MonthlyTask') return _isSameMonth(dt, now);
        return false;
      });
    }

    // Update UI immediately
    setState(() {
      _currentCompletionStatus = value;
      completedList =
          currentStamps.map((ts) => ts.toDate()).toList()
            ..sort((a, b) => b.compareTo(a));
    });

    // Navigate back immediately (non-blocking)
    Navigator.pop(context);

    // Firestore update in background
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
          .set(updateData, SetOptions(merge: true)); // merge with existing
    } catch (e) {
      debugPrint('Failed to update Firestore: $e');
      // Optionally save to local cache for retry if offline
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

  Widget _buildCompletionTimesExpansion() => ExpansionTile(
    leading: const Icon(Icons.list_alt),
    title: const Text("See All Completion Times"),
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
    children:
        notificationTimes.isEmpty
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
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          "Note: Using default system sound. To add custom sounds:\n"
          "1. Add your sound file to android/app/src/main/res/raw\n"
          "2. Use the filename without extension in code\n"
          "3. Example: notification_sound.mp3 → 'notification_sound'",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
      const SizedBox(height: 10),
      ElevatedButton(
        onPressed: _triggerTestAlarm,
        child: const Text("Test Alarm (2 seconds)"),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed:
            () => _scheduleNativeAndLocalAlarm(
              delay: const Duration(minutes: 1),
              title: "⏰ Scheduled Alarm",
              body: "This alarm is scheduled for 1 minute later!",
            ),
        child: const Text("Schedule Alarm (1 min)"),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed:
            () => _scheduleNativeAndLocalAlarm(
              delay: const Duration(seconds: 10),
              title: "⏰ Scheduled Alarm",
              body: "This alarm is scheduled for 10 seconds later!",
            ),
        child: const Text("Schedule Alarm (10 seconds)"),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        onPressed: _cancelAllNotifications,
        child: const Text("Cancel All Scheduled Notifications"),
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
          children:
              widget.task.editHistory.map((edit) {
                final formattedEditTime = DateFormat(
                  'MMM d, yyyy • h:mm a',
                ).format(edit.timestamp);
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
  );
}
