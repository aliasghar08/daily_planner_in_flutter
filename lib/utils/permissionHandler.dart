import 'package:flutter/foundation.dart';
import 'native_permission_service.dart';

Future<void> requestPermission() async {
  if (kIsWeb) {
    debugPrint("🌐 Web platform: no notification permission required.");
    return;
  }
  
  final isGranted = await NativePermissionService.isNotificationPermissionGranted();
  if (!isGranted) {
    final result = await NativePermissionService.requestNotificationPermission();
    if (result) {
      debugPrint("✅ Android notification permission granted");
    } else {
      debugPrint("❌ Android notification permission denied");
    }
  } else {
    debugPrint("✅ Android notification already granted");
  }

  // Also check exact alarm permission
  final exactAlarm = await NativePermissionService.isExactAlarmPermissionGranted();
  if (!exactAlarm) {
    await NativePermissionService.requestExactAlarmPermission();
  }
}

