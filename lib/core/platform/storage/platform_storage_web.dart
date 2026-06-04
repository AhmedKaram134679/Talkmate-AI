import 'platform_storage_interface.dart';

class WebStorage implements IPlatformStorage {
  @override
  Future<String> getAppDataDirectory() async {
    return 'web_root'; // Virtual root for Web
  }

  @override
  Future<void> deleteFile(String path) async {
    // No-op for direct file system deletion on Web
  }

  @override
  Future<bool> fileExists(String path) async {
    return false; // Files don't exist on virtual disk usually
  }
}

IPlatformStorage getPlatformStorage() => WebStorage();
