import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../app_brain.dart';
import '../memory/feature_memory_store.dart';
import '../models/experience_record.dart';
import '../scoring/fis_calculator.dart';

/// The Adaptive Policy Engine replaces static rules with intelligent decisions.
class AdaptivePolicyEngine extends GetxService {
  final FeatureMemoryStore _memory = Get.put(FeatureMemoryStore());
  final FeatureIntelligenceScore _fis = Get.put(FeatureIntelligenceScore());

  /// Resolve the best policy for a feature given the current global state.
  Map<String, dynamic> resolvePolicy(AppSystemState state, String featureId) {
    // 1. Determine Context Hash
    final contextHash = _getContextHash(state);

    // 2. Calculate Intelligence Score (How much do we trust this feature here?)
    final score = _fis.calculateScore(featureId, contextHash);

    debugPrint(
        '🧠 Engine: Resolving for $featureId (State: ${state.name}, FIS: ${score.toStringAsFixed(1)})');

    // 3. Decide Strategy based on Score
    if (score < 40) {
      return _generateStrictPolicy(state, featureId);
    } else if (score < 80) {
      return _generateAdaptivePolicy(state, featureId);
    } else {
      return _generateExperimentalPolicy(state, featureId);
    }
  }

  /// Safe, rigid rules (Fallback for low trust/new implementations)
  Map<String, dynamic> _generateStrictPolicy(
      AppSystemState state, String featureId) {
    // Similar to Stage F1 rules
    switch (state) {
      case AppSystemState.emergency:
        return {'enabled': false};
      case AppSystemState.background:
        if (featureId == 'calls_v1') {
          return {'video_enabled': false, 'reduce_bitrate': true};
        }
        break;
      default:
        break;
    }
    return {};
  }

  /// Balanced approach (Try to degrade gracefully)
  Map<String, dynamic> _generateAdaptivePolicy(
      AppSystemState state, String featureId) {
    // Check memory for recent failures
    final recentFailures = _memory
        .getHistory(featureId)
        .where((e) => e.outcome == PolicyOutcome.failure)
        .length;

    if (state == AppSystemState.background && featureId == 'calls_v1') {
      if (recentFailures > 2) {
        // Policy failed often? Be strict.
        return {'video_enabled': false, 'reduce_bitrate': true};
      }
      // Instead of forcing video off, maybe just reduce quality if history says it worked?
      return {
        'video_enabled': false,
        'reduce_bitrate': true
      }; // Keep safe defaults for now
    }
    // Notifications: Don't silence completely, maybe just Heads-up off
    if (state == AppSystemState.calling && featureId == 'notifications') {
      return {'sound': false, 'heads_up': true}; // Soft constraint
    }
    return {};
  }

  /// High trust approach (Maximize UX, risk minor issues)
  Map<String, dynamic> _generateExperimentalPolicy(
      AppSystemState state, String featureId) {
    // If highly trusted, maybe we allow video in PIP even in background?
    // For now, let's keep it safe but logging intended behavior.
    return _generateAdaptivePolicy(state, featureId);
  }

  String _getContextHash(AppSystemState state) {
    // In future, mix in Network + Battery levels here
    return state.name;
  }
}
