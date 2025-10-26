import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart';

class PushNotifications {
  static final PushNotifications _instance = PushNotifications._internal();

  factory PushNotifications() => _instance;

  PushNotifications._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

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
  int _notificationId = 0;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();
      await _setupLocalNotifications();
      await _setupFirebaseMessaging();
      await _requestPermissions();

      _isInitialized = true;
      print('PushNotifications initialized successfully');
    } catch (e) {
      print('Error initializing PushNotifications: $e');
      rethrow;
    }
  }

  /// Setup local notifications
  Future<void> _setupLocalNotifications() async {
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

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onDidReceiveBackgroundNotificationResponse,
    );

    // Create notification channels
    await _createNotificationChannels();
  }

  /// Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel generalChannel =
        AndroidNotificationChannel(
          'general_channel',
          'General Notifications',
          description: 'General notifications channel',
          importance: Importance.max,
          playSound: true,
        );

    const AndroidNotificationChannel scheduledChannel =
        AndroidNotificationChannel(
          'scheduled_channel',
          'Scheduled Notifications',
          description: 'Scheduled reminders and alerts',
          importance: Importance.high,
          playSound: true,
        );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(generalChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(scheduledChannel);
  }

  /// Setup Firebase messaging handlers
  Future<void> _setupFirebaseMessaging() async {
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
    RemoteMessage? initialMessage =
        await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _onMessageOpenedAppController.add(initialMessage);
    }
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
            criticalAlert: false,
            provisional: false,
          );

      print('Notification permissions: ${settings.authorizationStatus}');
    } catch (e) {
      print('Error requesting permissions: $e');
    }
  }

  // ============ FCM TOPIC MANAGEMENT ============

  /// Subscribe to FCM topic
  Future<bool> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      print('Subscribed to topic: $topic');
      return true;
    } catch (e) {
      print('Error subscribing to topic $topic: $e');
      return false;
    }
  }

  /// Unsubscribe from FCM topic
  Future<bool> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      print('Unsubscribed from topic: $topic');
      return true;
    } catch (e) {
      print('Error unsubscribing from topic $topic: $e');
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

  /// Schedule a local notification
  Future<int> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
    String? channelId = 'scheduled_channel',
    String? channelName = 'Scheduled Notifications',
  }) async {
    try {
      final int notificationId = _generateNotificationId();

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            channelId!,
            channelName!,
            channelDescription: 'Scheduled notifications',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            timeoutAfter: 0,
          );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.zonedSchedule(
        notificationId,
        title,
        body,
        TZDateTime.from(scheduledTime, _localNotifications as Location),
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exact,
      );

      print('Scheduled notification ID: $notificationId for $scheduledTime');
      return notificationId;
    } catch (e) {
      print('Error scheduling notification: $e');
      return -1;
    }
  }

  /// Schedule a repeating local notification
  Future<int> scheduleRepeatingNotification({
    required String title,
    required String body,
    required DateTime firstDate,
    required RepeatInterval repeatInterval,
    String? payload,
    String? channelId = 'scheduled_channel',
  }) async {
    try {
      final int notificationId = _generateNotificationId();

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            channelId!,
            'Repeating Notifications',
            channelDescription: 'Repeating scheduled notifications',
            importance: Importance.high,
            priority: Priority.high,
          );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.periodicallyShow(
        notificationId,
        title,
        body,
        repeatInterval,
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      print('Scheduled repeating notification ID: $notificationId');
      return notificationId;
    } catch (e) {
      print('Error scheduling repeating notification: $e');
      return -1;
    }
  }

  /// Show immediate local notification
  Future<int> showNotification({
    required String title,
    required String body,
    String? payload,
    String? channelId = 'general_channel',
  }) async {
    try {
      final int notificationId = _generateNotificationId();

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            channelId!,
            'General Notifications',
            channelDescription: 'General notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        notificationId,
        title,
        body,
        details,
        payload: payload,
      );

      print('Shown notification ID: $notificationId');
      return notificationId;
    } catch (e) {
      print('Error showing notification: $e');
      return -1;
    }
  }

  // ============ NOTIFICATION MANAGEMENT ============

  /// Cancel a specific notification by ID
  Future<void> cancelNotification(int notificationId) async {
    try {
      await _localNotifications.cancel(notificationId);
      print('Cancelled notification ID: $notificationId');
    } catch (e) {
      print('Error cancelling notification: $e');
    }
  }

  /// Cancel multiple notifications
  Future<void> cancelNotifications(List<int> notificationIds) async {
    try {
      for (int id in notificationIds) {
        await _localNotifications.cancel(id);
      }
      print('Cancelled ${notificationIds.length} notifications');
    } catch (e) {
      print('Error cancelling notifications: $e');
    }
  }

  /// Cancel all pending notifications
  Future<void> cancelAllNotifications() async {
    try {
      await _localNotifications.cancelAll();
      print('Cancelled all notifications');
    } catch (e) {
      print('Error cancelling all notifications: $e');
    }
  }

  /// Get list of pending notification requests
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      return await _localNotifications.pendingNotificationRequests();
    } catch (e) {
      print('Error getting pending notifications: $e');
      return [];
    }
  }

  /// Check if a notification is scheduled
  Future<bool> isNotificationScheduled(int notificationId) async {
    try {
      final pending = await getPendingNotifications();
      return pending.any((notification) => notification.id == notificationId);
    } catch (e) {
      print('Error checking notification schedule: $e');
      return false;
    }
  }

  /// Update/modify a scheduled notification
  Future<bool> updateScheduledNotification({
    required int notificationId,
    String? newTitle,
    String? newBody,
    DateTime? newScheduledTime,
    String? newPayload,
  }) async {
    try {
      // First cancel the existing notification
      await cancelNotification(notificationId);

      // If new time is provided, reschedule it
      if (newScheduledTime != null) {
        await scheduleNotification(
          title: newTitle ?? 'Updated Notification',
          body: newBody ?? 'Notification content updated',
          scheduledTime: newScheduledTime,
          payload: newPayload,
        );
      } else {
        // Just show updated notification immediately
        await showNotification(
          title: newTitle ?? 'Updated Notification',
          body: newBody ?? 'Notification content updated',
          payload: newPayload,
        );
      }

      print('Updated notification ID: $notificationId');
      return true;
    } catch (e) {
      print('Error updating notification: $e');
      return false;
    }
  }

  // ============ FCM TOKEN MANAGEMENT ============

  /// Get current FCM token
  Future<String?> getFCMToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  /// Delete FCM token
  Future<bool> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      print('FCM token deleted');
      return true;
    } catch (e) {
      print('Error deleting FCM token: $e');
      return false;
    }
  }

  // ============ UTILITY METHODS ============

  /// Show local notification for FCM message
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'general_channel',
            'General Notifications',
            channelDescription: 'General notifications channel',
            importance: Importance.max,
            priority: Priority.high,
          );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        message.hashCode,
        message.notification?.title ?? 'Notification',
        message.notification?.body ?? '',
        details,
        payload: message.data.toString(),
      );
    } catch (e) {
      print('Error showing local notification: $e');
    }
  }

  /// Generate unique notification ID
  int _generateNotificationId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(100000);
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

  // ============ NOTIFICATION HANDLERS ============

  static void _onDidReceiveLocalNotification(
    int id,
    String? title,
    String? body,
    String? payload,
  ) {
    print('Received local notification: $title - $body');
  }

  static void _onDidReceiveNotificationResponse(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // You can handle notification tap actions here
    _instance._onNotificationActionController.add({
      'action': 'tap',
      'payload': response.payload,
      'id': response.id,
    });
  }

  static void _onDidReceiveBackgroundNotificationResponse(
    NotificationResponse response,
  ) {
    print('Background notification tapped: ${response.payload}');
    // Handle background notification taps
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
  print('Handling background message: ${message.messageId}');

  // You can show local notification for background messages
  final PushNotifications notifications = PushNotifications();
  await notifications._showLocalNotification(message);
}
