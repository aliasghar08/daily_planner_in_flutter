package com.example.daily_planner

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "daily_planner_service_channel"
        const val NOTIF_ID = 99991
        private const val TAG = "AlarmForegroundService"

        fun start(context: Context) {
            try {
                val intent = Intent(context, AlarmForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "Foreground service start requested")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting foreground service: ${e.message}")
            }
        }

        fun stop(context: Context) {
            try {
                val intent = Intent(context, AlarmForegroundService::class.java)
                context.stopService(intent)
                Log.d(TAG, "Foreground service stopped")
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping foreground service: ${e.message}")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Daily Planner Service",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Keeps alarm service active"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Daily Planner")
            .setContentText("Alarm service active in background")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
