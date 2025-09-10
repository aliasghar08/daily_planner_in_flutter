import 'dart:io' show Platform, exit;
import 'package:daily_planner/utils/battery_optimization_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/reset_task.dart';
import 'package:daily_planner/utils/thememode.dart';
import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/screens/login.dart';
import 'package:daily_planner/screens/changePass.dart';
import 'package:daily_planner/screens/forgotPass.dart';
import 'package:timezone/timezone.dart' as tz;
import 'firebase_options.dart';

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase & timezone
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  tz.initializeTimeZones();
  await NativeAlarmHelper.initialize();

  // Call runApp immediately to avoid splash hang
  runApp(const MyApp());

  // Perform async initializations in background
  if (!kIsWeb && Platform.isAndroid) {
    _initializeAndroidServices();
    BatteryOptimizationHelper.promptDisableBatteryOptimization();
  }
}

Future<void> _initializeAndroidServices() async {
  await Permission.notification.request();

  final hasExact = await NativeAlarmHelper.checkExactAlarmPermission();
  if (!hasExact) {
    await NativeAlarmHelper.requestExactAlarmPermission();
    await Future.delayed(const Duration(milliseconds: 500));
  }
  if (await NativeAlarmHelper.checkExactAlarmPermission()) {
    await NativeAlarmHelper.schedulePermissionDummyAlarm();
  }

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
      if (response.actionId == 'STOP_ACTION') {
        flutterLocalNotificationsPlugin.cancel(response.id!);
      } else if (response.actionId == 'SNOOZE_ACTION') {
        flutterLocalNotificationsPlugin.cancel(response.id!);
        flutterLocalNotificationsPlugin.zonedSchedule(
          response.id!,
          'Snoozed Reminder',
          'Reminder after snooze!',
          tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5)),
          const NotificationDetails(),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    },
  );
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
      await resetAllTasksIfNeeded();
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
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
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
