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
import androidx.core.content.ContextCompat  // For ContextCompat.getSystemService
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
                            requestExactAlarmPermission(this)
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
                            openAutoStartSettings()
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

    private fun openAutoStartSettings() {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val intent = Intent()
        
        try {
            when {
                manufacturer.contains("xiaomi") -> {
                    intent.component = android.content.ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity"
                    )
                }
                manufacturer.contains("oppo") -> {
                    intent.component = android.content.ComponentName(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                    )
                }
                manufacturer.contains("vivo") -> {
                    intent.component = android.content.ComponentName(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                    )
                }
                manufacturer.contains("huawei") -> {
                    intent.component = android.content.ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                    )
                }
                manufacturer.contains("samsung") -> {
                    intent.component = android.content.ComponentName(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.ui.battery.BatteryActivity"
                    )
                }
                manufacturer.contains("oneplus") -> {
                    intent.component = android.content.ComponentName(
                        "com.oneplus.security",
                        "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
                    )
                }
                manufacturer.contains("infinix") -> {
                    intent.component = android.content.ComponentName(
                        "com.transsion.phonemanager",
                        "com.transsion.phonemanager.activity.StartupAppListActivity"
                    )
                }
                else -> {
                    // Fallback to generic settings
                    intent.action = Settings.ACTION_SETTINGS
                }
            }
            
            if (intent.component != null) {
                 intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                 startActivity(intent)
                 Log.d("AutoStart", "Opened AutoStart settings for $manufacturer")
            } else {
                 // Try generic fallback if no component matched but we want to do something
                 val genericIntent = Intent(Settings.ACTION_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                 }
                 startActivity(genericIntent)
                 Log.d("AutoStart", "Opened generic settings for $manufacturer")
            }

        } catch (e: Exception) {
            Log.e("AutoStart", "Specific screen not found, opening generic settings", e)
            try {
                val genericIntent = Intent(Settings.ACTION_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(genericIntent)
            } catch (_: Exception) {}
        }
    }

    private fun canScheduleExactAlarms(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val alarmManager = ContextCompat.getSystemService(this, AlarmManager::class.java)
        alarmManager?.canScheduleExactAlarms() ?: false
    } else {
        true
    }
}

    private fun requestExactAlarmPermission(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
        return  // No permission needed before Android 12
    }

    val alarmManager = ContextCompat.getSystemService(context, AlarmManager::class.java)
    alarmManager?.let { am: AlarmManager ->
        if (am.canScheduleExactAlarms()) {
            return  // Permission already granted
        }
    }

    // Primary method: Standard system intent
    val primaryIntent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
        data = android.net.Uri.parse("package:${context.packageName}")
        flags = Intent.FLAG_ACTIVITY_NEW_TASK
    }

    // Backup method: App info page
    val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
        data = android.net.Uri.parse("package:${context.packageName}")
        flags = Intent.FLAG_ACTIVITY_NEW_TASK
    }

    // Try intents in order
    if (primaryIntent.resolveActivity(context.packageManager) != null) {
        context.startActivity(primaryIntent)
    } else {
        context.startActivity(fallbackIntent)
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
