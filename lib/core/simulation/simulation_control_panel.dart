import 'package:get/get.dart';

import 'decision_consistency_analyzer.dart';
import 'simulation_scenario.dart';
import 'stress_report.dart';

/// SimulationControlPanel: Developer control for stress tests and scenarios.
class SimulationControlPanel extends GetxController {
  static SimulationControlPanel get instance =>
      Get.isRegistered<SimulationControlPanel>()
          ? Get.find<SimulationControlPanel>()
          : Get.put(SimulationControlPanel());

  final RxBool isScenarioRunning = false.obs;
  final RxString currentScenarioName = 'None'.obs;
  SimulationScenario? _activeScenario;

  // Stress Level (Mock configuration for speed/burst)
  final Rx<StressLevel> stressLevel = StressLevel.low.obs;

  Future<void> startScenario(SimulationScenario scenario) async {
    if (isScenarioRunning.value) return;

    _activeScenario = scenario;
    currentScenarioName.value = scenario.name;
    isScenarioRunning.value = true;

    try {
      await scenario.run();
    } finally {
      isScenarioRunning.value = false;
      currentScenarioName.value = 'None';
      _activeScenario = null;

      // Auto-analyze after run
      DecisionConsistencyAnalyzer.instance.analyze();
    }
  }

  void stopCurrentScenario() {
    _activeScenario?.stop();
    isScenarioRunning.value = false;
  }

  StressReport get report => StressReport.instance;
  List<String> get anomalies => DecisionConsistencyAnalyzer.instance.warnings;
}

enum StressLevel { low, medium, extreme }
