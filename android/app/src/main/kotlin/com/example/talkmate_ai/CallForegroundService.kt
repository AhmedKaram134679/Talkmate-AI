package com.example.talkmate_ai

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class CallForegroundService : Service() {

    companion object {
        const val ACTION_START_RINGING = "ACTION_START_RINGING"
        const val ACTION_START_ACTIVE_CALL = "ACTION_START_ACTIVE_CALL"
        const val ACTION_STOP_SERVICE = "ACTION_STOP_SERVICE"

        private const val CHANNEL_RINGING = "calls_ringing_v1"
        private const val CHANNEL_ACTIVE = "calls_active_v1"
        
        private const val NOTIFICATION_ID_RINGING = 2024
        private const val NOTIFICATION_ID_ACTIVE = 2025
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_NOT_STICKY
        val callId = intent.getStringExtra("call_id") ?: "unknown"
        val senderId = intent.getStringExtra("sender_id") ?: "unknown"
        val callerName = intent.getStringExtra("caller_name") ?: "TalkMate User"
        val isVideo = intent.getBooleanExtra("is_video", false)

        Log.d("CallService", "Command received: $action for call $callId")

        when (action) {
            ACTION_START_RINGING -> handleStartRinging(callerName, isVideo, callId, senderId)
            ACTION_START_ACTIVE_CALL -> handleStartActive(callerName, isVideo, callId, senderId)
            ACTION_STOP_SERVICE -> stopSelf()
        }

        return START_NOT_STICKY
    }

    private fun handleStartRinging(callerName: String, isVideo: Boolean, callId: String, senderId: String) {
        createRingingChannel()
        
        // Ensure Active Notification is hidden if present
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID_ACTIVE)

        val notification = buildRingingNotification(callerName, isVideo, callId, senderId)
        
        startForegroundSafe(NOTIFICATION_ID_RINGING, notification)
        
        // RingtoneController is the SOLE authority.
        RingtoneController.start(this)
    }

    private fun handleStartActive(callerName: String, isVideo: Boolean, callId: String, senderId: String) {
        createActiveChannel()
        
        // Stop Ringtone explicitly
        RingtoneController.stop()

        // Cancel Ringing Notification
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID_RINGING)

        val notification = buildActiveNotification(callerName, isVideo, callId, senderId)

        // Switch Foreground Service to Active ID
        startForegroundSafe(NOTIFICATION_ID_ACTIVE, notification)
    }

    private fun startForegroundSafe(id: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
        } else {
            startForeground(id, notification)
        }
    }

    private fun createRingingChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_RINGING,
                "Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming call notifications"
                setSound(null, null) 
                enableLights(true)
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun createActiveChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ACTIVE,
                "Active Calls",
                NotificationManager.IMPORTANCE_DEFAULT // Lower importance for active calls
            ).apply {
                description = "Ongoing active call"
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildRingingNotification(callerName: String, isVideo: Boolean, callId: String, senderId: String): Notification {
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("route", "/call_ringing") 
            putExtra("callId", callId)
            putExtra("otherId", senderId)
            putExtra("isIncoming", true)
            putExtra("isVideo", isVideo)
        }
        
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this, 1001, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_RINGING)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Incoming Call")
            .setContentText("$callerName is calling...")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun buildActiveNotification(callerName: String, isVideo: Boolean, callId: String, senderId: String): Notification {
        val activeIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP // Just bring to front
        }
        
        val activePendingIntent = PendingIntent.getActivity(
            this, 1002, activeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action to hang up (communicated via broadcast to Flutter or another service - simplification for now)
        // For now, tapping notification opens app
        return NotificationCompat.Builder(this, CHANNEL_ACTIVE)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Ongoing Call")
            .setContentText("Talking with $callerName")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setContentIntent(activePendingIntent)
            .setOngoing(true) // Cannot be swiped away
            .setUsesChronometer(true)
            .build()
    }

    override fun onDestroy() {
        Log.d("CallService", "Service Destroyed - Stopping Ringtone")
        RingtoneController.stop()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
