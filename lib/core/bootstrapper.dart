import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/controllers/language_controller.dart';
import 'package:talkmate_ai/controllers/notification_controller.dart';
import 'package:talkmate_ai/controllers/search_controller.dart' as app_search;
import 'package:talkmate_ai/controllers/theme_controller.dart';
import 'package:talkmate_ai/core/app_brain/adaptive/adaptive_controller.dart';
import 'package:talkmate_ai/core/app_brain/app_brain.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_invitation_service.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_presence_engine.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/feature_assimilation_layer.dart';
import 'package:talkmate_ai/core/communication/communication_controller.dart';
import 'package:talkmate_ai/core/feedback/sovereign_feedback_service.dart';
import 'package:talkmate_ai/core/governance/beta_feature_flags_service.dart';
import 'package:talkmate_ai/core/platform/database/database.dart';
import 'package:talkmate_ai/core/platform/notifications/notifications.dart';
import 'package:talkmate_ai/core/platform/storage/storage.dart';
import 'package:talkmate_ai/core/predictive/predictive_engine.dart';
import 'package:talkmate_ai/core/predictive/self_healing_controller.dart';
import 'package:talkmate_ai/core/release/feature_flag_provider.dart';
import 'package:talkmate_ai/core/release/release_manager.dart';
import 'package:talkmate_ai/core/security/security_gatekeeper.dart';
import 'package:talkmate_ai/core/telemetry/sovereign_telemetry_service.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';
import 'package:talkmate_ai/data/di/data_bindings.dart';
import 'package:talkmate_ai/data/services/badge_service.dart';
import 'package:talkmate_ai/data/services/firebase_service.dart';
import 'package:talkmate_ai/data/services/media_services.dart';
import 'package:talkmate_ai/data/services/messaging_service.dart';
import 'package:talkmate_ai/data/services/presence_service.dart';
import 'package:talkmate_ai/data/services/supabase_service.dart';
import 'package:talkmate_ai/services/audio/app_audio_service.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';
import 'package:talkmate_ai/services/call/foreground_service.dart';
import 'package:talkmate_ai/services/observability/analytics_service.dart';
import 'package:talkmate_ai/services/observability/app_observability.dart';
import 'package:talkmate_ai/services/observability/performance_tracker.dart';
import 'package:talkmate_ai/services/platform/platform_service.dart';
import 'package:talkmate_ai/services/security/encrypted_storage_service.dart';
import 'package:window_manager/window_manager.dart';

/// The central bootstrapper for the application.
/// Isolates platform-specific startup logic from main.dart.
class AppBootstrapper {
  static Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Initialize Firebase FIRST (Stage Z Fix)
    await FirebaseService.initialize();

    // 2. Initialize Media & Platform Pre-flights (Stage Z)
    if (!kIsWeb) {
      try {
        MediaKit.ensureInitialized();
      } catch (e) {
        AppLogger.error('MediaKit initialization failed',
            context: {'error': e.toString()});
      }
    }

    Get.put(PerformanceTracker(), permanent: true);
    Get.put(AnalyticsService(), permanent: true);
    Get.put(ReleaseManager(), permanent: true);
    Get.put(FeatureFlagProvider(), permanent: true);

    // Initialize & Register AppAudioService (centralized extraction)
    final audioService = Get.put(AppAudioService(), permanent: true);
    await audioService.init();

    Get.put(SecurityGatekeeper(), permanent: true);
    Get.put(AdaptiveController(), permanent: true);
    Get.put(AppBrain(), permanent: true); // The Central Brain
    Get.put(SelfHealingController(), permanent: true);
    Get.put(PredictiveEngine(), permanent: true);
    Get.put(AppObservability(), permanent: true);
    Get.put(PlatformService(), permanent: true);
    Get.put(EncryptedStorageService(), permanent: true);

    if (AppConfig.enablePerformanceMonitoring) {
      await PerformanceTracker.instance.startTrace('app_startup');

      // Stage D5: Perform Release Integrity Audit
      unawaited(ReleaseManager.instance.validateInProduction());

      // Stage D6: Start Predictive Forecasting
      PredictiveEngine.instance.startForecasting();

      // Run security audit early
      unawaited(SecurityGatekeeper.instance.performStartupAudit());

      // Periodically check memory usage in production environment (simulated via Bridge)
      Timer.periodic(const Duration(minutes: 5), (timer) {
        // This would typically use a platform-specific plugin to get RSS,
        // here we use a placeholder that can be hooked to real OS metrics.
        AppObservability.instance
            .logMemoryUsage(150 * 1024 * 1024); // Baseline example
      });
    }

