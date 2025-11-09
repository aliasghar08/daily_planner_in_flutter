package com.example.daily_planner

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class AlarmReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_ID = "daily_planner_channel"
        const val CHANNEL_NAME = "Daily Planner"
        private const val KEEP_ALIVE_ALARM_ID = 888
        private const val ALARMS_PREFS = "alarms_prefs"

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val EXTRA_NOTIFICATION_ID = "notificationId"
        private const val EXTRA_PAYLOAD = "payload"

        const val ACTION_STOP_ALARM = "com.example.daily_planner.STOP_ALARM"
        const val ACTION_SNOOZE_ALARM = "com.example.daily_planner.SNOOZE_ALARM"
        const val ACTION_KEEP_ALIVE = "com.example.daily_planner.KEEP_ALIVE"

        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

                val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                val soundUri = alarmSound ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Task reminders and alerts"
                    enableLights(true)
                    enableVibration(true)
                    setSound(soundUri, attrs)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                }

                context.getSystemService(NotificationManager::class.java)
                    ?.createNotificationChannel(channel)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "Received action: ${intent.action}")

        when (intent.action) {
            ACTION_STOP_ALARM -> stopAlarm(context, intent)
            ACTION_SNOOZE_ALARM -> snoozeAlarm(context, intent)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> rescheduleAllAlarms(context)
            ACTION_KEEP_ALIVE -> scheduleKeepAliveAlarm(context)
            else -> handleAlarmTrigger(context, intent)
        }
    }

    private fun handleAlarmTrigger(context: Context, intent: Intent) {
        showNotification(context, intent)
        scheduleKeepAliveAlarm(context)
    }

    private fun showNotification(context: Context, intent: Intent) {
        createNotificationChannel(context)

        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Reminder"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "You have a task!"
        val id = intent.getIntExtra(EXTRA_NOTIFICATION_ID, System.currentTimeMillis().toInt())

        val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

        // STOP ACTION
        val stopIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_STOP_ALARM
            putExtra(EXTRA_NOTIFICATION_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
        }
        val stopPending = PendingIntent.getBroadcast(
            context, id + 10000, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // SNOOZE ACTION
        val snoozeIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_SNOOZE_ALARM
            putExtra(EXTRA_NOTIFICATION_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
        }
        val snoozePending = PendingIntent.getBroadcast(
            context, id + 20000, snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("from_notification", true)
            putExtra("notification_id", id)
        }
        val tapPendingIntent = PendingIntent.getActivity(
            context, id, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // FIXED: Use Android system icons instead of custom drawables
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(tapPendingIntent)
            .setSound(alarmSound)
            .setVibrate(longArrayOf(1000, 1000, 1000))
            .setOngoing(false)
            .setAutoCancel(false)
            .setTimeoutAfter(300000) // Auto cancel after 5 minutes
            // FIXED: Use Android system icons that exist
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPending)
            .addAction(android.R.drawable.ic_media_play, "Snooze", snoozePending)
            .build()

        // FIXED: Remove the problematic FLAG_NO_CLEAR code
        // This was causing compilation errors
        ContextCompat.getSystemService(context, NotificationManager::class.java)
            ?.notify(id, notification)
        
        Log.d("AlarmReceiver", "Notification shown with ID: $id - Buttons should be touchable")
    }

    private fun stopAlarm(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        val title = intent.getStringExtra(EXTRA_TITLE)
        val body = intent.getStringExtra(EXTRA_BODY)
        
        if (id != -1) {
            val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
            nm?.cancel(id)
            Log.d("AlarmReceiver", "Alarm stopped for ID = $id")
            
            // Remove from shared preferences
            val prefs = context.getSharedPreferences(ALARMS_PREFS, Context.MODE_PRIVATE)
            prefs.edit().remove(id.toString()).apply()
            
            // Notify Flutter
            notifyFlutterAction(context, "stop", id, title, body)
        }
    }

    private fun snoozeAlarm(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Reminder"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "Snoozed Task"

        if (id == -1) return

        val snoozeTime = System.currentTimeMillis() + (5 * 60 * 1000)

        // Schedule snoozed alarm
        scheduleAlarm(context, id + 1000, "Snoozed: $title", body, snoozeTime)

        // Cancel current notification
        val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
        nm?.cancel(id)

        Log.d("AlarmReceiver", "Alarm snoozed for ID $id - 5 minutes")
        
        // Notify Flutter
        notifyFlutterAction(context, "snooze", id, title, body)
    }

    // FIXED: Simplified Flutter notification - remove FlutterEngine creation
    private fun notifyFlutterAction(context: Context, action: String, id: Int, title: String?, body: String?) {
        try {
            Log.d("AlarmReceiver", "Notifying Flutter about action: $action for ID: $id")
            
            // Simple approach: Launch the app with intent extras
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("notification_action", action)
                putExtra("notification_id", id)
                putExtra("notification_title", title)
                putExtra("notification_body", body)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            context.startActivity(launchIntent)
            
            Log.d("AlarmReceiver", "Launched MainActivity with action: $action")
            
        } catch (e: Exception) {
            Log.e("AlarmReceiver", "Error notifying Flutter: ${e.message}", e)
        }
    }

    // FIXED: Remove the problematic getFlutterEngine method entirely
    // Creating new FlutterEngine in BroadcastReceiver doesn't work well

    private fun scheduleKeepAliveAlarm(context: Context) {
        val alarmManager = ContextCompat.getSystemService(context, AlarmManager::class.java) ?: return
        val intent = Intent(context, AlarmReceiver::class.java).apply { action = ACTION_KEEP_ALIVE }

        val pendingIntent = PendingIntent.getBroadcast(
            context, KEEP_ALIVE_ALARM_ID, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = System.currentTimeMillis() + (15 * 60 * 1000)

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerTime,
            pendingIntent
        )
    }

    private fun rescheduleAllAlarms(context: Context) {
        val prefs = context.getSharedPreferences(ALARMS_PREFS, Context.MODE_PRIVATE)
        prefs.all.forEach { (key, value) ->
            if (value is Long) {
                key.toIntOrNull()?.let { id ->
                    scheduleAlarm(context, id, "Reminder", "Scheduled task", value)
                }
            }
        }
    }

    private fun scheduleAlarm(context: Context, id: Int, title: String, body: String, time: Long) {
        val alarmManager = ContextCompat.getSystemService(context, AlarmManager::class.java) ?: return
        val prefs = context.getSharedPreferences(ALARMS_PREFS, Context.MODE_PRIVATE)
        prefs.edit().putLong(id.toString(), time).apply()

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_NOTIFICATION_ID, id)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            time,
            pendingIntent
        )
    }
}