import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
class FCMService {
  
  static Future<String?> getFCMToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      debugPrint("FCM Token: $token"); // Set breakpoint here
      return token;
    } catch (e) {
      debugPrint("Error getting token: $e");
      return null;
    }
  }

  static void configureFCM() {
    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("Foreground message: ${message.notification?.title}");
      // Set breakpoint here to inspect message
    });

    // When app is opened from terminated state
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("App opened from notification: ${message.data}");
    });
  }
}