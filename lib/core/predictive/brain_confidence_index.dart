import 'package:get/get.dart';
import 'predictive_contracts.dart';

/// BrainConfidenceIndex: The definitive health authority for App Brain.
class BrainConfidenceIndex extends GetxController {
  static BrainConfidenceIndex get instance =>
      Get.isRegistered<BrainConfidenceIndex>()
          ? Get.find<BrainConfidenceIndex>()
          : Get.put(BrainConfidenceIndex());

  final Rx<BrainConfidence> _currentBCI =
      BrainConfidence(100, DateTime.now()).obs;
  BrainConfidence get current => _currentBCI.value;

  void updateScore(double newScore) {
    _currentBCI.value = BrainConfidence(newScore.clamp(0, 100), DateTime.now());
  }

  /// Called by EngagementEngine to check if a decision should be allowed.
  bool shouldAllowDecision(DecisionPriority priority) {
    if (current.preventCritical) return false;
    if (current.smartRestriction && priority.index < 2) return false;
    return true;
  }
}

enum DecisionPriority { low, normal, high, critical }
