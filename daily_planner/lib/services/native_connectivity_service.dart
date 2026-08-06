import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

enum CustomConnectivityResult {
  mobile,
  wifi,
  ethernet,
  none,
}

/// Custom in-house connectivity service replacing package:connectivity_plus.
class NativeConnectivityService {
  static const MethodChannel _channel =
      MethodChannel('daily_planner/native_connectivity');

  static final StreamController<CustomConnectivityResult> _controller =
      StreamController<CustomConnectivityResult>.broadcast();

  static Stream<CustomConnectivityResult> get onConnectivityChanged =>
      _controller.stream;

  static Timer? _pollingTimer;
  static CustomConnectivityResult _lastStatus = CustomConnectivityResult.none;

  /// Initialize connectivity listeners
  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onConnectivityChanged') {
        final statusStr = call.arguments as String? ?? 'none';
        final result = _parseStatus(statusStr);
        if (result != _lastStatus) {
          _lastStatus = result;
          _controller.add(result);
        }
      }
    });

    // Start background fallback heartbeat
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final current = await checkConnectivity();
      if (current != _lastStatus) {
        _lastStatus = current;
        _controller.add(current);
      }
    });
  }

  /// Check current network connectivity state
  static Future<CustomConnectivityResult> checkConnectivity() async {
    if (Platform.isAndroid) {
      try {
        final String? status =
            await _channel.invokeMethod<String>('checkConnectivity');
        return _parseStatus(status ?? 'none');
      } catch (_) {}
    }

    // Fallback: socket ping
    try {
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      if (lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty) {
        return CustomConnectivityResult.wifi;
      }
    } catch (_) {}

    return CustomConnectivityResult.none;
  }

  /// Quick boolean check if internet is reachable
  static Future<bool> isOnline() async {
    final status = await checkConnectivity();
    return status != CustomConnectivityResult.none;
  }

  /// Convenience getter matching common connectivity APIs
  static Future<bool> get isConnected => isOnline();

  static CustomConnectivityResult _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'wifi':
        return CustomConnectivityResult.wifi;
      case 'mobile':
      case 'cellular':
        return CustomConnectivityResult.mobile;
      case 'ethernet':
        return CustomConnectivityResult.ethernet;
      default:
        return CustomConnectivityResult.none;
    }
  }

  static void dispose() {
    _pollingTimer?.cancel();
  }
}
