/// Stores behavioral patterns over time to detect drift.
class TemporalBehaviorMemory {
  // Simplified: Storing daily aggregate of "Risk Taken"
  final Map<DateTime, double> _dailyRiskIndex = {};

  void recordDailyRisk(double dailyAverageRisk) {
    final today = DateTime.now();
    final key = DateTime(today.year, today.month, today.day);
    _dailyRiskIndex[key] = dailyAverageRisk;
  }

  double getHistoricalStability() {
    if (_dailyRiskIndex.isEmpty) return 1.0;

    // Calculate variance of risk over last 7 entries
    final values = _dailyRiskIndex.values.toList();
    if (values.length < 2) return 1.0;

    final double mean = values.reduce((a, b) => a + b) / values.length;
    final double variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;

    // Invert variance: High variance = Low stability
    return (1.0 - variance).clamp(0.0, 1.0);
  }
}
