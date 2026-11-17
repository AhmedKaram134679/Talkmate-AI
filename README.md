# TalkMate AI

A secure, intelligent, multi-platform real-time communication application built with **Flutter**, **Supabase**, **WebRTC**, and **Firebase**.

---

## 🌟 Key Features

- **Real-Time Messaging**: High-performance text chat, media sharing (images, videos, audio notes, documents), and rich emoji reactions.
- **Crystal-Clear Calls**: End-to-end peer-to-peer audio and video calls powered by WebRTC with custom native Android and Windows audio pipeline hardening.
- **AI-Powered Routing & Push Notifications**: Adaptive notification delivery powered by Supabase Edge Functions with quiet hours, device attention scoring, and multi-device arbitration.
- **Enterprise Security**: Row Level Security (RLS) across all database models, private Supabase Storage buckets with short-lived signed URLs, and zero hardcoded secrets.
- **Offline First**: Resilient local SQLite cache, automatic sync conflict resolution, and background message queueing.

---

## 🏗️ Architecture & Tech Stack

- **Client Framework**: Flutter `>=3.27.0` (Dart SDK `>=3.27.0 <4.0.0`)
- **State Management**: GetX (Controllers, Bindings, Dependency Injection)
- **Backend & Database**: Supabase (PostgreSQL, Realtime, Auth, Storage, Edge Functions)
- **VoIP & Video**: WebRTC (custom native Android audio sinks + `dart_webrtc`)
- **Push Notifications**: Firebase Cloud Messaging (FCM) & Web Push (VAPID)
- **Android Configuration**:
  - Namespace / Application ID: `com.talkmate.ai`
  - Compile SDK: `36` (Target SDK `36`, Min SDK `23`)
  - Toolchain: JDK 17, Kotlin 2.1.0, AGP 8.9.1
  - ProGuard/R8: Fully enabled with customized keep rules for WebRTC, Firebase, and TalkMate native services.

---

## 🚀 Getting Started

### 1. Prerequisites
- **Flutter SDK**: `>= 3.27.0`
- **Dart SDK**: `>= 3.27.0`
- **Java Development Kit**: JDK 17
- **Android Studio** / **VS Code** with Flutter & Dart extensions

### 2. Environment Configuration
Create an `.env` or configure runtime values for Supabase and Firebase:
```properties
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-supabase-publishable-key
```

For Android production release builds, copy the template and configure your keystore:
```powershell
cp android/key.properties.example android/key.properties
```

### 3. Installation & Run
```powershell
# Get dependencies
flutter pub get

# Run static code analysis
flutter analyze

# Launch application (Debug)
flutter run
```

### 4. Production Release Build
```powershell
# Build signed Android App Bundle (AAB)
flutter build appbundle --release

# Build signed Android APK
flutter build apk --release
```

---

## 🛡️ Security & Privacy

- **Private Storage**: Storage files are private (`public = false`) and accessed via temporary 24-hour signed URLs.
- **Row-Level Security**: Every table enforces strict authentication ownership guards and participant access limits.
- **Secrets Isolation**: Triggers and edge functions dynamically retrieve keys using Supabase Vault without static repository commits.

---

## 📄 License

Proprietary and confidential. All rights reserved.