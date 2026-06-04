import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';

/// Secure local storage for sensitive user data.
class EncryptedStorageService extends GetxService {
  static EncryptedStorageService get instance => Get.find();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Writes a value to secure storage.
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e, stack) {
      AppLogger.error('Security: Failed to write to secure storage',
          error: e, stackTrace: stack);
    }
  }

  /// Reads a value from secure storage.
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e, stack) {
      AppLogger.error('Security: Failed to read from secure storage',
          error: e, stackTrace: stack);
      return null;
    }
  }

  /// Deletes a value from secure storage.
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      AppLogger.error('Security: Failed to delete from secure storage',
          error: e);
    }
  }

  /// Clear all secure storage (Logout scenario).
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
      AppLogger.info('Security: Secure storage wiped successfully');
    } catch (e) {
      AppLogger.error('Security: Critical failure during storage wipe',
          error: e);
    }
  }
}
