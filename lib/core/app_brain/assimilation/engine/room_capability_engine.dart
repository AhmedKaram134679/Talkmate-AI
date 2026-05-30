import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/room_capability_models.dart';

/// Room Capability Engine (G7).
/// Manages what a room can do and negotiates hardware limits sovereignly.
class RoomCapabilityEngine extends GetxService {
  final _activeCapabilities = <RoomCapability>{}.obs;
  final _currentProfile = RoomProfile.meeting.obs;
  final _userPreferredResolution = VideoResolution.r720p.obs;

  Set<RoomCapability> get activeCapabilities => _activeCapabilities;
  RoomProfile get currentProfile => _currentProfile.value;
  VideoResolution get preferredResolution => _userPreferredResolution.value;

  /// Updates room profile and adjusts capabilities dynamicly.
  void switchProfile(RoomProfile profile) {
    _currentProfile.value = profile;
    debugPrint('🏢 RoomCapability: Switching to profile: ${profile.name}');

    _activeCapabilities.clear();
    _activeCapabilities.add(RoomCapability.audio); // Always enabled

    switch (profile) {
      case RoomProfile.meeting:
        _activeCapabilities
            .addAll([RoomCapability.video, RoomCapability.screenShare]);
        break;
      case RoomProfile.lecture:
        _activeCapabilities
            .addAll([RoomCapability.video, RoomCapability.screenShare]);
        break;
      case RoomProfile.gameStream:
        _activeCapabilities.add(RoomCapability.screenShare);
        break;
      case RoomProfile.support:
        _activeCapabilities.add(RoomCapability.screenShare);
        break;
      case RoomProfile.hybrid:
        _activeCapabilities.addAll([
          RoomCapability.video,
          RoomCapability.screenShare,
          RoomCapability.dataChannel
        ]);
        break;
    }
  }

  /// Sovereign Quality Adjustment (G7).
  void setPreferredResolution(VideoResolution resolution) {
    _userPreferredResolution.value = resolution;
    debugPrint(
        '📉 RoomCapability: User requested quality change to ${resolution.name}');
  }

  /// Negotiate if a capability is supported by current hardware/platform.
  bool isCapabilitySupported(RoomCapability capability) {
    if (kIsWeb && capability == RoomCapability.screenShare) return true;
    if (GetPlatform.isWindows) return true;
    if (GetPlatform.isAndroid) {
      // Android might have specific limits (e.g. background screen share)
      return true;
    }
    return false;
  }

  /// Toggles a specific capability without switching profile.
  void toggleCapability(RoomCapability capability, bool enable) {
    if (enable) {
      if (isCapabilitySupported(capability)) {
        _activeCapabilities.add(capability);
      }
    } else {
      _activeCapabilities.remove(capability);
    }
    debugPrint('⚡ RoomCapability: Capability ${capability.name} -> $enable');
  }
}
