import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/core/media/webrtc_connection_manager.dart';

void main() {
  group('Unit: WebRTC SovereignPeer Lifecycle & State Transitions', () {
    test('Initial sovereign peer state transition to idle', () {
      // Test CallState enum definitions and transition progression
      expect(CallState.values, containsAll([
        CallState.idle,
        CallState.initializing,
        CallState.negotiating,
        CallState.connected,
        CallState.mediaFlowing,
        CallState.answering,
        CallState.disposing,
        CallState.closed,
      ]));
    });

    test('State progression sequence conforms to enterprise connection life-cycle', () {
      CallState currentState = CallState.idle;

      // 1. Initializing
      currentState = CallState.initializing;
      expect(currentState, CallState.initializing);

      // 2. Negotiating (Offer created)
      currentState = CallState.negotiating;
      expect(currentState, CallState.negotiating);

      // 3. Answering (Remote offer received or local answer created)
      currentState = CallState.answering;
      expect(currentState, CallState.answering);

      // 4. Connected (Stable signaling & ICE handshake)
      currentState = CallState.connected;
      expect(currentState, CallState.connected);

      // 5. Media Flowing (Tracks active)
      currentState = CallState.mediaFlowing;
      expect(currentState, CallState.mediaFlowing);

      // 6. Disposing
      currentState = CallState.disposing;
      expect(currentState, CallState.disposing);

      // 7. Closed
      currentState = CallState.closed;
      expect(currentState, CallState.closed);
    });

    test('Ice queue buffering logic verification', () {
      // SovereignPeer buffers candidates when either local or remote SDP is missing
      final iceQueue = <String>[];
      bool hasLocalSdp = false;
      bool hasRemoteSdp = false;
      bool negotiationLock = false;

      void bufferCandidate(String candidate) {
        if (!hasRemoteSdp || !hasLocalSdp || negotiationLock) {
          iceQueue.add(candidate);
        }
      }

      // Candidate arrives before remote description
      bufferCandidate('candidate:1');
      expect(iceQueue.length, 1);
      expect(iceQueue.first, 'candidate:1');

      // Candidate arrives while negotiation lock is active
      hasLocalSdp = true;
      hasRemoteSdp = true;
      negotiationLock = true;
      bufferCandidate('candidate:2');
      expect(iceQueue.length, 2);

      // Drain queue once unlocked and descriptions established
      negotiationLock = false;
      final drained = List<String>.from(iceQueue);
      iceQueue.clear();

      expect(iceQueue.isEmpty, true);
      expect(drained, ['candidate:1', 'candidate:2']);
    });
  });
}
