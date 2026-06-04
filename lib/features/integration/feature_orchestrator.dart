import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../core/app_brain/app_brain.dart';
import '../../core/app_brain/feature_contracts.dart';
import 'event_subscribers.dart';

/// FeatureOrchestrator: The central manager for keeping features in sync.
class FeatureOrchestrator extends GetxService {
  static FeatureOrchestrator get instance => Get.find<FeatureOrchestrator>();

  final _brain = Get.find<IAppBrain>();
  final List<IBrainFeature> _features = [];

  void init() {
    debugPrint('FeatureOrchestrator: Bootstrapping integration layer...');

    // Register primary feature subscribers
    _register(ChatBrainFeature());
    _register(CallBrainFeature());
    _register(NotificationBrainFeature());

    _bootAll();
  }

  void _register(IBrainFeature feature) {
    _features.add(feature);
    _brain.registerFeature(feature.featureId);
  }

  Future<void> _bootAll() async {
    for (final feature in _features) {
      try {
        await feature.boot();
        debugPrint(
            'FeatureOrchestrator: Feature [${feature.featureId}] booted.');
      } catch (e) {
        debugPrint(
            'FeatureOrchestrator: Failed to boot [${feature.featureId}]: $e');
      }
    }
  }

  /// Broadcasts a global event through the brain
  void broadcast(dynamic event) {
    // Logic to translate local events to AppBrainEvents
  }
}
