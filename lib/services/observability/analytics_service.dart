import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/data/services/firebase_service.dart';

class AnalyticsService extends GetxService {
  static AnalyticsService get instance => Get.find();

  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  Future<void> logEvent(
      {required String name, Map<String, Object>? parameters}) async {
    if (!AppConfig.enableAnalytics || !FirebaseService.supportsAnalytics) {
      return;
    }

    try {
      await _analytics.logEvent(name: name, parameters: parameters);
      if (kDebugMode && AppConfig.enableLogging) {
        debugPrint('Analytics Event: $name | Params: $parameters');
      }
    } catch (e) {
      debugPrint('Failed to log analytics event $name: $e');
    }
  }

  Future<void> logUserMilestone(String milestone) async {
    await logEvent(
      name: 'user_milestone',
      parameters: {
        'milestone': milestone,
        'timestamp': DateTime.now().toIso8601String()
      },
    );
  }

  Future<void> logAppError(String errorType, String message,
      {Map<String, dynamic>? extra}) async {
    if (!AppConfig.enableErrorTracking || !FirebaseService.supportsAnalytics) {
      return;
    }
    await logEvent(
      name: 'app_error',
      parameters: {
        'type': errorType,
        'message': message,
        if (extra != null) ...extra,
      },
    );
  }

  Future<void> logScreenView(String screenName) async {
    await logEvent(
      name: 'screen_view',
      parameters: {'screen_name': screenName},
    );
  }

  Future<void> logInteraction(String target, {String type = 'click'}) async {
    await logEvent(
      name: 'user_interaction',
      parameters: {'target': target, 'type': type},
    );
  }
}
