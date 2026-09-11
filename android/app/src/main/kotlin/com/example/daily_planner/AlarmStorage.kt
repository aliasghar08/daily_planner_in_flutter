package com.example.daily_planner

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONObject

data class AlarmItem(
    val id: Int,
    val title: String,
    val body: String,
    val timeInMillis: Long,
    val payload: String? = null,
    val createdAt: Long = System.currentTimeMillis()
) {
    fun toJson(): String {
        val json = JSONObject()
        json.put("id", id)
        json.put("title", title)
        json.put("body", body)
        json.put("timeInMillis", timeInMillis)
        json.put("payload", payload ?: "")
        json.put("createdAt", createdAt)
        return json.toString()
    }

    companion object {
        fun fromJson(jsonStr: String): AlarmItem? {
            return try {
                val json = JSONObject(jsonStr)
                AlarmItem(
                    id = json.getInt("id"),
                    title = json.optString("title", "Daily Planner"),
                    body = json.optString("body", "You have a scheduled reminder"),
                    timeInMillis = json.getLong("timeInMillis"),
                    payload = json.optString("payload", null),
                    createdAt = json.optLong("createdAt", System.currentTimeMillis())
                )
            } catch (e: Exception) {
                Log.e("AlarmStorage", "Error parsing AlarmItem JSON: $jsonStr", e)
                null
            }
        }
    }
}

object AlarmStorage {
    private const val PREFS_NAME = "daily_planner_native_alarms"
    private const val TAG = "AlarmStorage"

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun saveAlarm(context: Context, alarm: AlarmItem) {
        try {
            val prefs = getPrefs(context)
            prefs.edit().putString(alarm.id.toString(), alarm.toJson()).apply()
            Log.d(TAG, "Saved alarm to persistent storage: ID=${alarm.id}, time=${alarm.timeInMillis}, title=${alarm.title}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save alarm ID=${alarm.id}", e)
        }
    }

    fun removeAlarm(context: Context, id: Int) {
        try {
            val prefs = getPrefs(context)
            prefs.edit().remove(id.toString()).apply()
            Log.d(TAG, "Removed alarm from persistent storage: ID=$id")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove alarm ID=$id", e)
        }
    }

    fun getAlarm(context: Context, id: Int): AlarmItem? {
        val prefs = getPrefs(context)
        val jsonStr = prefs.getString(id.toString(), null) ?: return null
        return AlarmItem.fromJson(jsonStr)
    }

    fun getAllAlarms(context: Context): List<AlarmItem> {
        val alarms = mutableListOf<AlarmItem>()
        try {
            val prefs = getPrefs(context)
            for ((_, value) in prefs.all) {
                if (value is String) {
                    val item = AlarmItem.fromJson(value)
                    if (item != null) {
                        alarms.add(item)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get all alarms", e)
        }
        return alarms
    }

    fun clearExpired(context: Context, currentTime: Long = System.currentTimeMillis()) {
        try {
            val prefs = getPrefs(context)
            val editor = prefs.edit()
            for ((key, value) in prefs.all) {
                if (value is String) {
                    val item = AlarmItem.fromJson(value)
                    // If alarm is older than 10 minutes in the past, clean it up
                    if (item != null && item.timeInMillis < (currentTime - 10 * 60 * 1000)) {
                        editor.remove(key)
                        Log.d(TAG, "Cleaned up expired alarm: ID=${item.id}")
                    }
                }
            }
            editor.apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear expired alarms", e)
        }
    }

    fun clearAll(context: Context) {
        try {
            val prefs = getPrefs(context)
            prefs.edit().clear().apply()
            Log.d(TAG, "Cleared all alarms from storage")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear all alarms", e)
        }
    }
}
