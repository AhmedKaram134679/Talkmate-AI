# ProGuard / R8 Rules for TalkMate AI

# --- Flutter Wrapper & Engine ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.**  { *; }

# --- WebRTC Native SDK & JNI ---
-keep class org.webrtc.** { *; }
-keep interface org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keepclasseswithmembernames class org.webrtc.** {
    native <methods>;
}

# --- TalkMate AI Custom Native Audio & Services ---
-keep class com.talkmate.ai.** { *; }
-keepclassmembers class com.talkmate.ai.** { *; }
-dontwarn com.talkmate.ai.**

# --- Firebase & Google Play Services ---
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# --- Kotlin Coroutines & Serialization ---
-dontwarn kotlinx.coroutines.**
-keepclassmembers class kotlinx.coroutines.** { *; }

# --- Play Core / Deferred Components (Not used) ---
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
