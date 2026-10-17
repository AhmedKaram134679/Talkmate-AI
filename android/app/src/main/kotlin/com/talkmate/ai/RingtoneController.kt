package com.talkmate.ai

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log

/**
 * [Constitutional Authority]
 * Sole Owner of the Ringing Lifecycle on Android.
 * Process-Safe Singleton providing audio playback for incoming calls.
 */
object RingtoneController {
    @Volatile
    var isRinging = false
        private set

    private var mediaPlayer: MediaPlayer? = null

    fun start(context: Context) {
        synchronized(this) {
            if (isRinging) {
                Log.d("RingtoneController", "🔔 Already ringing, ignoring duplicate start request.")
                return
            }

            try {
                Log.d("RingtoneController", "🔔 Starting native incoming call ringtone...")
                val resId = context.resources.getIdentifier("call_incomming", "raw", context.packageName)
                if (resId != 0) {
                    mediaPlayer = MediaPlayer.create(context.applicationContext, resId).apply {
                        setAudioAttributes(
                            AudioAttributes.Builder()
                                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                                .build()
                        )
                        isLooping = true
                        start()
                    }
                    isRinging = true
                    Log.d("RingtoneController", "🔔 Native ringtone playback started successfully.")
                } else {
                    Log.w("RingtoneController", "⚠️ raw/call_incomming sound resource not found.")
                    isRinging = true
                }
            } catch (e: Exception) {
                Log.e("RingtoneController", "⚠️ Error starting native ringtone: ${e.message}", e)
                isRinging = true
            }
        }
    }

    fun stop() {
        synchronized(this) {
            try {
                mediaPlayer?.let {
                    if (it.isPlaying) {
                        it.stop()
                    }
                    it.release()
                }
                mediaPlayer = null
                Log.d("RingtoneController", "🛑 Native ringtone stopped and released.")
            } catch (e: Exception) {
                Log.e("RingtoneController", "⚠️ Error stopping ringtone: ${e.message}", e)
            } finally {
                isRinging = false
            }
        }
    }
}
