import 'package:flutter/foundation.dart';

/// DecisionOutcome: The finalized action to be taken on an event.
enum DecisionOutcome {
  display, // Show the notification/UI immediately
  queue, // Hold for later (e.g., missed call log, pending message)
  cancel, // Drop the event entirely
  silent, // Process data but don't alert user (e.g., badge only)
  logOnly, // Internal tracking only
}

/// EngagementDecision: A deterministic object explaining WHY a decision was made.
@immutable
class EngagementDecision {
  final DecisionOutcome outcome;
  final String reason;
  final int priority;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  EngagementDecision({
    required this.outcome,
    required this.reason,
    required this.priority,
    this.metadata = const {},
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'DECISION: [$outcome] Priority: $priority | Reason: $reason';
}

/// DecisionLogEntry: Struct for auditing the engine's history.
class DecisionLogEntry {
  final String eventType;
  final String source;
  final EngagementDecision decision;
  final String systemState;

  DecisionLogEntry({
    required this.eventType,
    required this.source,
    required this.decision,
    required this.systemState,
  });
}
