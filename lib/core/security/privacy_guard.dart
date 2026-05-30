import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Ensures no PII (Personally Identifiable Information) leaks into telemetry.
class PrivacyGuard {
  /// Masks an ID or sensitive string using SHA-256 for tracking without PII.
  static String maskIdentifier(String? id) {
    if (id == null || id.isEmpty) return 'anonymous';

    // Create a deterministic hash of the ID
    final bytes = utf8.encode(id);
    final hash = sha256.convert(bytes);

    // Return a short version of the hash
    return hash.toString().substring(0, 12);
  }

  /// Sanitizes a log message or data map to remove potentially sensitive content.
  static Map<String, dynamic> sanitizeContext(Map<String, dynamic>? context) {
    if (context == null) return {};

    final sanitized = Map<String, dynamic>.from(context);

    // Sensitive keys to be removed or masked
    const sensitiveKeys = {
      'email',
      'password',
      'token',
      'auth',
      'secret',
      'message_content',
      'text',
      'address'
    };

    for (var key in context.keys) {
      final lowerKey = key.toLowerCase();
      if (sensitiveKeys.any((s) => lowerKey.contains(s))) {
        sanitized[key] = '[REDACTED_BY_PRIVACY_GUARD]';
      } else if (sanitized[key] is Map) {
        sanitized[key] = sanitizeContext(sanitized[key]);
      }
    }

    return sanitized;
  }

  /// Verifies if a piece of data is safe for public logs.
  static bool isSafeForLogging(String data) {
    // Basic heuristics to detect potential PII or secrets
    // e.g. Regex for emails, long random strings (tokens), etc.
    final emailRegex =
        RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}');
    return !emailRegex.hasMatch(data);
  }
}
