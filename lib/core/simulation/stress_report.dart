import '../observability/decision_timeline_recorder.dart';

/// StressReport: In-memory performance metrics for brain decisions.
class StressReport {
  static final StressReport instance = StressReport._();
  StressReport._();

  int get totalDecisions =>
      DecisionTimelineRecorder.instance.recentDecisions.length;

  double calculateDecisionsPerSecond() {
    final decisions = DecisionTimelineRecorder.instance.recentDecisions;
    if (decisions.length < 2) return 0.0;

    final duration = decisions.first.timestamp
        .difference(decisions.last.timestamp)
        .inMilliseconds
        .abs();
    if (duration == 0) return decisions.length.toDouble();

    return (decisions.length / (duration / 1000.0));
  }

  Map<String, int> getFeaturePressure() {
    final pressure = <String, int>{};
    final decisions = DecisionTimelineRecorder.instance.recentDecisions;

    for (var d in decisions) {
      pressure[d.source] = (pressure[d.source] ?? 0) + 1;
    }

    return pressure;
  }

  String? getTopPressureFeature() {
    final map = getFeaturePressure();
    if (map.isEmpty) return null;
    return map.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  bool hasDelays() =>
      calculateDecisionsPerSecond() < 1.0 && totalDecisions > 50;
}
