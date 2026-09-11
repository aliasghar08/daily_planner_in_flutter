import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Custom Native Permission Service
/// Handles notification, exact alarm, battery optimization, and autostart permissions
/// natively via MethodChannel without relying on third-party packages.
class NativePermissionService {
  static const MethodChannel _channel = MethodChannel('daily_planner/native_permissions');
  static const MethodChannel _alarmChannel = MethodChannel('com.example.daily_planner/alarm');

  /// Check if notification permission is granted
  static Future<bool> isNotificationPermissionGranted() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('checkNotificationPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('⚠️ Error checking notification permission: $e');
      return true;
    }
  }

  /// Request notification permission (Android 13+ & iOS runtime permission)
  static Future<bool> requestNotificationPermission() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('⚠️ Error requesting notification permission: $e');
      return false;
    }
  }

  /// Check if exact alarms can be scheduled (Android 12+ API 31, always true on iOS)
  static Future<bool> isExactAlarmPermissionGranted() async {
    if (kIsWeb) return true;
    if (Platform.isIOS) return true;
    if (!Platform.isAndroid) return true;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('checkExactAlarmPermission');
      return granted ?? true;
    } catch (e) {
      debugPrint('⚠️ Error checking exact alarm permission: $e');
      return true;
    }
  }

  /// Request exact alarm permission (opens system exact alarm settings on Android)
  static Future<void> requestExactAlarmPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestExactAlarmPermission');
    } catch (e) {
      debugPrint('⚠️ Error requesting exact alarm permission: $e');
    }
  }

  /// Check if app is ignoring battery optimizations (unrestricted background on Android)
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? ignored = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return ignored ?? false;
    } catch (e) {
      debugPrint('⚠️ Error checking battery optimization: $e');
      return false;
    }
  }

  /// Request user to disable battery optimizations for reliable background alarms (Android)
  static Future<void> disableBatteryOptimization() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('disableBatteryOptimization');
    } catch (e) {
      debugPrint('⚠️ Error requesting battery optimization disable: $e');
    }
  }

  /// Open OEM autostart settings (Android OEM specific)
  static Future<bool> openAutoStartSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? opened = await _channel.invokeMethod<bool>('openAutoStartSettings');
      return opened ?? false;
    } catch (e) {
      debugPrint('⚠️ Error opening OEM autostart settings: $e');
      return false;
    }
  }

  /// Open application details settings
  static Future<void> openAppSettings() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (e) {
      debugPrint('⚠️ Error opening app settings: $e');
    }
  }

  /// Open notification channel / app notification settings
  static Future<void> openNotificationSettings() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (e) {
      debugPrint('⚠️ Error opening notification settings: $e');
    }
  }

  /// Check if critical alert (DND-bypass) permission is granted (iOS 12+ only)
  static Future<bool> isCriticalAlertPermissionGranted() async {
    if (kIsWeb || !Platform.isIOS) return false;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('checkCriticalAlertPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('⚠️ Error checking critical alert permission: $e');
      return false;
    }
  }

  /// Request critical alert (DND-bypass) permission on iOS 12+
  static Future<bool> requestCriticalAlertPermission() async {
    if (kIsWeb || !Platform.isIOS) return false;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('requestCriticalAlertPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('⚠️ Error requesting critical alert permission: $e');
      return false;
    }
  }

  /// Get Android SDK version (returns 0 on iOS/web)
  static Future<int> getAndroidSdkVersion() async {
    if (kIsWeb || !Platform.isAndroid) return 0;
    try {
      final int? sdk = await _channel.invokeMethod<int>('getAndroidSdkVersion');
      return sdk ?? 0;
    } catch (e) {
      debugPrint('⚠️ Error getting Android SDK version: $e');
      return 0;
    }
  }

  /// Fetch device brand, OEM, and battery optimization state
  static Future<Map<String, dynamic>> getDeviceBrandInfo() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return {};
    try {
      final dynamic info = await _alarmChannel.invokeMethod('getDeviceBrandInfo');
      if (info is Map) {
        return Map<String, dynamic>.from(info);
      }
    } catch (e) {
      debugPrint('⚠️ Error getting device brand info: $e');
    }
    return {};
  }

  /// Request all essential initial permissions
  static Future<void> requestAllCorePermissions() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    final notifGranted = await isNotificationPermissionGranted();
    if (!notifGranted) {
      await requestNotificationPermission();
    }
    if (Platform.isAndroid) {
      final exactAlarmGranted = await isExactAlarmPermissionGranted();
      if (!exactAlarmGranted) {
        await requestExactAlarmPermission();
      }
    }
  }
}
