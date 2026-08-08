import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'Alarm_helper.dart';
import 'native_permission_service.dart';

/// PushNotifications service layer
/// Uses Firebase Messaging for cloud messages and custom NativeAlarmHelper
/// for all local/exact alarm and scheduled notification handling.
class PushNotifications {
  static final PushNotifications _instance = PushNotifications._internal();

  factory PushNotifications() => _instance;

  PushNotifications._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // Stream controllers for notification events
  final StreamController<RemoteMessage> _onMessageController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> _onMessageOpenedAppController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<String> _onTokenRefreshController =
      StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _onNotificationActionController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters for streams
  Stream<RemoteMessage> get onMessage => _onMessageController.stream;
  Stream<RemoteMessage> get onMessageOpenedApp =>
      _onMessageOpenedAppController.stream;
  Stream<String> get onTokenRefresh => _onTokenRefreshController.stream;
  Stream<Map<String, dynamic>> get onNotificationAction =>
      _onNotificationActionController.stream;

  bool _isInitialized = false;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();
      await NativeAlarmHelper.initialize();
      await _setupFirebaseMessaging();
      await _requestPermissions();

      _isInitialized = true;
      debugPrint('✅ PushNotifications initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing PushNotifications: $e');
      rethrow;
    }
  }

  /// Setup Firebase messaging handlers
  Future<void> _setupFirebaseMessaging() async {
    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _onMessageController.add(message);
      _showLocalNotification(message);
    });

    // Background/terminated messages when app is opened
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _onMessageOpenedAppController.add(message);
    });

    // Token refresh
    _firebaseMessaging.onTokenRefresh.listen((String newToken) {
      _onTokenRefreshController.add(newToken);
    });

    // Get initial message if app was terminated
    final RemoteMessage? initialMessage =
        await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _onMessageOpenedAppController.add(initialMessage);
    }
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      await NativePermissionService.requestNotificationPermission();
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: false,
        provisional: false,
      );
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
    }
  }

  // ============ FCM TOPIC MANAGEMENT ============

  /// Subscribe to FCM topic
  Future<bool> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      debugPrint('Subscribed to topic: $topic');
      return true;
    } catch (e) {
      debugPrint('Error subscribing to topic $topic: $e');
      return false;
    }
  }

  /// Unsubscribe from FCM topic
  Future<bool> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from topic: $topic');
      return true;
    } catch (e) {
      debugPrint('Error unsubscribing from topic $topic: $e');
      return false;
    }
  }

  /// Subscribe to multiple topics
  Future<void> subscribeToTopics(List<String> topics) async {
    for (String topic in topics) {
      await subscribeToTopic(topic);
    }
  }

  /// Unsubscribe from multiple topics
  Future<void> unsubscribeFromTopics(List<String> topics) async {
    for (String topic in topics) {
      await unsubscribeFromTopic(topic);
    }
  }

  // ============ LOCAL NOTIFICATION SCHEDULING ============

  /// Schedule a notification using custom native alarm engine
  Future<bool> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
    String? channelId,
  }) async {
    try {
      if (id <= 0) {
        debugPrint('Error: Notification ID must be positive, got: $id');
        return false;
      }

      await NativeAlarmHelper.scheduleHybridAlarm(
        id: id,
        title: title,
        body: body,
        dateTime: scheduledTime,
        payload: {'payload': payload ?? '', 'id': id},
      );

      debugPrint('✅ Scheduled notification with ID: $id for $scheduledTime');
      return true;
    } catch (e) {
      debugPrint('❌ Error scheduling notification with ID $id: $e');
      return false;
    }
  }

  /// Schedule a repeating notification with specific ID
  Future<bool> scheduleRepeatingNotification({
    required int id,
    required String title,
    required String body,
    required DateTime firstDate,
    String? payload,
    String? channelId,
  }) async {
    try {
      if (id <= 0) {
        debugPrint('Error: Notification ID must be positive, got: $id');
        return false;
      }

      await NativeAlarmHelper.scheduleHybridAlarm(
        id: id,
        title: title,
        body: body,
        dateTime: firstDate,
        payload: {'payload': payload ?? '', 'id': id, 'repeating': true},
      );

      debugPrint('Scheduled repeating notification with ID: $id');
      return true;
    } catch (e) {
      debugPrint('Error scheduling repeating notification with ID $id: $e');
      return false;
    }
  }

  /// Debug method to print all pending notifications
  Future<void> debugPrintScheduledNotifications() async {
    try {
      final pending = await NativeAlarmHelper.getScheduledAlarms();
      debugPrint('=== SCHEDULED NOTIFICATIONS (${pending.length}) ===');
      for (final notification in pending) {
        debugPrint('Alarm: $notification');
      }
    } catch (e) {
      debugPrint('Error debugging notifications: $e');
    }
  }

  /// Show immediate local notification with specific ID
  Future<bool> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? channelId,
  }) async {
    try {
      if (id <= 0) {
        debugPrint('Error: Notification ID must be positive, got: $id');
        return false;
      }

      await NativeAlarmHelper.showNow(
        id: id,
        title: title,
        body: body,
      );

      debugPrint('Shown notification with ID: $id');
      return true;
    } catch (e) {
      debugPrint('Error showing notification with ID $id: $e');
      return false;
    }
  }

  // ============ NOTIFICATION MANAGEMENT ============

  /// Cancel a specific notification by ID
  Future<void> cancelNotification(int notificationId) async {
    try {
      await NativeAlarmHelper.cancelHybridAlarm(notificationId);
      debugPrint('Cancelled notification ID: $notificationId');
    } catch (e) {
      debugPrint('Error cancelling notification ID $notificationId: $e');
    }
  }

  /// Cancel multiple notifications
  Future<void> cancelNotifications(List<int> notificationIds) async {
    for (int id in notificationIds) {
      await cancelNotification(id);
    }
  }

  /// Cancel all pending notifications
  Future<void> cancelAllNotifications() async {
    try {
      await NativeAlarmHelper.cancelAllAlarms();
      debugPrint('Cancelled all notifications');
    } catch (e) {
      debugPrint('Error cancelling all notifications: $e');
    }
  }

  /// Get list of pending notification requests
  Future<List<dynamic>> getPendingNotifications() async {
    return await NativeAlarmHelper.getScheduledAlarms();
  }

  /// Check if a notification is scheduled
  Future<bool> isNotificationScheduled(int notificationId) async {
    try {
      final pending = await getPendingNotifications();
      return pending.any((notification) {
        if (notification is Map) {
          return notification['id'] == notificationId;
        }
        return false;
      });
    } catch (e) {
      debugPrint('Error checking notification schedule for ID $notificationId: $e');
      return false;
    }
  }

  // ============ FCM TOKEN MANAGEMENT ============

  /// Get current FCM token
  Future<String?> getFCMToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Delete FCM token
  Future<bool> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      debugPrint('FCM token deleted');
      return true;
    } catch (e) {
      debugPrint('Error deleting FCM token: $e');
      return false;
    }
  }

  // ============ UTILITY METHODS ============

  /// Show local notification for FCM message
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final int notificationId = message.hashCode.abs() % 100000;
      await NativeAlarmHelper.showNow(
        id: notificationId,
        title: message.notification?.title ?? 'Daily Planner',
        body: message.notification?.body ?? 'New notification',
      );
    } catch (e) {
      debugPrint('Error showing local notification: $e');
    }
  }

  /// Set foreground notification presentation options
  Future<void> setForegroundNotificationPresentationOptions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
  }) async {
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: alert,
      badge: badge,
      sound: sound,
    );
  }

  /// Get notification settings
  Future<NotificationSettings> getNotificationSettings() async {
    return await _firebaseMessaging.getNotificationSettings();
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Dispose all streams
  void dispose() {
    _onMessageController.close();
    _onMessageOpenedAppController.close();
    _onTokenRefreshController.close();
    _onNotificationActionController.close();
  }
}

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Handling background message: ${message.messageId}');

  if (message.notification != null) {
    await NativeAlarmHelper.showNow(
      id: message.hashCode.abs() % 100000,
      title: message.notification!.title ?? 'Daily Planner',
      body: message.notification!.body ?? 'New notification',
    );
  }
}