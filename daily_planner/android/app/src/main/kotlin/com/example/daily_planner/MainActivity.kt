package com.example.daily_planner

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
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
        // Create notification channel when app starts
        AlarmReceiver.createNotificationChannel(this)
        
        // Handle notification actions when app is opened from notification
        handleNotificationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Handle notification actions when app is already running
        handleNotificationIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        intent?.let { 
            if (it.hasExtra("from_notification") || it.hasExtra("notification_action")) {
                Log.d("MainActivity", "App opened from notification: ${it.extras}")
                
                // Forward the notification action to Flutter
                val action = it.getStringExtra("notification_action")
                val id = it.getIntExtra("notification_id", -1)
                val title = it.getStringExtra("notification_title")
                val body = it.getStringExtra("notification_body")
                
                if (action != null && id != -1) {
                    // You can forward this to Flutter via MethodChannel if needed
                    Log.d("MainActivity", "Forwarding action to Flutter: $action for ID: $id")
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Create notification channel when Flutter engine is configured
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
                            disableBatteryOptimization()
                            result.success(null)
                        }

                        "openManufacturerSettings" -> {
                            openManufacturerSettings()
                            result.success(null)
                        }

                        "cancelAlarm" -> {
                            val id = call.argument<Int>("id") ?: 0
                            cancelAlarm(id)
                            result.success(null)
                        }

                        "promptDisableBatteryOptimization" -> {
                            promptDisableBatteryOptimization()
                            result.success(null)
                        }

                        "ensureNotificationChannel" -> {
                            AlarmReceiver.createNotificationChannel(this)
                            result.success(null)
                        }

                        "checkBatteryOptimization" -> {
                            result.success(isIgnoringBatteryOptimizations())
                        }

                        "openAutoStartSettings" -> {
                            openAutoStartSettings()
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
        // Ensure notification channel exists before scheduling alarm
        AlarmReceiver.createNotificationChannel(this)
        
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
            putExtra("notificationId", id)
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
                // Fallback to inexact alarm
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, pendingIntent)
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
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
            } else {
                Log.w("PermissionRequest", "No activity to handle exact-alarm permission")
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun disableBatteryOptimization() {
        try {
            val packageName = applicationContext.packageName
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
            } else {
                Log.i("BatteryOpt", "Already ignoring battery optimizations.")
            }
        } catch (e: Exception) {
            Log.e("BatteryOpt", "Failed to open battery optimization settings", e)
        }
    }

    private fun promptDisableBatteryOptimization() {
        try {
            val packageName = applicationContext.packageName
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                } else {
                    disableBatteryOptimization() // Fallback to settings
                }
            } else {
                Log.i("BatteryOpt", "Already ignoring battery optimizations.")
            }
        } catch (e: Exception) {
            Log.e("BatteryOpt", "Failed to prompt disable battery optimization", e)
        }
    }

    private fun openManufacturerSettings() {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.getDefault())
        val intent = when {
            manufacturer.contains("samsung") -> {
                // For Samsung, try to open battery optimization settings directly
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            }
            manufacturer.contains("xiaomi") -> Intent().apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            }
            manufacturer.contains("infinix") -> {
                Intent().apply {
                    action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                    data = Uri.parse("package:$packageName")
                }
            }
            manufacturer.contains("oppo") -> Intent().apply {
                component = ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.startupapp.StartupAppListActivity"
                )
            }
            manufacturer.contains("vivo") -> Intent().apply {
                component = ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                )
            }
            manufacturer.contains("huawei") -> Intent().apply {
                component = ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                )
            }
            else -> Intent(Settings.ACTION_SETTINGS)
        }

        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        try {
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
            } else {
                // Fallback to general app info
                Log.w("ManuSettings", "Manufacturer-specific settings not found, using fallback")
                val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(fallbackIntent)
            }
        } catch (e: Exception) {
            Log.e("ManuSettings", "Failed to open manufacturer settings", e)
            // Ultimate fallback
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    // ADD THIS MISSING METHOD
    private fun openAutoStartSettings() {
        Log.d("AutoStartSettings", "Opening auto-start settings")
        // For most devices, auto-start settings are within manufacturer settings
        openManufacturerSettings()
    }

    private fun cancelAlarm(id: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java)

        val pendingIntent = PendingIntent.getBroadcast(
            this, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
        
        // Also cancel any related notifications
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(id)
        notificationManager.cancel(id + 10000)
        notificationManager.cancel(id + 20000)
        notificationManager.cancel(id + 30000)
        notificationManager.cancel(id + 40000)
        
        Log.d("AlarmCancel", "Alarm with ID $id cancelled and notifications cleared.")
    }
}