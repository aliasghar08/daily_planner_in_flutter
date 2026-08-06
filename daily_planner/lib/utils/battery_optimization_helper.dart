import 'package:flutter/foundation.dart';
import 'native_permission_service.dart';

/// Custom Battery Optimization & AutoStart Helper
/// Uses native Android system intents and power manager APIs directly.
class BatteryOptimizationHelper {
  /// Checks if battery optimization is disabled and prompts the user if needed.
  static Future<void> ensureDisabled() async {
    try {
      final isIgnored = await NativePermissionService.isIgnoringBatteryOptimizations();

      if (kDebugMode) {
        debugPrint("🔋 Battery optimization ignored: $isIgnored");
      }

      if (!isIgnored) {
        await NativePermissionService.disableBatteryOptimization();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ Error requesting battery optimization disable: $e");
      }
    }
  }

  /// Opens OEM-specific power saver / autostart settings if applicable.
  static Future<void> ensureManufacturerBatteryOptimizationDisabled() async {
    try {
      final isIgnored = await NativePermissionService.isIgnoringBatteryOptimizations();
      if (!isIgnored) {
        await NativePermissionService.openAutoStartSettings();
      }
    } catch (e) {
      debugPrint("❌ Error ensuring manufacturer battery optimization: $e");
    }
  }

  /// Opens OEM autostart settings for Chinese & customized Android ROMs.
  static Future<void> ensureAutoStartEnabled() async {
    try {
      await NativePermissionService.openAutoStartSettings();
    } catch (e) {
      debugPrint("❌ Error opening auto-start settings: $e");
    }
  }
}

