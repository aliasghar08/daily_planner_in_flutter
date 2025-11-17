package com.example.daily_planner

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_ID = "daily_planner_channel"
        const val CHANNEL_NAME = "Daily Planner"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_ID = "id"

        const val ACTION_STOP = "daily_planner.STOP"
        const val ACTION_SNOOZE = "daily_planner.SNOOZE"

        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    enableLights(true)
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                    setSound(alarmSound, attrs)
                    description = "Daily Planner alarm notifications"
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                }

                val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
                nm?.createNotificationChannel(channel)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "Triggered: ${intent.action}")

        when (intent.action) {
            ACTION_STOP -> handleStop(context, intent)
            ACTION_SNOOZE -> handleSnooze(context, intent)
            else -> showNotification(context, intent)
        }
    }

    private fun showNotification(context: Context, intent: Intent) {
        createNotificationChannel(context)

        val id = intent.getIntExtra(EXTRA_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Reminder"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "You have a reminder!"

        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

        // Stop action
        val stopIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_STOP
            putExtra(EXTRA_ID, id)
        }
        val stopPending = PendingIntent.getBroadcast(
            context, id + 1000, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Snooze action
        val snoozeIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_SNOOZE
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
        }
        val snoozePending = PendingIntent.getBroadcast(
            context, id + 2000, snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Full-screen intent → opens MainActivity
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("alarm_id", id)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val tapPending = PendingIntent.getActivity(
            context, id, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(tapPending)
            .setAutoCancel(false)
            .setOngoing(true) // prevent dismissal
            .setSound(alarmUri)
            .setVibrate(longArrayOf(0, 1000, 500, 1000, 500, 1000))
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPending)
            .addAction(android.R.drawable.ic_media_play, "Snooze", snoozePending)
            .setPriority(NotificationCompat.PRIORITY_MAX) // highest priority
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(tapPending, true) // triggers full-screen alarm
            .build()

        val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
        nm?.notify(id, notification)

        Log.d("AlarmReceiver", "Notification displayed with ID: $id")
    }

    private fun handleStop(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, -1)
        if (id != -1) {
            val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
            nm?.cancel(id)
            Log.d("AlarmReceiver", "Alarm stopped for $id")
        }
    }

    private fun handleSnooze(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, -1)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Reminder"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "Reminder"

        if (id == -1) return

        val snoozeTime = System.currentTimeMillis() + 5 * 60 * 1000 // 5 minutes
        scheduleAlarm(context, id + 9999, title, body, snoozeTime)

        val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
        nm?.cancel(id)

        Log.d("AlarmReceiver", "Alarm snoozed for ID $id by 5 minutes")
    }

    private fun scheduleAlarm(context: Context, id: Int, title: String, body: String, time: Long) {
        val am = ContextCompat.getSystemService(context, AlarmManager::class.java) ?: return

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        am.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            time,
            pendingIntent
        )

        Log.d("AlarmReceiver", "Scheduled alarm ID $id at $time")
    }
}
