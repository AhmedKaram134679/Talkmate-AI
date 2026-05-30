import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../app_brain.dart';
import '../app_events.dart';
import 'behavior_log.dart';
import 'user_behavior_model.dart';

/// BehaviorTracker: Non-invasive listener for collecting interaction telemetry.
class BehaviorTracker extends GetxService {
  static BehaviorTracker get instance => Get.find<BehaviorTracker>();

  final _brain = Get.find<IAppBrain>();
  final Rx<InteractionProfile> profile = const InteractionProfile().obs;
  final BehaviorLog logger = BehaviorLog();

  void init() {
    debugPrint('BehaviorTracker: Initializing telemetry collector...');
    _brain.eventBus.listen(_onEventObserved);
  }

  void _onEventObserved(AppBrainEvent event) {
    // Audit the frequency of events per source
    final stats = profile.value.features[event.source] ?? const FeatureStats();

    final updatedFeatures =
        Map<String, FeatureStats>.from(profile.value.features);
    updatedFeatures[event.source] = stats.increment();

    profile.value = profile.value.copyWith(features: updatedFeatures);

    _analyzePatterns();
  }

  /// Records an explicit feedback (e.g., user swiped away a notification)
  void recordInteractionResult(String source,
      {required bool ignored, Duration? responseTime}) {
    final stats = profile.value.features[source] ?? const FeatureStats();

    final updatedFeatures =
        Map<String, FeatureStats>.from(profile.value.features);
    updatedFeatures[source] =
        stats.increment(ignored: ignored, responseTime: responseTime);

    profile.value = profile.value.copyWith(features: updatedFeatures);

    // Audit log the interaction
    logger.add(BehaviorLogEntry(
      source: source,
      interactionType: ignored ? 'ignored' : 'responded',
      responseTime: responseTime,
    ));
  }

  void _analyzePatterns() {
    final emerging = logger.detectEmergingPatterns();
    if (emerging.isNotEmpty) {
      debugPrint('BehaviorTracker: Detected potential patterns -> $emerging');
      // In a real app, we would store these in the InteractionProfile or shared preferences
    }
  }
}
