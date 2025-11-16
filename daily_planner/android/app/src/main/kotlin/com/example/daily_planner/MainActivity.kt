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
import java.util.*

class MainActivity : FlutterActivity() {

    private val CHANNEL = "exact_alarm_permission"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AlarmReceiver.createNotificationChannel(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmReceiver.createNotificationChannel(this)

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

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e("MainActivity", "Method call failed: ${call.method}", e)
                    result.error("ERROR", "Failed to execute ${call.method}", e.message)
                }
            }
    }

    private fun scheduleAlarm(id: Int, title: String, body: String, time: Long) {
        AlarmReceiver.createNotificationChannel(this)

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
            putExtra("id", id)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, pendingIntent)
                Log.d("AlarmSchedule", "Alarm scheduled with ID: $id for time: $time")
            } else {
                Log.w("AlarmWarning", "Exact-alarm permission denied; cannot schedule alarm.")
            }
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, pendingIntent)
            Log.d("AlarmSchedule", "Alarm scheduled with ID: $id for time: $time")
        }
    }

    private fun canScheduleExactAlarms(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else true
    }

    private fun requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            if (intent.resolveActivity(packageManager) != null) startActivity(intent)
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
                startActivity(intent)
            }
        } catch (e: Exception) {
            Log.e("BatteryOpt", "Failed to prompt disable battery optimization", e)
        }
    }
}
