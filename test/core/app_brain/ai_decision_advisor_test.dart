import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/ai/ai_decision_advisor.dart';
import 'package:talkmate_ai/core/app_brain/app_brain.dart';
import 'package:talkmate_ai/core/app_brain/app_events.dart';
import 'package:talkmate_ai/core/app_brain/engagement/decision_model.dart';
import 'package:talkmate_ai/core/app_brain/learning/behavior_tracker.dart';

void main() {
  late AIDecisionAdvisor advisor;

  setUp(() {
    Get.testMode = true;
    // AIDecisionAdvisor.getDecision() reads BehaviorTracker.instance, which in
    // turn resolves IAppBrain. Register both so the advisor can access them.
    if (!Get.isRegistered<IAppBrain>()) {
      Get.put<IAppBrain>(AppBrain());
    }
    if (!Get.isRegistered<BehaviorTracker>()) {
      Get.put<BehaviorTracker>(BehaviorTracker());
    }
    advisor = AIDecisionAdvisor();
  });

  tearDown(() async {
    if (Get.isRegistered<BehaviorTracker>()) {
      await Get.delete<BehaviorTracker>(force: true);
    }
    if (Get.isRegistered<IAppBrain>()) {
      await Get.delete<IAppBrain>(force: true);
    }
  });

  group('AIDecisionAdvisor Tests', () {
    test('Should prioritize incoming call during Idle state', () {
      final event =
          CallEvent(source: 'calls', callId: '123', status: 'ringing');
      final decision = advisor.getDecision(
        event: event,
        currentState: AppSystemState.idle,
      );

      expect(decision.outcome, DecisionOutcome.display);
    });

    test('Should queue incoming call if user is already in a call (Busy)', () {
      final event =
          CallEvent(source: 'calls', callId: '456', status: 'ringing');
      final decision = advisor.getDecision(
        event: event,
        currentState: AppSystemState.calling,
      );

      expect(decision.outcome, DecisionOutcome.queue);
      expect(decision.reason, contains('Busy'));
    });

    test('Should make chat silent message if user is in a call', () {
      final event =
          ChatEvent(source: 'chat', chatId: 'abc', action: 'newMessage');
      final decision = advisor.getDecision(
        event: event,
        currentState: AppSystemState.calling,
      );

      expect(decision.outcome, DecisionOutcome.silent);
    });

    test('Should apply network-aware policy for calls in poor connection', () {
      advisor.updateContext({'network_quality': 'poor'});

      final event =
          CallEvent(source: 'calls', callId: '789', status: 'ringing');
      final decision = advisor.getDecision(
        event: event,
        currentState: AppSystemState.idle,
      );

      expect(decision.outcome, DecisionOutcome.queue);
      expect(decision.reason, contains('bandwidth'));
    });
  });
}
