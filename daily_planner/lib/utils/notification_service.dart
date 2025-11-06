// // services/notification_service.dart
// import 'dart:async';
// import 'dart:convert';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:http/http.dart' as http;
// import 'package:timezone/data/latest.dart' as tz;
// import 'package:timezone/timezone.dart' as tz;
// import 'package:permission_handler/permission_handler.dart';
// import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

// class NotificationService {
//   static final NotificationService _instance = NotificationService._internal();
//   factory NotificationService() => _instance;
//   NotificationService._internal();

//   late FlutterLocalNotificationsPlugin localNotifications;
//   final Connectivity _connectivity = Connectivity();
//   late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

//   // Separate storage for different notification types
//   final String _pendingPushNotificationsKey = 'pending_push_notifications';
//   final String _scheduledLocalNotificationsKey = 'scheduled_local_notifications';
//   final String _scheduledAlarmsKey = 'scheduled_alarms';

//   // Track current connectivity state
//   bool _isOnline = false;

//   // 🆕 Add initialization status tracking
//   bool _isInitialized = false;

//   // 🆕 Callback for alarm actions
//   static Function(String, String)? onAlarmAction;

//   Future<void> initialize({
//     Function(String, String)? alarmActionCallback,
//   }) async {
//     if (_isInitialized) {
//       debugPrint('⚠️ NotificationService already initialized');
//       return;
//     }

//     try {
//       debugPrint('🛠️ Initializing NotificationService...');

//       // 🆕 Set the alarm action callback
//       onAlarmAction = alarmActionCallback;

//       await _setupLocalNotifications();
//       await _setupConnectivityMonitoring();
//       await _requestNotificationPermissions();
//       await _checkInitialConnectivity();

//       // ✅ Initialize Android Alarm Manager Plus
//       await AndroidAlarmManager.initialize();
//       debugPrint('✅ Android Alarm Manager Plus initialized');

//       _isInitialized = true;
//       debugPrint('🎉 NotificationService initialized successfully');
//     } catch (e) {
//       debugPrint('❌ Error initializing NotificationService: $e');
//       _isInitialized = false;
//     }
//   }

//   // // 🚀 FIXED: CORRECT ALARM CALLBACK SIGNATURE
//   // @pragma('vm:entry-point')
//   // static Future<void> alarmCallback(int alarmId) async {
//   //   debugPrint('🚨 Alarm triggered with ID: $alarmId');
    
//   //   try {
//   //     // Ensure Flutter bindings are initialized in background isolate
//   //     WidgetsFlutterBinding.ensureInitialized();

//   //     // Initialize local notifications in background isolate
//   //     final FlutterLocalNotificationsPlugin localNotifications =
//   //         FlutterLocalNotificationsPlugin();

//   //     const AndroidInitializationSettings androidSettings =
//   //         AndroidInitializationSettings('@mipmap/ic_launcher');

//   //     const InitializationSettings settings = InitializationSettings(
//   //       android: androidSettings,
//   //     );

//   //     await localNotifications.initialize(settings);

//   //     // 🚨 PERSISTENT ALARM NOTIFICATION
//   //     final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
//   //       'alarm_channel',
//   //       'Alarm Reminders',
//   //       channelDescription: 'System-level alarms for critical task reminders',
//   //       importance: Importance.max,
//   //       priority: Priority.high,
//   //       playSound: true,
//   //       sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
//   //       enableVibration: true,
//   //       vibrationPattern: Int64List.fromList([
//   //         0, 1000, 500, 1000, 500, 1000, 500, 2000, // Longer pattern
//   //         500, 1000, 500, 1000, 500, 1000, 500, 2000 // Repeat pattern
//   //       ]),
//   //       fullScreenIntent: true,
//   //       autoCancel: false, // Don't auto-cancel
//   //       ongoing: true, // Ongoing notification
//   //       colorized: true,
//   //       color: const Color(0xFFFF6B6B),
//   //       ledColor: const Color(0xFFFF0000),
//   //       ledOnMs: 1000,
//   //       ledOffMs: 1000,
//   //       timeoutAfter: 0, // No timeout
//   //       additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
//   //       // 🆕 ADD ACTIONS FOR ALARM
//   //       actions: <AndroidNotificationAction>[
//   //         AndroidNotificationAction('snooze_action', 'Snooze'),
//   //         AndroidNotificationAction('stop_action', 'Stop'),
//   //       ],
//   //     );

//   //     final NotificationDetails details = NotificationDetails(
//   //       android: androidDetails,
//   //     );

//   //     // 🆕 CREATE PAYLOAD WITH ACTION DATA
//   //     final Map<String, dynamic> notificationPayload = {
//   //       'alarmId': alarmId.toString(),
//   //       'type': 'alarm',
//   //       'timestamp': DateTime.now().toIso8601String(),
//   //     };

//   //     await localNotifications.show(
//   //       alarmId,
//   //       '🚨 ALARM',
//   //       'Your scheduled alarm is ringing!',
//   //       details,
//   //       payload: jsonEncode(notificationPayload),
//   //     );

//   //     debugPrint('✅ Alarm shown successfully with ID: $alarmId');
//   //   } catch (e) {
//   //     debugPrint('❌ Error in alarm callback: $e');
//   //   }
//   // }

//    @pragma('vm:entry-point')
//   static Future<void> alarmCallback(int alarmId) async {
//     debugPrint('🚨 Alarm triggered with ID: $alarmId');
    
//     try {
//       // Ensure Flutter bindings are initialized in background isolate
//       WidgetsFlutterBinding.ensureInitialized();

//       // Initialize local notifications in background isolate
//       final FlutterLocalNotificationsPlugin localNotifications =
//           FlutterLocalNotificationsPlugin();

//       const AndroidInitializationSettings androidSettings =
//           AndroidInitializationSettings('@mipmap/ic_launcher');

//       const InitializationSettings settings = InitializationSettings(
//         android: androidSettings,
//       );

