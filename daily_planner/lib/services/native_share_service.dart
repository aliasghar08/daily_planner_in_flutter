import 'dart:io';
import 'package:flutter/services.dart';

/// Custom in-house share service replacing package:share_plus.
class NativeShareService {
  static const MethodChannel _channel =
      MethodChannel('daily_planner/native_share');

  /// Shares plain text with optional subject header via native Android Share sheet.
  static Future<void> share(String text, {String? subject}) async {
    if (text.isEmpty) return;

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('shareText', {
          'text': text,
          'subject': subject ?? '',
        });
      } catch (_) {}
    }
  }
}
