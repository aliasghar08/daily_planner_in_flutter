package com.example.daily_planner

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

fun scheduleAlarm(
    context: Context,
    id: Int,
    timeInMillis: Long,
    title: String,
    body: String
) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    val intent = Intent(context, AlarmReceiver::class.java).apply {
        putExtra("title", title)
        putExtra("body", body)
    }

    val pendingIntent = PendingIntent.getBroadcast(
        context,
        id,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            timeInMillis,
            pendingIntent
        )
    } else {
        alarmManager.setExact(
            AlarmManager.RTC_WAKEUP,
            timeInMillis,
            pendingIntent
        )
    }
}
