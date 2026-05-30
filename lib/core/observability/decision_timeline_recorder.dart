import 'dart:collection';
import 'observability_contracts.dart';

/// DecisionTimelineRecorder: In-memory circular buffer for the last 100 decisions.
class DecisionTimelineRecorder implements IDecisionTraceable {
  static final DecisionTimelineRecorder instance = DecisionTimelineRecorder._();
  DecisionTimelineRecorder._();

  final ListQueue<ObservedDecision> _history = ListQueue<ObservedDecision>(100);
  static const int _maxSize = 100;

  @override
  List<ObservedDecision> get recentDecisions =>
      List.unmodifiable(_history.toList().reversed);

  @override
  void record(ObservedDecision decision) {
    if (_history.length >= _maxSize) {
      _history.removeFirst();
    }
    _history.addLast(decision);
  }

  void clear() {
    _history.clear();
  }
}
