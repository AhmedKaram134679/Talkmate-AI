package com.example.talkmate_ai

import android.content.Context
import android.util.Log

/**
 * [Constitutional Authority]
 * Sole Owner of the Ringing Lifecycle.
 * Process-Safe Singleton.
 *
 * [AUDIT]: System Audio Disabled.
 * All ringing is strictly handled by AppAudioService (Dart side) via assets.
 */
object RingtoneController {
    @Volatile
    var isRinging = false
        private set

    fun start(context: Context) {
        synchronized(this) {
           Log.d("RingtoneController", "🔔 Start request received, but NATIVE playback is DISABLED (Strict AppAudioService Enforcement).")
           isRinging = true
        }
    }

    fun stop() {
        synchronized(this) {
            Log.d("RingtoneController", "🛑 Stop request received (State updated).")
            isRinging = false
        }
    }
}
