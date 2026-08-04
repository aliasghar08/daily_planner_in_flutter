package com.example.daily_planner

import android.app.AlarmManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "MainActivity"
        const val CHANNEL_EXACT_ALARM = "exact_alarm_permission"
        const val CHANNEL_MAIN_ALARM = "com.example.daily_planner/alarm"
        const val CHANNEL_SERVICE = "daily_planner/alarm_service"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AlarmReceiver.createNotificationChannel(this)

        // Reschedule/validate alarms on startup
        AlarmScheduler.rescheduleAllAlarms(this)

        // Start foreground service if helpful
        try {
            AlarmForegroundService.start(this)
        } catch (e: Exception) {
            Log.w(TAG, "Could not start foreground service on create: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmReceiver.createNotificationChannel(this)

        val handler = MethodChannel.MethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        // Register handlers for all channel names used in Dart code
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_EXACT_ALARM).setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_MAIN_ALARM).setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SERVICE).setMethodCallHandler(handler)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "scheduleNativeAlarm", "scheduleAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val title = call.argument<String>("title") ?: "Daily Planner"
                    val body = call.argument<String>("body") ?: "You have a scheduled reminder"
                    val time = call.argument<Long>("time")
                        ?: call.argument<Long>("timeInMillis")
                        ?: 0L
                    val payload = call.argument<String>("payload")

                    if (id <= 0 || time <= 0L) {
                        result.error("INVALID_ARGS", "Valid id and time are required", null)
                        return
                    }

                    val success = AlarmScheduler.scheduleAlarm(
                        context = this,
                        id = id,
                        timeInMillis = time,
                        title = title,
                        body = body,
                        payload = payload,
                        saveToStorage = true
                    )
                    result.success(success)
                }

                "cancelAlarm", "cancelNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val success = if (id > 0) {
                        AlarmScheduler.cancelAlarm(this, id)
                    } else {
                        false
                    }
                    result.success(success)
                }

                "cancelAllAlarms" -> {
                    val success = AlarmScheduler.cancelAllAlarms(this)
                    result.success(success)
                }

                "getScheduledAlarms" -> {
                    val alarms = AlarmStorage.getAllAlarms(this).map {
                        mapOf(
                            "id" to it.id,
                            "title" to it.title,
                            "body" to it.body,
                            "timeInMillis" to it.timeInMillis,
                            "payload" to (it.payload ?: ""),
                            "createdAt" to it.createdAt
                        )
                    }
                    result.success(alarms)
                }

                "checkExactAlarmPermission" -> {
                    result.success(canScheduleExactAlarms())
                }

                "requestExactAlarmPermission", "openExactAlarmSettings" -> {
                    requestExactAlarmPermission(this)
                    result.success(true)
                }

                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                "disableBatteryOptimization" -> {
                    promptDisableBatteryOptimization()
                    result.success(true)
                }

                "openAutoStartSettings" -> {
                    val opened = openAutoStartSettings()
                    result.success(opened)
                }

                "getDeviceBrandInfo" -> {
                    val brandInfo = mapOf(
                        "manufacturer" to Build.MANUFACTURER.lowercase(),
                        "brand" to Build.BRAND.lowercase(),
                        "model" to Build.MODEL,
                        "sdkVersion" to Build.VERSION.SDK_INT,
                        "isIgnoringBatteryOptimizations" to isIgnoringBatteryOptimizations(),
                        "canScheduleExactAlarms" to canScheduleExactAlarms()
                    )
                    result.success(brandInfo)
                }

                "ensureNotificationChannel" -> {
                    AlarmReceiver.createNotificationChannel(this)
                    result.success(true)
                }

                "startForegroundService" -> {
                    AlarmForegroundService.start(this)
                    result.success(true)
                }

                "stopForegroundService" -> {
                    AlarmForegroundService.stop(this)
                    result.success(true)
                }

                "isServiceRunning" -> {
                    result.success(true)
                }

                "getAndroidSdkVersion" -> {
                    result.success(Build.VERSION.SDK_INT)
                }

                "openAppSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Method call failed: ${call.method}", e)
            result.error("ERROR", "Method execution failed: ${e.message}", null)
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
            return
        }

        val alarmManager = ContextCompat.getSystemService(context, AlarmManager::class.java)
        if (alarmManager?.canScheduleExactAlarms() == true) {
            return
        }

        try {
            val primaryIntent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            if (primaryIntent.resolveActivity(context.packageManager) != null) {
                context.startActivity(primaryIntent)
                return
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not open exact alarm intent, trying fallback: ${e.message}")
        }

        val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(fallbackIntent)
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(POWER_SERVICE) as? PowerManager
            pm?.isIgnoringBatteryOptimizations(packageName) ?: true
        } else {
            true
        }
    }

    private fun promptDisableBatteryOptimization() {
        try {
            val pm = getSystemService(POWER_SERVICE) as? PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && pm?.isIgnoringBatteryOptimizations(packageName) == false) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request battery optimization disable", e)
        }

        try {
            val appDetailsIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(appDetailsIntent)
        } catch (_: Exception) {}
    }

    /**
     * Resilient AutoStart & Background Execution launcher for Chinese OEMs:
     * Infinix, Tecno, itel (Transsion), Xiaomi, Redmi, Poco, Oppo, Realme, Vivo, iQOO, Huawei, Honor, OnePlus, Samsung
     */
    private fun openAutoStartSettings(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()

        val candidateIntents = mutableListOf<Intent>()

        // 1. Infinix / Tecno / itel (Transsion) - HiOS, XOS
        if (manufacturer.contains("infinix") || manufacturer.contains("tecno") ||
            manufacturer.contains("transsion") || manufacturer.contains("itel") ||
            brand.contains("infinix") || brand.contains("tecno") || brand.contains("itel")
        ) {
            candidateIntents.add(Intent().setComponent(ComponentName("com.transsion.phonemaster", "com.transsion.phonemaster.AutoStartManagementActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.transsion.phonemaster", "com.transsion.phonemaster.activity.StartupAppListActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.transsion.phonemanager", "com.transsion.phonemanager.activity.StartupAppListActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.transsion.phonemanager", "com.transsion.phonemanager.activity.AutoStartActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.transsion.phonemaster", "com.transsion.phonemaster.powersave.PowerSaveManagerActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.transsion.phonemaster", "com.transsion.phonemaster.activity.PowerManagerActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.transsion.phonemaster", "com.transsion.phonemaster.activity.SettingsActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.transsion.smartpanel", "com.transsion.smartpanel.settings.AutoStartManageActivity")))
        }

        // 2. Xiaomi / Redmi / Poco (MIUI, HyperOS)
        if (manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco") ||
            brand.contains("xiaomi") || brand.contains("redmi") || brand.contains("poco")
        ) {
            candidateIntents.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.powercenter.PowerSettings")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.permissions.PermissionsEditorActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.appmanager.AppManagerMainActivity")))
            candidateIntents.add(Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT))
        }

        // 3. Oppo / Realme (ColorOS, RealmeUI)
        if (manufacturer.contains("oppo") || manufacturer.contains("realme") ||
            brand.contains("oppo") || brand.contains("realme")
        ) {
            candidateIntents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startupmanager.StartupManagerActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.coloros.oppoguardelf", "com.coloros.oppoguardelf.permission.startup.StartupAppListActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.oplus.battery", "com.oplus.battery.AppBatteryMainActivity")))
        }

        // 4. Vivo / iQOO (FuntouchOS, OriginOS)
        if (manufacturer.contains("vivo") || manufacturer.contains("iqoo") ||
            brand.contains("vivo") || brand.contains("iqoo")
        ) {
            candidateIntents.add(Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.PurviewTabActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.vivo.abe", "com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity")))
        }

        // 5. Huawei / Honor (EMUI, MagicUI, HarmonyOS)
        if (manufacturer.contains("huawei") || manufacturer.contains("honor") ||
            brand.contains("huawei") || brand.contains("honor")
        ) {
            candidateIntents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.bootstart.BootStartActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.mainscreen.MainScreenActivity")))
        }

        // 6. OnePlus (OxygenOS)
        if (manufacturer.contains("oneplus") || brand.contains("oneplus")) {
            candidateIntents.add(Intent().setComponent(ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.oplus.battery", "com.oplus.battery.AppBatteryMainActivity")))
        }

        // 7. Samsung (OneUI)
        if (manufacturer.contains("samsung") || brand.contains("samsung")) {
            candidateIntents.add(Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity")))
            candidateIntents.add(Intent().setComponent(ComponentName("com.samsung.android.sm_cn", "com.samsung.android.sm.ui.battery.BatteryActivity")))
        }

        // Try candidate intents in order
        for (candidate in candidateIntents) {
            try {
                candidate.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                if (candidate.resolveActivity(packageManager) != null) {
                    startActivity(candidate)
                    Log.d(TAG, "Successfully opened OEM autostart screen: ${candidate.component}")
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed candidate: ${candidate.component}, ${e.message}")
            }
        }

        // Fallback: Open application details or battery settings
        try {
            val appDetailsIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(appDetailsIntent)
            return true
        } catch (_: Exception) {
            try {
                val genericIntent = Intent(Settings.ACTION_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(genericIntent)
                return true
            } catch (_: Exception) {
                return false
            }
        }
    }

    override fun onResume() {
        super.onResume()
        try {
            AlarmForegroundService.start(this)
        } catch (_: Exception) {}
    }
}
