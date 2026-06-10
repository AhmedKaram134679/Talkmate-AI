import 'package:flutter/foundation.dart';

class ForensicLogger {
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
      'remoteUrl=${remoteUrl ?? "N/A"}, '
      'status=${status ?? "N/A"}, '
      'uploadProgress=$effectiveUploadProgress, '
      'generatedStorageKey=${generatedStorageKey ?? "N/A"}, '
      'fileExtension=${fileExtension ?? "N/A"}'
      '${extra != null ? ", extra=$extra" : ""}',
    );
  }
}

