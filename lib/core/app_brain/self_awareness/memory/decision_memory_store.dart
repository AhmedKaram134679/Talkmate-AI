// Using basic List since Queue might need import 'dart:collection';

/// Short-term memory for recent decisions.
class DecisionMemoryStore {
  final List<dynamic> _traces =
      []; // Using dynamic to avoid circular dependency issues if any, but properly it's DecisionTrace
  static const int maxCapacity = 50;

  void addTrace(dynamic trace) {
    if (_traces.length >= maxCapacity) {
      _traces.removeAt(0); // Remove oldest
    }
    _traces.add(trace);
  }

  List<dynamic> getRecentTraces() => List.unmodifiable(_traces);

  int get blockCount =>
      _traces.where((t) => (t as Object).toString().contains('block')).length;
}
