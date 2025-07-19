import 'package:flutter/services.dart';

class BatteryOptimizationHelper {
  static const platform = MethodChannel('com.alias.daily_planner/battery');

  static Future<void> requestDisableBatteryOptimization() async {
    try {
      await platform.invokeMethod('disableBatteryOptimization');
    } on PlatformException catch (e) {
      print('Failed to disable battery optimization: ${e.message}');
    }
  }

  static Future<void> promptDisableBatteryOptimization() async {
  try {
    await platform.invokeMethod('promptDisableBatteryOptimization');
  } on PlatformException catch (e) {
    print('Failed to prompt for disabling battery optimization: ${e.message}');
  }
}

}
