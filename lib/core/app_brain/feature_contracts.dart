import 'app_events.dart';

/// IBrainFeature: The interface that every major feature (Chat, Call, Notification)
/// must eventually implement to be governed by the App Brain.
abstract class IBrainFeature {
  /// Unique identifier of the feature (e.g., 'calls_v1')
  String get featureId;

  /// Current health status of the feature
  bool get isHealthy;

  /// Called by the Brain to initialize the feature's coordination
  Future<void> boot();

  /// Handle a global event dispatched by the Brain
  void handleGlobalEvent(AppBrainEvent event);

  /// Called when the Brain requires the feature to "gracefully pause" or "back off"
  /// e.g., Reducing polling during a call or disabling video.
  Future<void> applyPolicy(Map<String, dynamic> constraints);
}
