import 'package:flutter/foundation.dart';

class ForensicLogger {
  /// Sanitize remote URLs by stripping user credentials (username/password),
  /// HMAC signed query parameters (tokens), and URL fragments.
  static String sanitizeUrl(String? url) {
    if (url == null || url.isEmpty || url == 'N/A') return 'N/A';
    try {
      final uri = Uri.parse(url);
      return Uri(
        scheme: uri.scheme.isNotEmpty ? uri.scheme : null,
        userInfo: null, // Strictly remove credentials
        host: uri.host.isNotEmpty ? uri.host : null,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString();
    } catch (_) {
      return '[REDACTED_URL]';
    }
  }

  /// Sanitize local file paths to prevent leaking user home directories
  static String sanitizePath(String? path) {
    if (path == null || path.isEmpty || path == 'N/A') return 'N/A';
    if (path.contains('/') || path.contains(r'\')) {
      final parts = path.split(RegExp(r'[/\\]'));
      return parts.isNotEmpty ? parts.last : 'N/A';
    }
    return path;
  }

  /// Sanitize extra metadata to avoid leaking sensitive arbitrary free-form strings
  static String sanitizeExtra(String? extra) {
    if (extra == null || extra.isEmpty) return '';
    return extra.replaceAll(
      RegExp(r'(token|code|key|secret|password|jwt|auth)=[^\s&,]+', caseSensitive: false),
      '[REDACTED]',
    );
  }

  static void log({
    required String tag,
    required String messageId,
    String? localId,
    String? chatId,
    String? taskId,
    String? filename,
    String? localFilePath,
    String? thumbnailPath,
    String? remoteUrl,
    String? status,
    double? uploadProgress,
    // New parameters for STORAGE keys sanitization validation
    String? originalFileName,
    String? generatedStorageKey,
    String? fileExtension,
    // Legacy parameters for backward compatibility
    String? fileName,
    String? localPath,
    int? fileSize,
    String? extra,
  }) {
    final effectiveLocalId = localId ?? (messageId.isNotEmpty ? messageId : 'N/A');
    final effectiveFilename = filename ?? originalFileName ?? fileName ?? 'N/A';
    final effectiveLocalFilePath = sanitizePath(localFilePath ?? localPath);
    final effectiveUploadProgress = uploadProgress ?? 0.0;
    final sanitizedExtraStr = sanitizeExtra(extra);

    debugPrint(
      '🎬 [$tag] '
      'messageId=${messageId.isEmpty ? "N/A" : messageId}, '
      'localId=$effectiveLocalId, '
      'chatId=${chatId ?? "N/A"}, '
      'taskId=${taskId ?? "N/A"}, '
      'filename=$effectiveFilename, '
      'originalFileName=${originalFileName ?? effectiveFilename}, '
      'localFilePath=$effectiveLocalFilePath, '
      'thumbnailPath=${sanitizePath(thumbnailPath)}, '
      'remoteUrl=${sanitizeUrl(remoteUrl)}, '
      'status=${status ?? "N/A"}, '
      'uploadProgress=$effectiveUploadProgress, '
      'generatedStorageKey=${generatedStorageKey ?? "N/A"}, '
      'fileExtension=${fileExtension ?? "N/A"}'
      '${sanitizedExtraStr.isNotEmpty ? ", extra=$sanitizedExtraStr" : ""}',
    );
  }
}
