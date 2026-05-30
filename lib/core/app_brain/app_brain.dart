import 'package:get/get.dart';
import 'package:rxdart/rxdart.dart' hide Rx;

import '../utils/app_logger.dart';
import 'app_events.dart';

/// AppSystemState: Represents the global engagement level of the application.
enum AppSystemState {
  idle, // App is open but no active engagement
  chatting, // User is actively in a chat
  calling, // Active audio/video call
  background, // App is in background
  emergency, // Global kill-switch active or critical error
}

/// IAppBrain: The central coordinator for TalkMate AI.
/// It orchestrates how features interact and ensures system stability.
abstract class IAppBrain {
  /// Current global state
  Rx<AppSystemState> get state;

  /// Stream of all global events for cross-feature monitoring
  Stream<AppBrainEvent> get eventBus;

  /// Publish a new event to the bus
  void publish(AppBrainEvent event);

  /// Request a state change (subject to engagement rules)
  Future<bool> transitionTo(AppSystemState newState, {String? reason});

  /// Feature Registration
  void registerFeature(String featureId);
}

/// Singleton access for the brain (Implementation skeleton)
class AppBrain extends GetxService implements IAppBrain {
  @override
  final Rx<AppSystemState> state = AppSystemState.idle.obs;

  final _eventBus = BehaviorSubject<AppBrainEvent>();

  @override
  Stream<AppBrainEvent> get eventBus => _eventBus.stream;

  @override
  void publish(AppBrainEvent event) {
    AppLogger.brain('[Event] $event');
    _eventBus.add(event);
  }

  @override
  Future<bool> transitionTo(AppSystemState newState, {String? reason}) async {
    if (state.value == newState) return true;
    AppLogger.brain(
        '[Transition] ${state.value.name} -> ${newState.name} ($reason)');
    state.value = newState;
    return true;
  }

  @override
  void onClose() {
    AppLogger.brain('Shutting down...');
    _eventBus.close();
    super.onClose();
  }

  @override
  void registerFeature(String featureId) {
    // Audit feature registration
  }

  /// Trigger emergency state for critical failures
  void enterEmergencyMode(String reason) {
    AppLogger.e('🧠 EMERGENCY MODE TRIGGERED: $reason');
    transitionTo(AppSystemState.emergency, reason: reason);
    publish(SystemEvent(
      source: 'brain',
      type: 'emergency_start',
      metadata: {
        'action': 'protect_ui',
        'value': reason,
      },
    ));
  }
}
