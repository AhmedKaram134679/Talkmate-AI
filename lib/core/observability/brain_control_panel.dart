import 'package:get/get.dart';

/// BrainControlPanel: Temporary, runtime-only developer overrides.
/// Note: These settings are not persisted and do not affect end-user experience.
class BrainControlPanel extends GetxController {
  static BrainControlPanel get instance => Get.isRegistered<BrainControlPanel>()
      ? Get.find<BrainControlPanel>()
      : Get.put(BrainControlPanel());

  // Overrides
  final RxBool smartLearningEnabled = true.obs;
  final RxBool priorityMatrixFrozen = false.obs;

  // Force modes (Testing only)
  final RxBool forceSilentMode = false.obs;
  final RxMap<String, int> priorityOverrides = <String, int>{}.obs;

  void resetAll() {
    smartLearningEnabled.value = true;
    priorityMatrixFrozen.value = false;
    forceSilentMode.value = false;
    priorityOverrides.clear();
  }

  /// Checks if a specific adjustment should be ignored due to overrides.
  bool shouldIgnoreLearning() => !smartLearningEnabled.value;

  /// Returns forced priority if exists.
  int? getForcedPriority(String source) => priorityOverrides[source];
}