//       await localNotifications.initialize(settings);

//       // 🚨 PERSISTENT ALARM NOTIFICATION
//       final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
//         'alarm_channel',
//         'Alarm Reminders',
//         channelDescription: 'System-level alarms for critical task reminders',
//         importance: Importance.max,
//         priority: Priority.high,
//         playSound: true,
//         sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
//         enableVibration: true,
//         vibrationPattern: Int64List.fromList([
//           0, 1000, 500, 1000, 500, 1000, 500, 2000, // Longer pattern
//           500, 1000, 500, 1000, 500, 1000, 500, 2000 // Repeat pattern
//         ]),
//         fullScreenIntent: true,
//         autoCancel: false, // Don't auto-cancel
//         ongoing: true, // Ongoing notification
//         colorized: true,
//         color: const Color(0xFFFF6B6B),
//         ledColor: const Color(0xFFFF0000),
//         ledOnMs: 1000,
//         ledOffMs: 1000,
//         timeoutAfter: 0, // No timeout
//         additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
//         // 🆕 ADD ACTIONS FOR ALARM
//         actions: <AndroidNotificationAction>[
//           AndroidNotificationAction('snooze_action', 'Snooze'),
//           AndroidNotificationAction('stop_action', 'Stop'),
//         ],
//       );

//       final NotificationDetails details = NotificationDetails(
//         android: androidDetails,
//       );

//       // 🆕 CREATE PAYLOAD WITH ACTION DATA
//       final Map<String, dynamic> notificationPayload = {
//         'alarmId': alarmId.toString(),
//         'type': 'alarm',
//         'timestamp': DateTime.now().toIso8601String(),
//       };

//       await localNotifications.show(
//         alarmId,
//         '🚨 ALARM',
//         'Your scheduled alarm is ringing!',
//         details,
//         payload: jsonEncode(notificationPayload),
//       );

//       debugPrint('✅ Alarm shown successfully with ID: $alarmId');
//     } catch (e) {
//       debugPrint('❌ Error in alarm callback: $e');
//     }
//   }

//   Future<void> _checkInitialConnectivity() async {
//     try {
//       final results = await _connectivity.checkConnectivity();
//       _isOnline = _isAnyConnectivityOnline(results);
//       debugPrint('Initial connectivity: ${_isOnline ? 'Online' : 'Offline'}');
//     } catch (e) {
//       debugPrint('❌ Error checking connectivity: $e');
//       _isOnline = false;
//     }
//   }

//   Future<void> _requestNotificationPermissions() async {
//     try {
//       debugPrint('🔐 Requesting notification permissions...');

//       // Request notification permission first (required for Android 13+)
//       final notificationStatus = await Permission.notification.request();
//       debugPrint('Notification permission: $notificationStatus');

//       // ✅ FIXED: Use permission_handler to check exact alarm permission
//       bool canScheduleExactAlarms = false;
//       try {
//         if (await Permission.scheduleExactAlarm.isGranted) {
//           canScheduleExactAlarms = true;
//           debugPrint('Exact alarm permission: Granted');
//         } else {
//           // Request the permission if not granted
//           final status = await Permission.scheduleExactAlarm.request();
//           canScheduleExactAlarms = status.isGranted;
//           debugPrint('Exact alarm permission requested: $status');
//         }
//       } catch (e) {
//         debugPrint('Error checking exact alarm permission: $e');
//         canScheduleExactAlarms = false;
//       }

//       debugPrint('Can schedule exact alarms: $canScheduleExactAlarms');
//     } catch (e) {
//       debugPrint('❌ Error requesting permissions: $e');
//     }
//   }

//   Future<void> _setupLocalNotifications() async {
//     try {
//       debugPrint('🛠️ Setting up local notifications...');

//       tz.initializeTimeZones();

//       localNotifications = FlutterLocalNotificationsPlugin();

//       // 🚀 CREATE ALARM CHANNEL FOR HIGH-PRIORITY NOTIFICATIONS
//       final AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
//         'alarm_channel',
//         'Alarm Reminders',
//         description: 'System-level alarms for critical task reminders',
//         importance: Importance.max,
//         playSound: true,
//         sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
//         enableVibration: true,
//         vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 2000]),
//         ledColor: Colors.red,
//         enableLights: true,
//         showBadge: true,
//       );

//       // 🆕 CREATE REGULAR NOTIFICATION CHANNEL
//       final AndroidNotificationChannel regularChannel = AndroidNotificationChannel(
//         'task_channel',
//         'Task Notifications',
//         description: 'Notifications for task reminders',
//         importance: Importance.high,
//         playSound: true,
//         enableVibration: true,
//       );

//       const AndroidInitializationSettings androidSettings =
//           AndroidInitializationSettings('@mipmap/ic_launcher');

//       const DarwinInitializationSettings iosSettings =
//           DarwinInitializationSettings(
//         requestAlertPermission: true,
//         requestBadgePermission: true,
//         requestSoundPermission: true,
//       );

//       const InitializationSettings settings = InitializationSettings(
//         android: androidSettings,
//         iOS: iosSettings,
//       );

//       // 🆕 UPDATED: Add notification response handling for alarm actions
//       await localNotifications.initialize(
//         settings,
//         onDidReceiveNotificationResponse: (NotificationResponse response) {
//           debugPrint('📱 Notification tapped: ${response.payload}');
//           _handleNotificationResponse(response);
//         },
//         onDidReceiveBackgroundNotificationResponse:
//             _handleBackgroundNotificationResponse,
//       );

//       // Create notification channels
//       final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
//           localNotifications.resolvePlatformSpecificImplementation<
//               AndroidFlutterLocalNotificationsPlugin>();

//       await androidPlugin?.createNotificationChannel(alarmChannel);
//       await androidPlugin?.createNotificationChannel(regularChannel);

