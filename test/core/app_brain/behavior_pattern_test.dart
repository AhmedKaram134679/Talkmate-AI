import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/core/app_brain/learning/behavior_log.dart';
import 'package:talkmate_ai/core/app_brain/learning/user_behavior_model.dart';

void main() {
  group('BehaviorLog Pattern Detection Tests', () {
    test('Should detect repetitive ignore pattern', () {
      final logger = BehaviorLog();

      // Inject 10 ignored events
      for (int i = 0; i < 11; i++) {
        logger.add(BehaviorLogEntry(
          source: 'chat',
          interactionType: 'ignored',
        ));
      }

      final patterns = logger.detectEmergingPatterns();
      expect(patterns, contains(BehaviorPattern.ignoreRepetitive));
    });

    test('Should not detect patterns with too few logs', () {
      final logger = BehaviorLog();
      logger.add(BehaviorLogEntry(source: 'chat', interactionType: 'ignored'));

      final patterns = logger.detectEmergingPatterns();
      expect(patterns, isEmpty);
    });
    group('BehaviorPattern Enum tests', () {
      test('Enum values should exist', () {
        expect(BehaviorPattern.values.length, greaterThan(0));
      });
    });
  });
}
