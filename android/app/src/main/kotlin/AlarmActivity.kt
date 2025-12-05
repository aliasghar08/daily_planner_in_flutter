package com.example.daily_planner

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.widget.LinearLayout

class AlarmActivity : Activity() {

    private lateinit var ringtone: Ringtone

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Simple layout with stop/snooze (you can customize)
        val stopButton = Button(this).apply { text = "Stop" }
        val snoozeButton = Button(this).apply { text = "Snooze 5 min" }

        stopButton.setOnClickListener {
            ringtone.stop()
            finish()
        }

        snoozeButton.setOnClickListener {
            ringtone.stop()
            // TODO: Implement snooze by rescheduling alarm via MethodChannel
            finish()
        }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(stopButton)
            addView(snoozeButton)
        }

        setContentView(layout)

        // Play default alarm
        val alarmUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        ringtone = RingtoneManager.getRingtone(applicationContext, alarmUri)
        ringtone.play()
    }
}
