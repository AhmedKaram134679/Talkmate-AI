import 'platform_storage_interface.dart';

IPlatformStorage getPlatformStorage() => throw UnsupportedError(
      'Cannot create a IPlatformStorage without dart:html or dart:io',
    );
