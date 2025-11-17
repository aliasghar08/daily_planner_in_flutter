// In NativeAlarmHelper - UPDATED with correct method channels
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

@pragma('vm:entry-point')
void alarmCallback(int id, [Map<String, dynamic>? params]) {
  final title = params?['title']?.toString() ?? 'Reminder';
  final body = params?['body']?.toString() ?? 'Task';

  NativeAlarmHelper._alarmChannel.invokeMethod('showAlarmNotification', {
    'id': id,
    'title': title,
    'body': body,
  });
}

class NativeAlarmHelper {
  // Channel for alarm scheduling (matches your MainActivity.kt)
  static const MethodChannel _alarmChannel = MethodChannel(
    'exact_alarm_permission',
  );

  // Channel for notification actions (matches your AlarmReceiver.kt)
  static const MethodChannel _notificationChannel = MethodChannel(
    'com.example.daily_planner/alarm',
  );

  static final _flnp = FlutterLocalNotificationsPlugin();
  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>?
  _connectivitySubscription;
  static bool _isOnline = false;
  static final List<Map<String, dynamic>> _pendingNotifications = [];

  // Add this stream controller to handle action callbacks
  static final StreamController<Map<String, dynamic>> _actionStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get actionStream =>
      _actionStreamController.stream;

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
      enableLights: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    await _flnp
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // Ensure Kotlin notification channel is created
    await _alarmChannel.invokeMethod('ensureNotificationChannel');

    // Your existing initialization code
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _flnp.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    // Timezone setup
    tz_data.initializeTimeZones();
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    // Initialize connectivity monitoring
    await _setupConnectivityMonitoring();

    // Setup method channel for native actions from Kotlin
    _setupNotificationChannel();