//       debugPrint('✅ Notification channels created successfully');
//     } catch (e) {
//       debugPrint('❌ Error setting up local notifications: $e');
//       rethrow;
//     }
//   }

//   // 🆕 HANDLE NOTIFICATION RESPONSES (ALARM ACTIONS)
//   void _handleNotificationResponse(NotificationResponse response) {
//     debugPrint(
//       '🎯 Notification action: ${response.actionId} with payload: ${response.payload}',
//     );

//     if (response.actionId != null && response.payload != null) {
//       _handleAlarmAction(response.actionId!, response.payload!);
//     }
//   }

//   // 🆕 BACKGROUND NOTIFICATION HANDLER
//   @pragma('vm:entry-point')
//   static void _handleBackgroundNotificationResponse(
//     NotificationResponse response,
//   ) {
//     debugPrint(
//       '🎯 Background notification action: ${response.actionId} with payload: ${response.payload}',
//     );

//     if (response.actionId != null && response.payload != null) {
//       WidgetsFlutterBinding.ensureInitialized();
//       final Map<String, dynamic> data =
//           jsonDecode(response.payload!) as Map<String, dynamic>;
//       final String alarmId = data['alarmId'] ?? '';

//       if (response.actionId == 'stop_action') {
//         debugPrint('🛑 Background stop action for alarm: $alarmId');
//       } else if (response.actionId == 'snooze_action') {
//         debugPrint('⏰ Background snooze action for alarm: $alarmId');
//       }
//     }
//   }

//   // 🆕 HANDLE ALARM ACTIONS (STOP/SNOOZE)
//   void _handleAlarmAction(String actionId, String payload) {
//     try {
//       final Map<String, dynamic> data =
//           jsonDecode(payload) as Map<String, dynamic>;
//       final String alarmId = data['alarmId'] ?? '';

//       debugPrint('🔄 Handling alarm action: $actionId for alarm: $alarmId');

//       switch (actionId) {
//         case 'stop_action':
//           _stopAlarm(alarmId);
//           break;
//         case 'snooze_action':
//           _snoozeAlarm(alarmId);
//           break;
//         default:
//           debugPrint('Unknown action: $actionId');
//       }

//       // Notify the callback if set
//       if (onAlarmAction != null) {
//         onAlarmAction!(actionId, alarmId);
//       }
//     } catch (e) {
//       debugPrint('❌ Error handling alarm action: $e');
//     }
//   }

//   // 🆕 STOP ALARM ACTION
//   void _stopAlarm(String alarmId) {
//     debugPrint('🛑 Stopping alarm: $alarmId');
//     try {
//       // Cancel the notification
//       localNotifications.cancel(int.parse(alarmId));
//       // Cancel the Android Alarm Manager alarm
//       AndroidAlarmManager.cancel(int.parse(alarmId));
      
//       _showLocalNotification(
//         'Alarm Stopped',
//         'Alarm has been stopped',
//       );
//     } catch (e) {
//       debugPrint('❌ Error stopping alarm: $e');
//     }
//   }

//   // 🆕 SNOOZE ALARM ACTION
//   void _snoozeAlarm(String alarmId) {
//     debugPrint('⏰ Snoozing alarm: $alarmId');
//     try {
//       // Cancel current alarm
//       localNotifications.cancel(int.parse(alarmId));
      
//       // Reschedule alarm for 10 minutes later
//       final DateTime snoozeTime = DateTime.now().add(const Duration(minutes: 10));
      
//       // Schedule new alarm
//       AndroidAlarmManager.oneShotAt(
//         snoozeTime,
//         int.parse(alarmId) + 1, // Use different ID
//         alarmCallback,
//         exact: true,
//         wakeup: true,
//         rescheduleOnReboot: true,
//       );

//       _showLocalNotification(
//         'Alarm Snoozed',
//         'Alarm snoozed until ${snoozeTime.hour}:${snoozeTime.minute.toString().padLeft(2, '0')}',
//       );
//     } catch (e) {
//       debugPrint('❌ Error snoozing alarm: $e');
//     }
//   }

//   // 🆕 SHOW LOCAL NOTIFICATION
//   Future<void> _showLocalNotification(String title, String body) async {
//     try {
//       const AndroidNotificationDetails androidDetails =
//           AndroidNotificationDetails(
//         'task_channel',
//         'Task Notifications',
//         importance: Importance.high,
//         priority: Priority.high,
//       );

//       const NotificationDetails details = NotificationDetails(
//         android: androidDetails,
//       );

//       await localNotifications.show(
//         DateTime.now().millisecondsSinceEpoch.remainder(100000),
//         title,
//         body,
//         details,
//       );
//     } catch (e) {
//       debugPrint('Error showing local notification: $e');
//     }
//   }

//   Future<void> _setupConnectivityMonitoring() async {
//     _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
//       List<ConnectivityResult> results,
//     ) async {
//       final bool wasOnline = _isOnline;
//       _isOnline = _isAnyConnectivityOnline(results);

//       debugPrint('Connectivity changed: ${_isOnline ? 'Online' : 'Offline'}');

//       // ✅ FIXED: Process pending push notifications when coming back online
//       if (_isOnline && !wasOnline) {
//         await _processPendingPushNotifications();
//       }
//     });
//   }

//   bool _isAnyConnectivityOnline(List<ConnectivityResult> results) {
//     return results.any(
//       (result) =>
//           result == ConnectivityResult.wifi ||
//           result == ConnectivityResult.mobile ||
//           result == ConnectivityResult.ethernet ||
//           result == ConnectivityResult.vpn,
//     );
//   }

//   void _showSuccessSnackBar(BuildContext context, String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message, style: const TextStyle(color: Colors.white)),
//         backgroundColor: Colors.green,
//         duration: const Duration(seconds: 4),
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//       ),
//     );
//   }

//   void _showErrorSnackBar(BuildContext context, String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message, style: const TextStyle(color: Colors.white)),
//         backgroundColor: Colors.red,
//         duration: const Duration(seconds: 4),
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//       ),
//     );
//   }

