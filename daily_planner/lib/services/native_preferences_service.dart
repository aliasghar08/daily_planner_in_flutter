import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// In-house native implementation of persistent key-value preferences.
/// Replaces third-party package:shared_preferences with zero external dependencies.
class NativePreferencesService {
  static const MethodChannel _channel =
      MethodChannel('daily_planner/native_preferences');

  static NativePreferencesService? _instance;
  final Map<String, Object?> _preferenceCache;

  NativePreferencesService._(this._preferenceCache);

  /// Get the singleton instance of NativePreferencesService
  static Future<NativePreferencesService> getInstance() async {
    if (_instance == null) {
      final Map<String, Object?> cache = {};
      try {
        final dynamic allValues = await _channel.invokeMethod('getAll');
        if (allValues is Map) {
          allValues.forEach((key, value) {
            if (key is String && value != null) {
              cache[key] = value;
            }
          });
        }
      } catch (e) {
        debugPrint('NativePreferencesService: Error fetching initial prefs: $e');
      }
      _instance = NativePreferencesService._(cache);
    }
    return _instance!;
  }

  /// Reloads preference cache from disk
  Future<void> reload() async {
    try {
      final dynamic allValues = await _channel.invokeMethod('getAll');
      _preferenceCache.clear();
      if (allValues is Map) {
        allValues.forEach((key, value) {
          if (key is String && value != null) {
            _preferenceCache[key] = value;
          }
        });
      }
    } catch (e) {
      debugPrint('NativePreferencesService: Error reloading prefs: $e');
    }
  }

  /// Reads a value of any type from persistent storage.
  Object? get(String key) => _preferenceCache[key];

  /// Reads a boolean value from persistent storage.
  bool? getBool(String key) {
    final value = _preferenceCache[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is num) return value != 0;
    return null;
  }

  /// Reads an integer value from persistent storage.
  int? getInt(String key) {
    final value = _preferenceCache[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Reads a double value from persistent storage.
  double? getDouble(String key) {
    final value = _preferenceCache[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Reads a string value from persistent storage.
  String? getString(String key) {
    final value = _preferenceCache[key];
    if (value == null) return null;
    return value.toString();
  }

  /// Reads a set of string values from persistent storage.
  List<String>? getStringList(String key) {
    final value = _preferenceCache[key];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return null;
  }

  /// Returns true if persistent storage contains the given [key].
  bool containsKey(String key) => _preferenceCache.containsKey(key);

  /// Returns all keys in persistent storage.
  Set<String> getKeys() => Set<String>.from(_preferenceCache.keys);

  /// Saves a boolean [value] to persistent storage in the background.
  Future<bool> setBool(String key, bool value) async {
    _preferenceCache[key] = value;
    try {
      final bool? success = await _channel.invokeMethod<bool>('setBool', {
        'key': key,
        'value': value,
      });
      return success ?? true;
    } catch (e) {
      debugPrint('NativePreferencesService setBool error: $e');
      return false;
    }
  }

  /// Saves an integer [value] to persistent storage in the background.
  Future<bool> setInt(String key, int value) async {
    _preferenceCache[key] = value;
    try {
      final bool? success = await _channel.invokeMethod<bool>('setInt', {
        'key': key,
        'value': value,
      });
      return success ?? true;
    } catch (e) {
      debugPrint('NativePreferencesService setInt error: $e');
      return false;
    }
  }

  /// Saves a double [value] to persistent storage in the background.
  Future<bool> setDouble(String key, double value) async {
    _preferenceCache[key] = value;
    try {
      final bool? success = await _channel.invokeMethod<bool>('setDouble', {
        'key': key,
        'value': value,
      });
      return success ?? true;
    } catch (e) {
      debugPrint('NativePreferencesService setDouble error: $e');
      return false;
    }
  }

  /// Saves a string [value] to persistent storage in the background.
  Future<bool> setString(String key, String value) async {
    _preferenceCache[key] = value;
    try {
      final bool? success = await _channel.invokeMethod<bool>('setString', {
        'key': key,
        'value': value,
      });
      return success ?? true;
    } catch (e) {
      debugPrint('NativePreferencesService setString error: $e');
      return false;
    }
  }

  /// Saves a list of strings [value] to persistent storage in the background.
  Future<bool> setStringList(String key, List<String> value) async {
    _preferenceCache[key] = value;
    try {
      final bool? success = await _channel.invokeMethod<bool>('setStringList', {
        'key': key,
        'value': value,
      });
      return success ?? true;
    } catch (e) {
      debugPrint('NativePreferencesService setStringList error: $e');
      return false;
    }
  }

  /// Removes an entry from persistent storage.
  Future<bool> remove(String key) async {
    _preferenceCache.remove(key);
    try {
      final bool? success = await _channel.invokeMethod<bool>('remove', {
        'key': key,
      });
      return success ?? true;
    } catch (e) {
      debugPrint('NativePreferencesService remove error: $e');
      return false;
    }
  }

  /// Completes with true once the user preferences for the app has been cleared.
  Future<bool> clear() async {
    _preferenceCache.clear();
    try {
      final bool? success = await _channel.invokeMethod<bool>('clear');
      return success ?? true;
    } catch (e) {
      debugPrint('NativePreferencesService clear error: $e');
      return false;
    }
  }
}

/// Drop-in replacement alias for SharedPreferences
typedef SharedPreferences = NativePreferencesService;
