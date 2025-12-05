import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> requestPermission() async {

    if (kIsWeb) {
    print("🌐 Web platform: no notification permission required.");
    return;
  }
  if (Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      final result = await Permission.notification.request();
      if (result.isGranted) {
        print("✅ Android notification permission granted");
      } else {
        print("❌ Android notification permission denied");
      }
    } else {
      print("✅ Android notification already granted");
    }
  }
}
