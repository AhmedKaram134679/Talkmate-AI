import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/models/message_model.dart';
import 'package:talkmate_ai/screens/chat_screen.dart';
import 'package:talkmate_ai/services/platform/deep_link_queue.dart';
import 'package:talkmate_ai/utils/deep_link_logger.dart';

class PlatformService extends GetxService {
  static PlatformService get instance => Get.find();

  final _appLinks = AppLinks();
  StreamSubscription? _linkSubscription;
  StreamSubscription? _sharedIntentSubscription;
  String? _lastProcessedDeepLink; // Prevent duplicate processing

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
    DeepLinkLogger.log('DEEP_LINK_INIT_STARTED');
    
    try {
      // Check initial link if app was opened by a link
      DeepLinkLogger.log('REQUESTING_INITIAL_LINK');
      _appLinks.getInitialLink().then((uri) {
        if (uri != null) {
          DeepLinkLogger.logUri(uri, prefix: 'INITIAL_URI');
          _handleUri(uri);
        } else {
          DeepLinkLogger.log('INITIAL_LINK_NULL - app launched normally');
        }
      }).catchError((error) {
        DeepLinkLogger.logException('getInitialLink', error);
      });

      // Listen for incoming links while app is running
      DeepLinkLogger.log('SUBSCRIBING_TO_URI_STREAM');
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          DeepLinkLogger.logUri(uri, prefix: 'STREAM_URI');
          _handleUri(uri);
        },
        onError: (err) {
          DeepLinkLogger.log('STREAM_ERROR = $err');
          debugPrint('Deep Link Error: $err');
        },
      );
      
      DeepLinkLogger.log('DEEP_LINK_INIT_COMPLETE');
    } catch (e, stackTrace) {
      DeepLinkLogger.logException('_initDeepLinks', e, stackTrace: stackTrace);
      debugPrint('Deep Link initialization error: $e');
    }
  }

  void _handleUri(Uri uri) {
    DeepLinkLogger.log('HANDLE_URI_CALLED');
    DeepLinkLogger.logUri(uri, prefix: 'HANDLING');

    // ⚠️ CRITICAL ARCHITECTURAL RULE:
    // Deep Link layer MUST NOT access Supabase.
    // All business logic (code exchange, session verification) moved to screens.
    // This layer only parses URIs and queues navigation.

    // Prevent duplicate processing of the same Deep Link
    final uriString = uri.toString();
    if (_lastProcessedDeepLink == uriString) {
      DeepLinkLogger.log('DUPLICATE_DEEP_LINK_SKIPPED - same URI processed recently');
      return;
    }
    _lastProcessedDeepLink = uriString;

    try {
      // Parse and validate
      final scheme = uri.scheme;
      final host = uri.host;
      final path = uri.path;
      final pathSegments = uri.pathSegments;

      DeepLinkLogger.log('SCHEME = $scheme');
      DeepLinkLogger.log('HOST = $host');
      DeepLinkLogger.log('PATH = $path');
      DeepLinkLogger.log('PATH_SEGMENTS = ${pathSegments.join("/")}');

      // Validate scheme
      if (scheme != 'talkmate') {
        DeepLinkLogger.log('✗ INVALID_SCHEME - expected talkmate, got $scheme');
        return;
      }

      DeepLinkLogger.log('✓ SCHEME_VALID');

      // Route to appropriate screen based on host and path

      // CHAT route: talkmate://chat/id
      DeepLinkLogger.logDecision('CHAT_ROUTE');
      if (host == 'chat' && pathSegments.isNotEmpty) {
        final chatId = pathSegments.first;
        DeepLinkLogger.logMatched('CHAT_ROUTE');
        DeepLinkLogger.logNavigation('CHAT_SCREEN', args: {'chatId': chatId});

        try {
          _navigateToChat(chatId);
        } catch (e, st) {
          DeepLinkLogger.logNavigationFailure('CHAT_SCREEN', e.toString());
          DeepLinkLogger.logException('CHAT_NAVIGATION', e, stackTrace: st);
        }
        return;
      }

      // RESET_PASSWORD route: talkmate://auth/reset-password?code=xxx
      DeepLinkLogger.logDecision('RESET_PASSWORD_ROUTE');
      if (host == 'auth' && pathSegments.isNotEmpty && pathSegments.first == 'reset-password') {
        DeepLinkLogger.logMatched('RESET_PASSWORD_ROUTE');
        
        // Extract recovery code from query parameters (PKCE flow)
        final recoveryCode = uri.queryParameters['code'];
        if (recoveryCode != null && recoveryCode.isNotEmpty) {
          DeepLinkLogger.log('RECOVERY_CODE_DETECTED');
          DeepLinkLogger.log('RECOVERY_CODE_LENGTH = ${recoveryCode.length}');
          DeepLinkLogger.logNavigation('RESET_PASSWORD_SCREEN');
          
          try {
            _navigateToResetPasswordWithCodeExchange(recoveryCode);
          } catch (e, st) {
            DeepLinkLogger.logNavigationFailure('RESET_PASSWORD_SCREEN', e.toString());
            DeepLinkLogger.logException('RESET_PASSWORD_NAVIGATION', e, stackTrace: st);
          }
        } else {
          DeepLinkLogger.log('✗ RESET_PASSWORD_NO_CODE - code parameter missing');
          DeepLinkLogger.logNavigation('RESET_PASSWORD_SCREEN');
          
          try {
            _navigateToResetPassword();
          } catch (e, st) {
            DeepLinkLogger.logNavigationFailure('RESET_PASSWORD_SCREEN', e.toString());
            DeepLinkLogger.logException('RESET_PASSWORD_NAVIGATION', e, stackTrace: st);
          }
        }
        return;
      }

      // No matching route
      DeepLinkLogger.log('✗ NO_MATCHING_ROUTE for scheme=$scheme, host=$host, path=$path');
    } catch (e, stackTrace) {
      DeepLinkLogger.logException('_handleUri', e, stackTrace: stackTrace);
      debugPrint('Error handling Deep Link: $e');
    }
  }

  void _navigateToChat(String chatId) {
    DeepLinkLogger.log('_navigateToChat CALLED with chatId=$chatId');
    try {
      final chatController = Get.find<ChatController>();
      final chat =
          chatController.activeChats.firstWhereOrNull((c) => c.id == chatId);
      if (chat != null) {
        DeepLinkLogger.log('CHAT_FOUND - attempting navigation');
        
        final isQueued = DeepLinkQueue().queueNavigation(
          routeName: '/chat',
          arguments: {'chat': chat},
        );
        
        if (!isQueued) {
          // Navigation executed immediately
          DeepLinkLogger.log('✓ CHAT_NAVIGATION_EXECUTED');
        }
      } else {
        DeepLinkLogger.log('✗ CHAT_NOT_FOUND for chatId=$chatId');
        debugPrint('Chat not found for deep link: $chatId');
      }
    } catch (e, st) {
      DeepLinkLogger.logException('_navigateToChat', e, stackTrace: st);
      DeepLinkLogger.log('✗ CHAT_NAVIGATION_FAILED: ${e.toString()}');
    }
  }

  void _navigateToResetPassword() {
    DeepLinkLogger.log('_navigateToResetPassword CALLED');
    DeepLinkLogger.log('ARCHITECTURAL_RULE: No Supabase checks in Deep Link layer');
    
    try {
      DeepLinkLogger.log('QUEUEING_NAVIGATION to /auth/reset-password');
      
      final isQueued = DeepLinkQueue().queueNavigation(
        routeName: '/auth/reset-password',
      );
      
      if (!isQueued) {
        // Navigation executed immediately
        DeepLinkLogger.log('✓ RESET_PASSWORD_NAVIGATION_EXECUTED_IMMEDIATELY');
      } else {
        DeepLinkLogger.log('✓ RESET_PASSWORD_NAVIGATION_QUEUED');
      }
    } catch (e, st) {
      DeepLinkLogger.logException('_navigateToResetPassword', e, stackTrace: st);
      DeepLinkLogger.log('✗ RESET_PASSWORD_NAVIGATION_FAILED: ${e.toString()}');
      debugPrint('Error navigating to Reset Password: $e');
    }
  }

    /// Exchange PKCE recovery code for session, then navigate to reset password screen
  Future<void> _navigateToResetPasswordWithCodeExchange(String code) async {
    DeepLinkLogger.log('_navigateToResetPasswordWithCodeExchange CALLED');
    DeepLinkLogger.log('ARCHITECTURAL_RULE: No Supabase code exchange in Deep Link layer');
    
    try {
      // ⚠️ CRITICAL: Pass recovery code to screen, NOT exchange here.
      // All PKCE logic moved to ResetPasswordScreen.initState()
      DeepLinkLogger.log('RECOVERY_CODE_RECEIVED - passing to ResetPasswordScreen');
      DeepLinkLogger.log('CODE_LENGTH = ${code.length}');
      
      // Queue navigation with recovery code parameter
      final isQueued = DeepLinkQueue().queueNavigation(
        routeName: '/auth/reset-password',
        arguments: {'recoveryCode': code},
      );
      
      if (!isQueued) {
        // Navigation executed immediately
        DeepLinkLogger.log('✓ RESET_PASSWORD_NAVIGATION_EXECUTED_WITH_CODE');
      } else {
        DeepLinkLogger.log('✓ RESET_PASSWORD_NAVIGATION_QUEUED_WITH_CODE');
      }
    } catch (e, st) {
      DeepLinkLogger.log('✗ NAVIGATION_QUEUE_FAILED: ${e.toString()}');
      DeepLinkLogger.logException('_navigateToResetPasswordWithCodeExchange', e, stackTrace: st);
      debugPrint('Error queuing Reset Password with code: $e\nStackTrace: $st');
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
    final context = Get.context;
    if (context == null) return;
    final l10n = AppLocalizations.of(context);
    final chatController = Get.isRegistered<ChatController>() ? ChatController.to : null;
    if (chatController == null) return;

    final chats = chatController.chats;
    if (chats.isEmpty) {
      Get.snackbar(
        'مشاركة',
        'لا توجد محادثات نشطة للمشاركة معها',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    Get.dialog(
      AlertDialog(
        title: const Text('مشاركة'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text != null ? 'إرسال النص إلى:' : 'إرسال الملفات إلى:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(chat.getDisplayName(l10n).characters.firstOrNull ?? '?'),
                      ),
                      title: Text(
                        chat.getDisplayName(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        Get.back(); // Dismiss picker
                        if (text != null && text.isNotEmpty) {
                          await chatController.sendMessage(
                            chatId: chat.id,
                            content: text,
                            type: MessageType.text,
                          );
                        }
                        if (files != null && files.isNotEmpty) {
                          for (final file in files) {
                            if (file.path.isNotEmpty) {
                              await chatController.sendMessage(
                                chatId: chat.id,
                                content: file.path,
                                type: MessageType.file,
                              );
                            }
                          }
                        }
                        await Get.to(() => ChatScreen(chat: chat));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }
}
