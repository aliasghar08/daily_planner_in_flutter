package com.example.daily_planner

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class NativePreferencesHandler(private val context: Context) {

    companion object {
        private const val TAG = "NativePrefs"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"
    }

    private val sharedPreferences: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getAll" -> {
                    val all = sharedPreferences.all
                    val resultMap = mutableMapOf<String, Any?>()

                    for ((key, rawValue) in all) {
                        if (rawValue is String && rawValue.startsWith(LIST_PREFIX)) {
                            // Decode string list
                            val jsonString = rawValue.substring(LIST_PREFIX.length)
                            try {
                                val jsonArray = JSONArray(jsonString)
                                val list = mutableListOf<String>()
                                for (i in 0 until jsonArray.length()) {
                                    list.add(jsonArray.getString(i))
                                }
                                resultMap[key] = list
                            } catch (e: Exception) {
                                resultMap[key] = rawValue
                            }
                        } else {
                            resultMap[key] = rawValue
                        }
                    }
                    result.success(resultMap)
                }

                "setString" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<String>("value")
                    if (key != null && value != null) {
                        val success = sharedPreferences.edit().putString(key, value).commit()
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGS", "Key and value must not be null", null)
                    }
                }

                "setBool" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<Boolean>("value")
                    if (key != null && value != null) {
                        val success = sharedPreferences.edit().putBoolean(key, value).commit()
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGS", "Key and value must not be null", null)
                    }
                }

                "setInt" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<Number>("value")
                    if (key != null && value != null) {
                        val success = sharedPreferences.edit().putLong(key, value.toLong()).commit()
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGS", "Key and value must not be null", null)
                    }
                }

                "setDouble" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<Double>("value")
                    if (key != null && value != null) {
                        // Store as Float or String
                        val success = sharedPreferences.edit().putString(key, value.toString()).commit()
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGS", "Key and value must not be null", null)
                    }
                }

                "setStringList" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<List<String>>("value")
                    if (key != null && value != null) {
                        val jsonArray = JSONArray(value)
                        val storedValue = LIST_PREFIX + jsonArray.toString()
                        val success = sharedPreferences.edit().putString(key, storedValue).commit()
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGS", "Key and value must not be null", null)
                    }
                }

                "remove" -> {
                    val key = call.argument<String>("key")
                    if (key != null) {
                        val success = sharedPreferences.edit().remove(key).commit()
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGS", "Key must not be null", null)
                    }
                }

                "clear" -> {
                    val success = sharedPreferences.edit().clear().commit()
                    result.success(success)
                }

                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in method ${call.method}", e)
            result.error("PREFS_ERROR", e.message, null)
        }
    }
}
