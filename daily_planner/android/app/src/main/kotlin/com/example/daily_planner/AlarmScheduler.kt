package com.example.daily_planner

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationManagerCompat

object AlarmScheduler {
    private const val TAG = "AlarmScheduler"

    fun scheduleAlarm(
        context: Context,
        id: Int,
        timeInMillis: Long,
        title: String,
        body: String,
        payload: String? = null,
        saveToStorage: Boolean = true
    ): Boolean {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            if (alarmManager == null) {
                Log.e(TAG, "AlarmManager service not available")
                return false
            }

            // Save to persistent storage so it survives app kill and phone reboot
            if (saveToStorage) {
                val alarmItem = AlarmItem(
                    id = id,
                    title = title,
                    body = body,
                    timeInMillis = timeInMillis,
                    payload = payload
                )
                AlarmStorage.saveAlarm(context, alarmItem)
            }

            // Ensure notification channel is created
            AlarmReceiver.createNotificationChannel(context)

            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = AlarmReceiver.ACTION_TRIGGER_ALARM
                putExtra(AlarmReceiver.EXTRA_ID, id)
                putExtra(AlarmReceiver.EXTRA_TITLE, title)
                putExtra(AlarmReceiver.EXTRA_BODY, body)
                putExtra(AlarmReceiver.EXTRA_PAYLOAD, payload)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Intent for when user taps the alarm clock icon in lock screen
            val showIntent = Intent(context, MainActivity::class.java).apply {
                putExtra(AlarmReceiver.EXTRA_ID, id)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val showPendingIntent = PendingIntent.getActivity(
                context,
                id + 50000,
                showIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Use setAlarmClock for highest reliability (guarantees wakeup through Doze Mode)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val alarmClockInfo = AlarmManager.AlarmClockInfo(timeInMillis, showPendingIntent)
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
                Log.d(TAG, "⏰ Alarm scheduled via setAlarmClock: ID=$id at time=$timeInMillis ($title)")
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timeInMillis,
                    pendingIntent
                )
                Log.d(TAG, "⏰ Alarm scheduled via setExactAndAllowWhileIdle: ID=$id at time=$timeInMillis ($title)")
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    timeInMillis,
                    pendingIntent
                )
                Log.d(TAG, "⏰ Alarm scheduled via setExact: ID=$id at time=$timeInMillis ($title)")
            }

            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule alarm ID=$id", e)
            return false
        }
    }

    fun cancelAlarm(context: Context, id: Int): Boolean {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = AlarmReceiver.ACTION_TRIGGER_ALARM
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (alarmManager != null) {
                alarmManager.cancel(pendingIntent)
            }
            pendingIntent.cancel()

            // Remove from persistent storage
            AlarmStorage.removeAlarm(context, id)

            // Cancel any displayed notification with this ID
            NotificationManagerCompat.from(context).cancel(id)

            Log.d(TAG, "Cancelled alarm and notification: ID=$id")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel alarm ID=$id", e)
            return false
        }
    }

    fun cancelAllAlarms(context: Context): Boolean {
        try {
            val alarms = AlarmStorage.getAllAlarms(context)
            for (alarm in alarms) {
                cancelAlarm(context, alarm.id)
            }
            AlarmStorage.clearAll(context)
            Log.d(TAG, "Cancelled all alarms (${alarms.size} total)")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel all alarms", e)
            return false
        }
    }

    fun rescheduleAllAlarms(context: Context) {
        try {
            val currentTime = System.currentTimeMillis()
            AlarmStorage.clearExpired(context, currentTime)

            val alarms = AlarmStorage.getAllAlarms(context)
            Log.d(TAG, "🔄 Rescheduling ${alarms.size} alarms after boot/event...")

            var count = 0
            for (alarm in alarms) {
                if (alarm.timeInMillis > currentTime) {
                    scheduleAlarm(
                        context = context,
                        id = alarm.id,
                        timeInMillis = alarm.timeInMillis,
                        title = alarm.title,
                        body = alarm.body,
                        payload = alarm.payload,
                        saveToStorage = false // already saved in storage
                    )
                    count++
                } else {
                    // Passed time, remove
                    AlarmStorage.removeAlarm(context, alarm.id)
                }
            }
            Log.d(TAG, "✅ Successfully re-armed $count active future alarms")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reschedule alarms", e)
        }
    }
}
