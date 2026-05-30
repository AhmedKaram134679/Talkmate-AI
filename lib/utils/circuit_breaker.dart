import 'dart:async';
import 'package:talkmate_ai/core/utils/app_logger.dart';

enum CircuitState { closed, open, halfOpen }

/// A production safeguard that prevents repeated attempts to failing services.
class CircuitBreaker {
  final String serviceName;
  final int failureThreshold;
  final Duration resetTimeout;

  int _failureCount = 0;
  DateTime? _lastFailureTime;
  CircuitState _state = CircuitState.closed;

  CircuitBreaker({
    required this.serviceName,
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(seconds: 30),
  });

  CircuitState get state {
    if (_state == CircuitState.open && _lastFailureTime != null) {
      if (DateTime.now().difference(_lastFailureTime!) > resetTimeout) {
        return CircuitState.halfOpen;
      }
    }
    return _state;
  }

  Future<T> execute<T>(Future<T> Function() action) async {
    if (state == CircuitState.open) {
      AppLogger.warning(
          'CircuitBreaker [$serviceName]: Circuit is OPEN. Rejecting execution.');
      throw Exception(
          'Service $serviceName is temporarily unavailable (Circuit Breaker)');
    }

    try {
      final result = await action();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure(e);
      rethrow;
    }
  }

  void _onSuccess() {
    if (_state != CircuitState.closed) {
      AppLogger.info(
          'CircuitBreaker [$serviceName]: Service recovered. Closing circuit.');
    }
    _failureCount = 0;
    _state = CircuitState.closed;
  }

  void _onFailure(Object error) {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    AppLogger.error(
        'CircuitBreaker [$serviceName]: Failure detected ($_failureCount/$failureThreshold)',
        error: error);

    if (_failureCount >= failureThreshold) {
      AppLogger.critical(
          'CircuitBreaker [$serviceName]: TRIP! Circuit is now OPEN.');
      _state = CircuitState.open;
    }
  }
}
