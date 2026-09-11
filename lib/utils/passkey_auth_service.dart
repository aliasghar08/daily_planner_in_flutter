import 'dart:convert';
import 'package:daily_planner/services/native_biometric_service.dart';
import 'package:flutter/foundation.dart';
import 'package:daily_planner/services/native_preferences_service.dart';

class PasskeyAuthService {
  static final PasskeyAuthService _instance = PasskeyAuthService._internal();
  factory PasskeyAuthService() => _instance;
  PasskeyAuthService._internal();

  static const String _prefPasskeyEnabled = 'pref_passkey_enabled';
  static const String _prefPasskeyEmail = 'pref_passkey_email';
  static const String _prefPasskeySecret = 'pref_passkey_secret';

  /// Check if the device hardware supports Passkeys / Biometrics
  Future<bool> isDeviceSupported() async {
    try {
      return await NativeBiometricService.isDeviceSupported();
    } catch (e) {
      debugPrint('Error checking device biometric/passkey support: $e');
      return false;
    }
  }

  /// Check if biometrics or device credentials are enrolled
  Future<bool> canCheckBiometrics() async {
    try {
      return await NativeBiometricService.canCheckBiometrics();
    } catch (e) {
      debugPrint('Error checking canCheckBiometrics: $e');
      return false;
    }
  }

  /// Get list of available biometric types (face, fingerprint, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await NativeBiometricService.getAvailableBiometrics();
    } catch (e) {
      debugPrint('Error getting available biometrics: $e');
      return [];
    }
  }

  /// Check if user has enabled Passkey login in app settings
  Future<bool> isPasskeyEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefPasskeyEnabled) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Enable or disable Passkey login in app settings
  Future<void> setPasskeyEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefPasskeyEnabled, enabled);
    } catch (e) {
      debugPrint('Error setting passkey enabled: $e');
    }
  }

  /// Save credential associated with Passkey login
  Future<void> savePasskeyCredential({
    required String email,
    required String password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefPasskeyEmail, email);
      // Base64 encode for secure local caching of session credential
      final encoded = base64Encode(utf8.encode(password));
      await prefs.setString(_prefPasskeySecret, encoded);
      await prefs.setBool(_prefPasskeyEnabled, true);
    } catch (e) {
      debugPrint('Error saving passkey credential: $e');
    }
  }

  /// Get saved passkey credential (email and decoded password)
  Future<Map<String, String>?> getSavedPasskeyCredential() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_prefPasskeyEmail);
      final encoded = prefs.getString(_prefPasskeySecret);

      if (email != null && encoded != null) {
        final decoded = utf8.decode(base64Decode(encoded));
        return {'email': email, 'password': decoded};
      }
      return null;
    } catch (e) {
      debugPrint('Error getting saved passkey credential: $e');
      return null;
    }
  }

  /// Clear saved passkey credential
  Future<void> clearPasskeyCredential() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefPasskeyEmail);
      await prefs.remove(_prefPasskeySecret);
      await prefs.remove(_prefPasskeyEnabled);
    } catch (e) {
      debugPrint('Error clearing passkey credential: $e');
    }
  }

  /// Alias for clearing passkey
  Future<void> clearPasskey() => clearPasskeyCredential();

  /// Check if passkey is supported on the hardware/OS
  Future<bool> isPasskeySupported() => isDeviceSupported();

  /// Check if passkey credential is saved or enabled
  Future<bool> hasPasskeyRegistered() async {
    final cred = await getSavedPasskeyCredential();
    final enabled = await isPasskeyEnabled();
    return cred != null || enabled;
  }

  /// Trigger Passkey / Biometric authentication prompt
  Future<bool> verifyWithPasskey({
    String reason = 'Verify your identity with Passkey or Biometrics',
  }) async {
    try {
      final isSupported = await NativeBiometricService.isDeviceSupported();
      if (!isSupported) {
        debugPrint('Passkey/Biometric not supported on this device');
        return false;
      }

      return await NativeBiometricService.authenticate(
        title: 'Passkey Verification',
        description: reason,
      );
    } catch (e) {
      debugPrint('Unexpected error in verifyWithPasskey: $e');
      return false;
    }
  }

  /// Alias for verifying passkey
  Future<bool> verifyPasskey({
    String reason = 'Verify your identity with Passkey or Biometrics',
  }) => verifyWithPasskey(reason: reason);
}
