import 'dart:io' show Platform;
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/reset_task.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daily_planner/screens/changePass.dart';
import 'package:daily_planner/screens/forgotPass.dart';
import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/screens/login.dart';
import 'package:daily_planner/utils/thememode.dart';
import 'firebase_options.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize critical services first with error handling
  try {
    await _initializeCoreServices();
    runApp(const MyApp());
  } catch (e, stack) {
    debugPrint('Initialization failed: $e\n$stack');
    runApp(const InitializationErrorApp());
  }
}

Future<void> _initializeCoreServices() async {
  // 1. Firebase initialization
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Timezone initialization
  tz.initializeTimeZones();

  // 3. Android-specific services
  if (!kIsWeb && Platform.isAndroid) {
    await _initializeAndroidServices();
  }

  // 4. App-specific initializations
  await resetAllTasksIfNeeded();
  await ThemePreferences.loadTheme();
}

Future<void> _initializeAndroidServices() async {
  try {
    // Request notification permission with retry logic
    await _requestNotificationPermissionWithRetry();

    // Handle exact alarm permission
    await _handleAlarmPermissions();

    // Initialize notification services
    await NativeAlarmHelper.initialize();
  } catch (e) {
    debugPrint('Android services initialization error: $e');
    rethrow;
  }
}

// Future<void> _requestNotificationPermissionWithRetry() async {
//   const maxRetries = 2;
//   for (var i = 0; i < maxRetries; i++) {
//     try {
//       await NativeAlarmHelper.requestExactAlarmPermission();
//       if (await Permission.notification.isGranted) break;
//       await Future.delayed(const Duration(seconds: 1));
//     } catch (e) {
//       if (i == maxRetries - 1) rethrow;
//     }
//   }
// }

Future<void> _requestNotificationPermissionWithRetry() async {
  if (await Permission.notification.isGranted) return;

  const maxRetries = 2;
  for (var i = 0; i < maxRetries; i++) {
    try {
      final status = await Permission.notification.request();
      if (status.isGranted) break;
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      if (i == maxRetries - 1) rethrow;
    }
  }
}


Future<void> _handleAlarmPermissions() async {
  final hasPermission = await NativeAlarmHelper.checkExactAlarmPermission();

  if (!hasPermission) {
    await NativeAlarmHelper.requestExactAlarmPermission();
    // Optionally wait a moment for the user to respond to the dialog
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // Only schedule dummy alarm if permission is now granted
  if (await NativeAlarmHelper.checkExactAlarmPermission()) {
    await NativeAlarmHelper.schedulePermissionDummyAlarm();
  }
}


class InitializationErrorApp extends StatelessWidget {
  const InitializationErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('App initialization failed'),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: () {}, child: const Text('Exit')),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _handleBatteryOptimization();
  }

  Future<void> _handleBatteryOptimization() async {
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _requestIgnoreBatteryOptimization();
      });
    }
  }

  Future<void> _requestIgnoreBatteryOptimization() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('Battery optimization error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: "Daily Planner",
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: currentMode,
          home: const AuthWrapper(),
          routes: {
            "/home": (context) => const MyHome(),
            "/login": (context) => const LoginPage(),
            "/changepassword": (context) => const ChangePasswordPage(),
            "/forgotpass": (context) => const ForgotPasswordScreen(),
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return snapshot.hasData ? const MyHome() : const LoginPage();
      },
    );
  }
}