    debugPrint('✅ NativeAlarmHelper initialized with both method channels');
  }

  /// Setup method channel to receive native actions from Kotlin
  static void _setupNotificationChannel() {
    _notificationChannel.setMethodCallHandler((MethodCall call) async {
      debugPrint(
        '📱 Notification channel call: ${call.method} with args: ${call.arguments}',
      );

      // Your Kotlin code sends to 'onNotificationAction' method
      if (call.method == 'onNotificationAction') {
        final dynamic args = call.arguments;
        if (args is Map) {
          final String action = args['action']?.toString() ?? '';
          final int id = (args['id'] as num?)?.toInt() ?? 0;
          final String? title = args['title']?.toString();
          final String? body = args['body']?.toString();

          debugPrint(
            '🎯 Received notification action from Kotlin: $action for ID: $id',
          );

          // Send to stream controller
          _actionStreamController.add({
            'action': action,
            'id': id,
            'title': title,
            'body': body,
            'source': 'kotlin',
          });

          // Handle the action
          await _handleNativeAction(action, id, title, body);
        }
      } else {
        debugPrint(
          '❌ Unknown method call on notification channel: ${call.method}',
        );
      }
    });
  }

  /// Handle notification responses (taps and actions from Flutter local notifications)
  static void _handleNotificationResponse(NotificationResponse response) {
    debugPrint(
      '📱 Flutter notification response: actionId=${response.actionId}, id=${response.id}, payload=${response.payload}',
    );

    final String? action = response.actionId;
    final int id = response.id ?? 0;

    if (action != null && action.isNotEmpty) {
      _actionStreamController.add({
        'action': action,
        'id': id,
        'payload': response.payload,
        'source': 'flutter',
      });

      // Handle the action
      _handleNativeAction(action, id, null, null);
    } else {
      // This is a tap on the notification itself
      _actionStreamController.add({
        'action': 'tap',
        'id': id,
        'payload': response.payload,
        'source': 'flutter',
      });
    }
  }

  /// Handle native actions from both Kotlin and Flutter
  static Future<void> _handleNativeAction(
    String action,
    int id,
    String? title,
    String? body,
  ) async {
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

  static Future<void> scheduleUsingAlarmManager({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
  }) async {
    await AndroidAlarmManager.oneShotAt(
      dateTime,
      id,
      alarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      params: {'id': id, 'title': title, 'body': body},
    );

    debugPrint("⏰ Alarm Manager alarm scheduled for $dateTime");
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
      // Step 1: Schedule native alarm using android_alarm_manager-plus

      await scheduleUsingAlarmManager(
        id: id,
        title: title,
        body: body,
        dateTime: dateTime,
      );

      debugPrint(
        '✅ Native alarm scheduled via android_alarm_manager_plus: ID $id at $dateTime',
      );

      // Step 2: Schedule native alarm using your Kotlin code

      // await _scheduleNativeAlarm(
      //   id: id,
      //   title: title,
      //   body: body,
      //   dateTime: dateTime,
      // );

      // debugPrint('✅ Native alarm scheduled via Kotlin: ID $id at $dateTime');

      // Step 2: Also schedule local notification as backup
      // await _scheduleLocalNotification(
      //   id: id,
      //   title: title,
      //   body: body,
      //   dateTime: dateTime,
      //   payload: payload,
      // );

      // Step 3: Schedule FCM notification if online
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
      // Fallback to local notification only
      await _scheduleLocalNotification(
        id: id,
        title: title,
        body: body,
        dateTime: dateTime,
        payload: payload,
      );
    }
  }

  /// Schedule native Android alarm using your Kotlin code - MATCHES YOUR KOTLIN PARAMETERS
  static Future<void> _scheduleNativeAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
  }) async {
    try {
      // Match EXACTLY what your Kotlin expects
      await _alarmChannel.invokeMethod('scheduleNativeAlarm', {
        'id': id,
        'title': title,
        'body': body,
        'time':
            dateTime.millisecondsSinceEpoch, // Use 'time' not 'timeInMillis'
      });

      debugPrint('🎯 Native alarm scheduled via Kotlin: ID $id');
    } catch (e) {
      debugPrint('❌ Native alarm failed: $e');
      throw e; // Re-throw to trigger fallback
    }
  }

  /// Schedule local notification as backup
  static Future<void> _scheduleLocalNotification({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
    required Map<String, dynamic> payload,
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
        fullScreenIntent: false,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'stop_action',
            'Stop',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'snooze_action',
            'Snooze',
            showsUserInterface: true,
          ),
        ],
      );

      await _flnp.zonedSchedule(
        id,
        title,
        body,
        tzScheduled,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: json.encode(payload),
      );

      debugPrint('🔔 Local notification scheduled: ID $id');
    } catch (e) {
      debugPrint('❌ Local notification failed: $e');
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
      const String fcmSchedulingUrl =
          'https://your-server.com/api/schedule-fcm';

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
        // Don't throw - FCM is optional
      }
    } catch (e) {
      debugPrint('❌ FCM scheduling error: $e');
      // Don't throw - FCM is optional
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

    debugPrint(
      '📱 Queued FCM notification. Total pending: ${_pendingNotifications.length}',
    );
  }

  /// Process pending FCM notifications when connectivity returns
  static Future<void> _processPendingFcmNotifications() async {
    if (_pendingNotifications.isEmpty) return;

    debugPrint(
      '🔄 Processing ${_pendingNotifications.length} pending FCM notifications...',
    );

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
        debugPrint(
          '✅ Processed pending FCM notification: ${notification['id']}',
        );
      } catch (e) {
        debugPrint(
          '❌ Failed to process pending FCM notification ${notification['id']}: $e',
        );
        // Keep it in the queue for next connectivity change
      }
    }

    // Remove successfully processed notifications
    _pendingNotifications.removeWhere(
      (notification) => successfulNotifications.contains(notification),
    );

    debugPrint(
      '📱 Remaining pending notifications: ${_pendingNotifications.length}',
    );
  }

  /// Handle stop action
  static Future<void> handleStopAction(int id) async {
    debugPrint('🛑 Stop action triggered for alarm ID: $id');

    await cancelHybridAlarm(id);

    await cancelHybridAlarm(id + 1000);

    // Show confirmation notification
    // _showActionNotification('Alarm Stopped', 'Alarm has been stopped');
  }

  /// Handle snooze action
  static Future<void> handleSnoozeAction(
    int id,
    String title,
    String body,
  ) async {
    debugPrint('⏰ Snooze action triggered for alarm ID: $id');

    final snoozeTime = DateTime.now().add(const Duration(minutes: 5));

    await scheduleHybridAlarm(
      id: id + 1000, // Use different ID for snoozed alarm
      title: title,
      body: 'Snoozed: $body',
      dateTime: snoozeTime,
      payload: {'type': 'snoozed', 'originalId': id},
    );

    // _showActionNotification(
    //   'Alarm Snoozed',
    //   'Alarm will remind you in 5 minutes',
    // );
  }

  /// Show action confirmation notification
  static Future<void> _showActionNotification(String title, String body) async {
    final androidDetails = AndroidNotificationDetails(
      'daily_planner_channel',
      'Daily Planner',
      channelDescription: 'Task reminders and alerts',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    await _flnp.show(
      DateTime.now().millisecondsSinceEpoch ~/
          1000, // Unique ID based on timestamp
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
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

  /// Cancel hybrid alarm (both native and local)
  static Future<void> cancelHybridAlarm(int id) async {
    try {
      // Cancel native alarm using your Kotlin code
      // await _alarmChannel.invokeMethod('cancelAlarm', {'id': id});

      await AndroidAlarmManager.cancel(id);

      // Cancel local notification
      await _flnp.cancel(id);

      // Remove from pending FCM notifications
      _pendingNotifications.removeWhere(
        (notification) => notification['id'] == id,
      );

      debugPrint('✅ Hybrid alarm cancelled: ID $id');
    } catch (e) {
      debugPrint('Error cancelling hybrid alarm: $e');
    }
  }

  /// Check if the app has exact alarm permission (Android 12+) - MATCHES YOUR KOTLIN
  static Future<bool> checkExactAlarmPermission() async {
    try {
      if (!_isAndroid()) return true;

      final bool hasPermission = await _alarmChannel.invokeMethod(
        'checkExactAlarmPermission',
      );
      debugPrint('✅ Exact alarm permission check: $hasPermission');
      return hasPermission;
    } catch (e) {
      debugPrint('❌ Error checking exact alarm permission: $e');
      return true;
    }
  }

  /// Request exact alarm permission (Android 12+) - MATCHES YOUR KOTLIN
  static Future<void> requestExactAlarmPermission() async {
    try {
      if (!_isAndroid()) return;

      debugPrint('📱 Requesting exact alarm permission...');
      await _alarmChannel.invokeMethod('requestExactAlarmPermission');
      debugPrint('✅ Exact alarm permission request completed');
    } catch (e) {
      debugPrint('❌ Error requesting exact alarm permission: $e');
    }
  }

  /// Disable battery optimization - MATCHES YOUR KOTLIN
  static Future<void> disableBatteryOptimization() async {
    try {
      await _alarmChannel.invokeMethod('disableBatteryOptimization');
      debugPrint('✅ Battery optimization disable requested');
    } catch (e) {
      debugPrint('❌ Error disabling battery optimization: $e');
    }
  }

  /// Prompt disable battery optimization - MATCHES YOUR KOTLIN
  static Future<void> promptDisableBatteryOptimization() async {
    try {
      await _alarmChannel.invokeMethod('promptDisableBatteryOptimization');
      debugPrint('✅ Battery optimization prompt requested');
    } catch (e) {
      debugPrint('❌ Error prompting battery optimization: $e');
    }
  }

  /// Open manufacturer settings - MATCHES YOUR KOTLIN
  static Future<void> openManufacturerSettings() async {
    try {
      await _alarmChannel.invokeMethod('openManufacturerSettings');
      debugPrint('✅ Manufacturer settings opened');
    } catch (e) {
      debugPrint('❌ Error opening manufacturer settings: $e');
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
      payload: {'type': 'alarm', 'alarmId': id, 'title': title, 'body': body},
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
      fullScreenIntent: true,
      additionalFlags: Int32List.fromList([4]),
      category: AndroidNotificationCategory.alarm, // FLAG_INSISTENT
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'stop_action',
          'Stop',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'snooze_action',
          'Snooze',
          showsUserInterface: true,
        ),
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

  /// Test method to verify alarms are working with Kotlin
  static Future<void> testAlarm() async {
    final testTime = DateTime.now().add(const Duration(seconds: 10));
    await scheduleHybridAlarm(
      id: 9999,
      title: 'Test Alarm',
      body: 'This is a test alarm scheduled 10 seconds from now',
      dateTime: testTime,
      payload: {'type': 'test'},
    );
    debugPrint('🧪 Test alarm scheduled for ${testTime.toString()}');
  }

  /// Listen to action stream in your Flutter UI
  static void listenToActions(Function(Map<String, dynamic>) onAction) {
    actionStream.listen(onAction);
  }
}
