import 'dart:typed_data';

import 'package:image_picker/image_picker.dart'; // Provides XFile
import 'package:supabase_flutter/supabase_flutter.dart';

/// StorageService: wraps Supabase Storage uploads and returns public URLs
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final _client = Supabase.instance.client;
  static const String _bucket = 'talkmate';

  /// Upload a file from an [XFile] to a storage [path] and return the public URL
  Future<(String url, int size)> uploadFile({
    required XFile file,
    required String path,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    return uploadBytes(bytes: bytes, path: path, onProgress: onProgress);
  }

  /// Upload raw bytes and return URL
  Future<(String url, int size)> uploadBytes({
    required List<int> bytes,
    required String path,
    void Function(double progress)? onProgress,
  }) async {
    // Supabase storage doesn't have a built-in progress stream for putData
    // in the same way as Firebase, but we can call onProgress if needed
    // (though for small files it's almost instant).

    await _client.storage.from(_bucket).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: _inferContentType(path),
            upsert: true,
          ),
          // retryAttempts: 3,
        );

    final url = _client.storage.from(_bucket).getPublicUrl(path);
    final size = bytes.length;

    // Simulate completion progress if listener provided
    onProgress?.call(1.0);

    return (url, size);
  }

  String _inferContentType(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.mp4')) return 'video/mp4';
    if (p.endsWith('.mov')) return 'video/quicktime';
    if (p.endsWith('.mp3')) return 'audio/mpeg';
    if (p.endsWith('.m4a')) return 'audio/mp4';
    if (p.endsWith('.aac')) return 'audio/aac';
    if (p.endsWith('.wav')) return 'audio/wav';
    if (p.endsWith('.pdf')) return 'application/pdf';
    if (p.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }
}
