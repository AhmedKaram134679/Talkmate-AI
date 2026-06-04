import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../feature_gatekeeper.dart';
import '../models/session_identity_models.dart';
import '../models/session_sovereignty_models.dart';

/// Session Legitimacy Manager (F4 Sovereign Layer).
/// Manages identities, trust, and dynamic permissions within a session.
class SessionLegitimacyManager extends GetxService {
  final _gatekeeper = Get.find<FeatureGatekeeper>();

  final Map<String, List<SessionParticipant>> _activeParticipants = {};
  final Map<String, Map<String, ParticipantTrustStatus>> _trustStore = {};

  /// Validate entry and register a participant into the session sovereignty.
  Future<SessionParticipant?> validateAndRegister(String sessionId,
      String userId, SessionRole requestedRole, JoinContext context) async {
    debugPrint('⚖️ Legitimacy: Validating entry for $userId into $sessionId');

    // 1. Initial Gatekeeping
    final response = _gatekeeper.requestAccess('multimedia_system_v1',
        action: 'join_session');
    if (!response.isAllowed) {
      debugPrint('🛑 Legitimacy: Entry REJECTED: ${response.reason}');
      return null;
    }

    // 2. Create Sovereign ID
    final participant = SessionParticipant(
      participantId:
          'p_${DateTime.now().millisecondsSinceEpoch}_${userId.hashCode}',
      userId: userId,
      role: requestedRole,
      verification: requestedRole == SessionRole.host
          ? VerificationLevel.fullyVerified
          : VerificationLevel.softVerified,
      context: context,
      joinedAt: DateTime.now(),
    );

    // 3. Register and Initialize Trust
    _activeParticipants.putIfAbsent(sessionId, () => []).add(participant);
    _trustStore.putIfAbsent(sessionId, () => {})[participant.participantId] =
        ParticipantTrustStatus(participantId: participant.participantId);

    debugPrint(
        '✅ Legitimacy: Participant ${participant.participantId} Registered as ${participant.role}');
    return participant;
  }

  /// Calculates dynamic permissions for a participant based on current sovereignty state.
  SessionPermissions getPermissions(String sessionId, String participantId) {
    final participants = _activeParticipants[sessionId] ?? [];
    final participant = participants.firstWhere(
        (p) => p.participantId == participantId,
        orElse: () =>
            throw Exception('Participant not found in session sovereignty'));

    final trust = _trustStore[sessionId]?[participantId];
    final basePermissions = SessionPermissions.fromRole(participant.role);

    // Dynamic Throttling based on Trust Score
    if (trust != null && trust.trustScore < 30.0) {
      debugPrint(
          '⚠️ Legitimacy: Trust Score LOW ($trust.trustScore). Restricting permissions for $participantId');
      return SessionPermissions(
          canSpeak: false,
          canUseVideo: false,
          canInvite: false,
          canShareScreen: false);
    }

    return basePermissions;
  }

  /// Purges all session data (Constitutional Privacy Compliance).
  void purgeSessionSovereignty(String sessionId) {
    debugPrint(
        '🧼 Legitimacy: PURGING session sovereignty for $sessionId. Zeroing Trust Scores.');
    _activeParticipants.remove(sessionId);
    _trustStore.remove(sessionId);
  }
}
