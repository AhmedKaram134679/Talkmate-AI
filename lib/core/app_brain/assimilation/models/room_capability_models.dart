/// Enum representing individual room capabilities (G7).
enum RoomCapability {
  audio,
  video,
  screenShare,
  dataChannel,
  whiteboard,
}

/// Predefined Room Profiles based on combined capabilities.
enum RoomProfile {
  meeting, // Audio + Video + ScreenShare
  lecture, // Audio + Video (Host Only) + ScreenShare
  gameStream, // Audio + High Performance ScreenShare
  hybrid, // Dynamic switching
  support, // Audio + ScreenShare
}

/// Resolution profiles for sovereign quality control.
enum VideoResolution {
  r240p,
  r360p,
  r480p,
  r720p,
  r1080p,
}

/// Metadata for a specific stream capability.
class StreamProfile {
  final VideoResolution resolution;
  final int frameRate;
  final int maxBitrate; // in kbps

  const StreamProfile({
    required this.resolution,
    this.frameRate = 30,
    required this.maxBitrate,
  });

  static const low = StreamProfile(
      resolution: VideoResolution.r240p, frameRate: 15, maxBitrate: 300);
  static const standard = StreamProfile(
      resolution: VideoResolution.r480p, frameRate: 30, maxBitrate: 1000);
  static const high = StreamProfile(
      resolution: VideoResolution.r720p, frameRate: 30, maxBitrate: 2500);
  static const ultra = StreamProfile(
      resolution: VideoResolution.r1080p, frameRate: 60, maxBitrate: 6000);
}
