// services/notification_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  late FlutterLocalNotificationsPlugin localNotifications;
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  // Separate storage for different notification types
  final String _pendingPushNotificationsKey = 'pending_push_notifications';
  final String _scheduledLocalNotificationsKey = 'scheduled_local_notifications';
  final String _scheduledAlarmsKey = 'scheduled_alarms';

  // Track current connectivity state
  bool _isOnline = false;

  Future<void> initialize() async {
    await _setupLocalNotifications();
    await _setupConnectivityMonitoring();
    await _requestNotificationPermissions();
    await _checkInitialConnectivity();
    
    // ✅ Initialize Android Alarm Manager Plus
    await AndroidAlarmManager.initialize();
    debugPrint('✅ Android Alarm Manager Plus initialized');
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _isOnline = _isAnyConnectivityOnline(results);
    debugPrint('Initial connectivity: ${_isOnline ? 'Online' : 'Offline'}');
  }

  Future<void> _requestNotificationPermissions() async {
    try {
      // Request exact alarm permission for Android
      if (await Permission.scheduleExactAlarm.request().isGranted) {
        debugPrint('Exact alarm permission granted');
      } else {
        debugPrint('Exact alarm permission denied - using inexact alarms');
      }

      // Request notification permission
      await Permission.notification.request();
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
    }
  }

  Future<void> _setupLocalNotifications() async {
    tz.initializeTimeZones();

    localNotifications = FlutterLocalNotificationsPlugin();

    // 🚀 CREATE ALARM CHANNEL FOR HIGH-PRIORITY NOTIFICATIONS
    final AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
      'alarm_channel',
      'Alarm Reminders',
      description: 'System-level alarms for critical task reminders',
      importance: Importance.max,
      // priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('alarm_sound'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 1000, 500, 1000, 500, 1000]),
    );

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await localNotifications.initialize(settings);

    // Create the alarm channel
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(alarmChannel);

    debugPrint('✅ Alarm notification channel created');
  }

  Future<void> _setupConnectivityMonitoring() async {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      final bool wasOnline = _isOnline;
      _isOnline = _isAnyConnectivityOnline(results);
      
      debugPrint('Connectivity changed: ${_isOnline ? 'Online' : 'Offline'}');

      // Process pending push notifications when coming back online
      if (_isOnline && !wasOnline) {
        await _processPendingPushNotifications();
      }
    });
  }

  bool _isAnyConnectivityOnline(List<ConnectivityResult> results) {
    return results.any((result) => 
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet ||
        result == ConnectivityResult.vpn);
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // 🚀 ENHANCED HYBRID APPROACH WITH ALARM BEHAVIOR
  Future<void> scheduleTaskNotification({
    required BuildContext context,
    required String taskId,
    required String title,
    required String body,
    required DateTime scheduledTimeUtc,
    Map<String, dynamic>? payload,
    bool isAlarm = false, // 🆕 NEW PARAMETER: Enable alarm behavior
  }) async {
    try {
      // Convert UTC time from Firestore to local device time
      final DateTime scheduledTimeLocal = _utcToLocal(scheduledTimeUtc);
      
      // Generate notification ID at runtime
      final int notificationId = _generateNotificationId(taskId, scheduledTimeUtc);
      final int alarmId = _generateAlarmId(taskId, scheduledTimeUtc);

      // 🚀 STRATEGY 1: ANDROID ALARM MANAGER PLUS (System-level reliability)
      await _scheduleWithAlarmManager(
        alarmId: alarmId,
        taskId: taskId,
        title: title,
        body: body,
        scheduledTimeLocal: scheduledTimeLocal,
        payload: payload,
        isAlarm: isAlarm, // 🆕 Pass alarm flag
      );

      // 🚀 STRATEGY 2: LOCAL NOTIFICATIONS (Backup)
      await _scheduleLocalNotification(
        notificationId: notificationId,
        title: title,
        body: body,
        scheduledTimeLocal: scheduledTimeLocal,
        payload: payload,
        isAlarm: isAlarm, // 🆕 Pass alarm flag
      );

      // Store record of scheduled notifications
      await _storeScheduledLocalNotification(
        taskId: taskId,
        notificationId: notificationId,
        scheduledTimeUtc: scheduledTimeUtc,
      );

      await _storeScheduledAlarm(
        taskId: taskId,
        alarmId: alarmId,
        scheduledTimeUtc: scheduledTimeUtc,
      );

      // 🚀 STRATEGY 3: PUSH NOTIFICATION (For cross-device sync)
      if (_isOnline) {
        await _schedulePushNotification(
          taskId: taskId,
          title: title,
          body: body,
          scheduledTimeUtc: scheduledTimeUtc,
          payload: payload,
        );
      } else {
        await _storePendingPushNotification(
          taskId: taskId,
          title: title,
          body: body,
          scheduledTimeUtc: scheduledTimeUtc,
          payload: payload,
        );
      }

      // ✅ SHOW SNACKBAR INSTEAD OF DEBUG PRINT
      _showSuccessSnackBar(
        context,
        '✅ ${isAlarm ? 'ALARM' : 'Notification'} scheduled - Alarm Manager: System-level, Local: Backup, Push: ${_isOnline ? 'Immediate' : 'Pending'}',
      );

    } catch (e) {
      _showErrorSnackBar(context, '❌ Error in hybrid notification scheduling: $e');
      
      // Fallback to local notification only
      await _scheduleLocalNotificationFallback(
        notificationId: _generateNotificationId(taskId, scheduledTimeUtc),
        title: title,
        body: body,
        scheduledTimeLocal: _utcToLocal(scheduledTimeUtc),
        payload: payload,
        isAlarm: isAlarm, // 🆕 Pass alarm flag
      );
    }
  }

  // 🚀 ENHANCED ALARM MANAGER WITH ALARM BEHAVIOR
  Future<void> _scheduleWithAlarmManager({
    required int alarmId,
    required String taskId,
    required String title,
    required String body,
    required DateTime scheduledTimeLocal,
    Map<String, dynamic>? payload,
    bool isAlarm = false, // 🆕 NEW PARAMETER
  }) async {
    try {
      // Prepare payload for alarm callback
      final Map<String, dynamic> alarmPayload = {
        'taskId': taskId,
        'title': title,
        'body': body,
        'notificationId': _generateNotificationId(taskId, scheduledTimeLocal.toUtc()),
        'payload': payload,
        'isAlarm': isAlarm, // 🆕 Include alarm flag in payload
      };

      // Schedule with Android Alarm Manager Plus
      final bool scheduled = await AndroidAlarmManager.oneShotAt(
        scheduledTimeLocal,
        alarmId,
        _alarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        alarmClock: isAlarm, // 🆕 Only show in alarm clock if it's an alarm
        params: alarmPayload,
      );

      if (scheduled) {
        debugPrint('⏰ ${isAlarm ? 'ALARM' : 'Notification'} scheduled - ID: $alarmId, Time: $scheduledTimeLocal');
      } else {
        debugPrint('❌ Failed to schedule ${isAlarm ? 'alarm' : 'notification'}');
        throw Exception('Failed to schedule system ${isAlarm ? 'alarm' : 'notification'}');
      }
    } catch (e) {
      debugPrint('❌ Error scheduling with Android Alarm Manager: $e');
      rethrow;
    }
  }

  // 🚀 ENHANCED ALARM CALLBACK WITH ALARM BEHAVIOR
  @pragma('vm:entry-point')
  static Future<void> _alarmCallback(Map<String, dynamic>? params) async {
    debugPrint('🚨 ${params?['isAlarm'] == true ? 'ALARM' : 'Notification'} triggered with params: $params');
    
    if (params == null) return;

    try {
      // Ensure Flutter bindings are initialized in background isolate
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize local notifications in background isolate
      final FlutterLocalNotificationsPlugin localNotifications = 
          FlutterLocalNotificationsPlugin();

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
      );

      await localNotifications.initialize(settings);

      // Extract parameters
      final String title = params['title'] ?? 'Task Reminder';
      final String body = params['body'] ?? 'Your scheduled task is due!';
      final int notificationId = params['notificationId'] ?? DateTime.now().millisecondsSinceEpoch.remainder(100000);
      final bool isAlarm = params['isAlarm'] == true;

      // 🚀 USE ALARM CHANNEL FOR ALARM BEHAVIOR, REGULAR CHANNEL FOR NORMAL NOTIFICATIONS
      final AndroidNotificationDetails androidDetails = isAlarm 
          ? AndroidNotificationDetails(
              'alarm_channel', // 🚀 ALARM CHANNEL
              'Alarm Reminders',
              channelDescription: 'System-level alarms for critical task reminders',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              sound: const RawResourceAndroidNotificationSound('alarm_sound'),
              enableVibration: true,
              vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
              fullScreenIntent: true, // 🚀 Full screen for alarms
              autoCancel: false, // 🚀 Don't auto-cancel alarms
              ongoing: true, // 🚀 Ongoing notification for alarms
              colorized: true,
              color: const Color(0xFFFF0000), // 🚀 Red color for urgency
              ledColor: const Color(0xFFFF0000),
              ledOnMs: 1000,
              ledOffMs: 1000,
            )
          : AndroidNotificationDetails(
              'task_channel', // 📱 REGULAR CHANNEL
              'Task Notifications',
              channelDescription: 'Notifications for task reminders',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
            );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
      );

      await localNotifications.show(
        notificationId,
        isAlarm ? '🚨 $title' : title, // 🚀 Add alarm emoji for alarms
        body,
        details,
      );

      debugPrint('✅ ${isAlarm ? 'ALARM' : 'Notification'} shown successfully');
    } catch (e) {
      debugPrint('❌ Error in alarm callback: $e');
    }
  }

  // 🚀 ENHANCED LOCAL NOTIFICATION WITH ALARM BEHAVIOR
  Future<void> _scheduleLocalNotification({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledTimeLocal,
    Map<String, dynamic>? payload,
    bool isAlarm = false, // 🆕 NEW PARAMETER
  }) async {
    try {
      // 🚀 USE ALARM CHANNEL FOR ALARM BEHAVIOR, REGULAR CHANNEL FOR NORMAL NOTIFICATIONS
      final AndroidNotificationDetails androidDetails = isAlarm
          ? AndroidNotificationDetails(
              'alarm_channel', // 🚀 ALARM CHANNEL
              'Alarm Reminders',
              channelDescription: 'System-level alarms for critical task reminders',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              sound: const RawResourceAndroidNotificationSound('alarm_sound'),
              enableVibration: true,
              vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
            )
          : AndroidNotificationDetails(
              'task_channel', // 📱 REGULAR CHANNEL
              'Task Notifications',
              channelDescription: 'Notifications for task reminders',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
            );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final localTimeZone = tz.local;
      final scheduledTzTime = tz.TZDateTime.from(scheduledTimeLocal, localTimeZone);

      // Check if we have exact alarm permission, fallback to inexact if not
      AndroidScheduleMode scheduleMode;
      try {
        final hasExactAlarmPermission = await Permission.scheduleExactAlarm.isGranted;
        scheduleMode = hasExactAlarmPermission 
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle;
        
        debugPrint('Using schedule mode: $scheduleMode');
      } catch (e) {
        scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
        debugPrint('Permission check failed, using inexact scheduling');
      }

      await localNotifications.zonedSchedule(
        notificationId,
        isAlarm ? '🚨 $title' : title, // 🚀 Add alarm emoji for alarms
        body,
        scheduledTzTime,
        details,
        payload: payload != null ? jsonEncode(payload) : null,
        androidScheduleMode: scheduleMode,
      );

      debugPrint('📱 ${isAlarm ? 'ALARM' : 'Notification'} scheduled for: $scheduledTimeLocal');
    } catch (e) {
      debugPrint('❌ Error scheduling ${isAlarm ? 'alarm' : 'notification'}: $e');
      rethrow;
    }
  }

  // 🆕 CONVENIENCE METHOD FOR ALARMS (optional)
  Future<void> scheduleAlarmNotification({
    required BuildContext context,
    required String taskId,
    required String title,
    required String body,
    required DateTime scheduledTimeUtc,
    Map<String, dynamic>? payload,
  }) async {
    await scheduleTaskNotification(
      context: context,
      taskId: taskId,
      title: title,
      body: body,
      scheduledTimeUtc: scheduledTimeUtc,
      payload: payload,
      isAlarm: true, // 🚀 Set alarm behavior
    );
  }

  // 🆕 STORE SCHEDULED ALARM
  Future<void> _storeScheduledAlarm({
    required String taskId,
    required int alarmId,
    required DateTime scheduledTimeUtc,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> alarms = prefs.getStringList(_scheduledAlarmsKey) ?? [];

      final alarmData = {
        'taskId': taskId,
        'alarmId': alarmId.toString(),
        'scheduledTimeUtc': scheduledTimeUtc.toIso8601String(),
      };

      alarms.add(jsonEncode(alarmData));
      await prefs.setStringList(_scheduledAlarmsKey, alarms);

      debugPrint('💾 Stored alarm record for task: $taskId');
    } catch (e) {
      debugPrint('Error storing alarm record: $e');
    }
  }

  // 🆕 GENERATE ALARM ID
  int _generateAlarmId(String taskId, DateTime scheduledTimeUtc) {
    // Use different calculation than notification ID to avoid conflicts
    return (taskId + scheduledTimeUtc.toIso8601String() + '_alarm').hashCode.abs() % 100000;
  }

  // 🆕 UPDATE CANCEL METHODS TO HANDLE ALARMS
  Future<void> cancelNotification(String taskId, DateTime scheduledTimeUtc) async {
    try {
      final int notificationId = _generateNotificationId(taskId, scheduledTimeUtc);
      final int alarmId = _generateAlarmId(taskId, scheduledTimeUtc);
      
      // Cancel local notification
      await localNotifications.cancel(notificationId);
      
      // Cancel Android Alarm Manager alarm
      await AndroidAlarmManager.cancel(alarmId);
      
      // Remove from scheduled local notifications
      await _removeScheduledLocalNotification(taskId, scheduledTimeUtc);
      
      // Remove from scheduled alarms
      await _removeScheduledAlarm(taskId, scheduledTimeUtc);
      
      // Remove from pending push notifications
      await _removePendingPushNotification(taskId, scheduledTimeUtc);
      
      // Cancel push notification on server
      await _cancelPushNotification(taskId);

      debugPrint('🗑️ Cancelled all notifications and alarms for task: $taskId');
    } catch (e) {
      debugPrint('Error cancelling notification: $e');
    }
  }

  // 🆕 UPDATE CANCEL ALL METHOD
  Future<void> cancelAllNotificationsForDocument({
    required String docId,
    required List<DateTime> scheduledTimesUtc,
  }) async {
    try {
      debugPrint('🗑️ Cancelling all notifications for document: $docId with ${scheduledTimesUtc.length} scheduled times');
      
      int totalCancelled = 0;

      for (final scheduledTimeUtc in scheduledTimesUtc) {
        try {
          final int notificationId = _generateNotificationId(docId, scheduledTimeUtc);
          final int alarmId = _generateAlarmId(docId, scheduledTimeUtc);
          
          // Cancel local notification
          await localNotifications.cancel(notificationId);
          
          // Cancel Android Alarm Manager alarm
          await AndroidAlarmManager.cancel(alarmId);
          
          // Remove from scheduled local notifications
          await _removeScheduledLocalNotification(docId, scheduledTimeUtc);
          
          // Remove from scheduled alarms
          await _removeScheduledAlarm(docId, scheduledTimeUtc);
          
          // Remove from pending push notifications
          await _removePendingPushNotification(docId, scheduledTimeUtc);
          
          totalCancelled++;
          
          debugPrint('✅ Cancelled notification and alarm for time: $scheduledTimeUtc');
        } catch (e) {
          debugPrint('❌ Error cancelling notification for time $scheduledTimeUtc: $e');
        }
      }

      // Cancel all push notifications on server for this document
      await _cancelAllPushNotificationsForDocument(docId);

      debugPrint('🗑️ Successfully cancelled $totalCancelled/${scheduledTimesUtc.length} notifications and alarms for document: $docId');
    } catch (e) {
      debugPrint('❌ Error in cancelAllNotificationsForDocument: $e');
    }
  }

  // 🆕 REMOVE SCHEDULED ALARM
  Future<void> _removeScheduledAlarm(String taskId, DateTime scheduledTimeUtc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> alarms = prefs.getStringList(_scheduledAlarmsKey) ?? [];

      final List<String> updated = alarms.where((alarmJson) {
        try {
          final Map<String, dynamic> data = jsonDecode(alarmJson) as Map<String, dynamic>;
          return data['taskId'] != taskId || 
                 data['scheduledTimeUtc'] != scheduledTimeUtc.toIso8601String();
        } catch (e) {
          return true;
        }
      }).toList();

      if (updated.length != alarms.length) {
        await prefs.setStringList(_scheduledAlarmsKey, updated);
        debugPrint('🗑️ Removed alarm record for task: $taskId');
      }
    } catch (e) {
      debugPrint('Error removing scheduled alarm: $e');
    }
  }

  // ✅ YOUR EXISTING METHODS (unchanged)
  Future<void> _schedulePushNotification({
    required String taskId,
    required String title,
    required String body,
    required DateTime scheduledTimeUtc,
    Map<String, dynamic>? payload,
  }) async {
    // Your existing push notification code...
    try {
      // Your existing implementation...
      debugPrint('📤 Push notification scheduled for task: $taskId');
    } catch (e) {
      debugPrint('❌ Push notification error: $e');
      await _storePendingPushNotification(
        taskId: taskId,
        title: title,
        body: body,
        scheduledTimeUtc: scheduledTimeUtc,
        payload: payload,
      );
    }
  }

  // STORAGE METHODS (your existing code)
  Future<void> _storeScheduledLocalNotification({
    required String taskId,
    required int notificationId,
    required DateTime scheduledTimeUtc,
  }) async {
    // Your existing implementation...
  }

  Future<void> _storePendingPushNotification({
    required String taskId,
    required String title,
    required String body,
    required DateTime scheduledTimeUtc,
    Map<String, dynamic>? payload,
  }) async {
    // Your existing implementation...
  }

  Future<void> _processPendingPushNotifications() async {
    // Your existing implementation...
  }

  // UTILITY METHODS (your existing code)
  DateTime _utcToLocal(DateTime utcTime) {
    return utcTime.toLocal();
  }

  int _generateNotificationId(String taskId, DateTime scheduledTimeUtc) {
    return (taskId + scheduledTimeUtc.toIso8601String()).hashCode.abs();
  }

  Future<void> _removeScheduledLocalNotification(String taskId, DateTime scheduledTimeUtc) async {
    // Your existing implementation...
  }

  Future<void> _removePendingPushNotification(String taskId, DateTime scheduledTimeUtc) async {
    // Your existing implementation...
  }

  Future<void> _cancelPushNotification(String taskId) async {
    // Your existing implementation...
  }

  Future<void> _cancelAllPushNotificationsForDocument(String docId) async {
    // Your existing implementation...
  }

  // 🚀 ENHANCED FALLBACK METHOD WITH ALARM BEHAVIOR
  Future<void> _scheduleLocalNotificationFallback({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledTimeLocal,
    Map<String, dynamic>? payload,
    bool isAlarm = false, // 🆕 NEW PARAMETER
  }) async {
    // Your existing implementation with alarm behavior...
  }

  // Helper method to get all scheduled times for a document (your existing code)
  Future<List<DateTime>> getScheduledTimesForDocument(String docId) async {
    // Your existing implementation...
    return [];
  }

  void dispose() {
    _connectivitySubscription.cancel();
  }
}