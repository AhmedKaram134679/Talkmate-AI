import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/feature_intelligence/models/experience_record.dart';

/// Stores and retrieves experience records.
/// Currently in-memory, but designed to be swappable for Hive/SQLite.
class FeatureMemoryStore extends GetxService {
  // Map<FeatureId, List<ExperienceRecord>>
  final Map<String, List<ExperienceRecord>> _memory = {};

  final int _maxHistoryPerFeature = 50; // Keep memory light

  void record(ExperienceRecord record) {
    if (!_memory.containsKey(record.featureId)) {
      _memory[record.featureId] = [];
    }

    final history = _memory[record.featureId]!;
    history.add(record);

    // Prune old memories
    if (history.length > _maxHistoryPerFeature) {
      history.removeAt(0);
    }

    debugPrint(
        '🧠 Memory: Recorded ${record.outcome.name} for ${record.featureId} in context ${record.contextHash}');
  }

  /// Get relevant history for a feature in a specific context.
  List<ExperienceRecord> getRelevantHistory(
      String featureId, String contextHash) {
    final history = _memory[featureId] ?? [];
    // Filter by context match
    return history.where((r) => r.contextHash == contextHash).toList();
  }

  /// Get all history for a feature (regardless of context)
  List<ExperienceRecord> getHistory(String featureId) {
    return _memory[featureId] ?? [];
  }

  /// Calculate success rate (0.0 - 1.0) for a specific context.
  double getSuccessRate(String featureId, String contextHash) {
    final related = getRelevantHistory(featureId, contextHash);
    if (related.isEmpty) return 1.0; // Optimistic default

    final successful = related
        .where((r) =>
            r.outcome == PolicyOutcome.success ||
            r.outcome == PolicyOutcome.degraded)
        .length;
    return successful / related.length;
  }

  void clear() {
    _memory.clear();
  }
}
