import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Production-safe Deep Link diagnostic logger
/// Writes exclusively to application-private support storage on all platforms:
///            `<app_support_dir>`/talkmate_deeplink.log (sandboxed, never /sdcard, C:\Temp, or /tmp)
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
    'email',
  };

  /// Initialize logger (call once at app startup)
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final logPath = await _getLogPath();
      if (logPath == null) {
        _initialized = false;
        return;
      }
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

  /// Get platform-specific log file path in private app storage across all platforms
  static Future<String?> _getLogPath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return p.join(dir.path, 'talkmate_deeplink.log');
    } catch (_) {
      // Fail closed: do not fall back to shared public temp directories like C:\Temp or /tmp
      return null;
    }
  }

  /// Recursively sanitize any collection or value
  static dynamic sanitizeValue(dynamic value) {
    if (value is Map) {
      return sanitizeMap(value.cast<String, dynamic>());
    } else if (value is List) {
      return value.map(sanitizeValue).toList();
    }
    return value;
  }

  /// Sanitize query parameters or map arguments to avoid leaking secrets/tokens recursively
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
      } else {
        sanitized[entry.key] = sanitizeValue(entry.value);
      }
    }
    return sanitized;
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

  /// Log URI metadata safely without logging any query parameter values, fragments, or raw URIs
  static void logUri(Uri? uri, {String prefix = 'URI'}) {
    if (!_initialized || uri == null) return;

    try {
      log('$prefix: scheme=${uri.scheme}, host=${uri.host}, path=${uri.path}');
      if (uri.pathSegments.isNotEmpty) {
        log('  PATH_SEGMENTS = ${uri.pathSegments.join("/")}');
      }
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

  static const Set<String> _allowedRoutes = {
    '/',
    '/auth/login',
    '/auth/register',
    '/auth/reset-password',
    '/home',
    '/chat',
    '/chat/details',
    '/settings',
    '/call',
    '/profile',
    '/groups/create',
  };

  static String _safeRoute(String destination) {
    final clean = destination.trim().split('?').first;
    if (_allowedRoutes.contains(clean)) return clean;
    return '[OTHER_ROUTE]';
  }

  static String _safeFailureReason(String reason) {
    final lower = reason.toLowerCase();
    if (lower.contains('not found') || lower.contains('404')) return 'ROUTE_NOT_FOUND';
    if (lower.contains('auth') || lower.contains('unauthorized') || lower.contains('login')) return 'AUTH_REQUIRED';
    if (lower.contains('cancel')) return 'USER_CANCELLED';
    if (lower.contains('param') || lower.contains('argument') || lower.contains('invalid')) return 'INVALID_PARAMS';
    return 'NAVIGATION_ERROR';
  }

  /// Log an exception with sanitized context and runtimeType (never raw message/PII/stackTrace)
  static void logException(String context, Object exception, {StackTrace? stackTrace}) {
    if (!_initialized) return;

    try {
      log('EXCEPTION [$context]: errorType=${exception.runtimeType}');
      // Stack traces are omitted in production diagnostics to avoid leaking internal paths or tokens
    } catch (_) {
      // Silently fail
    }
  }

  /// Log a decision point (route checking)
  static void logDecision(String routeName) {
    if (!_initialized) return;

    try {
      log('CHECKING ${_safeRoute(routeName)}');
    } catch (_) {
      // Silently fail
    }
  }

  /// Log a matched route
  static void logMatched(String routeName) {
    if (!_initialized) return;

    try {
      log('✓ MATCHED ${_safeRoute(routeName)}');
    } catch (_) {
      // Silently fail
    }
  }

  /// Log navigation attempt with sanitized arguments
  static void logNavigation(String destination, {Map<String, dynamic>? args}) {
    if (!_initialized) return;

    try {
      String msg = 'NAVIGATING TO ${_safeRoute(destination)}';
      if (args != null && args.isNotEmpty) {
        msg += ' (args: ${sanitizeMap(args)})';
      }
      log(msg);
    } catch (_) {
      // Silently fail
    }
  }

  /// Log navigation success
  static void logNavigationSuccess(String destination) {
    if (!_initialized) return;

    try {
      log('✓ NAVIGATION SUCCESS: ${_safeRoute(destination)}');
    } catch (_) {
      // Silently fail
    }
  }

  /// Log navigation failure
  static void logNavigationFailure(String destination, String reason) {
    if (!_initialized) return;

    try {
      log('✗ NAVIGATION FAILED: ${_safeRoute(destination)} - ${_safeFailureReason(reason)}');
    } catch (_) {
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
    } catch (_) {
      // Silently fail
    }
  }

  /// Get current log contents (for debugging)
  static Future<String> getLogContents() async {
    if (!_initialized) return 'Logger not initialized';

    try {
      return await _logFile.readAsString();
    } catch (_) {
      return 'Error reading log: [FAILED]';
    }
  }
}
