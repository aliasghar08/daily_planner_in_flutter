import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/providers/medication_provider.dart';
import 'package:daily_planner/providers/task_provider.dart';
import 'package:daily_planner/providers/theme_provider.dart';
import 'package:daily_planner/providers/settings_provider.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/push_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:daily_planner/utils/reset_task.dart';
import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/screens/login.dart';
import 'package:daily_planner/screens/changePass.dart';
import 'package:daily_planner/screens/forgotPass.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:provider/provider.dart';
import 'package:daily_planner/utils/app_theme.dart';
import 'firebase_options.dart';

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// Global navigator key for notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");

  // Show notification when app is in background/terminated
  if (message.notification != null) {
    await _showNotification(
      title: message.notification!.title ?? 'Daily Planner',
      body: message.notification!.body ?? 'New notification',
    );
  }
}

Future<void> showNotification({
  required String title,
  required String body,
}) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'alarm_channel', // channel id
    'Alarm Notifications', // channel name
    channelDescription: 'This channel is for alarm notifications',
    importance: Importance.max,
    priority: Priority.max,
    ticker: 'ticker',
    playSound: true,
    category: AndroidNotificationCategory.alarm,
  );

  const NotificationDetails platformDetails = NotificationDetails(
    android: androidDetails,
  );

  await flutterLocalNotificationsPlugin.show(0, title, body, platformDetails);
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
    await NativeAlarmHelper.initialize();
    debugPrint('✅ NotificationService initialized successfully');
  } catch (e) {
    debugPrint('❌ Error initializing NotificationService: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

    // ✅ CRITICAL: Set persistence to LOCAL to remember login
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);

    debugPrint("✅ Firebase initialized with offline persistence");
  } catch (e) {
    debugPrint("❌ Firebase initialization error: $e");
    // Continue anyway - we'll use offline capabilities
  }

  // Initialize timezone FIRST
  tz.initializeTimeZones();

  // Initialize NotificationService BEFORE running app
  await _initializeNotificationService();

  // Call runApp AFTER all critical initializations
  runApp(const MyApp());

  // Initialize FCM and other services
  await _initializeFCM();
  await _initializeAndroidServices();

  // Perform async initializations in background
  resetAllTasksIfNeeded();
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

  debugPrint('Test notification scheduled: $success');

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => MedicationProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: "Daily Planner",
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            navigatorKey: navigatorKey,
            home: const AuthWrapper(),
            routes: {
              "/home": (_) => const MyHome(),
              "/login": (_) => const LoginPage(),
              "/changepassword": (_) => const ChangePasswordPage(),
              "/forgotpass": (_) => const ForgotPasswordScreen(),
            },
          );
        },
      ),
    );
  }
}

// ✅ AuthWrapper now consumes AuthProvider — no local state needed
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<app_auth.AuthProvider>();

    // Show loading spinner while checking auth
    if (authProvider.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Checking session...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Show error if any
    if (authProvider.error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'Authentication Error',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  authProvider.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => authProvider.retry(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Navigate based on auth state
    return authProvider.isLoggedIn ? const MyHome() : const LoginPage();
  }
}