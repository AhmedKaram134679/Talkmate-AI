import 'package:talkmate_ai/core/app_brain/app_events.dart';
import 'package:talkmate_ai/core/app_brain/feature_contracts.dart';

/// IMultimediaSystemGovernance: The theoretical contract for the multimedia system (Voice, Video, Streaming).
/// This is NOT an implementation. It is a constitutional skeleton.
abstract class IMultimediaSystemGovernance implements IBrainFeature {
  @override
  String get featureId => 'multimedia_system_v1';

  /// Kill switch implementation (Must release all media resources instantly: Voice, Video, Stream)
  Future<void> hardKill();

  /// Isolation status
  bool get isIsolated;

  /// Theoretical Signal: Multimedia signaling is ready but mutes/blinds everything.
  bool get isSignalingReady;

  /// Whether the feature supports video calls in the current state (Forbidden in E5)
  bool get supportsVideo;

  /// Whether the feature allows high bitrate audio
  bool get allowHighBitrate;

  /// Request to degrade quality (e.g., due to low bandwidth or battery)
  Future<void> degradeQuality({bool videoOff = false, bool lowBitrate = false});
}

/// A placeholder for the Multimedia Controller that respects E6 Isolation.
/// Currently non-functional by design.
class CallSystemPlaceholder implements IMultimediaSystemGovernance {
  @override
  String get featureId => 'voice_system_v1';

  @override
  bool get isHealthy => true;

  @override
  bool get isIsolated => true;

  @override
  bool get isSignalingReady => false;

  @override
  bool get supportsVideo => false;

  @override
  bool get allowHighBitrate => false;

  @override
  Future<void> boot() async {
    // Stage E5: Constitutional boot
  }

  @override
  Future<void> applyPolicy(Map<String, dynamic> constraints) async {
    // Stage E5: Placeholder does not process policies
  }

  @override
  void handleGlobalEvent(AppBrainEvent event) {
    // Stage E5: Non-functional
  }

  @override
  Future<void> hardKill() async {
    // Stage E5: No resources to release
  }

  @override
  Future<void> degradeQuality(
      {bool videoOff = false, bool lowBitrate = false}) async {
    // Stage E5: Non-functional
  }
}
