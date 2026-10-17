package com.talkmate.ai

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.util.Log
// import org.webrtc.voiceengine.WebRtcAudioManager
// import org.webrtc.voiceengine.WebRtcAudioUtils

/**
 * NativeAudioRouter: Manages Android's AudioManager for voice calls.
 * Ensures AudioFocus is gained and audio is routed to the correct device (Speaker/Earpiece).
 */
class NativeAudioRouter(private val context: Context) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val TAG = "NativeAudioRouter"

    fun startCommunication() {
        try {
            // [REPAIR P3]: Single audio owner = flutter_webrtc.
            // The audio MODE (MODE_IN_COMMUNICATION) and audio focus are now owned
            // exclusively by flutter_webrtc's setAndroidAudioConfiguration
            // (manageAudioFocus = true). We intentionally DO NOT set
            // audioManager.mode here anymore to stop the previous three-way mode/
            // focus fight (audio_session + flutter_webrtc + native) that tore down
            // mic capture mid-call. We only keep the harmless hardware routing:
            // ensure the global mic is not hard-muted and default to speaker.
            audioManager.isMicrophoneMute = false
            audioManager.isSpeakerphoneOn = true

            Log.d(TAG, "🔊 Native routing only: Speakerphone ON, Mic UNMUTED (mode/focus owned by flutter_webrtc)")
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Router Error: ${e.message}")
        }
    }

    fun stopCommunication() {
        try {
            audioManager.mode = AudioManager.MODE_NORMAL
            audioManager.isSpeakerphoneOn = false
            Log.d(TAG, "🔇 Mode reset to NORMAL")
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Router Stop Error: ${e.message}")
        }
    }

    fun setSpeakerOn(on: Boolean) {
        audioManager.isSpeakerphoneOn = on
        Log.d(TAG, "🔊 Speakerphone set to: $on")
    }

    fun setVolume(volume: Double) {
        try {
            val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            val index = (volume * maxVolume).toInt()
            audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, index, 0)
            Log.d(TAG, "🔊 Volume set to: $volume (Index: $index/$maxVolume)")
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Set Volume Error: ${e.message}")
        }
    }
}
