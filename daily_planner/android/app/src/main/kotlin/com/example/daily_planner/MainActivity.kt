package com.example.daily_planner

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "exact_alarm_permission"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
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
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent().apply {
                                action = android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM
                            }
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                }
            }

        // 🔥 SCHEDULE DUMMY ALARM ON APP STARTUP
        val dummyAlarmTime = System.currentTimeMillis() + 30_000 // 30 seconds from now
        scheduleAlarm(
            id = 777,
            title = "Permission Activation Alarm",
            body = "This is required for Alarms & Reminders permission",
            time = dummyAlarmTime
        )
    }

    private fun scheduleAlarm(id: Int, title: String, body: String, time: Long) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) {
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
}
