import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/notification_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/feature_assimilation_layer.dart';
import 'package:talkmate_ai/core/communication/communication_controller.dart';
import 'package:talkmate_ai/data/di/data_bindings.dart';
import 'package:talkmate_ai/data/services/supabase_service.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';

/// [SOVEREIGN BOOTSTRAPPER]: Ensures all call-related subsystems are ready.
/// Critical for Android background push handling where the app might be cold.
class CallBootstrapper {
  static final RxBool _isReady = false.obs;
  static bool get isReady => _isReady.value;

  static Future<void> ensureReady() async {
    if (_isReady.value) return;

    debugPrint('🚀 CallBootstrapper: Emergency Bootstrap Sequence Started...');

    // 1. Core Platform Service (Supabase)
    if (!Get.isRegistered<SupabaseService>()) {
      final supabase = SupabaseService();
      await supabase.initialize();
      Get.put(supabase, permanent: true);
    }

    // 2. Data Bindings (Repositories)
    DataBindings.init();

    // 3. Auth State (Needed for UserID)
    if (!Get.isRegistered<AuthController>()) {
      final auth = Get.put(AuthController(), permanent: true);
      await auth.loadState();
    } else {
      await Get.find<AuthController>().loadState();
    }

    // 4. Feature Assimilation (Registers Sovereign Engines)
    if (!Get.isRegistered<FeatureAssimilationLayer>()) {
      final layer = Get.put(FeatureAssimilationLayer(), permanent: true);
      await layer.init();
    }

    // 5. Communication Controller (Media Engine)
    if (!Get.isRegistered<CommunicationController>()) {
      Get.put(CommunicationController(), permanent: true);
    }

    // 6. Call Manager (Signaling Authority)
    if (!Get.isRegistered<CallManager>()) {
      // Note: CallManager.init() starts signaling
      final manager = CallManager.instance;
      await manager.init();
      Get.put(manager, permanent: true);
    }

    // 7. Notification Controller (UI Feedback)
    if (!Get.isRegistered<NotificationController>()) {
      Get.put(NotificationController(), permanent: true);
    }

    _isReady.value = true;
    debugPrint('✅ CallBootstrapper: System Hot. Subsystems synchronized.');
  }
}
