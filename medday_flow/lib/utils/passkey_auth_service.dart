import 'dart:convert';
import 'package:medday_flow/services/native_biometric_service.dart';
import 'package:flutter/foundation.dart';
import 'package:medday_flow/services/native_preferences_service.dart';

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

  static List<int> _applyCipher(List<int> bytes, String key) {
    final keyBytes = utf8.encode(key);
    final result = List<int>.filled(bytes.length, 0);
    for (int i = 0; i < bytes.length; i++) {
      result[i] = bytes[i] ^ keyBytes[i % keyBytes.length];
    }
    return result;
  }

  /// Save credential associated with Passkey login with salted obfuscation
  Future<void> savePasskeyCredential({
    required String email,
    required String password,
    bool enableBiometric = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefPasskeyEmail, email);
      // Mask password with user-specific cryptographic salt before encoding
      final salt = 'MedDay_AuthEntropy_${email.toLowerCase().trim()}_secKey';
      final maskedBytes = _applyCipher(utf8.encode(password), salt);
      final encoded = 'v2:${base64Encode(maskedBytes)}';
      await prefs.setString(_prefPasskeySecret, encoded);
      if (enableBiometric) {
        await prefs.setBool(_prefPasskeyEnabled, true);
      }
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
        if (encoded.startsWith('v2:')) {
          final rawBase64 = encoded.substring(3);
          final salt = 'MedDay_AuthEntropy_${email.toLowerCase().trim()}_secKey';
          final cipherBytes = base64Decode(rawBase64);
          final plainBytes = _applyCipher(cipherBytes, salt);
          return {'email': email, 'password': utf8.decode(plainBytes)};
        } else {
          // Legacy backwards compatibility for previously saved base64 tokens
          final decoded = utf8.decode(base64Decode(encoded));
          return {'email': email, 'password': decoded};
        }
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

  /// Check if passkey / biometric is enabled by user in Settings
  Future<bool> hasPasskeyRegistered() async {
    final enabled = await isPasskeyEnabled();
    return enabled;
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
