import 'dart:io' show Platform;
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/battery_optimization_helper.dart';
import 'package:daily_planner/utils/push_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:daily_planner/utils/reset_task.dart';
import 'package:daily_planner/utils/thememode.dart';
import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/screens/login.dart';
import 'package:daily_planner/screens/changePass.dart';
import 'package:daily_planner/screens/forgotPass.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// Global navigator key for notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");

  // Show notification when app is in background/terminated
  if (message.notification != null) {
    await _showNotification(
      title: message.notification!.title ?? 'Daily Planner',
      body: message.notification!.body ?? 'New notification',
    );
  }
}

// Show notification helper
Future<void> _showNotification({
  required String title,
  required String body,
}) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'daily_planner_channel',
        'Daily Planner Notifications',
        channelDescription: 'Channel for task reminders and notifications',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );

  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    platformChannelSpecifics,
  );
}

Future<void> _initializeNotificationService() async {
  try {
    //await NotificationService().initialize();
    await NativeAlarmHelper.initialize();
    debugPrint('✅ NotificationService initialized successfully');
  } catch (e) {
    debugPrint('❌ Error initializing NotificationService: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ FIXED: Initialize Android Alarm Manager Plus FIRST
  // await AndroidAlarmManager.initialize();

  // Initialize Firebase with offline persistence
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Enable Firestore offline persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
    // Continue anyway - we'll use offline capabilities
  }

  // ✅ FIXED: Initialize timezone FIRST
  tz.initializeTimeZones();

  // ✅ FIXED: Initialize NotificationService BEFORE running app
  await _initializeNotificationService();

  await AndroidAlarmManager.initialize();

  // ✅ FIXED: Call runApp AFTER all critical initializations
  runApp(const MyApp());

  // ✅ FIXED: Initialize FCM and other services
  await _initializeFCM();
  await _initializeAndroidServices();

  // ✅ FIXED: Remove test calls that might interfere
  // await testNotificationSystem(); // Remove this line - test separately

  // Perform async initializations in background
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await BatteryOptimizationHelper.promptDisableBatteryOptimization();
    } catch (e) {
      print("Battery optimization prompt not available $e");
    }
  }
}

// Test method - call this somewhere in your app
Future<void> testNotificationSystem() async {
  final notifications = PushNotifications();
  await notifications.initialize();

  // Schedule a test notification 1 minute from now
  final testTime = DateTime.now().add(Duration(minutes: 1));
  final testId = DateTime.now().millisecondsSinceEpoch;

  final success = await notifications.scheduleNotification(
    id: testId,
    title: 'Test Notification',
    body: 'This is a test scheduled notification',
    scheduledTime: testTime,
  );

  print('Test notification scheduled: $success');

  // Print all scheduled notifications
  await notifications.debugPrintScheduledNotifications();
}

Future<void> _initializeFCM() async {
  try {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request notification permissions
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    debugPrint('FCM Permission status: ${settings.authorizationStatus}');

    // Get FCM token
    try {
      String? token = await messaging.getToken();
      debugPrint('FCM Token: $token');

      // Save token to user's document in Firestore
      if (FirebaseAuth.instance.currentUser != null) {
        await _saveFCMTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint("Error uploading FCM token $e");
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint(
          'Message also contained a notification: ${message.notification}',
        );

        // Show notification when app is in foreground
        _showNotification(
          title: message.notification!.title ?? 'Daily Planner',
          body: message.notification!.body ?? 'New notification',
        );
      }
    });

    // Handle when app is opened from terminated state via notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('App opened via notification');
      debugPrint('Message data: ${message.data}');

      // Navigate to specific screen based on message data if needed
      navigatorKey.currentState?.pushNamed('/home');
    });

    // Handle token refresh
    messaging.onTokenRefresh.listen((String newToken) {
      debugPrint('FCM token refreshed: $newToken');
      _saveFCMTokenToFirestore(newToken);
    });
  } catch (e) {
    debugPrint('FCM initialization error: $e');
  }
}

Future<void> _saveFCMTokenToFirestore(String? token) async {
  if (token == null) return;

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Use array to store multiple tokens for multiple devices
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('FCM token saved to Firestore for user: ${user.uid}');
    }
  } catch (e) {
    debugPrint('Error saving FCM token to Firestore: $e');
  }
}

Future<void> _removeFCMTokenFromFirestore(String? token) async {
  if (token == null) return;

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {
          'fcmTokens': FieldValue.arrayRemove([token]),
        },
      );
    }
  } catch (e) {
    debugPrint('Error removing FCM token from Firestore: $e');
  }
}

Future<void> _initializeAndroidServices() async {
  try {
    await Permission.notification.request();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final initializationSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification tapped: ${response.payload}');

        // Handle notification tap
        if (response.actionId == 'STOP_ACTION') {
          flutterLocalNotificationsPlugin.cancel(response.id!);
        } else if (response.actionId == 'SNOOZE_ACTION') {
          flutterLocalNotificationsPlugin.cancel(response.id!);
          flutterLocalNotificationsPlugin.zonedSchedule(
            response.id!,
            'Snoozed Reminder',
            'Reminder after snooze!',
            tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5)),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'daily_planner_channel',
                'Daily Planner Notifications',
                channelDescription:
                    'Channel for task reminders and notifications',
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        } else {
          // Regular notification tap - navigate to home
          navigatorKey.currentState?.pushNamed('/home');
        }
      },
    );

    debugPrint('✅ Android services initialized successfully');
  } catch (e) {
    debugPrint('❌ Error initializing Android services: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _asyncInit();
  }

  Future<void> _asyncInit() async {
    // Firestore reset & theme loading
    try {
      // Make resetAllTasksIfNeeded non-blocking
      resetAllTasksIfNeeded().catchError((e) {
        debugPrint("resetAllTasksIfNeeded failed: $e");
      });

      await ThemePreferences.loadTheme();
    } catch (e) {
      debugPrint("Initialization failed inside MyApp: $e");
    } finally {
      if (mounted) setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      // Show spinner while async init is happening
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          title: "Daily Planner",
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          navigatorKey: navigatorKey, // Add navigator key for notifications
          home: const AuthWrapper(),
          routes: {
            "/home": (_) => const MyHome(),
            "/login": (_) => const LoginPage(),
            "/changepassword": (_) => const ChangePasswordPage(),
            "/forgotpass": (_) => const ForgotPasswordScreen(),
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  User? user;
  bool _isCheckingAuth = true;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    try {
      // First try to get current user from cache (works offline)
      user = FirebaseAuth.instance.currentUser;

      // Listen for auth changes (will update when online)
      FirebaseAuth.instance.authStateChanges().listen((User? newUser) {
        if (mounted) {
          setState(() {
            user = newUser;
            _isCheckingAuth = false;
          });
        }
      });

      // Set a timeout to prevent hanging
      await Future.delayed(const Duration(seconds: 3));
    } catch (e) {
      debugPrint("Auth check error: $e");
    } finally {
      if (mounted && _isCheckingAuth) {
        setState(() => _isCheckingAuth = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAuth) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return user != null ? const MyHome() : const LoginPage();
  }
}
