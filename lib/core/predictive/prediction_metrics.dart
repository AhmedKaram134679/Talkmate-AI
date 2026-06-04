class PredictionMetrics {
  static final PredictionMetrics instance = PredictionMetrics._();
  PredictionMetrics._();

  int preventedFailures = 0;
  int falsePositives = 0;
  double totalConfidence = 0.0;
  int predictionCount = 0;

  void recordPrevention() => preventedFailures++;
  void recordFalsePositive() => falsePositives++;

  double get accuracy => predictionCount == 0
      ? 1.0
      : (predictionCount - falsePositives) / predictionCount;
}
