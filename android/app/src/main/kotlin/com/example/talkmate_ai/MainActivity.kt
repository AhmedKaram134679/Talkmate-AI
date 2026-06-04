package com.example.talkmate_ai

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import org.webrtc.AudioTrack

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        audioRouter = NativeAudioRouter(this)
        
        // Constitutional Rule 4: Programmatic Lockscreen bypass (for Android 8.0+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        }
    }

    private val CHANNEL = "com.example.talkmate_ai/call_intent"
    private var audioRouter: NativeAudioRouter? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCallIntent" -> {
                    val intent = intent
                    val data = mutableMapOf<String, Any?>()
                    
                    if (intent != null && intent.hasExtra("callId")) {
                        data["callId"] = intent.getStringExtra("callId")
                        data["otherId"] = intent.getStringExtra("otherId")
                        data["isIncoming"] = intent.getBooleanExtra("isIncoming", false)
                        data["isVideo"] = intent.getBooleanExtra("isVideo", false)
                        data["route"] = intent.getStringExtra("route")
                        
                        // Clear the extras so they don't get processed again if the app is resumed
                        intent.removeExtra("callId")
                        result.success(data)
                    } else {
                        result.success(null)
                    }
                }
                "stopRingtone" -> {
                    // Legacy support
                    RingtoneController.stop()
                    val stopIntent = Intent(this, CallForegroundService::class.java)
                    stopIntent.action = CallForegroundService.ACTION_STOP_SERVICE
                    startService(stopIntent)
                    result.success(true)
                }
                "stopIncomingScreen" -> {
                    RingtoneController.stop()
                    val stopIntent = Intent(this, CallForegroundService::class.java)
                    stopIntent.action = CallForegroundService.ACTION_STOP_SERVICE
                    startService(stopIntent)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // [NATIVE_AUDIO_HARDENING]: Professional PCM Sink Channel (Simplified)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.talkmate_ai/native_audio").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareAudioIsolation" -> {
                    audioRouter?.startCommunication()
                    result.success(true)
                }
                "setSpeakerOn" -> {
                    val on = call.argument<Boolean>("on") ?: true
                    audioRouter?.setSpeakerOn(on)
                    result.success(true)
                }
                "setVolume" -> {
                    val volume = call.argument<Double>("volume") ?: 0.5
                    audioRouter?.setVolume(volume)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // Essential for getCallIntent to see the new extras from notification clicks
    }
}