//   // 🚀 REGULAR NOTIFICATION (Less intrusive)
//   Future<void> scheduleTaskNotification({
//     required BuildContext context,
//     required String taskId,
//     required String title,
//     required String body,
//     required DateTime scheduledTimeUtc,
//     Map<String, dynamic>? payload,
//   }) async {
//     await _scheduleNotification(
//       context: context,
//       taskId: taskId,
//       title: title,
//       body: body,
//       scheduledTimeUtc: scheduledTimeUtc,
//       payload: payload,
//       isAlarm: false, // Regular notification
//     );
//   }
  
//   // 🚀 ALARM NOTIFICATION (More intrusive)
//   Future<void> scheduleAlarmNotification({
//     required BuildContext context,
//     required String taskId,
//     required String title,
//     required String body,
//     required DateTime scheduledTimeUtc,
//     Map<String, dynamic>? payload,
//   }) async {
//     await _scheduleNotification(
//       context: context,
//       taskId: taskId,
//       title: title,
//       body: body,
//       scheduledTimeUtc: scheduledTimeUtc,
//       payload: payload,
//       isAlarm: true, // Alarm behavior
//     );
//   }

//   // 🆕 UNIFIED SCHEDULING METHOD
//   Future<void> _scheduleNotification({
//     required BuildContext context,
//     required String taskId,
//     required String title,
//     required String body,
//     required DateTime scheduledTimeUtc,
//     Map<String, dynamic>? payload,
//     required bool isAlarm,
//   }) async {
//     if (!_isInitialized) {
//       _showErrorSnackBar(
//         context,
//         'Notification service not initialized. Please restart the app.',
//       );
//       return;
//     }

//     try {
//       // Convert UTC time from Firestore to local device time
//       final DateTime scheduledTimeLocal = _utcToLocal(scheduledTimeUtc);
//       final DateTime now = DateTime.now();

//       // 🆕 CHECK IF SCHEDULED TIME IS IN FUTURE
//       if (scheduledTimeLocal.isBefore(now)) {
//         _showErrorSnackBar(context, 'Cannot schedule notification in the past');
//         return;
//       }

//       debugPrint('''
// 📅 Scheduling ${isAlarm ? 'ALARM' : 'Notification'}:
//    Task ID: $taskId
//    Title: $title
//    Scheduled UTC: $scheduledTimeUtc
//    Scheduled Local: $scheduledTimeLocal
//    Now Local: $now
//    In: ${scheduledTimeLocal.difference(now).inSeconds} seconds
// ''');

//       // Generate IDs
//       final int notificationId = _generateNotificationId(
//         taskId,
//         scheduledTimeUtc,
//       );
//       final int alarmId = _generateAlarmId(taskId, scheduledTimeUtc);

//       if (isAlarm) {
//         // 🚀 STRATEGY 1: ANDROID ALARM MANAGER PLUS (System-level reliability)
//         await _scheduleWithAlarmManager(
//           alarmId: alarmId,
//           scheduledTimeLocal: scheduledTimeLocal,
//         );
//       }

//       // 🚀 STRATEGY 2: LOCAL NOTIFICATIONS (Backup)
//       await _scheduleLocalNotification(
//         notificationId: notificationId,
//         title: title,
//         body: body,
//         scheduledTimeLocal: scheduledTimeLocal,
//         payload: payload,
//         isAlarm: isAlarm,
//       );

//       // Store records
//       await _storeScheduledLocalNotification(
//         taskId: taskId,
//         notificationId: notificationId,
//         scheduledTimeUtc: scheduledTimeUtc,
//       );

//       if (isAlarm) {
//         await _storeScheduledAlarm(
//           taskId: taskId,
//           alarmId: alarmId,
//           scheduledTimeUtc: scheduledTimeUtc,
//         );
//       }

//       // 🚀 STRATEGY 3: PUSH NOTIFICATION (For cross-device sync)
//       if (_isOnline) {
//         await _schedulePushNotification(
//           taskId: taskId,
//           title: title,
//           body: body,
//           scheduledTimeUtc: scheduledTimeUtc,
//           payload: payload,
//         );
//       } else {
//         await _storePendingPushNotification(
//           taskId: taskId,
//           title: title,
//           body: body,
//           scheduledTimeUtc: scheduledTimeUtc,
//           payload: payload,
//         );
//       }

//       _showSuccessSnackBar(
//         context,
//         '✅ ${isAlarm ? 'ALARM' : 'Reminder'} scheduled for ${scheduledTimeLocal.hour}:${scheduledTimeLocal.minute.toString().padLeft(2, '0')}',
//       );
//     } catch (e) {
//       debugPrint('❌ Error in hybrid notification scheduling: $e');
//       _showErrorSnackBar(
//         context,
//         'Failed to schedule ${isAlarm ? 'alarm' : 'notification'}: $e',
//       );

//       // Fallback to local notification only
//       await _scheduleLocalNotificationFallback(
//         notificationId: _generateNotificationId(taskId, scheduledTimeUtc),
//         title: title,
//         body: body,
//         scheduledTimeLocal: _utcToLocal(scheduledTimeUtc),
//         payload: payload,
//         isAlarm: isAlarm,
//       );
//     }
//   }

//   // 🚀 FIXED: SIMPLIFIED ALARM MANAGER SCHEDULING
// Future<void> _scheduleWithAlarmManager({
//   required int alarmId,
//   required DateTime scheduledTimeLocal,
// }) async {
//   try {
//     debugPrint(
//       '⏰ Scheduling with Alarm Manager - ID: $alarmId, Time: $scheduledTimeLocal',
//     );

//     // ✅ FIXED: Check exact alarm permission using permission_handler
//     bool canScheduleExactAlarms = false;
//     try {
//       canScheduleExactAlarms = await Permission.scheduleExactAlarm.isGranted;
//     } catch (e) {
//       debugPrint('Error checking exact alarm permission: $e');
//       canScheduleExactAlarms = false;
//     }

