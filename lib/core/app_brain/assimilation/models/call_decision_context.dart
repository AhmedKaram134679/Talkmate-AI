/// Context for making call-related decisions (resources, network, etc.)
class CallDecisionContext {
  final double networkQuality; // 0.0 (Dead) to 1.0 (Excellent)
  final double batteryLevel; // 0.0 to 1.0
  final bool isOnLowDataMode;
  final int concurrentCalls;

  CallDecisionContext({
    required this.networkQuality,
    required this.batteryLevel,
    this.isOnLowDataMode = false,
    this.concurrentCalls = 1,
  });

  Map<String, dynamic> toMap() => {
        'networkQuality': networkQuality,
        'batteryLevel': batteryLevel,
        'lowData': isOnLowDataMode,
        'concurrency': concurrentCalls,
      };
}
