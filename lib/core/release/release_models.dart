/// Environment types
enum AppEnvironment { production, staging, internal }

/// Release statuses
enum ReleaseStatus { active, deprecated, blocked, rollback }

/// Feature Flag states
enum FeatureState { enabled, disabled, softDisabled, hardKill }

/// Model for a release configuration
class ReleaseConfig {
  final String version;
  final String buildNumber;
  final ReleaseStatus status;
  final AppEnvironment environment;
  final Map<String, FeatureState> features;
  final DateTime updatedAt;

  ReleaseConfig({
    required this.version,
    required this.buildNumber,
    required this.status,
    required this.environment,
    this.features = const {},
  }) : updatedAt = DateTime.now();

  bool get isBlocked => status == ReleaseStatus.blocked;
  bool get needsRollback => status == ReleaseStatus.rollback;
}
