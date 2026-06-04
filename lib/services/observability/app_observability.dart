import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/adaptive/adaptive_controller.dart';
import 'package:talkmate_ai/core/app_brain/adaptive/adaptive_models.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';
import 'package:talkmate_ai/services/observability/analytics_service.dart';
import 'package:talkmate_ai/services/observability/performance_tracker.dart';

class AppObservability extends GetxService {
  static AppObservability get instance => Get.find();

  // --- 🏥 APP HEALTH & METRICS ---

  void logHeartbeat(String userId) {
    AnalyticsService.instance.logEvent(
      name: 'app_heartbeat',
      parameters: {
        'platform': defaultTargetPlatform.name,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  void logMemoryUsage(int bytes) {
    final mb = bytes / (1024 * 1024);

    // Broadcast signal to Adaptive Engine
    AdaptiveController.instance.processSignal(AdaptiveSignal(
      type: AdaptiveSignalType.memory,
      value: mb,
    ));

    if (mb > 500) {
      // Threshold for warning
      AppLogger.warning('High Memory Usage Detected',
          context: {'usage_mb': mb.toStringAsFixed(2)});
    }
    AnalyticsService.instance.logEvent(
      name: 'resource_usage',
      parameters: {
        'type': 'memory',
        'value_mb': mb,
      },
    );
  }

  void logPerformanceJank(String screen, Duration frameTime) {
    if (frameTime.inMilliseconds > 16) {
      // Frame drop detection (> 60fps)
      AnalyticsService.instance.logEvent(
        name: 'perf_jank',
        parameters: {
          'screen': screen,
          'latency_ms': frameTime.inMilliseconds,
        },
      );
    }
  }

  void logCriticalError(String source, String error,
      {StackTrace? stack, Map<String, dynamic>? extra}) {
    AnalyticsService.instance.logAppError(source, error, extra: extra);
    AppLogger.critical('CRITICAL ERROR [$source]: $error',
        error: error, stackTrace: stack, context: extra);
  }

  // --- 💬 MESSAGE LIFECYCLE TRACKING ---

  void trackMessageEnqueued(String localId) {
    PerformanceTracker.instance.startTrace('msg_sync_$localId');
    AnalyticsService.instance.logEvent(
      name: 'msg_lifecycle',
      parameters: {'event': 'enqueued', 'local_id': localId},
    );
  }

  void trackMessageSent(String localId, String remoteId) {
    AnalyticsService.instance.logEvent(
      name: 'msg_lifecycle',
      parameters: {
        'event': 'sent',
        'local_id': localId,
        'remote_id': remoteId,
      },
    );
  }

  void trackMessageDelivered(String remoteId) {
    PerformanceTracker.instance.stopTrace('msg_sync_ack_$remoteId');
    AnalyticsService.instance.logEvent(
      name: 'msg_lifecycle',
      parameters: {'event': 'delivered', 'remote_id': remoteId},
    );
  }

  // --- 🔔 NOTIFICATION JOURNEY ---

  void trackNotificationReceived(String? messageId, String method) {
    AnalyticsService.instance.logEvent(
      name: 'notification_flow',
      parameters: {
        'event': 'received',
        'message_id': messageId ?? 'unknown',
        'method': method, // e.g. 'fcm', 'supabase_realtime'
        'latency_ms': _calculateLatency(messageId),
      },
    );
  }

  void trackNotificationTapped(String? messageId) {
    AnalyticsService.instance.logEvent(
      name: 'notification_flow',
      parameters: {
        'event': 'tapped',
        'message_id': messageId ?? 'unknown',
      },
    );
  }

  // --- 📞 CALL & MULTIMEDIA QUALITY ---

  void logCallQualityMetrics(String sessionId, double jitter, double battery) {
    AnalyticsService.instance.logEvent(
      name: 'call_quality',
      parameters: {
        'session_id': sessionId,
        'jitter': jitter,
        'battery': battery,
      },
    );

    // Also signal Adaptive Engine if jitter is high or battery low
    AdaptiveController.instance.processSignal(AdaptiveSignal(
      type: AdaptiveSignalType.jitter,
      value: jitter,
      metadata: {'session_id': sessionId},
    ));

    AdaptiveController.instance.processSignal(AdaptiveSignal(
      type: AdaptiveSignalType.battery,
      value: battery,
      metadata: {'session_id': sessionId},
    ));
  }

  // --- 🛠️ UTILS ---

  int _calculateLatency(String? id) {
    // Basic latency calc placeholder - could use timestamps from payload
    return 0;
  }
}
