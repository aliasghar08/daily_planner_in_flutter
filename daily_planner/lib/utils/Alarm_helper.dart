import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';

class NativeAlarmHelper {
  static const MethodChannel _channel = MethodChannel('exact_alarm_permission');
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    if (!kIsWeb && Platform.isAndroid) {
      await Firebase.initializeApp();
      
      // Request notification permissions
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);
    }
  }

  // Background message handler
  @pragma('vm:entry-point')
  static Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    if (message.notification != null) {
      // You can add local notification display here if needed
      print('Received background notification: ${message.notification?.title}');
    }
  }

  static Future<void> schedulePermissionDummyAlarm() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('scheduleAlarm', {
          "id": 777,
          "title": "Permission Activation Alarm",
          "body": "This is required for Alarms & Reminders permission",
          "time": DateTime.now().millisecondsSinceEpoch + 30 * 1000, // 30 sec later
        });
        
        // Also schedule via FCM as fallback
        await _scheduleFcmNotification(
          id: 777,
          title: "Permission Activation Alarm",
          body: "This is required for Alarms & Reminders permission",
          triggerTime: DateTime.now().add(Duration(seconds: 30)),
        );
      } catch (e) {
        print("Failed to schedule native alarm: $e");
      }
    }
  }

  static Future<void> requestExactAlarmPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('requestExactAlarmPermission');
      } catch (e) {
        print("Failed to request exact alarm permission: $e");
      }
    }
  }

  /// Schedule an alarm for a specific time with custom title/body
  static Future<void> scheduleAlarmAtTime({
    required int id,
    required DateTime time,
    required String title,
    required String body,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        // Schedule native alarm first
        await _channel.invokeMethod('scheduleAlarm', {
          "id": id,
          "title": title,
          "body": body,
          "time": time.millisecondsSinceEpoch,
        });

        // Schedule FCM notification as fallback
        await _scheduleFcmNotification(
          id: id,
          title: title,
          body: body,
          triggerTime: time,
        );
      } catch (e) {
        print("Failed to schedule alarm at specific time: $e");
      }
    }
  }

  static Future<void> _scheduleFcmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime triggerTime,
  }) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        print("FCM token is null. Cannot schedule notification.");
        return;
      }

      final callable = FirebaseFunctions.instance.httpsCallable('scheduleFcmNotification');
      final result = await callable.call({
        'token': token,
        'title': title,
        'body': body,
        'triggerTime': triggerTime.toUtc().toIso8601String(),
        'payload': {
          'id': id.toString(),
        }
      });

      if (result.data['success'] == true) {
        print('✅ FCM notification scheduled successfully: ID = ${result.data['notificationId']}');
      } else {
        print('⚠️ Failed to schedule FCM notification. Result: ${result.data}');
      }
    } catch (e) {
      print('❌ Error calling Cloud Function to schedule FCM notification: $e');
    }
  }

  static Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } on PlatformException catch (e) {
      print("Failed to start foreground service: '${e.message}'.");
    }
  }

  static Future<bool> checkExactAlarmPermission() async {
    try {
      final bool granted = await _channel.invokeMethod('checkExactAlarmPermission');
      return granted;
    } catch (e) {
      debugPrint("checkExactAlarmPermission error: $e");
      return false;
    }
  }

  /// Cancel a scheduled alarm/notification by ID
  static Future<void> cancelAlarmById(int id) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancelAlarm', {"id": id});
        print("✅ Alarm with ID $id cancelled successfully.");
      } catch (e) {
        print("❌ Failed to cancel alarm with ID $id: $e");
      }
    }
  }
}