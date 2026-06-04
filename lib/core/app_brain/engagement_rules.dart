import 'app_brain.dart';
import 'app_events.dart';

/// IEngagementPolicy: Defines the logic for deciding if a feature interrupt is allowed.
/// Example: Should a message notification interrupt an active video call?
abstract class IEngagementPolicy {
  /// Priority score for the current state (Higher = More protected)
  int getPriority(AppSystemState state);

  /// Determine if an event should trigger an interrupt/notification
  bool shouldAllowInterrupt({
    required AppSystemState currentState,
    required AppBrainEvent incomingEvent,
  });

  /// Handle conflicting states
  AppSystemState resolveConflict(AppSystemState stateA, AppSystemState stateB);
}

/// Default engagement rules implementation skeleton
class DefaultEngagementPolicy implements IEngagementPolicy {
  @override
  int getPriority(AppSystemState state) {
    switch (state) {
      case AppSystemState.emergency:
        return 100;
      case AppSystemState.calling:
        return 80;
      case AppSystemState.chatting:
        return 40;
      case AppSystemState.background:
        return 20;
      case AppSystemState.idle:
        return 0;
    }
  }

  @override
  bool shouldAllowInterrupt({
    required AppSystemState currentState,
    required AppBrainEvent incomingEvent,
  }) {
    // Implement logic: e.g., Calls always interrupt Chats, but Chats don't interrupt Calls.
    return true;
  }

  @override
  AppSystemState resolveConflict(AppSystemState stateA, AppSystemState stateB) {
    return getPriority(stateA) >= getPriority(stateB) ? stateA : stateB;
  }
}
