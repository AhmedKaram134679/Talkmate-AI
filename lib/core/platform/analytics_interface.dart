import 'dart:async';

/// Abstract interface for analytics and performance tracking.
abstract class IPlatformAnalytics {
  /// Initializes the analytics engine.
  Future<void> initialize();

  /// Logs a custom event.
  Future<void> logEvent(String name, {Map<String, dynamic>? parameters});

  /// Sets user properties.
  Future<void> setUserProperty(String name, String value);
}
