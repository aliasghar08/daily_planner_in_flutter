import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:daily_planner/services/native_connectivity_service.dart';
import 'package:daily_planner/services/native_timezone_service.dart';
import 'native_permission_service.dart';

/// NativeAlarmHelper
/// Custom service layer connecting Flutter to native Android AlarmManager,
/// ForegroundService, NotificationManagerCompat, and OEM power optimizations.
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

  // Stream controller to handle action callbacks
  static final StreamController<Map<String, dynamic>> _actionStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get actionStream =>
      _actionStreamController.stream;

  /// MUST call once during app startup
  static Future<void> initialize() async {
    // Ensure notification channel/categories are created
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _alarmChannel.invokeMethod('ensureNotificationChannel');
      }
    } catch (_) {}

    // Initialize native connectivity monitoring
    NativeConnectivityService.initialize();

    // Cache device timezone
    await NativeTimezoneService.getLocalTimezone();

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
          final String? payload = args['payload']?.toString();

          debugPrint(
            '🎯 Received notification action from Kotlin: $action for ID: $id with payload: $payload',
          );

          _actionStreamController.add({
            'action': action,
            'id': id,
            'title': title,
            'body': body,
            'payload': payload,
            'source': 'kotlin',
          });

          await _handleNativeAction(action, id, title, body);
        }
      }
    });
  }

  /// Handle native actions from Kotlin
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
        debugPrint('ℹ️ Action: $action');
    }
  }

  static Future<void> openAutoStartSettings() async {
    await NativePermissionService.openAutoStartSettings();
  }

  static Future<void> disableBatteryOptimization() async {
    await NativePermissionService.disableBatteryOptimization();
  }

  static Future<void> startForegroundService() async {
    try {
      if (!Platform.isAndroid) return;
      await _foregroundServiceChannel.invokeMethod('startForegroundService');
      debugPrint('🔔 Foreground service started');
    } catch (e) {
      debugPrint('❌ Failed to start foreground service: $e');
    }
  }

  static Future<void> openExactAlarmSettings() async {
    await NativePermissionService.requestExactAlarmPermission();
  }

  static Future<void> stopForegroundService() async {
    try {
      if (!Platform.isAndroid) return;
      await _foregroundServiceChannel.invokeMethod('stopForegroundService');
      debugPrint('🔔 Foreground service stopped');
    } catch (e) {
      debugPrint('❌ Failed to stop foreground service: $e');
    }
  }

  /// Schedule custom native exact alarm
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
      // Schedule custom native Android alarm (persisted and survives reboots & killed states)
      await _scheduleNativeAlarm(
        id: id,
        title: title,
        body: body,
        dateTime: dateTime,
        payload: json.encode(payload),
      );

      debugPrint('✅ Native alarm scheduled via Kotlin: ID $id at $dateTime');
    } catch (e) {
      debugPrint('❌ Native alarm scheduling failed: $e');
    }
  }

  /// Schedule native alarm using platform engine (Kotlin on Android, UserNotifications on iOS)
  static Future<void> _scheduleNativeAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
    String? payload,
  }) async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      await _alarmChannel.invokeMethod('scheduleNativeAlarm', {
        'id': id,
        'title': title,
        'body': body,
        'time': dateTime.millisecondsSinceEpoch,
        'payload': payload ?? '',
      });

      debugPrint('🎯 Native alarm scheduled: ID $id');
    } catch (e) {
      debugPrint('❌ Native alarm failed: $e');
      rethrow;
    }
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

  /// Check online state using native connectivity service
  static Future<bool> get isOnline => NativeConnectivityService.isOnline();
  static int get pendingNotificationsCount => 0;

  /// Cancel alarm natively
  static Future<void> cancelHybridAlarm(int id) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Cancel custom native alarm from AlarmManager / UNUserNotificationCenter
        await _alarmChannel.invokeMethod('cancelAlarm', {'id': id});
      }

      debugPrint('✅ Native alarm cancelled: ID $id');
    } catch (e) {
      debugPrint('Error cancelling native alarm: $e');
    }
  }

  /// Cancel all alarms
  static Future<void> cancelAllAlarms() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _alarmChannel.invokeMethod('cancelAllAlarms');
      }
      debugPrint('✅ All native alarms cancelled');
    } catch (e) {
      debugPrint('Error cancelling all alarms: $e');
    }
  }

  /// Get list of active native alarms from persistent storage
  static Future<List<dynamic>> getScheduledAlarms() async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return [];
      final List<dynamic>? alarms = await _alarmChannel.invokeMethod('getScheduledAlarms');
      return alarms ?? [];
    } catch (e) {
      debugPrint('Error getting scheduled alarms: $e');
      return [];
    }
  }

  /// Cancel all alarms associated with a specific task
  static Future<void> cancelAlarmsForTask(String taskId) async {
    try {
      final List<dynamic> alarms = await getScheduledAlarms();
      int cancelledCount = 0;
      
      for (final alarm in alarms) {
        if (alarm is Map) {
          final String payloadStr = alarm['payload']?.toString() ?? '';
          if (payloadStr.isNotEmpty) {
            try {
              final Map<String, dynamic> payload = json.decode(payloadStr);
              if (payload['taskId'] == taskId) {
                final int alarmId = alarm['id'] as int;
                await cancelHybridAlarm(alarmId);
                cancelledCount++;
              }
            } catch (e) {
              debugPrint('Error decoding alarm payload: $e');
            }
          }
        }
      }
      debugPrint('✅ Cancelled $cancelledCount alarms for task: $taskId');
    } catch (e) {
      debugPrint('Error cancelling alarms for task $taskId: $e');
    }
  }

  /// Cancel all alarms associated with a specific medication
  static Future<void> cancelAlarmsForMedication(String medicationId) async {
    try {
      final List<dynamic> alarms = await getScheduledAlarms();
      int cancelledCount = 0;
      
      for (final alarm in alarms) {
        if (alarm is Map) {
          final String payloadStr = alarm['payload']?.toString() ?? '';
          if (payloadStr.isNotEmpty) {
            try {
              final Map<String, dynamic> payload = json.decode(payloadStr);
              if (payload['medicationId'] == medicationId) {
                final int alarmId = alarm['id'] as int;
                await cancelHybridAlarm(alarmId);
                cancelledCount++;
              }
            } catch (e) {
              debugPrint('Error decoding alarm payload: $e');
            }
          }
        }
      }
      debugPrint('✅ Cancelled $cancelledCount alarms for medication: $medicationId');
    } catch (e) {
      debugPrint('Error cancelling alarms for medication $medicationId: $e');
    }
  }

  /// Check if the app has exact alarm permission (Android 12+)
  static Future<bool> checkExactAlarmPermission() async {
    return await NativePermissionService.isExactAlarmPermissionGranted();
  }

  /// Request exact alarm permission (Android 12+)
  static Future<void> requestExactAlarmPermission() async {
    await NativePermissionService.requestExactAlarmPermission();
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

  // Show immediate notification
  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _alarmChannel.invokeMethod('showNotification', {
          'id': id,
          'title': title,
          'body': body,
        });
      }
    } catch (e) {
      debugPrint('❌ Error showing immediate notification: $e');
    }
  }

  static void dispose() {
    _actionStreamController.close();
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
        content: Text(message, style: const TextStyle(color: Colors.red)),
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
    return await NativePermissionService.getDeviceBrandInfo();
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
          '2. Tap "Battery Settings" below.';
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
