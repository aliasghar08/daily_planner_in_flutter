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
  // Method channels matching Android MainActivity.kt
  static const MethodChannel _alarmChannel = MethodChannel(
    'exact_alarm_permission',
  );

  static const MethodChannel _notificationChannel = MethodChannel(
    'com.example.daily_planner/alarm',
  );

  static const MethodChannel _foregroundServiceChannel = MethodChannel(
    'daily_planner/alarm_service',
  );

  static final _flnp = FlutterLocalNotificationsPlugin();
  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>?
  _connectivitySubscription;
  static bool _isOnline = false;
  static final List<Map<String, dynamic>> _pendingNotifications = [];

  // Stream controller to handle action callbacks
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
    try {
      await _alarmChannel.invokeMethod('ensureNotificationChannel');
    } catch (_) {}

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
    try {
      tz_data.initializeTimeZones();
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('Timezone initialization warning: $e');
    }

    // Initialize connectivity monitoring
    await _setupConnectivityMonitoring();

    // Setup method channel for native actions from Kotlin
    _setupNotificationChannel();

    // Start background service to maintain process health
    try {
      await startForegroundService();
    } catch (_) {}

    debugPrint('✅ NativeAlarmHelper initialized with custom native engine');
  }

  /// Setup method channel to receive native actions from Kotlin
  static void _setupNotificationChannel() {
    _notificationChannel.setMethodCallHandler((MethodCall call) async {
      debugPrint(
        '📱 Notification channel call: ${call.method} with args: ${call.arguments}',
      );

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

          _actionStreamController.add({
            'action': action,
            'id': id,
            'title': title,
            'body': body,
            'source': 'kotlin',
          });

          await _handleNativeAction(action, id, title, body);
        }
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

      _handleNativeAction(action, id, null, null);
    } else {
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
        debugPrint('👆 Notification tapped: ID $id');
        break;
      default:
        debugPrint('❌ Unknown action: $action');
    }
  }

  static Future<void> openAutoStartSettings() async {
    try {
      await _alarmChannel.invokeMethod('openAutoStartSettings');
    } catch (e) {
      debugPrint("Failed to open auto-start settings: $e");
    }
  }

  static Future<void> disableBatteryOptimization() async {
    try {
      await _alarmChannel.invokeMethod('disableBatteryOptimization');
    } catch (e) {
      debugPrint("Failed to prompt battery optimization: $e");
    }
  }

  static Future<void> startForegroundService() async {
    try {
      await _foregroundServiceChannel.invokeMethod('startForegroundService');
      debugPrint('🔔 Foreground service started');
    } catch (e) {
      debugPrint('❌ Failed to start service: $e');
    }
  }

  static Future<void> openExactAlarmSettings() async {
    try {
      await _alarmChannel.invokeMethod('requestExactAlarmPermission');
    } catch (e) {
      debugPrint("Error opening exact alarm settings: $e");
    }
  }

  static Future<void> stopForegroundService() async {
    try {
      await _foregroundServiceChannel.invokeMethod('stopForegroundService');
      debugPrint('🔔 Foreground service stopped');
    } catch (e) {
      debugPrint('❌ Failed to stop service: $e');
    }
  }

  /// HYBRID & NATIVE: Schedule custom native exact alarm and backup notifications
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
      // Step 1: Schedule custom native Android alarm (persisted and survives reboots & killed states)
      await _scheduleNativeAlarm(
        id: id,
        title: title,
        body: body,
        dateTime: dateTime,
        payload: json.encode(payload),
      );

      debugPrint('✅ Native alarm scheduled via Kotlin: ID $id at $dateTime');

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
      } else {
        _queuePendingFcmNotification(
          id: id,
          title: title,
          body: body,
          dateTime: dateTime,
          payload: payload,
          fcmTopic: fcmTopic,
          fcmTokens: fcmTokens,
        );
      }
    } catch (e) {
      debugPrint('❌ Native alarm scheduling failed: $e. Fallback to local notification.');
      await _scheduleLocalNotification(
        id: id,
        title: title,
        body: body,
        dateTime: dateTime,
        payload: payload,
      );
    }
  }

  /// Schedule native Android alarm using custom Kotlin engine
  static Future<void> _scheduleNativeAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
    String? payload,
  }) async {
    try {
      await _alarmChannel.invokeMethod('scheduleNativeAlarm', {
        'id': id,
        'title': title,
        'body': body,
        'time': dateTime.millisecondsSinceEpoch,
        'payload': payload ?? '',
      });

      debugPrint('🎯 Native alarm scheduled via Kotlin: ID $id');
    } catch (e) {
      debugPrint('❌ Native alarm failed: $e');
      rethrow;
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
        ongoing: false,
        autoCancel: true,
        fullScreenIntent: true,
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

  /// Schedule FCM notification via server
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
      }
    } catch (e) {
      debugPrint('❌ FCM scheduling error: $e');
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
      }
    }

    _pendingNotifications.removeWhere(
      (notification) => successfulNotifications.contains(notification),
    );
  }

  /// Handle stop action
  static Future<void> handleStopAction(int id) async {
    debugPrint('🛑 Stop action triggered for alarm ID: $id');
    await cancelHybridAlarm(id);
    await cancelHybridAlarm(id + 1000);
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
      id: id + 1000,
      title: title,
      body: 'Snoozed: $body',
      dateTime: snoozeTime,
      payload: {'type': 'snoozed', 'originalId': id},
    );
  }

  /// Setup connectivity monitoring
  static Future<void> _setupConnectivityMonitoring() async {
    final initialResult = await _connectivity.checkConnectivity();
    _isOnline = _isAnyConnectivityOnline(initialResult);

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      final bool wasOnline = _isOnline;
      _isOnline = _isAnyConnectivityOnline(results);

      if (_isOnline && !wasOnline) {
        await _processPendingFcmNotifications();
      }
    });
  }

  static bool _isAnyConnectivityOnline(List<ConnectivityResult> results) {
    return results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn,
    );
  }

  static bool get isOnline => _isOnline;
  static int get pendingNotificationsCount => _pendingNotifications.length;

  /// Cancel alarm natively and from all local queues
  static Future<void> cancelHybridAlarm(int id) async {
    try {
      // Cancel custom native alarm from AlarmManager & AlarmStorage
      await _alarmChannel.invokeMethod('cancelAlarm', {'id': id});

      // Cancel local notification
      await _flnp.cancel(id);

      // Remove from pending FCM notifications
      _pendingNotifications.removeWhere(
        (notification) => notification['id'] == id,
      );

      debugPrint('✅ Native alarm cancelled: ID $id');
    } catch (e) {
      debugPrint('Error cancelling native alarm: $e');
    }
  }

  /// Cancel all alarms
  static Future<void> cancelAllAlarms() async {
    try {
      await _alarmChannel.invokeMethod('cancelAllAlarms');
      await _flnp.cancelAll();
      _pendingNotifications.clear();
      debugPrint('✅ All native alarms cancelled');
    } catch (e) {
      debugPrint('Error cancelling all alarms: $e');
    }
  }

  /// Get list of active native alarms from persistent storage
  static Future<List<dynamic>> getScheduledAlarms() async {
    try {
      final List<dynamic>? alarms = await _alarmChannel.invokeMethod('getScheduledAlarms');
      return alarms ?? [];
    } catch (e) {
      debugPrint('Error getting scheduled alarms: $e');
      return [];
    }
  }

  /// Check if the app has exact alarm permission (Android 12+)
  static Future<bool> checkExactAlarmPermission() async {
    try {
      if (!_isAndroid()) return true;

      final bool hasPermission = await _alarmChannel.invokeMethod(
        'checkExactAlarmPermission',
      );
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
      await _alarmChannel.invokeMethod('requestExactAlarmPermission');
    } catch (e) {
      debugPrint('❌ Error requesting exact alarm permission: $e');
    }
  }

  /// Schedule method for backward compatibility
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

  /// Cancel alarm by ID for backward compatibility
  static Future<void> cancelAlarmById(int id) async {
    await cancelHybridAlarm(id);
  }

  // Show immediate notification with actions
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
      ongoing: false,
      autoCancel: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
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

  static bool _isAndroid() {
    return Platform.isAndroid;
  }

  static void dispose() {
    _connectivitySubscription?.cancel();
    _actionStreamController.close();
    _pendingNotifications.clear();
  }

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

  /// Fetch device brand and battery optimization info
  static Future<Map<String, dynamic>> getDeviceBrandInfo() async {
    try {
      if (!_isAndroid()) return {};
      final dynamic res = await _alarmChannel.invokeMethod('getDeviceBrandInfo');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('Error getting device brand info: $e');
    }
    return {};
  }

  /// Show customized OEM optimization guidance dialog
  static Future<void> showOemOptimizationGuide(BuildContext context) async {
    final info = await getDeviceBrandInfo();
    final String manufacturer = (info['manufacturer'] ?? '').toString().toLowerCase();
    final bool isIgnoringBattery = info['isIgnoringBatteryOptimizations'] == true;

    String oemTitle = 'Background Alarm Optimization';
    String oemGuide = '';

    if (manufacturer.contains('infinix') || manufacturer.contains('tecno') || manufacturer.contains('transsion') || manufacturer.contains('itel')) {
      oemTitle = 'Infinix / Tecno (Transsion) Setup';
      oemGuide = 'To ensure alarms ring when your phone is locked or after reboot:\n\n'
          '1. Tap "Open Auto-Start" below.\n'
          '2. In Phone Master, turn ON "Auto-start" for Daily Planner.\n'
          '3. Disable "App Freeze" / Power Save restrictions for Daily Planner.';
    } else if (manufacturer.contains('xiaomi') || manufacturer.contains('redmi') || manufacturer.contains('poco')) {
      oemTitle = 'Xiaomi / MIUI / HyperOS Setup';
      oemGuide = 'To ensure alarms ring when your phone is locked or after reboot:\n\n'
          '1. Tap "Open Auto-Start" below and turn ON "Autostart" for Daily Planner.\n'
          '2. In App Info -> Battery saver, select "No restrictions".\n'
          '3. Under Other Permissions, allow "Show on Lock screen".';
    } else if (manufacturer.contains('oppo') || manufacturer.contains('realme')) {
      oemTitle = 'Oppo / Realme (ColorOS) Setup';
      oemGuide = 'To ensure alarms ring when your phone is locked or after reboot:\n\n'
          '1. Tap "Open Auto-Start" below.\n'
          '2. Enable "Auto-launch" for Daily Planner.\n'
          '3. Under Battery -> App Battery Management, enable "Allow background activity".';
    } else if (manufacturer.contains('vivo') || manufacturer.contains('iqoo')) {
      oemTitle = 'Vivo / iQOO (FuntouchOS) Setup';
      oemGuide = 'To ensure alarms ring when your phone is locked or after reboot:\n\n'
          '1. Tap "Open Auto-Start" below and enable Daily Planner.\n'
          '2. In Settings -> Battery, enable "High background power consumption".';
    } else if (manufacturer.contains('huawei') || manufacturer.contains('honor')) {
      oemTitle = 'Huawei / Honor Setup';
      oemGuide = 'To ensure alarms ring when your phone is locked or after reboot:\n\n'
          '1. Tap "Open Auto-Start" below.\n'
          '2. Set Daily Planner launch to "Manage manually".\n'
          '3. Turn ON Auto-launch, Secondary launch, and Run in background.';
    } else if (manufacturer.contains('samsung')) {
      oemTitle = 'Samsung OneUI Setup';
      oemGuide = 'To ensure alarms ring when your phone is locked or after reboot:\n\n'
          '1. In Settings -> Battery -> Background usage limits, ensure Daily Planner is NOT in "Sleeping apps" or "Deep sleeping apps".\n'
          '2. Tap "Disable Battery Limits" below.';
    } else {
      oemTitle = 'Alarm Reliability Settings';
      oemGuide = 'To ensure notifications & alarms ring reliably even when the app is closed or after restarting:\n\n'
          '1. Disable battery optimization for Daily Planner.\n'
          '2. Ensure exact alarm permissions are granted.';
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(oemTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(oemGuide, style: const TextStyle(fontSize: 14, height: 1.4)),
              const SizedBox(height: 12),
              if (isIgnoringBattery)
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 6),
                    Text('Battery optimization disabled', style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton(
            onPressed: () async {
              await disableBatteryOptimization();
            },
            child: const Text('Battery Settings'),
          ),
          ElevatedButton(
            onPressed: () async {
              await openAutoStartSettings();
            },
            child: const Text('Open Auto-Start'),
          ),
        ],
      ),
    );
  }

  static void listenToActions(Function(Map<String, dynamic>) onAction) {
    actionStream.listen(onAction);
  }
}

