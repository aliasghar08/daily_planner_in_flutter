import 'dart:convert';
import 'package:daily_planner/screens/medication_detail_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/providers/medication_provider.dart';
import 'package:daily_planner/providers/task_provider.dart';
import 'package:daily_planner/providers/theme_provider.dart';
import 'package:daily_planner/providers/settings_provider.dart';
import 'package:daily_planner/providers/sync_provider.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/native_permission_service.dart';
import 'package:daily_planner/utils/push_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/screens/login.dart';
import 'package:daily_planner/screens/changePass.dart';
import 'package:daily_planner/screens/forgotPass.dart';
import 'package:daily_planner/services/custom_state_management.dart';
import 'package:daily_planner/utils/app_theme.dart';
import 'package:daily_planner/utils/reset_task.dart';
import 'package:daily_planner/widgets/app_lock_wrapper.dart';
import 'firebase_options.dart';

// Global navigator key for notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ✅ Tracks whether all initialization has finished
final ValueNotifier<bool> _appReady = ValueNotifier<bool>(false);

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");

  if (message.notification != null) {
    await NativeAlarmHelper.showNow(
      id: message.hashCode.abs() % 100000,
      title: message.notification!.title ?? 'Daily Planner',
      body: message.notification!.body ?? 'New notification',
    );
  }
}

Future<void> showNotification({
  required String title,
  required String body,
}) async {
  await NativeAlarmHelper.showNow(
    id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title: title,
    body: body,
  );
}

Future<void> _showNotification({
  required String title,
  required String body,
}) async {
  await NativeAlarmHelper.showNow(
    id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title: title,
    body: body,
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

// ✅ THE FIX: runApp is called FIRST, then heavy init runs in background
Future<void> main() async {
  // 1. Minimum required to boot the engine
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Draw the first frame IMMEDIATELY — satisfies the iOS watchdog
  runApp(const MyApp());

  // 3. Everything else runs AFTER the first frame
  _runStartupTasks();
}

// All slow work runs here, AFTER the UI is on screen
Future<void> _runStartupTasks() async {
  try {
    // Firebase
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }

      debugPrint("✅ Firebase initialized with offline persistence");
    } catch (e) {
      debugPrint("❌ Firebase initialization error: $e");
    }

    // Notification service
    await _initializeNotificationService();

    // FCM + platform services
    await _initializeFCM();
    await _initializePlatformServices();

    // Background task
    resetAllTasksIfNeeded();

    debugPrint('✅ All startup tasks completed');
  } catch (e) {
    debugPrint('❌ Startup task error: $e');
  } finally {
    // Signal to the UI that it's safe to show the real app
    _appReady.value = true;
  }
}

Future<void> testNotificationSystem() async {
  final notifications = PushNotifications();
  await notifications.initialize();

  final testTime = DateTime.now().add(const Duration(minutes: 1));
  final testId = DateTime.now().millisecondsSinceEpoch;

  final success = await notifications.scheduleNotification(
    id: testId,
    title: 'Test Notification',
    body: 'This is a test scheduled notification',
    scheduledTime: testTime,
  );

  debugPrint('Test notification scheduled: $success');
  await notifications.debugPrintScheduledNotifications();
}

Future<void> _initializeFCM() async {
  try {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    debugPrint('FCM Permission status: ${settings.authorizationStatus}');

    try {
      final String? token = await messaging.getToken();
      debugPrint('FCM Token: $token');

      if (FirebaseAuth.instance.currentUser != null) {
        await _saveFCMTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint("Error uploading FCM token $e");
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        _showNotification(
          title: message.notification!.title ?? 'Daily Planner',
          body: message.notification!.body ?? 'New notification',
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('App opened via notification');
      debugPrint('Message data: ${message.data}');
      navigatorKey.currentState?.pushNamed('/home');
    });

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

Future<void> _initializePlatformServices() async {
  try {
    await NativePermissionService.requestAllCorePermissions();

    NativeAlarmHelper.listenToActions((actionData) {
      debugPrint('Notification action received: $actionData');
      final action = actionData['action'];
      if (action == 'tap') {
        final payloadStr = actionData['payload']?.toString();
        if (payloadStr != null && payloadStr.isNotEmpty) {
          try {
            final payload = jsonDecode(payloadStr);
            if (payload['type'] == 'medication') {
              final medicationId = payload['medicationId'];
              final context = navigatorKey.currentContext;
              if (context != null) {
                final medProvider = Provider.of<MedicationProvider>(context, listen: false);
                try {
                  final med = medProvider.medications.firstWhere((m) => m.medicationId == medicationId);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MedicationDetailPage(medication: med),
                  ));
                  return;
                } catch (e) {
                  debugPrint('Medication not found for tap action: $medicationId');
                }
              }
            }
          } catch (e) {
            debugPrint('Failed to parse payload: $e');
          }
        }
        navigatorKey.currentState?.pushNamed('/home');
      }
    });

    debugPrint('✅ Platform services initialized successfully');
  } catch (e) {
    debugPrint('❌ Error initializing platform services: $e');
  }
}

// ✅ MyApp shows a splash screen until _appReady becomes true
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _appReady,
      builder: (context, ready, _) {
        if (!ready) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return const _MyAppBody();
      },
    );
  }
}

// The actual app UI — only built after init is done
class _MyAppBody extends StatelessWidget {
  const _MyAppBody();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => MedicationProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
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
            builder: (context, child) {
              return AppLockWrapper(child: child!);
            },
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

// ✅ AuthWrapper unchanged
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<app_auth.AuthProvider>();

    if (authProvider.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking session...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (authProvider.error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                const Text(
                  'Authentication Error',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  authProvider.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
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

    return authProvider.isLoggedIn ? const MyHome() : const LoginPage();
  }
}