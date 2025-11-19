import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/foundation.dart';

class BatteryOptimizationHelper {
  /// Checks if battery optimization is disabled and,
  /// if not, prompts the user to disable it.
  static Future<void> ensureDisabled() async {
    try {
      final isIgnored =
          await DisableBatteryOptimization.isBatteryOptimizationDisabled;

      if (kDebugMode) {
        print("🔋 Battery optimization ignored: $isIgnored");
      }

      if (!isIgnored!) {
        final result =
            await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();

        if (kDebugMode) {
          print("🔋 Battery optimization disable request result: $result");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Error requesting battery optimization disable: $e");
      }
    }
  }

    static Future<void> ensureManufacturerBatteryOptimizationDisabled() async {
    bool? isManBatteryOptimizationDisabled =
        await DisableBatteryOptimization.isManufacturerBatteryOptimizationDisabled;

    if (isManBatteryOptimizationDisabled == false) {
      await DisableBatteryOptimization.showDisableManufacturerBatteryOptimizationSettings(
        "Your device has additional battery optimization",
        "Follow the steps and disable the optimizations to allow smooth functioning of this app",
      );
    }
  }

  static Future<void> ensureAutoStartEnabled() async {
    bool? isAutoStartEnabled =
        await DisableBatteryOptimization.isAutoStartEnabled;

    if (!(isAutoStartEnabled ?? false)) {
      await DisableBatteryOptimization.showEnableAutoStartSettings(
        "Enable Auto Start",
        "Follow the steps and enable the auto start of this app",
      );
    }
  }
}
