import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Production-safe Deep Link diagnostic logger
/// Writes to app-private storage on mobile devices:
///            Android: `<app_support_dir>`/talkmate_deeplink.log (sandboxed, never /sdcard)
///            iOS: `<app_support_dir>`/talkmate_deeplink.log
///            Windows: C:\Temp\talkmate_deeplink.log
///            Linux/macOS: /tmp/talkmate_deeplink.log
///
/// Usage:
/// DeepLinkLogger.log('MESSAGE');
/// DeepLinkLogger.logUri(uri);
/// DeepLinkLogger.logException('CONTEXT', exception);
class DeepLinkLogger {
  static late File _logFile;
  static bool _initialized = false;

  static const Set<String> _sensitiveKeyPatterns = {
    'code',
    'recoverycode',
    'token',
    'accesstoken',
    'refreshtoken',
    'password',
    'secret',
    'key',
    'apikey',
    'auth',
    'authorization',
  };

  /// Initialize logger (call once at app startup)
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final logPath = await _getLogPath();
      final logDir = Directory(p.dirname(logPath));

      // Create directory if needed
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      _logFile = File(logPath);
      _initialized = true;
      log('=== DEEP LINK LOGGER INITIALIZED ===');
    } catch (e) {
      // Silently fail - don't crash the app if logging fails
      _initialized = false;
    }
  }

  /// Get platform-specific log file path
  static Future<String> _getLogPath() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getApplicationSupportDirectory();
        return p.join(dir.path, 'talkmate_deeplink.log');
      }
    } catch (_) {
      // Fallback if path_provider fails in headless/test environments
    }

    if (Platform.isWindows) {
      return r'C:\Temp\talkmate_deeplink.log';
    } else if (Platform.isMacOS || Platform.isLinux) {
      return '/tmp/talkmate_deeplink.log';
    }
    return '/tmp/talkmate_deeplink.log';
  }

  /// Sanitize query parameters or map arguments to avoid leaking secrets/tokens
  static Map<String, dynamic> sanitizeMap(Map<String, dynamic>? map) {
    if (map == null) return {};
    final sanitized = <String, dynamic>{};
    for (final entry in map.entries) {
      final normalizedKey =
          entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final isSensitive = _sensitiveKeyPatterns.any(
        (pattern) => normalizedKey.contains(pattern),
      );
      if (isSensitive) {
        sanitized[entry.key] = '[REDACTED]';
      } else if (entry.value is Map<String, dynamic>) {
        sanitized[entry.key] =
            sanitizeMap(entry.value as Map<String, dynamic>);
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  /// Build a sanitized representation of a URI with sensitive query parameters and fragments redacted
  static String sanitizeUri(Uri? uri) {
    if (uri == null) return 'null';
    try {
      final sanitizedQueryParams = uri.queryParameters.map((key, value) {
        final normalizedKey =
            key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final isSensitive = _sensitiveKeyPatterns.any(
          (pattern) => normalizedKey.contains(pattern),
        );
        return MapEntry(
          key,
          isSensitive ? '[REDACTED]' : value,
        );
      });

      final sanitized = uri.replace(
        queryParameters:
            sanitizedQueryParams.isNotEmpty ? sanitizedQueryParams : null,
        fragment: uri.hasFragment ? '[REDACTED]' : null,
      );
      return sanitized.toString();
    } catch (_) {
      return '[REDACTED_URI]';
    }
  }

  /// Log a simple message with timestamp
  static void log(String message) {
    if (!_initialized) return;

    try {
      final timestamp = _getTimestamp();
      final logEntry = '[$timestamp] $message\n';

      _logFile.writeAsStringSync(
        logEntry,
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // Silently fail
    }
  }

  /// Log a URI safely without leaking sensitive tokens or query strings
  static void logUri(Uri? uri, {String prefix = 'URI'}) {
    if (!_initialized || uri == null) return;

    try {
      log('$prefix = ${sanitizeUri(uri)}');
      log('  SCHEME = ${uri.scheme}');
      log('  HOST = ${uri.host}');
      log('  PATH = ${uri.path}');
      log('  PATH_SEGMENTS = ${uri.pathSegments.join("/")}');
      if (uri.queryParameters.isNotEmpty) {
        log('  QUERY_KEYS = ${uri.queryParameters.keys.join(", ")}');
      } else {
        log('  QUERY_KEYS = (none)');
      }
      log('  HAS_FRAGMENT = ${uri.hasFragment}');
    } catch (e) {
      // Silently fail
    }
  }

  /// Log an exception with context
  static void logException(String context, Object exception, {StackTrace? stackTrace}) {
    if (!_initialized) return;

    try {
      log('EXCEPTION [$context]: $exception');
      if (stackTrace != null) {
        log('STACK_TRACE: $stackTrace');
      }
    } catch (e) {
      // Silently fail
    }
  }

  /// Log a decision point (route checking)
  static void logDecision(String routeName) {
    if (!_initialized) return;

    try {
      log('CHECKING $routeName');
    } catch (e) {
      // Silently fail
    }
  }

  /// Log a matched route
  static void logMatched(String routeName) {
    if (!_initialized) return;

    try {
      log('✓ MATCHED $routeName');
    } catch (e) {
      // Silently fail
    }
  }

  /// Log navigation attempt with sanitized arguments
  static void logNavigation(String destination, {Map<String, dynamic>? args}) {
    if (!_initialized) return;

    try {
      String msg = 'NAVIGATING TO $destination';
      if (args != null && args.isNotEmpty) {
        msg += ' (args: ${sanitizeMap(args)})';
      }
      log(msg);
    } catch (e) {
      // Silently fail
    }
  }

  /// Log navigation success
  static void logNavigationSuccess(String destination) {
    if (!_initialized) return;

    try {
      log('✓ NAVIGATION SUCCESS: $destination');
    } catch (e) {
      // Silently fail
    }
  }

  /// Log navigation failure
  static void logNavigationFailure(String destination, String reason) {
    if (!_initialized) return;

    try {
      log('✗ NAVIGATION FAILED: $destination - $reason');
    } catch (e) {
      // Silently fail
    }
  }

  /// Get formatted timestamp
  static String _getTimestamp() {
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
    return formatter.format(now);
  }

  /// Clear log file (for testing)
  static Future<void> clearLog() async {
    if (!_initialized) return;

    try {
      await _logFile.writeAsString('');
      log('LOG CLEARED');
    } catch (e) {
      // Silently fail
    }
  }

  /// Get current log contents (for debugging)
  static Future<String> getLogContents() async {
    if (!_initialized) return 'Logger not initialized';

    try {
      return await _logFile.readAsString();
    } catch (e) {
      return 'Error reading log: $e';
    }
  }
}
