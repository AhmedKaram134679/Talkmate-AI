import '../feature_contracts.dart';

/// Contract for the Calls feature.
/// Defines constraints and capabilities specific to audio/video calling.
abstract class ICallFeature extends IBrainFeature {
  /// Whether the feature supports video calls in the current state
  bool get supportsVideo;

  /// Whether the feature allows high bitrate audio
  bool get allowHighBitrate;

  /// Request to degrade quality (e.g., due to low bandwidth or battery)
  Future<void> degradeQuality({bool videoOff = false, bool lowBitrate = false});
}

/// Contract for the Chat feature.
/// Defines constraints for messaging.
abstract class IChatFeature extends IBrainFeature {
  /// Whether media uploads/downloads are allowed
  bool get allowMediaTransfer;

  /// Whether real-time typing indicators are enabled
  bool get enableRealtimeEvents;

  /// Apply restrictions to chat (e.g., read-only mode)
  Future<void> setReadOnly(bool enabled);
}

/// Contract for the Notifications feature.
/// Defines how notifications should be handled.
abstract class INotificationFeature extends IBrainFeature {
  /// Whether audible notifications are allowed
  bool get allowSound;

  /// Whether heads-up (banner) notifications are allowed
  bool get allowHeadsUp;

  /// Set a quiet mode schedule or immediate state
  Future<void> setQuietMode(bool enabled);
}

/// Contract for Search & Presence features.
/// Defines limits on background polling and resource usage.
abstract class ISearchFeature extends IBrainFeature {
  /// Whether to allow live/fuzzy search as user types
  bool get allowLiveSearch;

  /// Limit the scope of search to local data only
  Future<void> setLocalOnly(bool enabled);
}