//     // 🚀 FIXED: Use top-level callback function
//     final bool scheduled = await AndroidAlarmManager.oneShotAt(
//       scheduledTimeLocal,
//       alarmId,
//       alarmCallback, // ✅ Use the top-level function
//       exact: canScheduleExactAlarms,
//       wakeup: true,
//       rescheduleOnReboot: true,
//       alarmClock: true, // Show in alarm clock
//     );

//     if (scheduled) {
//       debugPrint(
//         '✅ ALARM scheduled successfully with Alarm Manager (exact: $canScheduleExactAlarms)',
//       );
//     } else {
//       debugPrint('❌ Failed to schedule alarm with Alarm Manager');
//       throw Exception('Alarm Manager scheduling failed');
//     }
//   } catch (e) {
//     debugPrint('❌ Error scheduling with Android Alarm Manager: $e');
//     rethrow;
//   }
// }
//   // 🚀 ENHANCED LOCAL NOTIFICATION WITH PERSISTENT ALARM
//   Future<void> _scheduleLocalNotification({
//     required int notificationId,
//     required String title,
//     required String body,
//     required DateTime scheduledTimeLocal,
//     Map<String, dynamic>? payload,
//     required bool isAlarm,
//   }) async {
//     try {
//       final localTimeZone = tz.local;
//       final scheduledTzTime = tz.TZDateTime.from(
//         scheduledTimeLocal,
//         localTimeZone,
//       );

//       debugPrint(
//         '📱 Scheduling local ${isAlarm ? 'ALARM' : 'notification'} - ID: $notificationId, Time: $scheduledTzTime',
//       );

//       // 🚀 USE DIFFERENT CHANNELS FOR ALARMS VS NOTIFICATIONS
//       final AndroidNotificationDetails androidDetails;

//       if (isAlarm) {
//         // 🚨 PERSISTENT ALARM CHANNEL WITH ACTIONS
//         androidDetails = AndroidNotificationDetails(
//           'alarm_channel',
//           'Alarm Reminders',
//           channelDescription: 'System-level alarms for critical task reminders',
//           importance: Importance.max,
//           priority: Priority.high,
//           playSound: true,
//           sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
//           enableVibration: true,
//           vibrationPattern: Int64List.fromList([
//             0, 1000, 500, 1000, 500, 1000, 500, 2000,
//             500, 1000, 500, 1000, 500, 1000, 500, 2000
//           ]),
//           fullScreenIntent: true,
//           autoCancel: false, // Don't auto-cancel
//           ongoing: true, // Ongoing notification
//           timeoutAfter: 0, // No timeout
//           additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
//           // 🆕 ADD ACTIONS FOR ALARM
//           actions: <AndroidNotificationAction>[
//             AndroidNotificationAction('snooze_action', 'Snooze'),
//             AndroidNotificationAction('stop_action', 'Stop'),
//           ],
//         );
//       } else {
//         // 📱 REGULAR CHANNEL
//         androidDetails = AndroidNotificationDetails(
//           'task_channel',
//           'Task Notifications',
//           channelDescription: 'Notifications for task reminders',
//           importance: Importance.high,
//           priority: Priority.high,
//           playSound: true,
//           enableVibration: true,
//           autoCancel: true,
//           timeoutAfter: 30000, // Auto-dismiss after 30 seconds
//         );
//       }

//       final NotificationDetails details = NotificationDetails(
//         android: androidDetails,
//         iOS: const DarwinNotificationDetails(),
//       );

//       // 🚀 Add emoji prefix for alarms
//       final String displayTitle = isAlarm ? '🚨 $title' : title;

//       // 🆕 CREATE PAYLOAD FOR ACTIONS
//       final Map<String, dynamic> notificationPayload = {
//         'taskId': payload?['taskId'] ?? 'unknown',
//         'type': isAlarm ? 'alarm' : 'notification',
//         'scheduledTime': scheduledTimeLocal.toIso8601String(),
//         'alarmId': notificationId.toString(), // Add alarm ID for actions
//       };

//       await localNotifications.zonedSchedule(
//         notificationId,
//         displayTitle,
//         body,
//         scheduledTzTime,
//         details,
//         payload: jsonEncode(notificationPayload),
//         androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
     
//       );

//       debugPrint(
//         '✅ Local ${isAlarm ? 'ALARM' : 'notification'} scheduled successfully',
//       );
//     } catch (e) {
//       debugPrint(
//         '❌ Error scheduling local ${isAlarm ? 'alarm' : 'notification'}: $e',
//       );
//       rethrow;
//     }
//   }

//   // 🆕 TEST METHODS
//   Future<void> testNotification(BuildContext context) async {
//     if (!_isInitialized) {
//       _showErrorSnackBar(context, 'Notification service not initialized');
//       return;
//     }

//     final testTime = DateTime.now().add(const Duration(seconds: 10));

//     await scheduleTaskNotification(
//       context: context,
//       taskId: 'test_${DateTime.now().millisecondsSinceEpoch}',
//       title: 'Test Notification',
//       body: 'This is a regular notification scheduled 10 seconds from now',
//       scheduledTimeUtc: testTime.toUtc(),
//     );

//     _showSuccessSnackBar(
//       context,
//       'Test notification scheduled for ${testTime.toLocal()}',
//     );
//   }

//   Future<void> testAlarm(BuildContext context) async {
//     if (!_isInitialized) {
//       _showErrorSnackBar(context, 'Notification service not initialized');
//       return;
//     }

//     final testTime = DateTime.now().add(const Duration(seconds: 15));
//     final testAlarmId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

//     try {
//       // Test Android Alarm Manager
//       await AndroidAlarmManager.oneShotAt(
//         testTime,
//         testAlarmId,
//         alarmCallback,
//         exact: true,
//         wakeup: true,
//         alarmClock: true,
//       );

