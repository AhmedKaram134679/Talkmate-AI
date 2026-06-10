import 'dart:io';
import 'package:intl/intl.dart';

/// Production-safe Deep Link diagnostic logger
/// Writes to: C:\Temp\talkmate_deeplink.log (Windows)
///            /tmp/talkmate_deeplink.log (Linux/macOS)
///
/// Usage:
/// DeepLinkLogger.log('MESSAGE');
/// DeepLinkLogger.logUri(uri);
/// DeepLinkLogger.logException('CONTEXT', exception);
class DeepLinkLogger {
  static late File _logFile;
  static bool _initialized = false;

  /// Initialize logger (call once at app startup)
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final logPath = _getLogPath();
      final logDir = Directory(logPath).parent;

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
  static String _getLogPath() {
    if (Platform.isWindows) {
      return r'C:\Temp\talkmate_deeplink.log';
    } else if (Platform.isMacOS || Platform.isLinux) {
      return '/tmp/talkmate_deeplink.log';
    } else if (Platform.isAndroid) {
      return '/sdcard/talkmate_deeplink.log';
    } else if (Platform.isIOS) {
      return '/tmp/talkmate_deeplink.log';
    }
    return '/tmp/talkmate_deeplink.log';
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

  /// Log a URI with all components parsed
  static void logUri(Uri? uri, {String prefix = 'URI'}) {
    if (!_initialized || uri == null) return;

    try {
      log('$prefix = $uri');
      log('  SCHEME = ${uri.scheme}');
      log('  HOST = ${uri.host}');
      log('  PATH = ${uri.path}');
      log('  PATH_SEGMENTS = ${uri.pathSegments.join("/")}');
      log('  QUERY = ${uri.query}');
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

  /// Log navigation attempt
  static void logNavigation(String destination, {Map<String, dynamic>? args}) {
    if (!_initialized) return;

    try {
      String msg = 'NAVIGATING TO $destination';
      if (args != null) {
        msg += ' (args: $args)';
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
