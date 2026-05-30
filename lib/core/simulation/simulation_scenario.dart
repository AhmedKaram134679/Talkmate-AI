import 'dart:async';
import '../app_brain/app_events.dart';
import 'event_simulation_engine.dart';

/// SimulationScenario: A predefined sequence of events to test system behavior.
class SimulationScenario {
  final String name;
  final String description;
  final List<SimulationStep> steps;
  final bool loop;

  SimulationScenario({
    required this.name,
    required this.description,
    required this.steps,
    this.loop = false,
  });

  bool _isStopping = false;

  Future<void> run() async {
    _isStopping = false;
    do {
      for (var step in steps) {
        if (_isStopping) break;
        await step.execute();
      }
    } while (loop && !_isStopping);
  }

  void stop() {
    _isStopping = true;
  }
}

/// SimulationStep: A single action within a scenario.
abstract class SimulationStep {
  Future<void> execute();
}

/// InjectEventStep: Injects a specific event.
class InjectEventStep extends SimulationStep {
  final AppBrainEvent event;
  InjectEventStep(this.event);

  @override
  Future<void> execute() async {
    EventSimulationEngine.instance.injectEvent(event);
  }
}

/// WaitStep: Pauses simulation for a duration.
class WaitStep extends SimulationStep {
  final Duration duration;
  WaitStep(this.duration);

  @override
  Future<void> execute() async {
    await Future.delayed(duration);
  }
}

/// Popular Scenarios Library
class ScenarioLibrary {
  static SimulationScenario incomingCallWithChatBurst() {
    return SimulationScenario(
      name: 'Incoming Call + Chat Burst',
      description: 'Tests if system prioritizes call over message spam.',
      steps: [
        InjectEventStep(CallEvent(
            source: 'SimUser', callId: 'call_123', status: 'ringing')),
        WaitStep(Duration(milliseconds: 500)),
        InjectEventStep(
            ChatEvent(source: 'Spammer', chatId: 'c1', action: 'newMessage')),
        InjectEventStep(
            ChatEvent(source: 'Spammer', chatId: 'c1', action: 'newMessage')),
        InjectEventStep(
            ChatEvent(source: 'Spammer', chatId: 'c1', action: 'newMessage')),
        WaitStep(Duration(seconds: 2)),
      ],
    );
  }

  static SimulationScenario stressTest(int messageCount) {
    return SimulationScenario(
      name: 'Stress Test: $messageCount messages',
      description: 'Rapid message injection.',
      steps: List.generate(
          messageCount,
          (i) => InjectEventStep(ChatEvent(
              source: 'StressBot', chatId: 's$i', action: 'newMessage'))),
    );
  }
}
