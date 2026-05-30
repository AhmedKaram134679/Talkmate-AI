import 'package:flutter/foundation.dart';
import '../resilience/resilience_contracts.dart';

/// PredictedFailure: Data structure representing a potential upcoming failure.
@immutable
class PredictedFailure {
  final FailureType component;
  final double riskLevel; // 0.0 to 1.0
  final double confidence; // 0.0 to 1.0
  final Duration expectedWindow;

  const PredictedFailure({
    required this.component,
    required this.riskLevel,
    required this.confidence,
    required this.expectedWindow,
  });
}

/// IFailurePredictor: Analyzes patterns to foresee outages.
abstract class IFailurePredictor {
  Future<List<PredictedFailure>> predict();
  void train(PredictedFailure prediction, bool actuallyFailed);
}

/// IWeakSignalDetector: Monitors subtle indicators of instability.
abstract class IWeakSignalDetector {
  double getCongestionLevel();
  double getInstabilityScore(FailureType type);
  Stream<double> monitorSignal(String signalName);
}

/// BrainConfidenceIndex (BCI): Central health score influencing brain decisions.
class BrainConfidence {
  final double score; // 0-100
  final DateTime timestamp;

  const BrainConfidence(this.score, this.timestamp);

  bool get fullOperation => score >= 90;
  bool get cautiousOperation => score >= 70 && score < 90;
  bool get smartRestriction => score >= 40 && score < 70;
  bool get preventCritical => score < 40;
}
