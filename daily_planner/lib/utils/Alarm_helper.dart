// In NativeAlarmHelper - update the method channel to match your Kotlin
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

class NativeAlarmHelper {
  static const MethodChannel _channel = MethodChannel('com.example.daily_planner/alarm');
  static final _flnp = FlutterLocalNotificationsPlugin();
  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static bool _isOnline = false;
  static final List<Map<String, dynamic>> _pendingNotifications = [];
  
  // Add this stream controller to handle action callbacks
  static final StreamController<Map<String, dynamic>> _actionStreamController = 
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get actionStream => _actionStreamController.stream;

  /// MUST call once during app startup
  static Future<void> initialize() async {
    // Create notification channel first (Android 8.0+)
    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      'daily_planner_channel',
      'Daily Planner',
      description: 'Task reminders and alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
    );
    
    await _flnp.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

    // Your existing initialization code
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    
    );
    
    await _flnp.initialize(
      InitializationSettings(
        android: androidSettings, 
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    // Timezone setup
    tz_data.initializeTimeZones();
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    // Initialize connectivity monitoring
    await _setupConnectivityMonitoring();

    // Setup method channel for native actions
    _setupMethodChannel();
  }

  /// Setup method channel to receive native actions
  static void _setupMethodChannel() {
    _channel.setMethodCallHandler((MethodCall call) async {
      debugPrint('📱 Method channel call: ${call.method} with args: ${call.arguments}');
      
      switch (call.method) {
        case 'onNotificationAction':
          final dynamic args = call.arguments;
          if (args is Map) {
            final String action = args['action'] ?? '';
            final int id = args['id'] ?? 0;
            final String? title = args['title'];
            final String? body = args['body'];
            
            debugPrint('🎯 Received notification action: $action for ID: $id');
            
            _actionStreamController.add({
              'action': action,
              'id': id,
              'title': title,
              'body': body,
            });
            
            // Handle the action
            await _handleNativeAction(action, id, title, body);
          }
          break;
        default:
          debugPrint('❌ Unknown method call: ${call.method}');
      }
    });
  }

  /// Handle notification responses (taps and actions)
  static void _handleNotificationResponse(NotificationResponse response) {
    debugPrint('📱 Notification response: actionId=${response.actionId}, id=${response.id}, payload=${response.payload}');
    
    final String? action = response.actionId;
    final int id = response.id ?? 0;
    
    if (action != null && action.isNotEmpty) {
      _actionStreamController.add({
        'action': action,
        'id': id,
        'payload': response.payload,
      });
      
      // Handle the action
      _handleNativeAction(action, id, null, null);
    } else {
      // This is a tap on the notification itself
      _actionStreamController.add({
        'action': 'tap',
        'id': id,
        'payload': response.payload,
      });
    }
  }

  /// Handle native actions
  static Future<void> _handleNativeAction(String action, int id, String? title, String? body) async {
    debugPrint('🔄 Handling action: $action for ID: $id');
    
    switch (action) {
      case 'stop_action':
      case 'stop':
        await handleStopAction(id);
        break;
      case 'snooze_action':
      case 'snooze':
        await handleSnoozeAction(id, title ?? 'Reminder', body ?? 'Task');
        break;
      case 'tap':
        // Handle notification tap
        debugPrint('👆 Notification tapped: ID $id');
        break;
      default:
        debugPrint('❌ Unknown action: $action');
    }
  }

  /// HYBRID: Schedule both native alarm and FCM notification based on connectivity
  static Future<void> scheduleHybridAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
    required Map<String, dynamic> payload,
    String? fcmTopic,
    List<String>? fcmTokens,
  }) async {
    try {
      // Step 1: Always schedule native alarm (works offline)
      await _scheduleNativeAlarmWithActions(
        id: id,
        title: title,
        body: body,
        dateTime: dateTime,
        payload: payload,
      );

      debugPrint('✅ Native alarm scheduled: ID $id at $dateTime');

      // Step 2: Schedule FCM notification if online
      if (_isOnline) {
        await _scheduleFcmNotification(
          id: id,
          title: title,
          body: body,
          dateTime: dateTime,
          payload: payload,
          fcmTopic: fcmTopic,
          fcmTokens: fcmTokens,
        );
        debugPrint('✅ FCM notification scheduled: ID $id');
      } else {
        // Queue FCM notification for when we come online
        _queuePendingFcmNotification(
          id: id,
          title: title,
          body: body,
          dateTime: dateTime,
          payload: payload,
          fcmTopic: fcmTopic,
          fcmTokens: fcmTokens,
        );
        debugPrint('📱 FCM notification queued (offline): ID $id');
      }

    } catch (e) {
      debugPrint('❌ Hybrid alarm failed: $e');
      
      // Fallback: Use local notifications only
      await _scheduleFallbackLocalNotification(
        id: id,
        title: title,
        body: body,
        dateTime: dateTime,
      );
    }
  }

  /// Schedule native Android alarm with actions (most reliable)
  static Future<void> _scheduleNativeAlarmWithActions({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await _channel.invokeMethod('scheduleAlarm', {
        'id': id,
        'timeInMillis': dateTime.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        'payload': payload,
      });
    } catch (e) {
      debugPrint('❌ Native alarm failed: $e');
      throw e; // Re-throw to trigger fallback
    }
  }

  /// Schedule FCM notification via your server
  static Future<void> _scheduleFcmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
    required Map<String, dynamic> payload,
    String? fcmTopic,
    List<String>? fcmTokens,
  }) async {
    try {
      // Replace with your actual FCM scheduling endpoint
      const String fcmSchedulingUrl = 'https://your-server.com/api/schedule-fcm';
      
      final Map<String, dynamic> fcmData = {
        'notificationId': id,
        'title': title,
        'body': body,
        'scheduledTime': dateTime.millisecondsSinceEpoch,
        'payload': payload,
        'topic': fcmTopic,
        'tokens': fcmTokens,
      };

      final response = await http.post(
        Uri.parse(fcmSchedulingUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(fcmData),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ FCM notification scheduled successfully');
      } else {
        debugPrint('❌ FCM scheduling failed: ${response.statusCode}');
        throw Exception('FCM scheduling failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ FCM scheduling error: $e');
      throw e;
    }
  }

  /// Queue FCM notification for when connectivity returns
  static void _queuePendingFcmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
    required Map<String, dynamic> payload,
    String? fcmTopic,
    List<String>? fcmTokens,
  }) {
    _pendingNotifications.add({
      'id': id,
      'title': title,
      'body': body,
      'dateTime': dateTime,
      'payload': payload,
      'fcmTopic': fcmTopic,
      'fcmTokens': fcmTokens,
      'timestamp': DateTime.now(),
    });

    debugPrint('📱 Queued FCM notification. Total pending: ${_pendingNotifications.length}');
  }

  /// Process pending FCM notifications when connectivity returns
  static Future<void> _processPendingFcmNotifications() async {
    if (_pendingNotifications.isEmpty) return;

    debugPrint('🔄 Processing ${_pendingNotifications.length} pending FCM notifications...');

    final successfulNotifications = <Map<String, dynamic>>[];

    for (final notification in _pendingNotifications) {
      try {
        await _scheduleFcmNotification(
          id: notification['id'],
          title: notification['title'],
          body: notification['body'],
          dateTime: notification['dateTime'],
          payload: notification['payload'],
          fcmTopic: notification['fcmTopic'],
          fcmTokens: notification['fcmTokens'],
        );

        successfulNotifications.add(notification);
        debugPrint('✅ Processed pending FCM notification: ${notification['id']}');
      } catch (e) {
        debugPrint('❌ Failed to process pending FCM notification ${notification['id']}: $e');
        // Keep it in the queue for next connectivity change
      }
    }

    // Remove successfully processed notifications
    _pendingNotifications.removeWhere((notification) => 
      successfulNotifications.contains(notification)
    );

    debugPrint('📱 Remaining pending notifications: ${_pendingNotifications.length}');
  }

  /// Fallback to local notifications with actions
  static Future<void> _scheduleFallbackLocalNotification({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
  }) async {
    try {
      final tzScheduled = tz.TZDateTime.from(dateTime, tz.local);
      
      final androidDetails = AndroidNotificationDetails(
        'daily_planner_channel',
        'Daily Planner',
        channelDescription: 'Task reminders and alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        ongoing: true,
        autoCancel: false,
        additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction('stop_action', 'Stop'),
          AndroidNotificationAction('snooze_action', 'Snooze'),
        ],
      );
      
      await _flnp.zonedSchedule(
        id,
        title,
        body,
        tzScheduled,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
       // uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );

      debugPrint('🔄 Fallback local notification scheduled with actions: ID $id');
    } catch (e) {
      debugPrint('❌ Fallback local notification also failed: $e');
    }
  }

  /// Handle stop action
  static Future<void> handleStopAction(int id) async {
    debugPrint('🛑 Stop action triggered for alarm ID: $id');
    await cancelHybridAlarm(id);
    
    // You can add additional logic here
    // e.g., mark task as completed, update UI, etc.
  }

  /// Handle snooze action
  static Future<void> handleSnoozeAction(int id, String title, String body) async {
    debugPrint('⏰ Snooze action triggered for alarm ID: $id');
    
    final snoozeTime = DateTime.now().add(Duration(minutes: 5));
    
    await scheduleHybridAlarm(
      id: id + 1000, // Use different ID for snoozed alarm
      title: title,
      body: 'Snoozed: $body',
      dateTime: snoozeTime,
      payload: {'type': 'snoozed', 'originalId': id},
    );
    
    // You can add additional logic here
  }

  /// Setup connectivity monitoring
  static Future<void> _setupConnectivityMonitoring() async {
    // Get initial connectivity status
    final initialResult = await _connectivity.checkConnectivity();
    _isOnline = _isAnyConnectivityOnline(initialResult);

    debugPrint('Initial connectivity: ${_isOnline ? 'Online' : 'Offline'}');

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      final bool wasOnline = _isOnline;
      _isOnline = _isAnyConnectivityOnline(results);

      debugPrint('Connectivity changed: ${_isOnline ? 'Online' : 'Offline'}');

      // Process pending FCM notifications when coming back online
      if (_isOnline && !wasOnline) {
        await _processPendingFcmNotifications();
      }
    });
  }

  /// Check if any connectivity result indicates online status
  static bool _isAnyConnectivityOnline(List<ConnectivityResult> results) {
    return results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn,
    );
  }

  /// Get current connectivity status
  static bool get isOnline => _isOnline;

  /// Get number of pending FCM notifications
  static int get pendingNotificationsCount => _pendingNotifications.length;

  /// Cancel hybrid alarm (both native and FCM)
  static Future<void> cancelHybridAlarm(int id) async {
    try {
      // Cancel native alarm
      await _channel.invokeMethod('cancelAlarm', {'id': id});
      
      // Cancel local notification
      await _flnp.cancel(id);
      
      // Remove from pending FCM notifications
      _pendingNotifications.removeWhere((notification) => notification['id'] == id);
      
      // TODO: Cancel FCM notification on server (implement server endpoint)
      debugPrint('✅ Hybrid alarm cancelled: ID $id');
    } catch (e) {
      debugPrint('Error cancelling hybrid alarm: $e');
    }
  }

  /// Check if the app has exact alarm permission (Android 12+)
  static Future<bool> checkExactAlarmPermission() async {
    try {
      if (!_isAndroid()) return true;
      
      final bool hasPermission = await _channel.invokeMethod('checkExactAlarmPermission');
      debugPrint('✅ Exact alarm permission check: $hasPermission');
      return hasPermission;
    } catch (e) {
      debugPrint('❌ Error checking exact alarm permission: $e');
      return true;
    }
  }

  /// Request exact alarm permission (Android 12+)
  static Future<void> requestExactAlarmPermission() async {
    try {
      if (!_isAndroid()) return;
      
      debugPrint('📱 Requesting exact alarm permission...');
      await _channel.invokeMethod('requestExactAlarmPermission');
      debugPrint('✅ Exact alarm permission request completed');
    } catch (e) {
      debugPrint('❌ Error requesting exact alarm permission: $e');
      _openSystemAlarmSettings();
    }
  }

  /// Original schedule method (backward compatibility)
  static Future<void> scheduleAlarmAtTime({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
  }) async {
    await scheduleHybridAlarm(
      id: id,
      title: title,
      body: body,
      dateTime: dateTime,
      payload: {
        'type': 'alarm',
        'alarmId': id,
        'title': title,
        'body': body,
      },
    );
  }

  /// Cancel both native and local alarms (backward compatibility)
  static Future<void> cancelAlarmById(int id) async {
    await cancelHybridAlarm(id);
  }

  // Keep your existing showNow method with actions
  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'daily_planner_channel',
      'Daily Planner',
      channelDescription: 'Task reminders and alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      ongoing: true,
      autoCancel: false,
      additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction('stop_action', 'Stop'),
        AndroidNotificationAction('snooze_action', 'Snooze'),
      ],
    );

    await _flnp.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  // Helper method to check if running on Android
  static bool _isAndroid() {
    return Platform.isAndroid;
  }

  // Fallback method to open system alarm settings
  static Future<void> _openSystemAlarmSettings() async {
    try {
      const MethodChannel('flutter.baseflow.com/app_retainer')
          .invokeMethod('openSystemAlarmSettings');
    } catch (e) {
      debugPrint('❌ Failed to open system alarm settings: $e');
      try {
        await _channel.invokeMethod('openAppSettings');
      } catch (e2) {
        debugPrint('❌ Failed to open app settings: $e2');
      }
    }
  }

  /// Dispose connectivity subscription and stream controller
  static void dispose() {
    _connectivitySubscription?.cancel();
    _actionStreamController.close();
    _pendingNotifications.clear();
  }

  // Snackbar helpers for UI feedback
  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}