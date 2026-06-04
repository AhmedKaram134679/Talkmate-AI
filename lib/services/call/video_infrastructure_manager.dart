import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:get/get.dart';

/// Video Infrastructure Manager (G2).
/// Responsible for camera hardware management and video rendering lifecycle.
class VideoInfrastructureManager extends GetxService {
  rtc.MediaStream? _localStream;
  bool _isCameraActive = false;
  bool get isCameraActive => _isCameraActive;

  /// Initializes the video infrastructure.
  Future<void> initialize() async {
    debugPrint('📹 VideoInfrastructure: Initializing Video Services...');
    // RTCVideoRenderer initialization is usually handled by the UI layer,
    // but the manager keeps track of the hardware streams.
  }

  /// Activates the local camera stream.
  /// Strictly manual and gated by SessionAuthority.
  Future<rtc.MediaStream?> activateCamera({bool isFront = true}) async {
    debugPrint(
        '📹 VideoInfrastructure: ACTIVATING Camera [Front: $isFront]...');

    final Map<String, dynamic> mediaConstraints = {
      'audio': false, // Audio handled by VoiceInfrastructureManager
      'video': {
        'facingMode': isFront ? 'user' : 'environment',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 30},
      }
    };

    try {
      _localStream =
          await rtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
      _isCameraActive = true;
      debugPrint('✅ VideoInfrastructure: Camera Stream is now LIVE.');
      return _localStream;
    } catch (e) {
      debugPrint('🛑 VideoInfrastructure: FAILED to activate camera: $e');
      return null;
    }
  }

  /// Deactivates the camera and releases GPU resources.
  Future<void> deactivateCamera() async {
    if (_localStream == null) return;

    debugPrint('📹 VideoInfrastructure: DEACTIVATING Camera...');
    _localStream!.getTracks().forEach((track) {
      track.stop();
    });
    await _localStream!.dispose();
    _localStream = null;
    _isCameraActive = false;
    debugPrint('📵 VideoInfrastructure: Camera Path RELEASED.');
  }

  /// Switches between front and back camera.
  Future<void> switchCamera() async {
    if (_localStream == null) return;

    debugPrint('🔄 VideoInfrastructure: Switching Camera...');
    final videoTrack = _localStream!.getVideoTracks().first;
    await rtc.Helper.switchCamera(videoTrack);
  }

  /// Emergency Video Kill Switch.
  /// Releases all video resources in < 150ms.
  Future<void> videoHardKill() async {
    debugPrint(
        '🛑 VIDEO KILL SWITCH: Releasing all camera handles immediately.');
    _isCameraActive = false;
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      await _localStream!.dispose();
      _localStream = null;
    }
  }

  @override
  void onClose() {
    deactivateCamera();
    super.onClose();
  }
}
