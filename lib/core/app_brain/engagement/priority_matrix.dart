import '../app_brain.dart';

/// InterruptionPriority: Static mapping of feature importance.
class PriorityMatrix {
  /// Higher values mean higher priority.
  static const int priorityEmergency = 1000;
  static const int priorityCallIncoming = 900;
  static const int priorityCallOngoing = 850;
  static const int priorityChatMessage = 500;
  static const int priorityFriendRequest = 300;
  static const int prioritySystemAlert = 100;

  /// Returns base priority for a given event source.
  static int getBasePriority(String source) {
    switch (source) {
      case 'emergency':
        return priorityEmergency;
      case 'calls':
        return priorityCallIncoming;
      case 'chat':
        return priorityChatMessage;
      case 'presence':
        return priorityFriendRequest;
      case 'system':
        return prioritySystemAlert;
      default:
        return 0;
    }
  }

  /// Calculates adjusted priority based on current app state.
  static int getAdjustedPriority(int base, AppSystemState state) {
    switch (state) {
      case AppSystemState.emergency:
        return base - 1000; // Block almost everything
      case AppSystemState.calling:
        return base - 500; // Lower other events effectively
      case AppSystemState.background:
        return base - 200;
      case AppSystemState.idle:
        return base;
      default:
        return base;
    }
  }
}
