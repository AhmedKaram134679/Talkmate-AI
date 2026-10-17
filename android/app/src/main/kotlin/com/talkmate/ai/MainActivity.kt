package com.talkmate.ai

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
    private val CHANNEL = "com.example.talkmate_ai/call_intent"
    private var audioRouter: NativeAudioRouter? = null
    private var pendingCallData: MutableMap<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        audioRouter = NativeAudioRouter(this)
        
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        if (intent.hasExtra("callId")) {
            // Restrict keyguard dismiss and screen-wake strictly to incoming call intents (A4, A9)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
                val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                keyguardManager.requestDismissKeyguard(this, null)
            }

            // Cache call intent data without mutating OS Intent extras (A2, B18)
            val data = mutableMapOf<String, Any?>()
            data["callId"] = intent.getStringExtra("callId")
            data["otherId"] = intent.getStringExtra("otherId")
            data["isIncoming"] = intent.getBooleanExtra("isIncoming", false)
            data["isVideo"] = intent.getBooleanExtra("isVideo", false)
            data["route"] = intent.getStringExtra("route")
            pendingCallData = data
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCallIntent" -> {
                    // Return cached call data if present, or inspect intent
                    if (pendingCallData != null) {
                        result.success(pendingCallData)
                    } else if (intent != null && intent.hasExtra("callId")) {
                        val data = mutableMapOf<String, Any?>()
                        data["callId"] = intent.getStringExtra("callId")
                        data["otherId"] = intent.getStringExtra("otherId")
                        data["isIncoming"] = intent.getBooleanExtra("isIncoming", false)
                        data["isVideo"] = intent.getBooleanExtra("isVideo", false)
                        data["route"] = intent.getStringExtra("route")
                        pendingCallData = data
                        result.success(data)
                    } else {
                        result.success(null)
                    }
                }
                "clearCallIntent" -> {
                    pendingCallData = null
                    intent?.removeExtra("callId")
                    result.success(true)
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
                    val router = audioRouter
                    if (router != null) {
                        router.startCommunication()
                        result.success(true)
                    } else {
                        Log.e("MainActivity", "NativeAudioRouter not ready during prepareAudioIsolation")
                        result.success(false)
                    }
                }
                "setSpeakerOn" -> {
                    val on = call.argument<Boolean>("on") ?: true
                    val router = audioRouter
                    if (router != null) {
                        router.setSpeakerOn(on)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "setVolume" -> {
                    val volume = call.argument<Double>("volume") ?: 0.5
                    val router = audioRouter
                    if (router != null) {
                        router.setVolume(volume)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // Essential for getCallIntent to see the new extras from notification clicks
        handleIntent(intent)
    }
}
