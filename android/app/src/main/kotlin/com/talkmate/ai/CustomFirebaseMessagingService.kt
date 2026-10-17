package com.talkmate.ai

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class CustomFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data: Map<String, String> = remoteMessage.data
        val type: String? = data["type"]

        if (type == "INCOMING_CALL") {
            Log.d("CustomFCM", "Incoming call push detected, launching CallForegroundService")
            startCallServiceWithFallback(data)
        } else {
            // For standard messages, FCM SDK automatically handles notification payloads
            // when in background, and flutter_local_notifications handles foreground dispatch
            Log.d("CustomFCM", "Handled non-call FCM message type: $type")
        }
    }

    private fun startCallServiceWithFallback(data: Map<String, String>) {
        val callId = data["call_id"] ?: "unknown"
        val senderId = data["sender_id"] ?: "unknown"
        val callerName = data["caller_name"] ?: "TalkMate User"
        val isVideo = data["is_video"] == "true"

        val intent = Intent(this, CallForegroundService::class.java).apply {
            action = CallForegroundService.ACTION_START_RINGING
            putExtra("call_id", callId)
            putExtra("sender_id", senderId)
            putExtra("caller_name", callerName)
            putExtra("is_video", isVideo)
            putExtra("route", "/call_ringing")
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.e("CustomFCM", "Failed to start CallForegroundService: ${e.message}, falling back to direct full-screen notification", e)
            showFallbackIncomingCallNotification(callerName, isVideo, callId, senderId)
        }
    }

    private fun showFallbackIncomingCallNotification(callerName: String, isVideo: Boolean, callId: String, senderId: String) {
        try {
            val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("route", "/call_ringing")
                putExtra("callId", callId)
                putExtra("otherId", senderId)
                putExtra("isIncoming", true)
                putExtra("isVideo", isVideo)
            }

            val pendingIntent = PendingIntent.getActivity(
                this, 1001, fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val channelId = "calls_ringing_v1"
            val notification = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Incoming Call")
                .setContentText("$callerName is calling...")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setFullScreenIntent(pendingIntent, true)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(2024, notification)
        } catch (ex: Exception) {
            Log.e("CustomFCM", "Fallback notification failed: ${ex.message}", ex)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // [A7]: Token sanitized - never log raw FCM token to logcat
        Log.d("CustomFCM", "FCM onNewToken invoked successfully.")
    }
}
