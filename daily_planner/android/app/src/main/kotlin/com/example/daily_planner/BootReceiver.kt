package com.example.daily_planner

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d(TAG, "📱 BootReceiver triggered with action: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON" ||
            action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_TIMEZONE_CHANGED
        ) {
            // Re-create notification channel
            AlarmReceiver.createNotificationChannel(context)

            // Reschedule all future saved alarms
            AlarmScheduler.rescheduleAllAlarms(context)

            // Ensure background service is running if needed
            try {
                AlarmForegroundService.start(context)
            } catch (e: Exception) {
                Log.w(TAG, "Could not start AlarmForegroundService on boot: ${e.message}")
            }

            Log.d(TAG, "✅ Device boot/restart handled: all alarms restored and re-armed successfully")
        }
    }
}
