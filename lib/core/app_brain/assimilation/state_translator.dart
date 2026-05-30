import '../app_brain.dart';

/// Translates abstract System States into concrete Feature Constraints.
class FeatureStateTranslator {
  /// Generates a configuration map for a feature based on the global state.
  static Map<String, dynamic> translate(
      AppSystemState state, String featureId) {
    final constraints = <String, dynamic>{};

    switch (state) {
      case AppSystemState.emergency:
        constraints['enabled'] = false;
        break;

      case AppSystemState.background:
        if (featureId == 'calls_v1') {
          constraints['video_enabled'] = false;
          constraints['reduce_bitrate'] = true;
        }
        if (featureId == 'chat_v1') {
          constraints['realtime_typing'] = false;
        }
        break;

      case AppSystemState.calling:
        if (featureId == 'notifications') {
          constraints['sound'] = false;
          constraints['heads_up'] = false;
        }
        break;

      case AppSystemState.chatting:
        // Prioritize chat resources?
        break;

      case AppSystemState.idle:
        // No specific constraints
        break;
    }

    // BCI signals integration placeholder.

    return constraints;
  }
}
