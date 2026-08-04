package com.example.daily_planner

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_ID = "daily_planner_channel"
        const val CHANNEL_NAME = "Daily Planner Notifications"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_ID = "id"
        const val EXTRA_PAYLOAD = "payload"

        const val ACTION_TRIGGER_ALARM = "daily_planner.ACTION_TRIGGER_ALARM"
        const val ACTION_STOP = "daily_planner.STOP"
        const val ACTION_SNOOZE = "daily_planner.SNOOZE"

        private const val TAG = "AlarmReceiver"

        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Task reminders and medication alerts"
                    enableLights(true)
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                    setSound(alarmSound, attrs)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                    setBypassDnd(true)
                }

                val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
                nm?.createNotificationChannel(channel)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val id = intent.getIntExtra(EXTRA_ID, -1)
        Log.d(TAG, "🔔 onReceive triggered with action: $action, ID: $id")

        // Acquire WakeLock for 10 seconds to ensure screen/CPU stays awake while presenting alarm
        acquireWakeLock(context)

        when (action) {
            ACTION_STOP -> handleStop(context, intent, id)
            ACTION_SNOOZE -> handleSnooze(context, intent, id)
            ACTION_TRIGGER_ALARM, null -> handleTriggerAlarm(context, intent, id)
            else -> {
                // If ID is valid, trigger alarm
                if (id > 0) {
                    handleTriggerAlarm(context, intent, id)
                } else {
                    Log.d(TAG, "Ignoring non-alarm broadcast: $action")
                }
            }
        }
    }

    private fun acquireWakeLock(context: Context) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = pm?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "DailyPlanner:AlarmWakeLock"
            )
            wakeLock?.acquire(10 * 1000L) // 10 seconds
        } catch (e: Exception) {
            Log.e(TAG, "Error acquiring WakeLock", e)
        }
    }

    private fun handleTriggerAlarm(context: Context, intent: Intent, id: Int) {
        if (id <= 0) {
            Log.w(TAG, "Invalid alarm ID: $id, skipping notification")
            return
        }

        createNotificationChannel(context)

        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Daily Planner Reminder"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "You have a scheduled reminder!"
        val payload = intent.getStringExtra(EXTRA_PAYLOAD)

        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        // 1. STOP Action PendingIntent
        val stopIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_STOP
            putExtra(EXTRA_ID, id)
        }
        val stopPending = PendingIntent.getBroadcast(
            context,
            id + 10000,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 2. SNOOZE Action PendingIntent (+5 mins)
        val snoozeIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_SNOOZE
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_PAYLOAD, payload)
        }
        val snoozePending = PendingIntent.getBroadcast(
            context,
            id + 20000,
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 3. TAP / FULL-SCREEN Intent
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_PAYLOAD, payload)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val tapPending = PendingIntent.getActivity(
            context,
            id,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(tapPending)
            .setAutoCancel(true)
            .setOngoing(false)
            .setSound(alarmUri)
            .setVibrate(longArrayOf(0, 1000, 500, 1000, 500, 1000))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(tapPending, true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)
            .addAction(android.R.drawable.ic_media_play, "Snooze 5m", snoozePending)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(id, notification)
            Log.d(TAG, "✅ Alarm notification posted successfully for ID: $id ($title)")
        } catch (e: SecurityException) {
            Log.e(TAG, "POST_NOTIFICATIONS permission not granted", e)
        } catch (e: Exception) {
            Log.e(TAG, "Error posting notification for ID: $id", e)
        }
    }

    private fun handleStop(context: Context, intent: Intent, id: Int) {
        if (id > 0) {
            NotificationManagerCompat.from(context).cancel(id)
            AlarmStorage.removeAlarm(context, id)
            Log.d(TAG, "🛑 Alarm stopped and dismissed for ID: $id")
        }
    }

    private fun handleSnooze(context: Context, intent: Intent, id: Int) {
        if (id <= 0) return

        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Daily Planner Reminder"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "Reminder"
        val payload = intent.getStringExtra(EXTRA_PAYLOAD)

        // Cancel current notification
        NotificationManagerCompat.from(context).cancel(id)

        // Reschedule 5 minutes later
        val snoozeTime = System.currentTimeMillis() + 5 * 60 * 1000L
        AlarmScheduler.scheduleAlarm(
            context = context,
            id = id,
            timeInMillis = snoozeTime,
            title = "[Snoozed] $title",
            body = body,
            payload = payload,
            saveToStorage = true
        )

        Log.d(TAG, "💤 Alarm ID $id snoozed by 5 minutes to $snoozeTime")
    }
}
