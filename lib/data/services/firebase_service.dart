import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/firebase_options.dart';

/// خدمة تهيئة Firebase متعددة المنصات
/// تُستدعى مرة واحدة في بداية التطبيق.
class FirebaseService {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  /// تهيئة Firebase بشكل آمن حسب المنصة.
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Check if Firebase is already initialized
      if (Firebase.apps.isNotEmpty) {
        _initialized = true;
        return;
      }

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') {
        _initialized = true;
        return;
      }
      debugPrint('Firebase initialization failed: ${e.code} - ${e.message}');
      _initialized = false;
    } on UnsupportedError catch (e) {
      debugPrint('Firebase options not configured for this platform: $e');
      _initialized = false;
    } catch (e) {
      debugPrint('Firebase initialization failed: $e');
      _initialized = false;
    }
  }

  /// فائدة بسيطة لمعرفة دعم بعض خدمات Firebase حسب المنصة.
  static bool get supportsMessaging {
    if (kIsWeb) return true;
    if (GetPlatform.isAndroid || GetPlatform.isIOS || GetPlatform.isMacOS) {
      return true;
    }
    return false;
  }

  static bool get supportsAnalytics {
    if (kIsWeb) return true;
    if (GetPlatform.isAndroid || GetPlatform.isIOS || GetPlatform.isMacOS) {
      return true;
    }
    return false;
  }

  static bool get supportsCrashlytics {
    if (kIsWeb) return false;
    if (GetPlatform.isAndroid || GetPlatform.isIOS || GetPlatform.isMacOS) {
      return true;
    }
    return false;
  }

  static bool get supportsPerformance {
    if (kIsWeb) return true;
    if (GetPlatform.isAndroid || GetPlatform.isIOS || GetPlatform.isMacOS) {
      return true;
    }
    return false;
  }
}
