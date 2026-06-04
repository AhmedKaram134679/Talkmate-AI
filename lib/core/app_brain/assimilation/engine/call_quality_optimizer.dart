import 'package:flutter/foundation.dart';

import '../models/assimilation_result.dart';
import '../models/call_decision_context.dart';
import '../models/participant_call_profile.dart';

/// Engine that optimizes call quality for each participant based on Brain decisions.
class CallQualityOptimizer {
  /// Optimizes a participant's profile based on the Brain's assimilation result and resource context.
  static void optimize(ParticipantCallProfile participant,
      AssimilationResult brainResult, CallDecisionContext resourceContext) {
    debugPrint('⚙️ Optimizing quality for ${participant.participantId}...');

    // 1. Check Global Block
    if (!brainResult.isAllowed) {
      participant.quality = CallQuality.audioOnly;
      participant.isMuted = true;
      return;
    }

    // 2. Resource-driven Baseline
    if (resourceContext.networkQuality < 0.3 ||
        resourceContext.batteryLevel < 0.1) {
      participant.quality = CallQuality.audioOnly;
    } else if (resourceContext.networkQuality < 0.6 ||
        resourceContext.isOnLowDataMode) {
      participant.quality = CallQuality.lowVideo;
    } else {
      participant.quality = CallQuality.highVideo;
    }

    // 3. Brain Constraint Overrides
    final constraints = brainResult.constraints;

    if (constraints['video_enabled'] == false) {
      participant.quality = CallQuality.audioOnly;
    } else if (constraints['reduce_bitrate'] == true) {
      if (participant.quality == CallQuality.highVideo) {
        participant.quality = CallQuality.lowVideo;
      }
    }

    // Group call scaling: If many participants, favor audio/low-video to save resources
    if (resourceContext.concurrentCalls > 4 &&
        participant.quality == CallQuality.highVideo) {
      participant.quality = CallQuality.lowVideo;
    }

    debugPrint('✅ Final quality: ${participant.quality.name}');
  }
}
