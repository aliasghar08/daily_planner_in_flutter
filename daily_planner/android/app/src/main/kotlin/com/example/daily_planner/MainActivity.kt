package com.example.daily_planner

import android.Manifest
import android.app.AlarmManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import android.app.KeyguardManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val REQUEST_CODE_NOTIFICATION = 1001
        const val CHANNEL_EXACT_ALARM = "exact_alarm_permission"
        const val CHANNEL_MAIN_ALARM = "com.example.daily_planner/alarm"
        const val CHANNEL_SERVICE = "daily_planner/alarm_service"
        const val CHANNEL_PERMISSION = "daily_planner/native_permissions"
        const val CHANNEL_CONNECTIVITY = "daily_planner/native_connectivity"
        const val CHANNEL_SHARE = "daily_planner/native_share"
        const val CHANNEL_TIMEZONE = "daily_planner/native_timezone"
        const val CHANNEL_BIOMETRIC = "daily_planner/native_biometric"
        const val CHANNEL_GOOGLE_AUTH = "daily_planner/native_google_signin"
        const val CHANNEL_PREFERENCES = "daily_planner/native_preferences"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private val googleAuthHandler by lazy { NativeGoogleAuthHandler(this) }
    private val preferencesHandler by lazy { NativePreferencesHandler(this) }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_PERMISSION).setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CONNECTIVITY).setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SHARE).setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_TIMEZONE).setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_BIOMETRIC).setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_GOOGLE_AUTH).setMethodCallHandler { call, result ->
            googleAuthHandler.handleMethodCall(call, result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_PREFERENCES).setMethodCallHandler { call, result ->
            preferencesHandler.handleMethodCall(call, result)
        }
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

                "showNotification", "showNow" -> {
                    val id = call.argument<Int>("id") ?: ((System.currentTimeMillis() % 100000).toInt())
                    val title = call.argument<String>("title") ?: "Daily Planner"
                    val body = call.argument<String>("body") ?: "Notification"
                    val payload = call.argument<String>("payload")

                    AlarmReceiver.showNotification(this, id, title, body, payload)
                    result.success(true)
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

                "checkNotificationPermission" -> {
                    result.success(checkNotificationPermission())
                }

                "requestNotificationPermission" -> {
                    requestNotificationPermission(result)
                }

                "openNotificationSettings" -> {
                    openNotificationSettings()
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
                        "canScheduleExactAlarms" to canScheduleExactAlarms(),
                        "isNotificationPermissionGranted" to checkNotificationPermission()
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

                "checkConnectivity" -> {
                    val status = checkNetworkConnectivity()
                    result.success(status)
                }

                "shareText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val subject = call.argument<String>("subject") ?: ""
                    shareText(text, subject)
                    result.success(true)
                }

                "getDeviceTimezone" -> {
                    val tz = TimeZone.getDefault().id
                    result.success(tz)
                }

                "isBiometricSupported" -> {
                    result.success(isBiometricSupported())
                }

                "canCheckBiometrics" -> {
                    result.success(canCheckBiometrics())
                }

                "getAvailableBiometrics" -> {
                    result.success(getAvailableBiometrics())
                }

                "authenticateBiometric" -> {
                    authenticateBiometric(call, result)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Method call failed: ${call.method}", e)
            result.error("ERROR", "Method execution failed: ${e.message}", null)
        }
    }

    private fun checkNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                result.success(true)
            } else {
                pendingPermissionResult = result
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQUEST_CODE_NOTIFICATION
                )
            }
        } else {
            result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
        }
    }

    private fun openNotificationSettings() {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to open notification settings: ${e.message}")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_NOTIFICATION) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (googleAuthHandler.onActivityResult(requestCode, resultCode, data)) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
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

    private fun checkNetworkConnectivity(): String {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return "none"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val network = cm.activeNetwork ?: return "none"
                val capabilities = cm.getNetworkCapabilities(network) ?: return "none"
                return when {
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> "wifi"
                    else -> "none"
                }
            } else {
                @Suppress("DEPRECATION")
                val activeInfo = cm.activeNetworkInfo
                if (activeInfo != null && activeInfo.isConnected) {
                    @Suppress("DEPRECATION")
                    return when (activeInfo.type) {
                        ConnectivityManager.TYPE_WIFI -> "wifi"
                        ConnectivityManager.TYPE_MOBILE -> "mobile"
                        ConnectivityManager.TYPE_ETHERNET -> "ethernet"
                        else -> "wifi"
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to check network connectivity: ${e.message}")
        }
        return "none"
    }

    private fun shareText(text: String, subject: String) {
        try {
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                if (subject.isNotEmpty()) {
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                }
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val chooser = Intent.createChooser(shareIntent, "Share with").apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(chooser)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to share text: ${e.message}", e)
        }
    }

    private fun isBiometricSupported(): Boolean {
        return try {
            val biometricManager = BiometricManager.from(this)
            val canAuth = biometricManager.canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
            )
            canAuth != BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE
        } catch (e: Exception) {
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            keyguardManager?.isKeyguardSecure ?: false
        }
    }

    private fun canCheckBiometrics(): Boolean {
        return try {
            val biometricManager = BiometricManager.from(this)
            val canAuth = biometricManager.canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
            )
            canAuth == BiometricManager.BIOMETRIC_SUCCESS
        } catch (e: Exception) {
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            keyguardManager?.isKeyguardSecure ?: false
        }
    }

    private fun getAvailableBiometrics(): List<String> {
        val types = mutableListOf<String>()
        try {
            val pm = packageManager
            if (pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)) {
                types.add("fingerprint")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && pm.hasSystemFeature(PackageManager.FEATURE_FACE)) {
                types.add("face")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && pm.hasSystemFeature(PackageManager.FEATURE_IRIS)) {
                types.add("iris")
            }
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            if (keyguardManager?.isKeyguardSecure == true) {
                types.add("deviceCredential")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error checking available biometrics: ${e.message}")
        }
        return types
    }

    private fun authenticateBiometric(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title") ?: "Authentication Required"
        val subtitle = call.argument<String>("subtitle") ?: ""
        val description = call.argument<String>("description") ?: "Verify your identity to continue"
        val negativeButtonText = call.argument<String>("negativeButtonText") ?: "Cancel"

        val executor = ContextCompat.getMainExecutor(this)
        var callbackInvoked = false

        val biometricPrompt = BiometricPrompt(
            this,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                    super.onAuthenticationSucceeded(authResult)
                    if (!callbackInvoked) {
                        callbackInvoked = true
                        result.success(true)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    super.onAuthenticationError(errorCode, errString)
                    if (!callbackInvoked) {
                        callbackInvoked = true
                        if (errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                            errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                            errorCode == BiometricPrompt.ERROR_CANCELED) {
                            result.success(false)
                        } else {
                            result.error("AUTH_ERROR_$errorCode", errString.toString(), null)
                        }
                    }
                }

                override fun onAuthenticationFailed() {
                    super.onAuthenticationFailed()
                    // Still listening for next attempt
                }
            }
        )

        try {
            val promptInfoBuilder = BiometricPrompt.PromptInfo.Builder()
                .setTitle(title)
                .setDescription(description)

            if (subtitle.isNotEmpty()) {
                promptInfoBuilder.setSubtitle(subtitle)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                promptInfoBuilder.setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
            } else {
                promptInfoBuilder.setNegativeButtonText(negativeButtonText)
            }

            val promptInfo = promptInfoBuilder.build()
            biometricPrompt.authenticate(promptInfo)
        } catch (e: Exception) {
            Log.e(TAG, "Biometric authentication setup failed: ${e.message}", e)
            result.error("BIOMETRIC_EXCEPTION", e.message, null)
        }
    }

    override fun onResume() {
        super.onResume()
        try {
            AlarmForegroundService.start(this)
        } catch (_: Exception) {}
    }
}