    // 3. Error tracking (Crashlytics)
    if (AppConfig.enableErrorTracking && FirebaseService.supportsCrashlytics) {
      FlutterError.onError = (errorDetails) {
        AppObservability.instance.logCriticalError(
            'flutter_framework', errorDetails.exception.toString(),
            stack: errorDetails.stack);
        FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        // [RESILIENCE_GUARD]: Ignore Realtime channel errors in the global dispatcher.
        // These are usually caught and handled (via refresh) by individual services.
        if (AppConfig.isStaleSessionError(error)) {
          AppLogger.warning(
              'PlatformDispatcher: Suppressed non-fatal Realtime error.',
              context: {'error': error.toString()});
          return true; // Handled
        }

        AppObservability.instance.logCriticalError(
            'platform_dispatcher', error.toString(),
            stack: stack);
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }

    // 4. Platform-Specific Setup (Desktop)

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      final WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 720),
        center: true, // Keep center for initial show, maximize happens after
        backgroundColor:
            null, // Default to system/opaque to avoid transparency issues
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );
      unawaited(windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
        // Delay maximize slightly to ensure window is rendered
        await Future.delayed(const Duration(milliseconds: 100));
        unawaited(windowManager.maximize());
      }));
    }

    // 5. Initialize Platform Database (Conditional Import)
    final db = getPlatformDatabase();
    await db.initialize();

    // 6. Initialize Notifications & Messaging
    final platformNotifications = getPlatformNotifications();
    await platformNotifications.initialize();

    // 7. Initialize Supabase (New Backend)
    final supabaseService = SupabaseService();
    await supabaseService.initialize();

    // 7.01 Initialize Media Services System
    final mediaInitializer = MediaServicesInitializer();
    await mediaInitializer.initialize();
    Get.put<MediaServicesInitializer>(mediaInitializer, permanent: true);
    Get.put<BackgroundUploadService>(mediaInitializer.backgroundUpload, permanent: true);
    Get.put<MediaCacheManager>(mediaInitializer.cacheManager, permanent: true);
    Get.put<AudioQueueManager>(mediaInitializer.audioQueue, permanent: true);
    Get.put<VoicePlaybackController>(VoicePlaybackController(), permanent: true);

    // 7.05 Initialize Platform Background Services (Stage R25)
    CallForegroundService.init();

    // 7.1 Pre-flight Audio Session (For RTC Readiness)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.speech());
        debugPrint('🎙️ Bootstrapper: Audio Session Pre-flight Complete.');
      } catch (e) {
        debugPrint('⚠️ Bootstrapper: Audio Session Pre-flight Failed: $e');
      }
    }

    // 8. Initialize Data Layer (Repositories via DI)
    DataBindings.init();

    // 9. Initialize Controllers (Global)
    // 9. Initialize Controllers (Global)
    final authController = Get.put(AuthController());
    Get.put(ThemeController());
    Get.put(LanguageController());
    Get.put(app_search.AppSearchController());
    Get.put(NotificationController());

    // 9.1 Await Auth State Load (Critical for Initial Route)
    await authController.loadState();

    // 10. Initialize Feature Assimilation Layer (Stage F1)
    // This MUST happen before CallManager as it registers the Sovereign Engines
    final featureLayer = Get.put(FeatureAssimilationLayer());
    await featureLayer.init();

    // 10.05 Initialize Communication & Chat Controllers
    Get.put(CommunicationController(), permanent: true);
    Get.put(ChatController());

    // 10.1 Initialize Sovereign Presence Engine (Stage C7)
    // Depends on SovereignCommunicationEngine (registered via featureLayer.init -> CallFeatureClient)
    Get.put(SovereignPresenceEngine(), permanent: true);
    Get.put(SovereignInvitationService(), permanent: true);

    // 10.2 Secondary Services
    await MessagingService.instance.handleInitialMessageIfAny();
    PresenceService.instance.init();
    await CallManager.instance.init();
    Get.put(CallManager.instance);
    await Get.putAsync(() => BadgeService().init());

    // 10.3 Initialize Sovereign Telemetry Service (Stage R7)
    Get.put(SovereignTelemetryService(), permanent: true);

    // 10.4 Initialize Beta Governance (Stage B1)
    Get.put(BetaFeatureFlagsService(), permanent: true);
    Get.put(SovereignFeedbackService(), permanent: true);

    // 11. Preferred orientations
    if (!kIsWeb) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }

    // 12. Inject Platform Interfaces into GetX for injection
    Get.put<PlatformDatabase>(db, permanent: true);
    Get.put<IPlatformStorage>(getPlatformStorage(), permanent: true);
    Get.put<IPlatformNotifications>(platformNotifications, permanent: true);

    AppLogger.info(
        'AppBootstrapper: Initialization complete for ${kIsWeb ? "Web" : defaultTargetPlatform.name}');
  }
}
