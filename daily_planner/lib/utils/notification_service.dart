// services/notification_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

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

  // Track current connectivity state
  bool _isOnline = false;

  Future<void> initialize() async {
    await _setupLocalNotifications();
    await _setupConnectivityMonitoring();
    await _requestNotificationPermissions();
    await _checkInitialConnectivity();
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

  // ENHANCED HYBRID APPROACH
  Future<void> scheduleTaskNotification({
    required String taskId,
    required String title,
    required String body,
    required DateTime scheduledTimeUtc,
    Map<String, dynamic>? payload,
  }) async {
    try {
      // Convert UTC time from Firestore to local device time
      final DateTime scheduledTimeLocal = _utcToLocal(scheduledTimeUtc);
      
      // Generate notification ID at runtime
      final int notificationId = _generateNotificationId(taskId, scheduledTimeUtc);
      
      // 🚀 STRATEGY 1: ALWAYS SCHEDULE LOCAL NOTIFICATION (Primary)
      // This ensures the user gets the notification even if:
      // - App is killed/closed
      // - No internet connection at notification time
      // - Push notification fails or is delayed
      await _scheduleLocalNotification(
        notificationId: notificationId,
        title: title,
        body: body,
        scheduledTimeLocal: scheduledTimeLocal,
        payload: payload,
      );

      // Store record of scheduled local notification
      await _storeScheduledLocalNotification(
        taskId: taskId,
        notificationId: notificationId,
        scheduledTimeUtc: scheduledTimeUtc,
      );

      // 🚀 STRATEGY 2: PUSH NOTIFICATION (Secondary - for cross-device sync & reliability)
      if (_isOnline) {
        // Online: Attempt to send push notification immediately
        await _schedulePushNotification(
          taskId: taskId,
          title: title,
          body: body,
          scheduledTimeUtc: scheduledTimeUtc,
          payload: payload,
        );
      } else {
        // Offline: Store push notification for later
        await _storePendingPushNotification(
          taskId: taskId,
          title: title,
          body: body,
          scheduledTimeUtc: scheduledTimeUtc,
          payload: payload,
        );
      }

      debugPrint('✅ Hybrid notification scheduled - Local: Always, Push: ${_isOnline ? 'Immediate' : 'Pending'}');

    } catch (e) {
      debugPrint('❌ Error in hybrid notification scheduling: $e');
      // Even if hybrid fails, ensure at least local notification works
      await _scheduleLocalNotificationFallback(
        notificationId: _generateNotificationId(taskId, scheduledTimeUtc),
        title: title,
        body: body,
        scheduledTimeLocal: _utcToLocal(scheduledTimeUtc),
        payload: payload,
      );
    }
  }

  // LOCAL NOTIFICATION METHODS (Primary)
  Future<void> _scheduleLocalNotification({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledTimeLocal,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'task_channel',
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
        title,
        body,
        scheduledTzTime,
        details,
        payload: payload != null ? jsonEncode(payload) : null,
        androidScheduleMode: scheduleMode,
      );

      debugPrint('📱 Local notification scheduled for: $scheduledTimeLocal');
    } catch (e) {
      debugPrint('❌ Error scheduling local notification: $e');
      rethrow;
    }
  }

  // PUSH NOTIFICATION METHODS (Secondary)
  Future<void> _schedulePushNotification({
    required String taskId,
    required String title,
    required String body,
    required DateTime scheduledTimeUtc,
    Map<String, dynamic>? payload,
  }) async {
    try {
      // This would call your server to schedule a push notification
      // For now, we'll simulate it with a direct FCM call
      const String pushServiceUrl =
          'https://fcm.googleapis.com/v1/projects/daily-planner-593d8/messages:send';

      final response = await http
          .post(
            Uri.parse(pushServiceUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer your-server-key' // You need server key
            },
            body: jsonEncode({
              'message': {
                'token': 'user-fcm-token', // You need to store user FCM token
                'notification': {
                  'title': title,
                  'body': body,
                },
                'data': {
                  'taskId': taskId,
                  'scheduledTime': scheduledTimeUtc.toIso8601String(),
                  'type': 'task_reminder',
                  ...?payload,
                },
                'android': {
                  'priority': 'high'
                },
                'apns': {
                  'payload': {
                    'aps': {
                      'content-available': 1,
                    }
                  }
                }
              }
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('📤 Push notification scheduled successfully');
      } else {
        debugPrint('❌ Push notification failed: ${response.statusCode}');
        // Store for retry later
        await _storePendingPushNotification(
          taskId: taskId,
          title: title,
          body: body,
          scheduledTimeUtc: scheduledTimeUtc,
          payload: payload,
        );
      }
    } catch (e) {
      debugPrint('❌ Push notification error: $e');
      // Store for retry when online
      await _storePendingPushNotification(
        taskId: taskId,
        title: title,
        body: body,
        scheduledTimeUtc: scheduledTimeUtc,
        payload: payload,
      );
    }
  }

  // STORAGE METHODS
  Future<void> _storeScheduledLocalNotification({
    required String taskId,
    required int notificationId,
    required DateTime scheduledTimeUtc,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> scheduled = 
          prefs.getStringList(_scheduledLocalNotificationsKey) ?? [];

      final notificationData = {
        'taskId': taskId,
        'notificationId': notificationId,
        'scheduledTimeUtc': scheduledTimeUtc.toIso8601String(),
      };

      scheduled.add(jsonEncode(notificationData));
      await prefs.setStringList(_scheduledLocalNotificationsKey, scheduled);

      debugPrint('💾 Stored local notification record for task: $taskId');
    } catch (e) {
      debugPrint('Error storing local notification record: $e');
    }
  }

  Future<void> _storePendingPushNotification({
    required String taskId,
    required String title,
    required String body,
    required DateTime scheduledTimeUtc,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> pending = 
          prefs.getStringList(_pendingPushNotificationsKey) ?? [];

      final notificationData = {
        'taskId': taskId,
        'title': title,
        'body': body,
        'scheduledTimeUtc': scheduledTimeUtc.toIso8601String(),
        'payload': payload,
        'storedAt': DateTime.now().toIso8601String(),
      };

      pending.add(jsonEncode(notificationData));
      await prefs.setStringList(_pendingPushNotificationsKey, pending);

      debugPrint('💾 Stored pending push notification for task: $taskId');
    } catch (e) {
      debugPrint('Error storing pending push notification: $e');
    }
  }

  Future<void> _processPendingPushNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> pending = 
          prefs.getStringList(_pendingPushNotificationsKey) ?? [];

      if (pending.isEmpty) return;

      debugPrint('🔄 Processing ${pending.length} pending push notifications');

      final List<String> failedNotifications = [];
      final DateTime now = DateTime.now();

      for (final String notificationJson in pending) {
        try {
          final Map<String, dynamic> notificationData =
              jsonDecode(notificationJson) as Map<String, dynamic>;

          final DateTime scheduledTime = 
              DateTime.parse(notificationData['scheduledTimeUtc'] as String);

          // Only process future notifications
          if (scheduledTime.isAfter(now)) {
            final bool success = await _sendSinglePushNotification(notificationData);
            
            if (!success) {
              failedNotifications.add(notificationJson);
            }
          } else {
            debugPrint('⏰ Skipping expired push notification');
          }
        } catch (e) {
          debugPrint('Error processing pending push notification: $e');
          failedNotifications.add(notificationJson);
        }
      }

      await prefs.setStringList(_pendingPushNotificationsKey, failedNotifications);

      if (failedNotifications.isEmpty) {
        debugPrint('✅ All pending push notifications processed successfully');
      } else {
        debugPrint('❌ ${failedNotifications.length} push notifications failed');
      }
    } catch (e) {
      debugPrint('Error in processPendingPushNotifications: $e');
    }
  }

  Future<bool> _sendSinglePushNotification(Map<String, dynamic> notificationData) async {
    // Similar to _schedulePushNotification but for retrying pending ones
    // Implementation would be similar to your existing _sendPushNotification
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate API call
    return true; // Simulate success
  }

  // UTILITY METHODS
  DateTime _utcToLocal(DateTime utcTime) {
    return utcTime.toLocal();
  }

  int _generateNotificationId(String taskId, DateTime scheduledTimeUtc) {
    return (taskId + scheduledTimeUtc.toIso8601String()).hashCode.abs();
  }

  Future<void> cancelNotification(String taskId, DateTime scheduledTimeUtc) async {
    try {
      final int notificationId = _generateNotificationId(taskId, scheduledTimeUtc);
      
      // Cancel local notification
      await localNotifications.cancel(notificationId);
      
      // Remove from scheduled local notifications
      await _removeScheduledLocalNotification(taskId, scheduledTimeUtc);
      
      // Remove from pending push notifications
      await _removePendingPushNotification(taskId, scheduledTimeUtc);
      
      // Cancel push notification on server
      await _cancelPushNotification(taskId);

      debugPrint('🗑️ Cancelled all notifications for task: $taskId');
    } catch (e) {
      debugPrint('Error cancelling notification: $e');
    }
  }

  Future<void> _removeScheduledLocalNotification(String taskId, DateTime scheduledTimeUtc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> scheduled = 
          prefs.getStringList(_scheduledLocalNotificationsKey) ?? [];

      final List<String> updated = scheduled.where((notificationJson) {
        try {
          final Map<String, dynamic> data = jsonDecode(notificationJson) as Map<String, dynamic>;
          return data['taskId'] != taskId || 
                 data['scheduledTimeUtc'] != scheduledTimeUtc.toIso8601String();
        } catch (e) {
          return true;
        }
      }).toList();

      if (updated.length != scheduled.length) {
        await prefs.setStringList(_scheduledLocalNotificationsKey, updated);
      }
    } catch (e) {
      debugPrint('Error removing scheduled local notification: $e');
    }
  }

  Future<void> _removePendingPushNotification(String taskId, DateTime scheduledTimeUtc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> pending = 
          prefs.getStringList(_pendingPushNotificationsKey) ?? [];

      final List<String> updated = pending.where((notificationJson) {
        try {
          final Map<String, dynamic> data = jsonDecode(notificationJson) as Map<String, dynamic>;
          return data['taskId'] != taskId || 
                 data['scheduledTimeUtc'] != scheduledTimeUtc.toIso8601String();
        } catch (e) {
          return true;
        }
      }).toList();

      if (updated.length != pending.length) {
        await prefs.setStringList(_pendingPushNotificationsKey, updated);
      }
    } catch (e) {
      debugPrint('Error removing pending push notification: $e');
    }
  }

  Future<void> _cancelPushNotification(String taskId) async {
    try {
      // Call your server to cancel the scheduled push notification
      const String cancelUrl = 'https://your-push-service.com/cancel';
      await http.post(
        Uri.parse(cancelUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'taskId': taskId}),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Error canceling push notification: $e');
    }
  }

  // Add other existing methods like getPendingNotificationsCount, dispose, etc.
  void dispose() {
    _connectivitySubscription.cancel();
  }

  // Fallback method
  Future<void> _scheduleLocalNotificationFallback({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledTimeLocal,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'task_channel_fallback',
        'Task Notifications Fallback',
        channelDescription: 'Fallback notifications for task reminders',
        importance: Importance.high,
        priority: Priority.high,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final localTimeZone = tz.local;
      final scheduledTzTime = tz.TZDateTime.from(scheduledTimeLocal, localTimeZone);

      await localNotifications.zonedSchedule(
        notificationId,
        title,
        body,
        scheduledTzTime,
        details,
        payload: payload != null ? jsonEncode(payload) : null,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );

      debugPrint('🆘 Fallback local notification scheduled');
    } catch (e) {
      debugPrint('❌ Fallback scheduling failed: $e');
    }
  }
}