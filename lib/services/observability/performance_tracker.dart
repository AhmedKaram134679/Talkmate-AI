import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/data/services/firebase_service.dart';

class PerformanceTracker extends GetxService {
  static PerformanceTracker get instance => Get.find();

  final Map<String, Trace> _activeTraces = {};

  Future<void> startTrace(String name) async {
    if (!AppConfig.enablePerformanceMonitoring ||
        !FirebaseService.supportsPerformance) {
      return;
    }

    try {
      final trace = FirebasePerformance.instance.newTrace(name);
      await trace.start();
      _activeTraces[name] = trace;
    } catch (e) {
      debugPrint('Failed to start performance trace $name: $e');
    }
  }

  Future<void> stopTrace(String name, {Map<String, String>? attributes}) async {
    if (!AppConfig.enablePerformanceMonitoring ||
        !FirebaseService.supportsPerformance) {
      return;
    }

    final trace = _activeTraces.remove(name);
    if (trace != null) {
      if (attributes != null) {
        attributes.forEach((key, value) => trace.putAttribute(key, value));
      }
      await trace.stop();
    }
  }

  Future<void> recordMetric(String name, int value,
      {Map<String, String>? attributes}) async {
    if (!AppConfig.enablePerformanceMonitoring ||
        !FirebaseService.supportsPerformance) {
      return;
    }

    try {
      final trace = FirebasePerformance.instance.newTrace(name);
      await trace.start();
      if (attributes != null) {
        attributes.forEach((key, value) => trace.putAttribute(key, value));
      }
      // Since we can't set individual values easily on start/stop without a long trace,
      // we use it as a point measurement if needed, or stick to start/stop patterns.
      await trace.stop();
    } catch (e) {
      debugPrint('Failed to record performance metric $name: $e');
    }
  }

  /// Specialized metric for startup tracking
  Future<void> logAppStartupComplete(Duration duration) async {
    await recordMetric('app_startup_time', duration.inMilliseconds);
  }
}
