package com.example.daily_planner

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "exact_alarm_permission"
    private val ALARM_SERVICE_CHANNEL = "daily_planner/alarm_service"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AlarmReceiver.createNotificationChannel(this)

        // Start foreground service when app launches
        AlarmForegroundService.start(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmReceiver.createNotificationChannel(this)

        // Channel 1
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "scheduleNativeAlarm" -> {
                            val id = call.argument<Int>("id") ?: 0
                            val title = call.argument<String>("title") ?: "No Title"
                            val body = call.argument<String>("body") ?: "No Body"
                            val time = call.argument<Long>("time") ?: 0L

                            scheduleAlarm(id, title, body, time)
                            AlarmForegroundService.start(this)
                            result.success(null)
                        }

                        "requestExactAlarmPermission" -> {
                            requestExactAlarmPermission()
                            result.success(null)
                        }

                        "checkExactAlarmPermission" -> {
                            result.success(canScheduleExactAlarms())
                        }

                        "disableBatteryOptimization" -> {
                            promptDisableBatteryOptimization()
                            result.success(null)
                        }

                        "ensureNotificationChannel" -> {
                            AlarmReceiver.createNotificationChannel(this)
                            result.success(null)
                        }

                        "showAlarmNotification" -> {
                            val id = call.argument<Int>("id") ?: 0
                            val title = call.argument<String>("title") ?: "No Title"
                            val body = call.argument<String>("body") ?: "No Body"

                            val intent = Intent(this, AlarmReceiver::class.java).apply {
                                putExtra(AlarmReceiver.EXTRA_ID, id)
                                putExtra(AlarmReceiver.EXTRA_TITLE, title)
                                putExtra(AlarmReceiver.EXTRA_BODY, body)
                            }
                            sendBroadcast(intent)
                            result.success(null)
                        }

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e("MainActivity", "Method call failed: ${call.method}", e)
                    result.error("ERROR", "Method failed", e.message)
                }
            }

        // Channel 2
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "startForegroundService" -> {
                            AlarmForegroundService.start(this)
                            Log.d("ServiceControl", "Foreground service started")
                            result.success(true)
                        }

                        "stopForegroundService" -> {
                            AlarmForegroundService.stop(this)
                            Log.d("ServiceControl", "Foreground service stopped")
                            result.success(true)
                        }

                        "openAutoStartSettings" -> {
                            openInfinixAutoStartSettings()
                            result.success(true)
                        }

                        "isServiceRunning" -> {
                            result.success(true)
                        }

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e("ServiceControl", "Service control failed: ${call.method}", e)
                    result.error("SERVICE_ERROR", "Service control failed", e.message)
                }
            }
    }

    private fun scheduleAlarm(id: Int, title: String, body: String, time: Long) {
        AlarmReceiver.createNotificationChannel(this)

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra(AlarmReceiver.EXTRA_TITLE, title)
            putExtra(AlarmReceiver.EXTRA_BODY, body)
            putExtra(AlarmReceiver.EXTRA_ID, id)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    time,
                    pendingIntent
                )
                Log.d("AlarmSchedule", "Alarm scheduled ID: $id at $time")
            } else {
                Log.w("AlarmWarning", "Exact alarm permission missing, trying anyway")
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    time,
                    pendingIntent
                )
            }
        } else {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                time,
                pendingIntent
            )
        }
    }

    private fun openInfinixAutoStartSettings() {
        try {
            val intent = Intent().apply {
                component = android.content.ComponentName(
                    "com.transsion.phonemanager",
                    "com.transsion.phonemanager.activity.StartupAppListActivity"
                )
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            Log.d("AutoStart", "Opened Infinix AutoStart settings")
        } catch (e: Exception) {
            Log.e("AutoStart", "Specific screen not found, opening generic settings", e)
            try {
                val intent = Intent(Settings.ACTION_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun canScheduleExactAlarms(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
    }

    private fun requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
            }
        }
    }

    private fun promptDisableBatteryOptimization() {
        try {
            val packageName = applicationContext.packageName
            val pm = getSystemService(POWER_SERVICE) as PowerManager

            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = android.net.Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                }
            }
        } catch (e: Exception) {
            Log.e("BatteryOpt", "Failed to request battery optimization disable", e)
        }
    }

    override fun onResume() {
        super.onResume()
        AlarmForegroundService.start(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        // Do not stop the service if you want alarms to work when app is closed
    }
}