//       _showSuccessSnackBar(
//         context,
//         'Test ALARM scheduled for ${testTime.toLocal()}',
//       );
//     } catch (e) {
//       debugPrint('❌ Error scheduling test alarm: $e');
//       _showErrorSnackBar(context, 'Failed to schedule test alarm: $e');
//     }
//   }

//   // 🆕 SHOW IMMEDIATE PERSISTENT ALARM (FOR TESTING)
//   Future<void> showImmediateAlarm(BuildContext context) async {
//     if (!_isInitialized) {
//       _showErrorSnackBar(context, 'Notification service not initialized');
//       return;
//     }

//     final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

//     try {
//       // 🚨 PERSISTENT ALARM CHANNEL WITH ACTIONS
//       final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
//         'alarm_channel',
//         'Alarm Reminders',
//         channelDescription: 'System-level alarms for critical task reminders',
//         importance: Importance.max,
//         priority: Priority.high,
//         playSound: true,
//         sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
//         enableVibration: true,
//         vibrationPattern: Int64List.fromList([
//           0, 1000, 500, 1000, 500, 1000, 500, 2000,
//           500, 1000, 500, 1000, 500, 1000, 500, 2000
//         ]),
//         fullScreenIntent: true,
//         autoCancel: false,
//         ongoing: true,
//         timeoutAfter: 0,
//         additionalFlags: Int32List.fromList([4]),
//         actions: const <AndroidNotificationAction>[
//           AndroidNotificationAction('snooze_action', 'Snooze'),
//           AndroidNotificationAction('stop_action', 'Stop'),
//         ],
//       );

//       final NotificationDetails details = NotificationDetails(
//         android: androidDetails,
//       );

//       // 🆕 CREATE PAYLOAD FOR ACTIONS
//       final Map<String, dynamic> notificationPayload = {
//         'alarmId': notificationId.toString(),
//         'type': 'alarm',
//         'timestamp': DateTime.now().toIso8601String(),
//       };

//       await localNotifications.show(
//         notificationId,
//         '🚨 IMMEDIATE PERSISTENT ALARM',
//         'This alarm will stay until you dismiss it with stop/snooze buttons',
//         details,
//         payload: jsonEncode(notificationPayload),
//       );

//       _showSuccessSnackBar(
//         context,
//         'Immediate PERSISTENT alarm shown - will stay until dismissed',
//       );
//     } catch (e) {
//       _showErrorSnackBar(context, 'Failed to show immediate alarm: $e');
//     }
//   }

//   // 🆕 PERMISSION CHECKER
//   Future<void> checkPermissions(BuildContext context) async {
//     final notificationStatus = await Permission.notification.status;
//     final exactAlarmStatus = await Permission.scheduleExactAlarm.status;

//     // ✅ FIXED: Use permission_handler instead of non-existent method
//     bool canScheduleExactAlarms = false;
//     try {
//       canScheduleExactAlarms = await Permission.scheduleExactAlarm.isGranted;
//     } catch (e) {
//       debugPrint('Error checking exact alarms: $e');
//     }

//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Permission Status'),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text('Notification: $notificationStatus'),
//             Text('Exact Alarm Permission: $exactAlarmStatus'),
//             Text('Can Schedule Exact: $canScheduleExactAlarms'),
//             Text('Service Initialized: $_isInitialized'),
//           ],
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('OK'),
//           ),
//         ],
//       ),
//     );
//   }

//   // 🚀 PROCESS PENDING PUSH NOTIFICATIONS
//   Future<void> _processPendingPushNotifications() async {
//     try {
//       debugPrint('📤 Processing pending push notifications...');

//       final prefs = await SharedPreferences.getInstance();
//       final List<String> pendingNotifications =
//           prefs.getStringList(_pendingPushNotificationsKey) ?? [];

//       if (pendingNotifications.isEmpty) {
//         debugPrint('📤 No pending push notifications to process');
//         return;
//       }

//       debugPrint(
//         '📤 Found ${pendingNotifications.length} pending push notifications',
//       );

//       for (final notificationJson in pendingNotifications) {
//         try {
//           final Map<String, dynamic> data =
//               jsonDecode(notificationJson) as Map<String, dynamic>;

//           await _schedulePushNotification(
//             taskId: data['taskId'],
//             title: data['title'],
//             body: data['body'],
//             scheduledTimeUtc: DateTime.parse(data['scheduledTimeUtc']),
//             payload: data['payload'],
//           );

//           debugPrint(
//             '✅ Processed pending push notification for task: ${data['taskId']}',
//           );
//         } catch (e) {
//           debugPrint('❌ Error processing pending notification: $e');
//         }
//       }

//       // Clear processed notifications
//       await prefs.remove(_pendingPushNotificationsKey);
//       debugPrint('✅ All pending push notifications processed and cleared');
//     } catch (e) {
//       debugPrint('❌ Error in _processPendingPushNotifications: $e');
//     }
//   }

//   // 🚀 PUSH NOTIFICATION METHOD
//   Future<void> _schedulePushNotification({
//     required String taskId,
//     required String title,
//     required String body,
//     required DateTime scheduledTimeUtc,
//     Map<String, dynamic>? payload,
//   }) async {
//     try {
//       // Your push notification implementation here
//       // This could be FCM, your backend API, etc.
//       debugPrint(
//         '📤 Push notification scheduled for task: $taskId at $scheduledTimeUtc',
//       );

//       // Simulate API call
//       await Future.delayed(const Duration(milliseconds: 100));
//     } catch (e) {
//       debugPrint('❌ Push notification error: $e');
//       await _storePendingPushNotification(
//         taskId: taskId,
//         title: title,
//         body: body,
//         scheduledTimeUtc: scheduledTimeUtc,
//         payload: payload,
//       );
//     }
//   }

