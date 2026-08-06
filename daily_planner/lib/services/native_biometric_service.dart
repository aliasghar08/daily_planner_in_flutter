import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Enum representing biometric types available on the device
enum BiometricType {
  face,
  fingerprint,
  iris,
  deviceCredential,
}

/// Custom native biometric service replacing third-party `local_auth` package
class NativeBiometricService {
  static const MethodChannel _channel = MethodChannel('daily_planner/native_biometric');

  /// Check if the device hardware supports biometrics or screen lock
  static Future<bool> isDeviceSupported() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    try {
      final bool? result = await _channel.invokeMethod<bool>('isBiometricSupported');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error checking biometric support: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Unexpected error in isDeviceSupported: $e');
      return false;
    }
  }

  /// Check if biometrics or device credentials are enrolled and ready
  static Future<bool> canCheckBiometrics() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    try {
      final bool? result = await _channel.invokeMethod<bool>('canCheckBiometrics');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error in canCheckBiometrics: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Unexpected error in canCheckBiometrics: $e');
      return false;
    }
  }

  /// Get list of available biometric modalities on this device
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return [];
    }
    try {
      final List<dynamic>? rawList = await _channel.invokeMethod<List<dynamic>>('getAvailableBiometrics');
      if (rawList == null) return [];

      final biometrics = <BiometricType>[];
      for (final item in rawList) {
        switch (item.toString().toLowerCase()) {
          case 'fingerprint':
            biometrics.add(BiometricType.fingerprint);
            break;
          case 'face':
            biometrics.add(BiometricType.face);
            break;
          case 'iris':
            biometrics.add(BiometricType.iris);
            break;
          case 'devicecredential':
            biometrics.add(BiometricType.deviceCredential);
            break;
        }
      }
      return biometrics;
    } on PlatformException catch (e) {
      debugPrint('Error getting available biometrics: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('Unexpected error in getAvailableBiometrics: $e');
      return [];
    }
  }

  /// Authenticate user using Biometrics / Device Passkey
  static Future<bool> authenticate({
    String title = 'Authentication Required',
    String subtitle = '',
    String description = 'Verify your identity to proceed',
    String negativeButtonText = 'Cancel',
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    try {
      final bool? result = await _channel.invokeMethod<bool>('authenticateBiometric', {
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'negativeButtonText': negativeButtonText,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException during authentication: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Unexpected error during authentication: $e');
      return false;
    }
  }
}
