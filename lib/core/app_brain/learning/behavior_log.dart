import 'package:flutter/foundation.dart';
import 'user_behavior_model.dart';

/// BehaviorLogEntry: Record of an observed user interaction pattern.
@immutable
class BehaviorLogEntry {
  final DateTime timestamp;
  final String source;
  final String interactionType; // e.g., 'ignored', 'responded', 'delayed'
  final Duration? responseTime;
  final String detectedPatternSuggestion;

  BehaviorLogEntry({
    required this.source,
    required this.interactionType,
    this.responseTime,
    this.detectedPatternSuggestion = '',
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      '[$timestamp] $source: $interactionType ${responseTime != null ? "in ${responseTime!.inSeconds}s" : ""}';
}

/// BehaviorLog: The auditing system for the Smart Learning Layer.
class BehaviorLog {
  final List<BehaviorLogEntry> _logs = [];

  void add(BehaviorLogEntry entry) {
    _logs.add(entry);
    debugPrint('BehaviorLog: $entry');
  }

  List<BehaviorLogEntry> get logs => List.unmodifiable(_logs);

  /// Analyzes the last N logs to see if a consistent pattern is emerging.
  List<BehaviorPattern> detectEmergingPatterns() {
    if (_logs.length < 10) return [];

    final List<BehaviorPattern> patterns = [];

    // 1. Analyze "Ignore" rate in the last 20 events
    final lastEvents =
        _logs.length > 20 ? _logs.sublist(_logs.length - 20) : _logs;
    final ignoreCount =
        lastEvents.where((log) => log.interactionType == 'ignored').length;

    if (ignoreCount / lastEvents.length > 0.8) {
      patterns.add(BehaviorPattern.ignoreRepetitive);
    }

    // 2. Analyze time-based patterns (Night Owl)
    final nightEvents = _logs
        .where((log) => log.timestamp.hour >= 22 || log.timestamp.hour <= 5)
        .length;
    if (nightEvents > _logs.length * 0.4 && _logs.length > 50) {
      patterns.add(BehaviorPattern.nightOwl);
    }

    return patterns;
  }
}
