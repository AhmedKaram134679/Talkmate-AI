import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/audio_presence_models.dart';

/// Audio Presence Controller (G6).
/// Manages user speaking intentions and listening states sovereignly.
class AudioPresenceController extends GetxService {
  final _userStates = <String, AudioPresenceState>{}.obs;
  final _priorityTokens = <String, AudioPriorityToken>{}.obs;
  final _speakingQueue = <String>[].obs;

  /// Gets the current audio state of a participant.
  AudioPresenceState getState(String userId) =>
      _userStates[userId] ?? AudioPresenceState.silent;

  /// Requests permission to speak (Stage G6).
  Future<void> requestToSpeak(String userId) async {
    if (_userStates[userId] == AudioPresenceState.mutedSelf) {
      debugPrint('🛑 AudioPresence: Cannot request to speak while Self-Muted.');
      return;
    }

    _userStates[userId] = AudioPresenceState.requestingToSpeak;
    if (!_speakingQueue.contains(userId)) {
      _speakingQueue.add(userId);
    }
    debugPrint('🎙️ AudioPresence: User $userId is REQUESTING to speak.');
  }

  /// Grants permission to speak based on priority and queue.
  void grantSpeakingPower(String userId, {int priority = 1}) {
    _priorityTokens[userId] = AudioPriorityToken(
      level: priority,
      issuedAt: DateTime.now(),
      reason: 'Standard Allocation',
    );
    _userStates[userId] = AudioPresenceState.speaking;
    _speakingQueue.remove(userId);
    debugPrint(
        '✅ AudioPresence: Speaking power GRANTED to $userId [Priority: $priority]');
  }

  /// Implements Sovereign Mute (Stage G6).
  void applyMute(String userId, MuteType type, {String? reason}) {
    final oldState = getState(userId);
    debugPrint(
        '🔇 AudioPresence: Transitioning $userId from ${oldState.name} due to ${type.name} mute.');

    switch (type) {
      case MuteType.self:
        _userStates[userId] = AudioPresenceState.mutedSelf;
        _revokeSpeakingPower(userId, 'User self-muted');
        break;
      case MuteType.system:
        _userStates[userId] = AudioPresenceState.mutedSystem;
        _revokeSpeakingPower(userId, 'System protective mute: $reason');
        break;
      case MuteType.hostReq:
        debugPrint(
            '📋 AudioPresence: Host requested mute for $userId. Awaiting user consent.');
        // In G6, Host-Mute is a request, not a force.
        break;
    }
  }

  void _revokeSpeakingPower(String userId, String reason) {
    _priorityTokens.remove(userId);
    if (_userStates[userId] == AudioPresenceState.speaking) {
      _userStates[userId] = AudioPresenceState.silent;
    }
    debugPrint(
        '🔇 AudioPresence: Speaking power REVOKED for $userId. Reason: $reason');
  }

  /// Emergency Audio Hard Kill protocol (G6).
  void audioHardKill(String userId) {
    debugPrint('🛑 AUDIO HARD KILL for $userId: Forcing immediate silence.');
    _revokeSpeakingPower(userId, 'Hard Kill Protocol Triggered');
    _userStates[userId] = AudioPresenceState.silent;
  }

  /// Cleans up presence for a user.
  void removeUser(String userId) {
    _userStates.remove(userId);
    _priorityTokens.remove(userId);
    _speakingQueue.remove(userId);
    debugPrint('👤 AudioPresence: Records purged for user $userId');
  }

  List<String> get speakingQueue => _speakingQueue.toList();
}
