import 'package:flutter/foundation.dart';

/// InteractionProfile: Statistical data about user interaction with features.
@immutable
class InteractionProfile {
  final Map<String, FeatureStats> features;

  const InteractionProfile({
    this.features = const {},
  });

  InteractionProfile copyWith({
    Map<String, FeatureStats>? features,
  }) {
    return InteractionProfile(
      features: features ?? this.features,
    );
  }
}

/// FeatureStats: Metrics for a specific feature (Chat, Call, etc.)
@immutable
class FeatureStats {
  final int eventCount;
  final int ignoreCount;
  final Duration averageResponseTime;
  final Map<int, int> hourlyDistribution; // Hour (0-23) -> Count

  const FeatureStats({
    this.eventCount = 0,
    this.ignoreCount = 0,
    this.averageResponseTime = Duration.zero,
    this.hourlyDistribution = const {},
  });

  double get ignoreRate => eventCount == 0 ? 0.0 : ignoreCount / eventCount;

  FeatureStats increment({bool ignored = false, Duration? responseTime}) {
    final now = DateTime.now();
    final newHourly = Map<int, int>.from(hourlyDistribution);
    newHourly[now.hour] = (newHourly[now.hour] ?? 0) + 1;

    return FeatureStats(
      eventCount: eventCount + 1,
      ignoreCount: ignoreCount + (ignored ? 1 : 0),
      averageResponseTime: responseTime != null
          ? Duration(
              milliseconds: (averageResponseTime.inMilliseconds +
                      responseTime.inMilliseconds) ~/
                  2)
          : averageResponseTime,
      hourlyDistribution: newHourly,
    );
  }
}

/// BehaviorPattern: Higher-level detected habits.
enum BehaviorPattern {
  nightOwl, // High activity at night
  busyMorning, // High ignore rate in morning
  callHeavy, // Prefers calls over texts
  textHeavy, // Prefers texts over calls
  ignoreRepetitive // Consistently ignores specific feature
}