//   // 🗄️ STORAGE METHODS
//   Future<void> _storePendingPushNotification({
//     required String taskId,
//     required String title,
//     required String body,
//     required DateTime scheduledTimeUtc,
//     Map<String, dynamic>? payload,
//   }) async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final List<String> pendingNotifications =
//           prefs.getStringList(_pendingPushNotificationsKey) ?? [];

//       final notificationData = {
//         'taskId': taskId,
//         'title': title,
//         'body': body,
//         'scheduledTimeUtc': scheduledTimeUtc.toIso8601String(),
//         'payload': payload,
//       };

//       pendingNotifications.add(jsonEncode(notificationData));
//       await prefs.setStringList(
//         _pendingPushNotificationsKey,
//         pendingNotifications,
//       );

//       debugPrint('💾 Stored pending push notification for task: $taskId');
//     } catch (e) {
//       debugPrint('Error storing pending push notification: $e');
//     }
//   }

//   Future<void> _storeScheduledLocalNotification({
//     required String taskId,
//     required int notificationId,
//     required DateTime scheduledTimeUtc,
//   }) async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final List<String> scheduledNotifications =
//           prefs.getStringList(_scheduledLocalNotificationsKey) ?? [];

//       final notificationData = {
//         'taskId': taskId,
//         'notificationId': notificationId.toString(),
//         'scheduledTimeUtc': scheduledTimeUtc.toIso8601String(),
//       };

//       scheduledNotifications.add(jsonEncode(notificationData));
//       await prefs.setStringList(
//         _scheduledLocalNotificationsKey,
//         scheduledNotifications,
//       );

//       debugPrint('💾 Stored scheduled local notification for task: $taskId');
//     } catch (e) {
//       debugPrint('Error storing scheduled local notification: $e');
//     }
//   }

//   Future<void> _storeScheduledAlarm({
//     required String taskId,
//     required int alarmId,
//     required DateTime scheduledTimeUtc,
//   }) async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final List<String> alarms = prefs.getStringList(_scheduledAlarmsKey) ?? [];

//       final alarmData = {
//         'taskId': taskId,
//         'alarmId': alarmId.toString(),
//         'scheduledTimeUtc': scheduledTimeUtc.toIso8601String(),
//       };

//       alarms.add(jsonEncode(alarmData));
//       await prefs.setStringList(_scheduledAlarmsKey, alarms);

//       debugPrint('💾 Stored alarm record for task: $taskId');
//     } catch (e) {
//       debugPrint('Error storing alarm record: $e');
//     }
//   }

//   // 🗑️ CANCELLATION METHODS
//   Future<void> cancelNotification(
//     String taskId,
//     DateTime scheduledTimeUtc,
//   ) async {
//     try {
//       final int notificationId = _generateNotificationId(
//         taskId,
//         scheduledTimeUtc,
//       );
//       final int alarmId = _generateAlarmId(taskId, scheduledTimeUtc);

//       // Cancel local notification
//       await localNotifications.cancel(notificationId);


//       // Remove from scheduled local notifications
//       await _removeScheduledLocalNotification(taskId, scheduledTimeUtc);

//       // Remove from scheduled alarms
//       await _removeScheduledAlarm(taskId, scheduledTimeUtc);

//       // Remove from pending push notifications
//       await _removePendingPushNotification(taskId, scheduledTimeUtc);

//       // Cancel push notification on server
//       await _cancelPushNotification(taskId);

//       debugPrint(
//         '🗑️ Cancelled all notifications and alarms for task: $taskId',
//       );
//     } catch (e) {
//       debugPrint('Error cancelling notification: $e');
//     }
//   }

//   Future<void> cancelAllNotificationsForDocument({
//     required String docId,
//     required List<DateTime> scheduledTimesUtc,
//   }) async {
//     try {
//       debugPrint(
//         '🗑️ Cancelling all notifications for document: $docId with ${scheduledTimesUtc.length} scheduled times',
//       );

//       int totalCancelled = 0;

//       for (final scheduledTimeUtc in scheduledTimesUtc) {
//         try {
//           final int notificationId = _generateNotificationId(
//             docId,
//             scheduledTimeUtc,
//           );
//           final int alarmId = _generateAlarmId(docId, scheduledTimeUtc);

//           // Cancel local notification
//           await localNotifications.cancel(notificationId);

//           // Cancel Android Alarm Manager alarm
//           await AndroidAlarmManager.cancel(alarmId);

//           // Remove from scheduled local notifications
//           await _removeScheduledLocalNotification(docId, scheduledTimeUtc);

//           // Remove from scheduled alarms
//           await _removeScheduledAlarm(docId, scheduledTimeUtc);

//           // Remove from pending push notifications
//           await _removePendingPushNotification(docId, scheduledTimeUtc);

//           totalCancelled++;

//           debugPrint(
//             '✅ Cancelled notification and alarm for time: $scheduledTimeUtc',
//           );
//         } catch (e) {
//           debugPrint(
//             '❌ Error cancelling notification for time $scheduledTimeUtc: $e',
//           );
//         }
//       }

//       // Cancel all push notifications on server for this document
//       await _cancelAllPushNotificationsForDocument(docId);

//       debugPrint(
//         '🗑️ Successfully cancelled $totalCancelled/${scheduledTimesUtc.length} notifications and alarms for document: $docId',
//       );
//     } catch (e) {
//       debugPrint('❌ Error in cancelAllNotificationsForDocument: $e');
//     }
//   }

//   // 🗑️ REMOVAL METHODS
//   Future<void> _removeScheduledLocalNotification(
//     String taskId,
//     DateTime scheduledTimeUtc,
//   ) async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final List<String> scheduledNotifications =
//           prefs.getStringList(_scheduledLocalNotificationsKey) ?? [];

//       final List<String> updated = scheduledNotifications.where((notificationJson) {
//         try {
//           final Map<String, dynamic> data =
//               jsonDecode(notificationJson) as Map<String, dynamic>;
//           return data['taskId'] != taskId ||
//               data['scheduledTimeUtc'] != scheduledTimeUtc.toIso8601String();
//         } catch (e) {
//           return true;
//         }
//       }).toList();

