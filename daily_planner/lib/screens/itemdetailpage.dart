import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:io';

class ItemDetailPage extends StatefulWidget {
  final Task task;

  const ItemDetailPage({super.key, required this.task});

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  List<DateTime> completedList = [];
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  List<DateTime> notificationTimes = [];
  bool? _currentCompletionStatus;
  bool _isLoading = true;

  // Use default system sound instead of custom resource
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
    _currentCompletionStatus = widget.task.isCompleted;
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    _initializeNotifications();
    _checkNotificationChannel();
    _loadTaskData();
  }

  Future<void> _loadTaskData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('tasks')
              .doc(widget.task.docId)
              .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _currentCompletionStatus = data['isCompleted'] ?? false;

          if (data['completionStamps'] != null) {
            final List<dynamic> stamps = data['completionStamps'];
            completedList =
                stamps.whereType<Timestamp>().map((ts) => ts.toDate()).toList();
          }

          if (data['notificationTimes'] != null) {
            final List<dynamic> times = data['notificationTimes'];
            notificationTimes =
                times.whereType<Timestamp>().map((ts) => ts.toDate()).toList();
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading task data: $e");
    }
  }

  @override
  void didUpdateWidget(ItemDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.docId != widget.task.docId) {
      _loadTaskData();
    }
  }

  Future<void> _checkNotificationChannel() async {
    if (Platform.isAndroid) {
      final channels =
          await flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.getNotificationChannels();

      if (channels == null || channels.isEmpty) {
        debugPrint('No notification channels found, creating one...');
        await _createNotificationChannel();
      } else {
        debugPrint('Existing notification channels found');
      }
    }
  }

  Future<void> _createNotificationChannel() async {
    if (Platform.isAndroid) {
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
  }

  Future<void> _initializeNotifications() async {
    try {
      tz.initializeTimeZones();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          );

      await flutterLocalNotificationsPlugin.initialize(
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        ),
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          debugPrint('Notification tapped: ${details.payload}');
        },
      );

      if (Platform.isAndroid) {
        await _requestAndroidPermissions();
      }
    } catch (e) {
      debugPrint('Notification initialization error: $e');
    }
  }

  Future<void> _requestAndroidPermissions() async {
    final bool? granted =
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
    debugPrint('Notification permission granted: $granted');
  }

  Future<void> _showInstantNotification() async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'daily_planner_channel',
            'Daily Planner Notifications',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
          );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
      );

      await flutterLocalNotificationsPlugin.show(
        0,
        'Test Notification',
        'This is a test notification',
        platformChannelSpecifics,
        payload: 'test_payload',
      );

      debugPrint('Notification shown successfully');
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  Future<void> _triggerTestAlarm() async {
    try {
      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      final time = DateTime.now().add(const Duration(seconds: 2));

      debugPrint('Attempting to schedule test alarm with ID: $id');

      final hasPermission = await NativeAlarmHelper.checkExactAlarmPermission();
      if (!hasPermission) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text("Please grant exact alarm permission first"),
          ),
        );
        return;
      }

      await NativeAlarmHelper.scheduleAlarmAtTime(
        id: id,
        title: '🔔 Test Alarm',
        body: 'You tapped the test alarm button!',
        dateTime: time,
      );

      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text("Native alarm scheduled in 2 seconds")),
      );

      debugPrint('Alarm scheduled successfully');
    } catch (e) {
      debugPrint('Error scheduling alarm: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text("Failed to schedule alarm: $e")),
      );
    }
  }

  Future<void> _scheduleAlarm(
    Duration duration,
    String title,
    String body,
  ) async {
    try {
      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      final time = DateTime.now().add(duration);

      debugPrint(
        'Attempting to schedule alarm with ID: $id for ${duration.inSeconds} seconds',
      );

      final hasPermission = await NativeAlarmHelper.checkExactAlarmPermission();
      if (!hasPermission) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text("Please grant exact alarm permission first"),
          ),
        );
        return;
      }

      await NativeAlarmHelper.scheduleAlarmAtTime(
        id: id,
        dateTime: time,
        title: title,
        body: body,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(time, tz.local),
        NotificationDetails(android: _androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text("Alarm scheduled in ${duration.inSeconds} seconds"),
        ),
      );

      debugPrint('Alarm and notification scheduled successfully');
    } catch (e) {
      debugPrint('Error scheduling alarm/notification: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text("Failed to schedule: $e")),
      );
    }
  }

  Future<void> _cancelAllNotifications() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text("All scheduled notifications canceled")),
      );
      debugPrint('All notifications cancelled');
    } catch (e) {
      debugPrint('Error cancelling notifications: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text("Failed to cancel notifications: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final formattedDate = DateFormat('MMM d, yyyy').format(task.date);
    final formattedTime = TimeOfDay.fromDateTime(task.date).format(context);

    completedList.sort((a, b) => b.compareTo(a));
    final lastCompleted = completedList.isNotEmpty ? completedList.first : null;

    return ScaffoldMessenger(
      key: scaffoldMessengerKey,
      child:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Scaffold(
                appBar: AppBar(title: const Text("Task Detail")),
                body: Padding(
                  padding: const EdgeInsets.all(16.0),
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
                            const Icon(Icons.calendar_today, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Date: $formattedDate",
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Time: $formattedTime",
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.history, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Created on: ${DateFormat('MMM d, yyyy • h:mm a').format(task.createdAt)}",
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.flag),
                            const SizedBox(width: 8),
                            Chip(
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
                          ],
                        ),

                        if (lastCompleted != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.check_circle_outline),
                              const SizedBox(width: 8),
                              if (task.taskType != 'oneTime') ...[
                                Text(
                                  "Last Completed: ${DateFormat('MMM d, yyyy • h:mm a').format(lastCompleted)}",
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ] else ...[
                                Text(
                                  "Completed At: ${DateFormat('MMM d, yyyy • h:mm a').format(lastCompleted)}",
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ],
                          ),
                        ],

                        if (task.taskType != 'oneTime') ...[
                          const SizedBox(height: 12),
                          ExpansionTile(
                            leading: const Icon(Icons.list_alt),
                            title: const Text("See All Completion Times"),
                            children:
                                completedList.isEmpty
                                    ? [
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 12.0,
                                        ),
                                        child: Center(
                                          child: Text(
                                            "No completion times available",
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ]
                                    : completedList.map((date) {
                                      return ListTile(
                                        leading: const Icon(Icons.check),
                                        title: Text(
                                          DateFormat(
                                            'MMM d, yyyy • h:mm a',
                                          ).format(date),
                                        ),
                                      );
                                    }).toList(),
                          ),
                        ],

                        const SizedBox(height: 24),
                        ExpansionTile(
                          leading: const Icon(Icons.notifications),
                          title: const Text("See All Notification Times"),
                          children:
                              notificationTimes.isEmpty
                                  ? [
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12.0,
                                      ),
                                      child: Center(
                                        child: Text(
                                          "No Notification Times available",
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  ]
                                  : notificationTimes.map((date) {
                                    return ListTile(
                                      leading: const Icon(Icons.check),
                                      title: Text(
                                        DateFormat(
                                          'MMM d, yyyy • h:mm a',
                                        ).format(date),
                                      ),
                                    );
                                  }).toList(),
                        ),
                        const Divider(),
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
                              () => _scheduleAlarm(
                                const Duration(minutes: 1),
                                "⏰ Scheduled Alarm",
                                "This alarm is scheduled for 1 minute later!",
                              ),
                          child: const Text("Schedule Alarm (1 min)"),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed:
                              () => _scheduleAlarm(
                                const Duration(seconds: 10),
                                "⏰ Scheduled Alarm",
                                "This alarm is scheduled for 10 seconds later!",
                              ),
                          child: const Text("Schedule Alarm (10 seconds)"),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: _cancelAllNotifications,
                          child: const Text(
                            "Cancel All Scheduled Notifications",
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Divider(),
                        const Text(
                          "📜 Edit History",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (task.editHistory.isEmpty)
                          const Text(
                            "No edits made yet.",
                            style: TextStyle(fontSize: 16),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children:
                                task.editHistory.map((edit) {
                                  final formattedEditTime = DateFormat(
                                    'MMM d, yyyy • h:mm a',
                                  ).format(edit.timestamp);
                                  return ListTile(
                                    leading: const Icon(Icons.edit_note),
                                    title: Text(formattedEditTime),
                                    subtitle:
                                        edit.note != null &&
                                                edit.note!.isNotEmpty
                                            ? Text(edit.note!)
                                            : const Text("No note"),
                                    contentPadding: EdgeInsets.zero,
                                  );
                                }).toList(),
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}
