import 'package:flutter/foundation.dart';

class ForensicLogger {
  /// Sanitize remote URLs by stripping query parameters (such as temporary HMAC signed tokens)
  static String sanitizeUrl(String? url) {
    if (url == null || url.isEmpty || url == 'N/A') return 'N/A';
    try {
      final uri = Uri.parse(url);
      if (uri.hasQuery || uri.hasFragment) {
        return Uri(
          scheme: uri.scheme.isNotEmpty ? uri.scheme : null,
          userInfo: uri.userInfo.isNotEmpty ? uri.userInfo : null,
          host: uri.host.isNotEmpty ? uri.host : null,
          port: uri.hasPort ? uri.port : null,
          path: uri.path,
        ).toString();
      }
      return url;
    } catch (_) {
      return '[REDACTED_URL]';
    }
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
    final effectiveLocalFilePath = localFilePath ?? localPath ?? 'N/A';
    final effectiveUploadProgress = uploadProgress ?? 0.0;

    debugPrint(
      '🎬 [$tag] '
      'messageId=${messageId.isEmpty ? "N/A" : messageId}, '
      'localId=$effectiveLocalId, '
      'chatId=${chatId ?? "N/A"}, '
      'taskId=${taskId ?? "N/A"}, '
      'filename=$effectiveFilename, '
      'originalFileName=${originalFileName ?? effectiveFilename}, '
      'localFilePath=$effectiveLocalFilePath, '
      'thumbnailPath=${thumbnailPath ?? "N/A"}, '
      'remoteUrl=${sanitizeUrl(remoteUrl)}, '
      'status=${status ?? "N/A"}, '
      'uploadProgress=$effectiveUploadProgress, '
      'generatedStorageKey=${generatedStorageKey ?? "N/A"}, '
      'fileExtension=${fileExtension ?? "N/A"}'
      '${extra != null ? ", extra=$extra" : ""}',
    );
  }
}