//       if (updated.length != scheduledNotifications.length) {
//         await prefs.setStringList(_scheduledLocalNotificationsKey, updated);
//         debugPrint(
//           '🗑️ Removed scheduled local notification for task: $taskId',
//         );
//       }
//     } catch (e) {
//       debugPrint('Error removing scheduled local notification: $e');
//     }
//   }

//   Future<void> _removeScheduledAlarm(
//     String taskId,
//     DateTime scheduledTimeUtc,
//   ) async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final List<String> alarms = prefs.getStringList(_scheduledAlarmsKey) ?? [];

//       final List<String> updated = alarms.where((alarmJson) {
//         try {
//           final Map<String, dynamic> data =
//               jsonDecode(alarmJson) as Map<String, dynamic>;
//           return data['taskId'] != taskId ||
//               data['scheduledTimeUtc'] != scheduledTimeUtc.toIso8601String();
//         } catch (e) {
//           return true;
//         }
//       }).toList();

//       if (updated.length != alarms.length) {
//         await prefs.setStringList(_scheduledAlarmsKey, updated);
//         debugPrint('🗑️ Removed alarm record for task: $taskId');
//       }
//     } catch (e) {
//       debugPrint('Error removing scheduled alarm: $e');
//     }
//   }

//   Future<void> _removePendingPushNotification(
//     String taskId,
//     DateTime scheduledTimeUtc,
//   ) async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final List<String> pendingNotifications =
//           prefs.getStringList(_pendingPushNotificationsKey) ?? [];

//       final List<String> updated = pendingNotifications.where((notificationJson) {
//         try {
//           final Map<String, dynamic> data =
//               jsonDecode(notificationJson) as Map<String, dynamic>;
//           return data['taskId'] != taskId ||
//               data['scheduledTimeUtc'] != scheduledTimeUtc.toIso8601String();
//         } catch (e) {
//           return true;
//         }
//       }).toList();

//       if (updated.length != pendingNotifications.length) {
//         await prefs.setStringList(_pendingPushNotificationsKey, updated);
//         debugPrint('🗑️ Removed pending push notification for task: $taskId');
//       }
//     } catch (e) {
//       debugPrint('Error removing pending push notification: $e');
//     }
//   }

//   // 🚀 FALLBACK METHOD WITH PERSISTENT ALARM
//   Future<void> _scheduleLocalNotificationFallback({
//     required int notificationId,
//     required String title,
//     required String body,
//     required DateTime scheduledTimeLocal,
//     Map<String, dynamic>? payload,
//     required bool isAlarm,
//   }) async {
//     try {
//       debugPrint('🔄 Using fallback local notification scheduling');

//       final AndroidNotificationDetails androidDetails = isAlarm
//           ? AndroidNotificationDetails(
//               'alarm_channel',
//               'Alarm Reminders',
//               importance: Importance.max,
//               priority: Priority.high,
//               playSound: true,
//               sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
//               enableVibration: true,
//               vibrationPattern: Int64List.fromList([
//                 0, 1000, 500, 1000, 500, 1000, 500, 2000,
//                 500, 1000, 500, 1000, 500, 1000, 500, 2000
//               ]),
//               autoCancel: false,
//               ongoing: true,
//               timeoutAfter: 0,
//               actions: <AndroidNotificationAction>[
//                 AndroidNotificationAction('snooze_action', 'Snooze'),
//                 AndroidNotificationAction('stop_action', 'Stop'),
//               ],
//             )
//           : AndroidNotificationDetails(
//               'task_channel',
//               'Task Notifications',
//               importance: Importance.high,
//               priority: Priority.high,
//               playSound: true,
//             );

//       final NotificationDetails details = NotificationDetails(
//         android: androidDetails,
//         iOS: const DarwinNotificationDetails(),
//       );

//       final localTimeZone = tz.local;
//       final scheduledTzTime = tz.TZDateTime.from(
//         scheduledTimeLocal,
//         localTimeZone,
//       );

//       await localNotifications.zonedSchedule(
//         notificationId,
//         isAlarm ? '🚨 $title' : title,
//         body,
//         scheduledTzTime,
//         details,
//         payload: payload != null ? jsonEncode(payload) : null,
//         androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
       
//       );

//       debugPrint(
//         '✅ Fallback ${isAlarm ? 'PERSISTENT ALARM' : 'notification'} scheduled successfully',
//       );
//     } catch (e) {
//       debugPrint('❌ Error in fallback scheduling: $e');
//     }
//   }

//   // 🔧 UTILITY METHODS
//   DateTime _utcToLocal(DateTime utcTime) {
//     return utcTime.toLocal();
//   }

//   int _generateNotificationId(String taskId, DateTime scheduledTimeUtc) {
//     return (taskId + scheduledTimeUtc.toIso8601String()).hashCode.abs();
//   }

//   int _generateAlarmId(String taskId, DateTime scheduledTimeUtc) {
//     return (taskId + scheduledTimeUtc.toIso8601String() + '_alarm').hashCode.abs() % 100000;
//   }

//   // 🆕 Add getter for initialization status
//   bool get isInitialized => _isInitialized;

//   // 📋 PLACEHOLDER METHODS (Implement based on your backend)
//   Future<void> _cancelPushNotification(String taskId) async {
//     // Implement your push notification cancellation logic
//     debugPrint('📤 Cancelled push notification for task: $taskId');
//   }

//   Future<void> _cancelAllPushNotificationsForDocument(String docId) async {
//     // Implement your push notification cancellation logic
//     debugPrint('📤 Cancelled all push notifications for document: $docId');
//   }

//   Future<List<DateTime>> getScheduledTimesForDocument(String docId) async {
//     // Implement your logic to get scheduled times
//     return [];
//   }

//   void dispose() {
//     _connectivitySubscription.cancel();
//   }
// }