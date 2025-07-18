package com.example.daily_planner

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import android.app.NotificationChannel
import android.app.NotificationManager

class AlarmReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_ID = "daily_planner_channel"
        const val CHANNEL_NAME = "Daily Planner"
        private const val KEEP_ALIVE_ALARM_ID = 888
        private const val ALARMS_PREFS = "alarms_prefs"

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val ACTION_KEEP_ALIVE = "com.example.daily_planner.KEEP_ALIVE"

        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
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
                    setShowBadge(true)
                }

                context.getSystemService(NotificationManager::class.java)
                    ?.createNotificationChannel(channel)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "Received intent with action: ${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                rescheduleAllAlarms(context)
            }

            ACTION_KEEP_ALIVE -> {
                Log.d("AlarmReceiver", "Keep-alive alarm triggered")
                scheduleKeepAliveAlarm(context) // Only reschedule, no notification
            }

            else -> {
                handleAlarmTrigger(context, intent)
            }
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

        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtras(intent.extras ?: Bundle())
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            id,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(context.applicationInfo.icon)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()

        ContextCompat.getSystemService(context, NotificationManager::class.java)
            ?.notify(id, notification)
    }

    private fun scheduleKeepAliveAlarm(context: Context) {
        val alarmManager = ContextCompat.getSystemService(context, AlarmManager::class.java) ?: return

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_KEEP_ALIVE
            putExtra(EXTRA_TITLE, "Daily Planner Active")
            putExtra(EXTRA_BODY, "Keeping your reminders running")
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            KEEP_ALIVE_ALARM_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = System.currentTimeMillis() + (15 * 60 * 1000)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) return

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
                    Log.d("AlarmReceiver", "Rescheduling alarm ID: $id at time $value")
                    scheduleAlarm(context, id, "Reminder", "Scheduled task", value)
                }
            }
        }
    }

    private fun scheduleAlarm(
        context: Context,
        id: Int,
        title: String,
        body: String,
        triggerAtMillis: Long
    ) {
        val alarmManager = ContextCompat.getSystemService(context, AlarmManager::class.java) ?: return

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_NOTIFICATION_ID, id)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) return

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerAtMillis,
            pendingIntent
        )
    }
}
