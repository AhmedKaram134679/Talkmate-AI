import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'platform_storage_interface.dart';

class MobileStorage implements IPlatformStorage {
  @override
  Future<String> getAppDataDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = io.File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> fileExists(String path) async {
    return await io.File(path).exists();
  }
}

IPlatformStorage getPlatformStorage() => MobileStorage();
