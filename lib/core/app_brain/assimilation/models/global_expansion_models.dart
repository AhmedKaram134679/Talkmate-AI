/// Global Regions for Sovereign Data Residency (G11).
enum GlobalRegion {
  naEast, // North America East
  naWest, // North America West
  euCentral, // Europe Central
  meSouth, // Middle East South
  asiaEast, // Asia East
  localOrg, // On-premise / Local Organization
}

/// Scaling states for global nodes.
enum NodeScalingState {
  cold, // Initializing
  warm, // Ready for sessions
  hot, // Near capacity
  overloaded, // Refusing new sessions
  draining, // Graceful shutdown
}

/// Metadata for a global infrastructure node.
class GlobalNode {
  final String nodeId;
  final GlobalRegion region;
  final String ipAddress;
  final NodeScalingState state;
  final int activeSessions;
  final int maxCapacity;

  const GlobalNode({
    required this.nodeId,
    required this.region,
    required this.ipAddress,
    required this.state,
    required this.activeSessions,
    required this.maxCapacity,
  });

  double get loadFactor => activeSessions / maxCapacity;
}

/// Deployment strategy for global rooms.
enum DeploymentStrategy {
  latencyFirst, // Closest node to user
  residencyStrict, // Must stay in specific region
  enterprisePrivate, // Local org infrastructure only
  balanced, // Cost/Performance balance
}
