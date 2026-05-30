import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../app_brain/app_brain.dart';
import '../app_brain/app_events.dart';

/// EventSimulationEngine: Generates mock events and publishes them to the App Brain.
class EventSimulationEngine extends GetxService {
  static EventSimulationEngine get instance =>
      Get.find<EventSimulationEngine>();

  final _brain = Get.find<IAppBrain>();
  Timer? _simTimer;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// simulates a specific event once
  void injectEvent(AppBrainEvent event) {
    debugPrint(
        'SimEngine: Injecting [${event.runtimeType}] from ${event.source}');
    _brain.publish(event);
  }

  /// Generates a burst of events
  Future<void> burst({
    required List<AppBrainEvent> events,
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    for (var event in events) {
      injectEvent(event);
      await Future.delayed(interval);
    }
  }

  void stop() {
    _simTimer?.cancel();
    _isRunning = false;
  }
}
