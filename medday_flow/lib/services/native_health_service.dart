import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// In-house native Apple Health (HealthKit) / Health Platform service
/// Communicates directly with iOS HealthKit via native MethodChannel.
class NativeHealthService {
  static const MethodChannel _channel = MethodChannel('daily_planner/native_health');

  /// Check if Health platform / HealthKit is available on this device
  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    if (!Platform.isIOS) return false;

    try {
      final bool? available = await _channel.invokeMethod<bool>('checkAvailability');
      return available ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('NativeHealthService.isAvailable error: $e');
      return false;
    }
  }

  /// Request authorization to read and write health records
  static Future<bool> requestPermissions() async {
    if (kIsWeb || !Platform.isIOS) return false;

    try {
      final bool? granted = await _channel.invokeMethod<bool>('requestPermissions');
      return granted ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('NativeHealthService.requestPermissions error: $e');
      return false;
    }
  }

  /// Check if the user has granted health authorization
  static Future<bool> checkPermissions() async {
    if (kIsWeb || !Platform.isIOS) return false;

    try {
      final bool? isGranted = await _channel.invokeMethod<bool>('checkPermissions');
      return isGranted ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('NativeHealthService.checkPermissions error: $e');
      return false;
    }
  }

  /// Save a medication intake record to Apple HealthKit
  static Future<bool> saveMedicationRecord(Map<String, dynamic> record) async {
    if (kIsWeb || !Platform.isIOS) return false;

    try {
      final bool? success = await _channel.invokeMethod<bool>('saveMedicationRecord', record);
      return success ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('NativeHealthService.saveMedicationRecord error: $e');
      return false;
    }
  }

  /// Fetch medication records previously synced to Apple HealthKit
  static Future<List<Map<String, dynamic>>> fetchMedicationRecords() async {
    if (kIsWeb || !Platform.isIOS) return [];

    try {
      final List<dynamic>? list = await _channel.invokeMethod<List<dynamic>>('fetchMedicationRecords');
      if (list == null) return [];
      return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } on MissingPluginException {
      return [];
    } catch (e) {
      debugPrint('NativeHealthService.fetchMedicationRecords error: $e');
      return [];
    }
  }

  /// Revoke health authorization
  static Future<void> revokePermissions() async {
    if (kIsWeb || !Platform.isIOS) return;

    try {
      await _channel.invokeMethod('revokePermissions');
    } catch (e) {
      debugPrint('NativeHealthService.revokePermissions error: $e');
    }
  }
}
