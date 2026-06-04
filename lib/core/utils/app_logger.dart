import 'package:flutter/foundation.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/core/security/privacy_guard.dart';

enum LogLevel { info, warning, error, critical, brain, ui, security }

/// Centralized Production-Ready logger for TalkMate AI.
class AppLogger {
  static void _log(LogLevel level, String message,
      {Map<String, dynamic>? context, dynamic error, StackTrace? stackTrace}) {
    // Production Filter: Only log Warnings and above in Release unless explicitly enabled
    if (!kDebugMode &&
        !AppConfig.enableLogging &&
        level != LogLevel.error &&
        level != LogLevel.critical &&
        level != LogLevel.security) {
      return;
    }

    // Privacy Gate: Sanitize any data before it touches the console/storage
    final sanitizedContext = PrivacyGuard.sanitizeContext(context);

    final timestamp = DateTime.now().toIso8601String();
    final tag = level.name.toUpperCase();
    final formattedContext =
        sanitizedContext.isNotEmpty ? ' | Context: $sanitizedContext' : '';

    debugPrint('[$timestamp] [$tag] $message$formattedContext');

    if (error != null) debugPrint('   Error: $error');
    if (stackTrace != null) debugPrint('   StackTrace: $stackTrace');

    // Integration with Crashlytics or external logging services can be added here
  }

  static void info(String message, {Map<String, dynamic>? context}) =>
      _log(LogLevel.info, message, context: context);

  static void warning(String message, {Map<String, dynamic>? context}) =>
      _log(LogLevel.warning, message, context: context);

  static void error(String message,
          {Map<String, dynamic>? context,
          dynamic error,
          StackTrace? stackTrace}) =>
      _log(LogLevel.error, message,
          context: context, error: error, stackTrace: stackTrace);

  static void critical(String message,
          {Map<String, dynamic>? context,
          dynamic error,
          StackTrace? stackTrace}) =>
      _log(LogLevel.critical, message,
          context: context, error: error, stackTrace: stackTrace);

  static void security(String message, {Map<String, dynamic>? context}) =>
      _log(LogLevel.security, message, context: context);

  static void brain(String message, {Map<String, dynamic>? context}) =>
      _log(LogLevel.brain, message, context: context);

  static void ui(String message, {Map<String, dynamic>? context}) =>
      _log(LogLevel.ui, message, context: context);

  // Legacy compatibility wrappers
  static void d(String message) => info(message);
  static void e(String message, [dynamic error, StackTrace? stackTrace]) =>
      AppLogger.error(message, error: error, stackTrace: stackTrace);
}
