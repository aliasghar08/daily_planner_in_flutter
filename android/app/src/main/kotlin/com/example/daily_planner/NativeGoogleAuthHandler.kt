package com.example.daily_planner

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInAccount
import com.google.android.gms.auth.api.signin.GoogleSignInClient
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NativeGoogleAuthHandler(private val activity: Activity) {

    companion object {
        private const val TAG = "NativeGoogleAuth"
        const val RC_SIGN_IN = 9001
        private const val DEFAULT_WEB_CLIENT_ID = "777337977048-c27q0hjrp8epvon0srnq8mq149nkm746.apps.googleusercontent.com"
    }

    private var pendingResult: MethodChannel.Result? = null
    private var googleSignInClient: GoogleSignInClient? = null

    private fun getClient(clientId: String? = null): GoogleSignInClient {
        val serverClientId = clientId?.takeIf { it.isNotEmpty() } ?: DEFAULT_WEB_CLIENT_ID
        val gso = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
            .requestIdToken(serverClientId)
            .requestEmail()
            .requestProfile()
            .build()
        val client = GoogleSignIn.getClient(activity, gso)
        googleSignInClient = client
        return client
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "signIn" -> {
                val clientId = call.argument<String>("serverClientId")
                startSignIn(clientId, result)
            }
            "signOut" -> {
                signOut(result)
            }
            "getCurrentUser" -> {
                getCurrentUser(result)
            }
            "disconnect" -> {
                disconnect(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startSignIn(clientId: String?, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("ALREADY_IN_PROGRESS", "Google sign-in already in progress", null)
            return
        }

        try {
            pendingResult = result
            val client = getClient(clientId)
            val signInIntent = client.signInIntent
            activity.startActivityForResult(signInIntent, RC_SIGN_IN)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start Google sign-in intent", e)
            pendingResult = null
            result.error("SIGN_IN_FAILED", e.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == RC_SIGN_IN) {
            val result = pendingResult
            pendingResult = null

            if (result == null) return true

            try {
                val task = GoogleSignIn.getSignedInAccountFromIntent(data)
                val account = task.getResult(ApiException::class.java)
                if (account != null) {
                    val map = accountToMap(account)
                    result.success(map)
                } else {
                    result.error("SIGN_IN_CANCELLED", "User cancelled or sign-in failed", null)
                }
            } catch (e: ApiException) {
                Log.w(TAG, "Google sign-in failed with status code: ${e.statusCode} message: ${e.message}")
                result.error("SIGN_IN_API_ERROR_${e.statusCode}", e.message, null)
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error in Google sign-in", e)
                result.error("SIGN_IN_ERROR", e.message, null)
            }
            return true
        }
        return false
    }

    private fun signOut(result: MethodChannel.Result) {
        try {
            val client = googleSignInClient ?: getClient()
            client.signOut().addOnCompleteListener(activity) {
                result.success(true)
            }.addOnFailureListener(activity) { e ->
                Log.w(TAG, "Sign out error: ${e.message}")
                result.success(false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to sign out", e)
            result.error("SIGN_OUT_ERROR", e.message, null)
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        try {
            val client = googleSignInClient ?: getClient()
            client.revokeAccess().addOnCompleteListener(activity) {
                result.success(true)
            }.addOnFailureListener(activity) { e ->
                result.error("DISCONNECT_ERROR", e.message, null)
            }
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", e.message, null)
        }
    }

    private fun getCurrentUser(result: MethodChannel.Result) {
        try {
            val account = GoogleSignIn.getLastSignedInAccount(activity)
            if (account != null) {
                result.success(accountToMap(account))
            } else {
                result.success(null)
            }
        } catch (e: Exception) {
            result.error("GET_USER_ERROR", e.message, null)
        }
    }

    private fun accountToMap(account: GoogleSignInAccount): Map<String, Any?> {
        return mapOf(
            "id" to account.id,
            "idToken" to account.idToken,
            "email" to account.email,
            "displayName" to account.displayName,
            "givenName" to account.givenName,
            "familyName" to account.familyName,
            "photoUrl" to account.photoUrl?.toString(),
            "serverAuthCode" to account.serverAuthCode
        )
    }
}
