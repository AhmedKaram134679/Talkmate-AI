import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';

class PlatformService extends GetxService {
  static PlatformService get instance => Get.find();

  final _appLinks = AppLinks();
  StreamSubscription? _linkSubscription;
  StreamSubscription? _sharedIntentSubscription;

  @override
  void onInit() {
    super.onInit();
    if (AppConfig.enableDeepLinks) {
      _initDeepLinks();
    }
    if (AppConfig.enableShareIntents &&
        (GetPlatform.isAndroid || GetPlatform.isIOS)) {
      _initShareIntents();
    }
  }

  @override
  void onClose() {
    _linkSubscription?.cancel();
    _sharedIntentSubscription?.cancel();
    super.onClose();
  }

  // --- Deep Links ---

  void _initDeepLinks() {
    // Check initial link if app was opened by a link
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleUri(uri);
    });

    // Listen for incoming links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    }, onError: (err) {
      debugPrint('Deep Link Error: $err');
    });
  }

  void _handleUri(Uri uri) {
    debugPrint('Handling Deep Link: $uri');
    // Example: talkmate://chat/<id>
    if (uri.scheme == 'talkmate' && uri.host == 'chat') {
      final chatId =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (chatId != null) {
        _navigateToChat(chatId);
      }
    }
  }

  void _navigateToChat(String chatId) {
    final chatController = Get.find<ChatController>();
    final chat =
        chatController.activeChats.firstWhereOrNull((c) => c.id == chatId);
    if (chat != null) {
      Get.toNamed('/chat', arguments: {'chat': chat});
    } else {
      debugPrint('Chat not found for deep link: $chatId');
    }
  }

  // --- Share Intents ---

  void _initShareIntents() {
    // Listen for shared media/text while the app is in memory
    _sharedIntentSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) {
        _handleSharedFiles(value);
      }
    }, onError: (err) {
      debugPrint('Sharing stream error: $err');
    });

    // Handle initial shared content if the app was opened via share
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        _handleSharedFiles(value);
      }
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    debugPrint('Shared content received: ${files.length} items');

    // Filter text/links vs files
    final texts = files
        .where((f) =>
            f.type == SharedMediaType.text || f.type == SharedMediaType.url)
        .toList();
    final media = files
        .where((f) =>
            f.type != SharedMediaType.text && f.type != SharedMediaType.url)
        .toList();

    if (texts.isNotEmpty) {
      _showShareTargetPicker(text: texts.map((t) => t.path).join('\n'));
    } else if (media.isNotEmpty) {
      _showShareTargetPicker(files: media);
    }
  }

  void _showShareTargetPicker({String? text, List<SharedMediaFile>? files}) {
    // Logic to show a dialog or screen to select a chat to share the content with
    Get.snackbar(
      'مشاركة محتوى',
      text != null ? 'نص مشترك: $text' : 'ملفات مشتركة: ${files?.length}',
      backgroundColor: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}
