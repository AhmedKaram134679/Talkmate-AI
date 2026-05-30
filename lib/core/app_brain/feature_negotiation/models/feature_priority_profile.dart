/// Defines how important a feature is relative to others.
class FeaturePriorityProfile {
  final int basePriority;
  final bool isCritical; // If true, difficult to block
  final double userSensitivity; // 0.0 - 1.0 (How mad will user get if blocked?)

  const FeaturePriorityProfile({
    required this.basePriority,
    this.isCritical = false,
    this.userSensitivity = 0.5,
  });

  // Predefined Profiles
  static const critical = FeaturePriorityProfile(
      basePriority: 90, isCritical: true, userSensitivity: 1.0);
  static const high =
      FeaturePriorityProfile(basePriority: 70, userSensitivity: 0.8);
  static const normal =
      FeaturePriorityProfile(basePriority: 40, userSensitivity: 0.5);
  static const background =
      FeaturePriorityProfile(basePriority: 10, userSensitivity: 0.1);
}
