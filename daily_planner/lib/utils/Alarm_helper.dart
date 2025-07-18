// import 'dart:io';
// import 'package:flutter/foundation.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:flutter_timezone/flutter_timezone.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:timezone/data/latest_all.dart' as tz;
// import 'package:timezone/timezone.dart' as tz;

// /// Standalone helper for local notifications
// class NativeAlarmHelper {
//   static final _flnp = FlutterLocalNotificationsPlugin();

//   /// MUST call once during app startup
//   static Future<void> initialize() async {
//     // Android settings
//     const androidSettings = AndroidInitializationSettings(
//       '@mipmap/ic_launcher',
//     );
//     // iOS settings
//     final iosSettings = DarwinInitializationSettings(
//       requestAlertPermission: true,
//       requestBadgePermission: true,
//       requestSoundPermission: true,
//     );

//     final initSettings = InitializationSettings(
//       android: androidSettings,
//       iOS: iosSettings,
//     );
//     await _flnp.initialize(initSettings);

//     // Timezone setup
//     tz.initializeTimeZones();
//     final name = await FlutterTimezone.getLocalTimezone();
//     tz.setLocalLocation(tz.getLocation(name));
//   }

//   /// Show a notification immediately
//   static Future<void> showNow({
//     required int id,
//     required String title,
//     required String body,
//   }) async {
//     const androidDetails = AndroidNotificationDetails(
//       'daily_planner_channel',
//       'Daily Planner',
//       channelDescription: 'Task reminders and alerts',
//       importance: Importance.high,
//       priority: Priority.high,
//     );
//     const iosDetails = DarwinNotificationDetails();

//     await _flnp.show(
//       id,
//       title,
//       body,
//       NotificationDetails(android: androidDetails, iOS: iosDetails),
//     );
//   }

//   /// Schedule a notification at a specific time
//   static Future<void> scheduleAlarmAtTime({
//     required int id,
//     required String title,
//     required String body,
//     required DateTime dateTime,
//   }) async {
//     final tzScheduled = tz.TZDateTime.from(dateTime, tz.local);
//     const androidDetails = AndroidNotificationDetails(
//       'daily_planner_channel',
//       'Daily Planner',
//       channelDescription: 'Task reminders and alerts',
//       importance: Importance.high,
//       priority: Priority.high,
//     );
//     const iosDetails = DarwinNotificationDetails();

//     await _flnp.zonedSchedule(
//       id,
//       title,
//       body,
//       tzScheduled,
//       NotificationDetails(android: androidDetails, iOS: iosDetails),
//       androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
//     );
//   }

//   /// Cancel a scheduled notification
//   static Future<void> cancelAlarmById(int id) async {
//     await _flnp.cancel(id);
//   }

//   static Future<void> startForegroundService() async {}

//   static Future<bool> checkExactAlarmPermission() async {
//     if (kIsWeb) {
//       return false;
//     }
//     if (Platform.isAndroid) {
//       final status = Permission.notification.status;
//       return status.isGranted;
//     }
//     return false;
//   }

//   static Future<void> requestExactAlarmPermission() async {
//     if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
//       if (await Permission.notification.request().isGranted) {
//         // Optional: show a sample notification to verify
//         await showNow(
//           id: -1,
//           title: 'Reminder Active',
//           body: 'Exact alarms enabled',
//         );
//       }
//     }
//   }

//   static Future<void> schedulePermissionDummyAlarm() async {}
// }

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Standalone helper for local notifications and native AlarmManager
class NativeAlarmHelper {
  static const MethodChannel _channel = MethodChannel('exact_alarm_permission');
  static final _flnp = FlutterLocalNotificationsPlugin();

  /// MUST call once during app startup
  static Future<void> initialize() async {
    // FlutterLocalNotifications setup
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
    );

    // Timezone setup
    tz.initializeTimeZones();
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
  }

  /// Show a notification immediately
  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'daily_planner_channel',
      'Daily Planner',
      channelDescription: 'Task reminders and alerts',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 1000, 500, 1000]),
      ongoing: true,
      autoCancel: false,
      sound: null, // place alarm_sound.mp3 in android/app/src/main/res/raw/
      additionalFlags: Int32List.fromList(<int>[
        4,
      ]), // FLAG_INSISTENT: repeats sound until user acts
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('STOP_ACTION', 'Stop'),
        AndroidNotificationAction('SNOOZE_ACTION', 'Snooze'),
      ],
    );
    const iosDetails = DarwinNotificationDetails();

    await _flnp.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// Schedule a notification at a specific time
  static Future<void> scheduleAlarmAtTime({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
  }) async {
    // Schedule native AlarmManager
    await _channel.invokeMethod('scheduleNativeAlarm', {
      'id': id,
      'title': title,
      'body': body,
      'time': dateTime.millisecondsSinceEpoch,
    });

    // Schedule fallback local notification
    final tzScheduled = tz.TZDateTime.from(dateTime, tz.local);
    const androidDetails = AndroidNotificationDetails(
      'daily_planner_channel',
      'Daily Planner',
      channelDescription: 'Task reminders and alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    await _flnp.zonedSchedule(
      id,
      title,
      body,
      tzScheduled,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Cancel both local and native alarms
  static Future<void> cancelAlarmById(int id) async {
    await _flnp.cancel(id);
    await _channel.invokeMethod('cancelAlarm', {'id': id});
  }

  /// Check notification permission on Android
  static Future<bool> checkExactAlarmPermission() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      return await Permission.notification.status.isGranted;
    }
    return true;
  }

  /// Request notification permission on Android
  static Future<void> requestExactAlarmPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      if (await Permission.notification.request().isGranted) {
        await showNow(
          id: -1,
          title: 'Reminder Active',
          body: 'Notifications enabled',
        );
      }
    }
  }

  /// Schedule a dummy alarm (to trigger permission prompt via exact alarm call)
  static Future<void> schedulePermissionDummyAlarm() async {
    final now = DateTime.now();
    await scheduleAlarmAtTime(
      id: 777,
      title: 'Permission Alarm',
      body: 'Checking alarm capability',
      dateTime: now.add(const Duration(seconds: 30)),
    );
  }
}
