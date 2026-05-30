package com.example.talkmate_ai

import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class CustomFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        // Log basic message info safely
        val from = remoteMessage.from
        Log.d("CustomFCM", "Message received from: $from")

        val data: Map<String, String> = remoteMessage.data
        val type: String? = data["type"]

        if (type == "INCOMING_CALL") {
            Log.d("CustomFCM", "Incoming call detected, starting CallForegroundService")
            startCallService(data)
        } else {
            // Forward other messages to Flutter via the default plugin mechanism
            Log.d("CustomFCM", "Handover to FlutterFirebaseMessagingService for type: $type")
            try {
                // Delegate to the original Flutter FCM service
                val flutterService = io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService()
                flutterService.onMessageReceived(remoteMessage)
            } catch (e: Exception) {
                Log.e("CustomFCM", "Failed to delegate to Flutter service", e)
            }
        }
    }

    private fun startCallService(data: Map<String, String>) {
        val intent = Intent(this, CallForegroundService::class.java).apply {
            action = CallForegroundService.ACTION_START_RINGING
            putExtra("call_id", data["call_id"])
            putExtra("sender_id", data["sender_id"])
            putExtra("caller_name", data["caller_name"])
            putExtra("is_video", data["is_video"] == "true")
            putExtra("route", "/call_ringing") 
        }
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("CustomFCM", "New token generated: $token")
        
        // Also delegate token to Flutter service to ensure it's synced with Supabase/FCM
        try {
            val flutterService = io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService()
            flutterService.onNewToken(token)
        } catch (e: Exception) {
            Log.e("CustomFCM", "Failed to delegate token to Flutter service", e)
        }
    }
}
