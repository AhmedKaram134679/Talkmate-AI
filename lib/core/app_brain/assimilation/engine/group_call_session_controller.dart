import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/communication/communication_session.dart';
import '../models/group_call_models.dart';
import '../models/room_capability_models.dart';
import 'audio_presence_controller.dart';
import 'media_hardening_manager.dart';
import 'room_capability_engine.dart';
import 'sovereign_communication_engine.dart';

/// Group Call Session Controller (G5).
/// Orchestrates multi-participant voice rooms with strict state isolation.
class GroupCallSessionController extends GetxService {
  final _participants = <String, GroupParticipant>{}.obs;
  final _sessionState = ParticipantMediaState.leaving.obs;
  String? _activeRoomId;
  String? get activeRoomId => _activeRoomId;
  ParticipantMediaState get sessionState => _sessionState.value;

  final _hardening = Get.find<MediaSessionHardeningManager>();
  final _audioPresence = Get.find<AudioPresenceController>();
  final _capabilities = Get.find<RoomCapabilityEngine>();
  final _commEngine = Get.find<SovereignCommunicationEngine>();

  /// List of active participants.
  List<GroupParticipant> get participants => _participants.values.toList();

  /// Updates the room's operational profile (G7).
  void updateRoomProfile(RoomProfile profile) {
    _capabilities.switchProfile(profile);
    debugPrint('🏢 GroupCall: Room configuration UPDATED to ${profile.name}');
  }

  /// Starts or joins a group voice room.
  Future<bool> joinRoom(String roomId, String userId, String displayName,
      ParticipantRole role) async {
    debugPrint('👥 GroupCall: User $userId joining room $roomId...');

    // Stage C3: Unified Comm Lock
    final metadata = CommSessionMetadata(
      sessionId: roomId,
      type: CommunicationSessionType.room,
      topic: roomId, // Topic could be fetched from room model if available here
    );
    final locked = await _commEngine.requestSessionLock(
        roomId, CommunicationSessionType.room,
        metadata: metadata);
    if (!locked) return false;

    // 1. Initial State: Joining
    final newParticipant = GroupParticipant(
      userId: userId,
      displayName: displayName,
      role: role,
      state: ParticipantMediaState.joining,
      joinedAt: DateTime.now(),
    );
    _participants[userId] = newParticipant;
    _activeRoomId = roomId;

    // 2. Sovereign Protection (Unified C3 Path)
    await _commEngine.activateProtection(userId);

    // 3. Set Active
    _participants[userId] =
        _participants[userId]!.copyWith(state: ParticipantMediaState.active);
    _sessionState.value = ParticipantMediaState.active;
    debugPrint('✅ GroupCall: User $userId is now ACTIVE in room $roomId');
    return true;
  }

  /// Toggles mute for a specific participant.
  void toggleMute(String userId, bool muted) {
    if (_participants.containsKey(userId)) {
      _participants[userId] = _participants[userId]!.copyWith(
        isMuted: muted,
        state:
            muted ? ParticipantMediaState.muted : ParticipantMediaState.active,
      );
      debugPrint('🎙️ GroupCall: User $userId mute state -> $muted');
    }
  }

  /// Leaves the current room and cleans up.
  Future<void> leaveRoom(String userId) async {
    if (_participants.containsKey(userId)) {
      _participants[userId] =
          _participants[userId]!.copyWith(state: ParticipantMediaState.leaving);
      await Future.delayed(
          const Duration(milliseconds: 100)); // Graceful period
      _removeParticipant(userId);

      // Unified C3 Release
      await _commEngine.endSession(userId);
    }
  }

  void _removeParticipant(String userId) {
    _participants.remove(userId);
    _audioPresence.removeUser(userId);

    if (_participants.isEmpty) {
      _activeRoomId = null;
      _hardening.releaseSession();
    }
    debugPrint('👤 GroupCall: Participant $userId removed.');
  }

  /// Emergency Kill for the entire room.
  void killRoom() {
    debugPrint('🛑 GROUP ROOM HARD KILL: Evicting all participants.');
    for (var userId in _participants.keys.toList()) {
      _removeParticipant(userId);
    }
  }

  @override
  void onClose() {
    killRoom();
    super.onClose();
  }
}
