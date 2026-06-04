import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:get/get.dart';

/// CommunicationSessionType: The dual nature of TalkMate communication.
enum CommunicationSessionType { call, room }

/// [Stage R12]: Constitutional Network Quality (Clause 8)
enum CommunicationNetworkQuality { excellent, good, poor, unstable }

/// Unified model for a participant in any communication session.
class CommunicationParticipant {
  final String id; // user_id
  final String rowId; // DB entry id (room_participants or call_participants)
  final String name;
  final String? avatarUrl;
  final bool isSpeaker;
  final bool isLocal;
  final RxBool isMuted;
  final RxBool isTalking;
  final RxBool isVideoOn;
  final RxBool isOnline;
  final Rx<webrtc.MediaStream?> remoteStream = Rx<webrtc.MediaStream?>(null);
  // [ANDROID_SINK]: Persistent renderer to force audio binding and prevent GC
  webrtc.RTCVideoRenderer? audioSinkRenderer;

  CommunicationParticipant({
    required this.id,
    required this.rowId,
    required this.name,
    this.avatarUrl,
    this.isSpeaker = false,
    this.isLocal = false,
    bool isMuted = true,
    bool isTalking = false,
    bool isVideoOn = false,
    bool isOnline = false,
    webrtc.MediaStream? stream,
  })  : isMuted = isMuted.obs,
        isTalking = isTalking.obs,
        isVideoOn = isVideoOn.obs,
        isOnline = isOnline.obs {
    if (stream != null) remoteStream.value = stream;
  }

  CommunicationParticipant copyWith({
    String? name,
    String? avatarUrl,
    bool? isSpeaker,
    bool? isOnline,
  }) {
    final p = CommunicationParticipant(
      id: id,
      rowId: rowId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isSpeaker: isSpeaker ?? this.isSpeaker,
      isLocal: isLocal,
      isMuted: isMuted.value,
      isTalking: isTalking.value,
      isVideoOn: isVideoOn.value,
      isOnline: isOnline ?? this.isOnline.value,
    );
    p.remoteStream.value = remoteStream.value;
    return p;
  }
}

/// [SOVEREIGN_CONTRACT]: Defines the lifecycle of any communication session.
abstract class SessionLifecycle {
  Future<void> leaveSession({String? reason, String? securityContext});
}
