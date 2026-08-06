import 'dart:io';
import 'package:flutter/services.dart';

/// Custom in-house timezone service replacing package:timezone and package:flutter_timezone.
class NativeTimezoneService {
  static const MethodChannel _channel =
      MethodChannel('daily_planner/native_timezone');

  static String? _cachedTimezone;

  /// Retrieves the device's exact IANA time zone identifier (e.g. 'America/New_York', 'Asia/Karachi')
  static Future<String> getLocalTimezone() async {
    if (_cachedTimezone != null) return _cachedTimezone!;

    if (Platform.isAndroid) {
      try {
        final String? tzId =
            await _channel.invokeMethod<String>('getDeviceTimezone');
        if (tzId != null && tzId.isNotEmpty) {
          _cachedTimezone = tzId;
          return tzId;
        }
      } catch (_) {}
    }

    // Fallback to Dart DateTime timezone name or offset representation
    final now = DateTime.now();
    _cachedTimezone = now.timeZoneName.isNotEmpty ? now.timeZoneName : 'UTC';
    return _cachedTimezone!;
  }

  /// Device current time zone offset
  static Duration get currentOffset => DateTime.now().timeZoneOffset;

  /// Convert a local date time to UTC timestamp in milliseconds
  static int toEpochUtc(DateTime dateTime) => dateTime.toUtc().millisecondsSinceEpoch;

  /// Formats a 24-hour hour/minute pair to exact next occurrence DateTime
  static DateTime nextInstanceOfTime(int hour, int minute) {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
