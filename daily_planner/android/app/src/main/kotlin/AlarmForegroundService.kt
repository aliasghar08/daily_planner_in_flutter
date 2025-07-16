package com.example.daily_planner

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AlarmForegroundService : Service() {

    override fun onCreate() {
        super.onCreate()
        startForegroundServiceWithNotification()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // If there's additional logic to process in the future, handle it here
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun startForegroundServiceWithNotification() {
        val channelId = AlarmReceiver.CHANNEL_ID
        val channelName = AlarmReceiver.CHANNEL_NAME

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Foreground service for keeping alarms alive"
            }

            getSystemService(NotificationManager::class.java)?.createNotificationChannel(serviceChannel)
        }

        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Daily Planner")
            .setContentText("Alarm service is running")
            .setSmallIcon(applicationInfo?.icon ?: android.R.drawable.ic_lock_idle_alarm)
            .setContentIntent(pendingIntent)
            .build()

        startForeground(1, notification)
    }
}
