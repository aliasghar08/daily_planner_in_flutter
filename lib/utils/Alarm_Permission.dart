import 'package:flutter/services.dart';

class AlarmPermissionHelper {
  static const MethodChannel _channel = MethodChannel('exact_alarm_permission');

  static Future<void> requestPermissionWithDummyAlarm() async {
  await Future.delayed(const Duration(seconds: 5)); 

  final now = DateTime.now().millisecondsSinceEpoch;
  final futureTime = now + 30 * 1000; 

  try {
    await _channel.invokeMethod('scheduleNativeAlarm', {
      'id': 777,
      'title': 'Permission Activation Alarm',
      'body': 'Dummy alarm to activate permissions',
      'time': futureTime,
    });

    await _channel.invokeMethod('requestExactAlarmPermission');
  } catch (e) {
    print("Dummy alarm or permission request failed: $e");
  }
}

}
