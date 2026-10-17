import 'dart:async';
// Phase 6: attachments and audio recording
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/controllers/rooms_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_invitation_service.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/models/comm_invitation_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart' as data_user_models;
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/data/services/media_file_service.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/models/chat_model.dart';
import 'package:talkmate_ai/models/message_model.dart';
import 'package:talkmate_ai/models/room_model.dart';
import 'package:talkmate_ai/models/user_model.dart' as ui_user;
import 'package:talkmate_ai/screens/group_management_screen.dart'
    as group_management_ui;
import 'package:talkmate_ai/screens/profile_screen.dart';
import 'package:talkmate_ai/services/audio/app_audio_service.dart';
// Phase 6: WebRTC Calling
import 'package:talkmate_ai/services/call/call_manager.dart';
import 'package:talkmate_ai/widgets/chat/chat_message_bubble_widget.dart';
import 'package:talkmate_ai/widgets/communication/presence_indicator_widget.dart';
import 'package:talkmate_ai/widgets/communication/sovereign_comm_entry_sheet.dart';
import 'package:talkmate_ai/widgets/emoji_picker_widget.dart';
import 'package:talkmate_ai/widgets/notifications/in_app_notification_indicator.dart';
import 'package:talkmate_ai/widgets/reply_message_widget.dart';

class ChatScreen extends StatefulWidget {
  final ChatModel chat;
  final ui_user.UserModel? otherUser;
  final bool autoStartCall;
  final bool isVideoCall;

  const ChatScreen({
    super.key,
    required this.chat,
    this.otherUser,
    this.autoStartCall = false,
    this.isVideoCall = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AuthController authController = Get.find<AuthController>();
  final ChatController chatController = Get.find<ChatController>();
  AppLocalizations get l10n => AppLocalizations.of(context);
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  MessageModel? _replyToMessage;
  bool _showEmojiPicker = false;
  Timer? _typingDebounce;
  bool _isSearching = false;
  String _messageSearchQuery = '';
  // For navigating between results and programmatic scroll
  final Map<String, GlobalKey> _messageKeys = {};
  int _currentMatchIndex = 0;
  // Advanced search options
  bool _searchMatchCase = false;
  bool _searchWholeWord = false;
  bool _searchRegex = false;
  // Realtime other user status (Phase 4)
  StreamSubscription? _otherUserSub;
  data_user_models.AppUser? _otherUserData;
  // Audio recording (Phase 6)
  AudioRecorder? _recorder;
  bool _isRecordingAudio = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  double _recordingDragOffset = 0;
  final double _cancelThreshold = -100.0; // Distance to drag left to cancel

  // Multi-selection (Phase 7)
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  // Resolve other participant id for individual chats
  String? get _otherUserId {
    if (widget.chat.type == ChatType.group) return null;
    try {
      final me = authController.userId;
      return widget.chat.participantIds
          .firstWhere((id) => id != me, orElse: () => '');
    } catch (_) {
      return null;
    }
  }

  // Start a 1:1 WebRTC call via controller (Supabase signaling)
  Future<void> _startFireCall({required bool isVideo}) async {
    final l10n = AppLocalizations.of(context);
    final me = authController.userId;
    final other = _otherUserId;
    if (me.isEmpty || other == null || other.isEmpty) {
      Get.snackbar(l10n.error, l10n.sendFailedDetail,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
      return;
    }

    try {
      await CallManager.instance.startOutgoingCall(
        calleeId: other,
        isVideo: isVideo,
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      Get.snackbar(l10n.callFailed, e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  void _showCommEntrySheet() {
    final isGroup = widget.chat.type == ChatType.group;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SovereignCommEntrySheet(
        mode: isGroup ? CommEntryMode.group : CommEntryMode.individual,
        targetName: isGroup
            ? widget.chat.name
            : _otherUserData?.displayName ?? widget.chat.name,
        targetStatus: _otherUserData?.status,
        onStartIndividualCall: (isVideo) {
          final status = _otherUserData?.status;
          // Governance: If target is busy, suggest invitation instead of force call
          if (status == data_user_models.UserStatus.busy ||
              status == data_user_models.UserStatus.inCall ||
              status == data_user_models.UserStatus.inRoomVoice ||
              status == data_user_models.UserStatus.inRoomVideo) {
            _promptToSendInvitation(isVideo);
          } else {
            _startFireCall(isVideo: isVideo);
          }
        },
        onStartRoom: (isVideo) {
          // Initialize Room via Controller
          final roomsCtrl = Get.find<RoomsController>();
          roomsCtrl.createRoom(
            'Room: ${widget.chat.name}',
            isVideo ? RoomType.video : RoomType.voice,
          );
          // For now, C7 only handles entry. Real room navigation is in Stage C2 logic.
          Get.snackbar('تم إنشاء الغرفة', 'تم تجهيز مساحة البث الجماعي بنجاح.',
              snackPosition: SnackPosition.TOP);
        },
      ),
    );
  }

  Future<void> _promptToSendInvitation(bool isVideo) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('المستخدم مشغول'),
        content: Text(
            '${_otherUserData?.displayName ?? 'المستخدم'} في جلسة أخرى حالياً. هل ترغب في إرسال دعوة انضمام بدلاً من المقاطعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال دعوة'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_otherUserData != null) {
        await SovereignInvitationService.instance.sendInvitation(
          targetUserId: _otherUserData!.id,
          type: InvitationType.individualCall,
          isVideo: isVideo,
        );
      } else {
        Get.snackbar(l10n.error, 'Could not identify user to invite.',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<void> _attachSticker() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: const ['png', 'webp', 'gif', 'jpg', 'jpeg'],
      );
      final path = res?.files.single.path;
      if (path == null) return;
      // Cross-platform safe file wrapper
      final xFile = XFile(path);

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          // Fire and forget with an indeterminate progress
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              await chatController.sendStickerFile(
                chatId: widget.chat.id,
                file: xFile,
                replyToMessageId: _replyToMessage?.id,
              );
              if (mounted) {
                setState(() => _replyToMessage = null);
              }
            } catch (e) {
              debugPrint('attachSticker failed: $e');
              if (mounted) {
                Get.snackbar(
                  l10n.imageUploadFailed,
                  '${l10n.imageUploadDetail}\n$e',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            } finally {
              if (mounted && Navigator.of(this.context).canPop()) {
                Navigator.of(this.context).pop();
              }
            }
          });
          return AlertDialog(
            title: Text(l10n.stickerLabel),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(l10n.stickerUploading),
              ],
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('attachSticker outer failed: $e');
      if (mounted) {
        Get.snackbar(AppLocalizations.of(context).error,
            AppLocalizations.of(context).imageUploadFailed);
      }
    }
  }

  // Resolve the latest chat instance (reactive) by id, fallback to the initial one
  ChatModel get _currentChat {
    final list = chatController.chats;
    final idx = list.indexWhere((c) => c.id == widget.chat.id);
    return idx != -1 ? list[idx] : widget.chat;
  }

  Widget _buildPinnedBanner() {
    return FutureBuilder<String?>(
      future: chatController.getPinnedId(widget.chat.id),
      builder: (context, snap) {
        final pinnedId = snap.data;
        if (pinnedId == null || pinnedId.isEmpty) {
          return const SizedBox.shrink();
        }
        final all = chatController.chatMessages[widget.chat.id] ??
            const <MessageModel>[];
        MessageModel? msg;
        for (final m in all) {
          if (m.id == pinnedId) {
            msg = m;
            break;
          }
        }
        if (msg == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, left: 12, right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  msg.getDisplayContent(AppLocalizations.of(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await chatController.unpinMessage(widget.chat.id);
                  if (mounted) setState(() {});
                },
                child: Text(AppLocalizations.of(context).removeLabel),
              )
            ],
          ),
        );
      },
    );
  }

  String _computeStatusText() {
    final l10n = AppLocalizations.of(context);
    // If any other participant is typing, show typing
    final typingUsers = chatController
        .getTypingUserNames(widget.chat.id)
        .where((name) => name.isNotEmpty)
        .toList();
    if (typingUsers.isNotEmpty) {
      return l10n.typing;
    }
    // Otherwise show online/last seen from watched user
    final u = _otherUserData;
    if (u == null) {
      return l10n.online; // fallback until data arrives
    }
    if (u.status == data_user_models.UserStatus.online) {
      return l10n.statusOnline; // was 'متصل الآن'
    }
    if (u.lastSeen != null) {
      return '${l10n.lastSeen} ${_formatLastSeen(u.lastSeen!)}';
    }
    return l10n.statusOffline;
  }

  String _formatLastSeen(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    final l10n = AppLocalizations.of(context);
    if (difference.inMinutes < 1) return l10n.justNow;
    if (difference.inMinutes < 60) return l10n.minutesAgo(difference.inMinutes);

    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final seenDate = DateTime(dt.year, dt.month, dt.day);

    final time = DateFormat.Hm(l10n.localeName).format(dt);

    if (seenDate == today) {
      return l10n.todayAt(time);
    } else if (seenDate == yesterday) {
      return l10n.yesterdayAt(time);
    } else {
      final date = DateFormat.yMMMd(l10n.localeName).format(dt);
      return l10n.dateTimeAt(date, time);
    }
  }

  Future<void> _showDeleteChatDialog() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteChatTitle),
        content: Text(l10n.deleteChatConfirmWithName(
          _currentChat.getDisplayName(AppLocalizations.of(context)),
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await chatController.deleteChat(_currentChat.id);
      if (mounted) {
        Get.back();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    chatController.setActiveChat(widget.chat.id);
    // activation trigger listener
    ever(chatController.showFirstMessageSuccess, (bool show) {
      if (show && mounted) {
        _showSuccessMoment();
        chatController.showFirstMessageSuccess.value = false;
      }
    });

    _loadDraft();
    // عند فتح شاشة المحادثة: تحدّث حالات الرسائل الواردة إلى "تم التسليم" ثم "تمت القراءة"
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // تحديث حالة آخر ظهور للمستخدم الحالي إلى online
      try {
        if (authController.userId.isNotEmpty) {
          await Get.find<IUserRepository>().updateStatus(
            authController.userId,
            data_user_models.UserStatus.online,
            lastSeen: DateTime.now(),
          );
        }
      } catch (e) {
        debugPrint('update last seen on chat open failed: $e');
      }
      try {
        // Start Stage Z-1 UI Sync
        unawaited(_initUiSync());
      } catch (e) {
        // لا نُظهر Snackbar هنا لتجنّب إزعاج المستخدم — نكتفي بالتسجيل
        debugPrint('update message statuses on open failed: $e');
      }

      // Initial scroll to latest message (U7)
      _scrollToBottom(animate: false);
    });

    // Watch other user's profile for status/lastSeen (individual chats only)
    final otherId = _otherUserId;
    if (otherId != null && otherId.isNotEmpty) {
      _otherUserSub =
          Get.find<IUserRepository>().watchById(otherId).listen((user) {
        if (!mounted) return;
        setState(() {
          _otherUserData = user;
        });
      }, onError: (e) {
        debugPrint('watch other user failed: $e');
      });
    }

    // Handle autoStartCall if requested
    if (widget.autoStartCall) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startFireCall(isVideo: widget.isVideoCall);
      });
    }
  }

  @override
  void dispose() {
    chatController.setActiveChat(null);
    _messageController.dispose();
    _scrollController.dispose();
    _typingDebounce?.cancel();
    try {
      _otherUserSub?.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _showSuccessMoment() {
    final l10n = AppLocalizations.of(context);
    Get.snackbar(
      l10n.successMomentTitle,
      l10n.successMomentMessage,
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.green.withValues(alpha: 0.9),
      colorText: Colors.white,
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.all(16),
      borderRadius: 20,
      icon: const Icon(Icons.celebration, color: Colors.white),
    );
  }

  Future<void> _initUiSync() async {
    if (AppConfig.useMockData) return;

    // 1. Initial ackRead (Stage Y)
    unawaited(chatController.markChatAsRead(widget.chat.id));
    chatController.clearThrottledCount(widget.chat.id);

    // 2. Fetch initial message states
    final messages = chatController.getMessages(widget.chat.id);
    if (messages.isNotEmpty) {
      final ids = messages.map((m) => m.id).toList();
      await chatController.fetchMessageStates(ids);
    }

    // 3. Subscribe to live updates
    await chatController.subscribeMessageState();
  }

  // ---- Draft helpers ----
  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'draft_${widget.chat.id}_${authController.userId}';
      final draft = prefs.getString(key);
      if (draft != null && draft.isNotEmpty) {
        _messageController.text = draft;
      }
    } catch (e) {
      debugPrint('loadDraft failed: $e');
    }
  }

  Future<void> _saveDraft(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'draft_${widget.chat.id}_${authController.userId}';
      if (value.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    } catch (e) {
      debugPrint('saveDraft failed: $e');
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'draft_${widget.chat.id}_${authController.userId}';
      await prefs.remove(key);
    } catch (e) {
      debugPrint('clearDraft failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildPinnedBanner(),
          Obx(() {
            final throttledCount =
                chatController.getThrottledCount(widget.chat.id);
            if (throttledCount == 0) return const SizedBox.shrink();
            return InAppNotificationIndicator(
              message: AppLocalizations.of(context)
                  .throttledMessagesCount(throttledCount),
              onTap: () {
                chatController.clearThrottledCount(widget.chat.id);
              },
            );
          }),
          Expanded(child: _buildMessagesList()),
          if (_replyToMessage != null)
            ReplyMessageWidget(
              replyToMessage: _replyToMessage!,
              onCancel: () => setState(() => _replyToMessage = null),
            ),
          _buildMessageInput(),
          if (_showEmojiPicker)
            EmojiPickerWidget(
              onEmojiSelected: (emoji) {
                _messageController.text += emoji;
                setState(() => _showEmojiPicker = false);
              },
            ),
        ],
      ),
    );

    if (AppConfig.enableKeyboardShortcuts &&
        (GetPlatform.isWindows || GetPlatform.isMacOS || GetPlatform.isLinux)) {
      content = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _sendMessage,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_showEmojiPicker) {
              setState(() => _showEmojiPicker = false);
            } else if (_isSearching) {
              setState(() => _isSearching = false);
            } else {
              Navigator.pop(context);
            }
          },
        },
        child: content,
      );
    }

    return content;
  }

  // --- UI Components migrated to ChatMessageBubble ---

  PreferredSizeWidget _buildAppBar() {
    if (_isSelectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitSelectionMode,
        ),
        title: Text(AppLocalizations.of(context)
            .selectedCountLabel(_selectedIds.length)),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_outline),
            tooltip: AppLocalizations.of(context).starLabelDetailed,
            onPressed: _bulkStar,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: AppLocalizations.of(context).copyLabelDetailed,
            onPressed: _bulkCopy,
          ),
          IconButton(
            icon: const Icon(Icons.forward),
            tooltip: AppLocalizations.of(context).forwardLabelDetailed,
            onPressed: _bulkForward,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: AppLocalizations.of(context).deleteLabelDetailed,
            onPressed: _bulkDelete,
          ),
        ],
      );
    } else if (_isSearching) {
      final matchesCount = _getFilteredMessages().length;
      return AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        title: TextField(
          autofocus: true,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).searchInChatHint,
            border: InputBorder.none,
            hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6)),
          ),
          onChanged: (v) {
            setState(() {
              _messageSearchQuery = v;
              _currentMatchIndex = 0;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToMatchAt(_currentMatchIndex);
            });
          },
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: AppLocalizations.of(context).searchOptions,
            icon: const Icon(Icons.tune),
            onSelected: (value) {
              setState(() {
                if (value == 'match_case') _searchMatchCase = !_searchMatchCase;
                if (value == 'whole_word') _searchWholeWord = !_searchWholeWord;
                if (value == 'regex') _searchRegex = !_searchRegex;
                _currentMatchIndex = 0;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToMatchAt(_currentMatchIndex);
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'match_case',
                child: Row(
                  children: [
                    Icon(
                      _searchMatchCase
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                    ),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context).matchCase)
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'whole_word',
                child: Row(
                  children: [
                    Icon(
                      _searchWholeWord
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                    ),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context).wholeWord)
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'regex',
                child: Row(
                  children: [
                    Icon(
                      _searchRegex
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                    ),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context).useRegex)
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: AppLocalizations.of(context).previous,
            onPressed: matchesCount == 0
                ? null
                : () {
                    setState(() {
                      _currentMatchIndex =
                          (_currentMatchIndex - 1 + matchesCount) %
                              matchesCount;
                    });
                    _scrollToMatchAt(_currentMatchIndex);
                  },
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                matchesCount == 0
                    ? '0/0'
                    : '${_currentMatchIndex + 1}/$matchesCount',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: AppLocalizations.of(context).next,
            onPressed: matchesCount == 0
                ? null
                : () {
                    setState(() {
                      _currentMatchIndex =
                          (_currentMatchIndex + 1) % matchesCount;
                    });
                    _scrollToMatchAt(_currentMatchIndex);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _isSearching = false;
              _messageSearchQuery = '';
              _currentMatchIndex = 0;
            }),
            tooltip: AppLocalizations.of(context).closeSearch,
          ),
        ],
      );
    } else {
      return AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        title: InkWell(
          onTap: () {
            if (widget.chat.isGroup) {
              Get.to(() => group_management_ui.GroupManagementScreen(
                  chatId: widget.chat.id));
            } else {
              final otherId = _otherUserId;
              if (otherId != null && otherId.isNotEmpty) {
                Get.to(() => ProfileScreen(userId: otherId));
              }
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                _buildUserAvatar(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _currentChat
                                  .getDisplayName(AppLocalizations.of(context)),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_otherUserData != null) ...[
                            const SizedBox(width: 8),
                            PresenceIndicatorWidget(
                                status: _otherUserData!.status, size: 10),
                          ],
                        ],
                      ),
                      Text(
                        _computeStatusText(),
                        style: TextStyle(
                          fontSize: 12,
                          color: _computeStatusText() ==
                                  AppLocalizations.of(context).statusOnline
                              ? Colors.greenAccent
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                          fontWeight: _computeStatusText() ==
                                  AppLocalizations.of(context).statusOnline
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sensors_rounded),
            onPressed: _showCommEntrySheet,
            tooltip: 'خيارات التواصل الموحدة',
            color: Theme.of(context).primaryColor,
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) {
              final freshChat = chatController.chats
                      .firstWhereOrNull((c) => c.id == widget.chat.id) ??
                  widget.chat;
              return [
                PopupMenuItem(
                  value: 'view_profile',
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(AppLocalizations.of(context).viewProfile),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (!_isSearching)
                  PopupMenuItem(
                    value: 'search',
                    child: ListTile(
                      leading: const Icon(Icons.search),
                      title: Text(AppLocalizations.of(context).searchInChat),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                PopupMenuItem(
                  value: 'mute',
                  child: ListTile(
                    leading: Icon(
                        freshChat.isMuted ? Icons.volume_up : Icons.volume_off),
                    title: Text(freshChat.isMuted
                        ? AppLocalizations.of(context).unmute
                        : AppLocalizations.of(context).muteNotifications),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: const Icon(Icons.delete_sweep),
                    title: Text(AppLocalizations.of(context).clearChat),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete_chat',
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    title: Text(AppLocalizations.of(context).deleteChat,
                        style: const TextStyle(color: Colors.redAccent)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ];
            },
          ),
        ],
      );
    }
  }

  Widget _buildUserAvatar() {
    if (widget.otherUser?.profilePicture != null) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: AssetImage(widget.otherUser!.profilePicture!),
        onBackgroundImageError: (exception, stackTrace) {},
        child: widget.otherUser?.profilePicture == null
            ? _buildDefaultAvatar()
            : null,
      );
    }
    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return CircleAvatar(
      radius: 20,
      backgroundColor: Theme.of(context).primaryColor,
      child: Text(
        widget.otherUser?.initials ??
            _currentChat
                .getDisplayName(AppLocalizations.of(context))[0]
                .toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return Obx(() {
      final messages = _getFilteredMessages();
      final typingUsers = chatController.getTypingUserNames(widget.chat.id);

      if (messages.isEmpty && typingUsers.isEmpty) {
        return _buildEmptyState();
      }

      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: messages.length + (typingUsers.isNotEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          // Show typing indicator as last item
          if (index == messages.length && typingUsers.isNotEmpty) {
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, child) =>
                  Opacity(opacity: value, child: child),
              child: _buildTypingIndicator(typingUsers),
            );
          }

          final message = messages[index];
          final isMe = message.senderId == authController.userId;
          final showDateSeparator = _shouldShowDateSeparator(index, messages);

          final isCurrent = _isSearching && index == _currentMatchIndex;

          // Bounded pruning for _messageKeys to prevent unmanaged memory growth (P6)
          if (_messageKeys.length > 200) {
            final activeIds = messages.map((m) => m.id).toSet();
            _messageKeys.removeWhere((id, _) => !activeIds.contains(id));
            if (_messageKeys.length > 200) {
              final keysToRemove = _messageKeys.keys.take(_messageKeys.length - 150).toList();
              for (final k in keysToRemove) {
                _messageKeys.remove(k);
              }
            }
          }
          final messageKey = _messageKeys.putIfAbsent(message.id, () => GlobalKey());

          final content = Column(
            key: messageKey,
            children: [
              if (showDateSeparator) _buildDateSeparator(message.timestamp),
              ChatMessageBubble(
                message: message,
                isMe: isMe,
                isCurrentMatch: isCurrent,
                isSelectionMode: _isSelectionMode,
                isSelected: _selectedIds.contains(message.id),
                chat: widget.chat,
                roleLabel: widget.chat.type == ChatType.group
                    ? _getMyGroupRoleLabel()
                    : null,
                onToggleSelection: _toggleSelection,
                onReply: () => setState(() => _replyToMessage = message),
                onLongPress: () => _showMessageOptions(message, isMe),
                onScrollToMessage: _scrollToMessageId,
                onShowReactionDetails: _showReactionsDetails,
                buildHighlightedText: _buildHighlightedText,
                formatTime: _formatTime,
                openUrl: _openUrl,
                inferFileName: _inferFileNameFromUrl,
                formatBytes: _formatBytes,
              ),
            ],
          );

          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutQuad,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 10 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: content,
          );
        },
      );
    });
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/illustrations/empty_chat.png',
            width: 150,
            height: 150,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.chat_bubble_outline,
                size: 80,
                color: Colors.grey,
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).startConversation,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).writeFirstMessage,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  bool _shouldShowDateSeparator(int index, List<MessageModel> source) {
    if (index == 0) return true;

    final currentMessage = source[index];
    final previousMessage = source[index - 1];

    final currentDate = DateTime(
      currentMessage.timestamp.year,
      currentMessage.timestamp.month,
      currentMessage.timestamp.day,
    );

    final previousDate = DateTime(
      previousMessage.timestamp.year,
      previousMessage.timestamp.month,
      previousMessage.timestamp.day,
    );

    return !currentDate.isAtSameMomentAs(previousDate);
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    final l10n = AppLocalizations.of(context);
    String dateText;
    if (messageDate.isAtSameMomentAs(today)) {
      dateText = l10n.chatToday;
    } else if (messageDate.isAtSameMomentAs(yesterday)) {
      dateText = l10n.chatYesterday;
    } else {
      dateText = DateFormat.yMMMd(l10n.localeName).format(date);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(
              dateText,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  // Placeholder for deleted methods

  // _showDeleteChoices removed: now deletion is a single action (حذف لدي)

  Future<bool> _confirmDelete(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).confirmLabel)),
        ],
      ),
    );
    return result == true;
  }

  String? _getMyGroupRoleLabel() {
    if (widget.chat.type != ChatType.group) return null;
    final me = authController.userId;
    final meta = widget.chat.metadata ?? const <String, dynamic>{};
    final ownerId = (meta['groupOwnerId'] as String?) ?? widget.chat.createdBy;
    if (ownerId == me && ownerId != null && ownerId.isNotEmpty) {
      return AppLocalizations.of(context).groupRoleAdmin;
    }
    final admins = (meta['adminIds'] is List)
        ? (meta['adminIds'] as List).whereType<String>().toList()
        : const <String>[];
    if (admins.contains(me)) {
      return AppLocalizations.of(context).groupRoleModerator;
    }
    return null;
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _scrollToMessageId(String messageId) {
    final key = _messageKeys[messageId];
    if (key == null || key.currentContext == null) {
      Get.snackbar(
          AppLocalizations.of(context).warning,
          AppLocalizations.of(context)
              .sendFailedDetail); // Reuse sendFailedDetail as generic failure
      return;
    }

    Scrollable.ensureVisible(
      key.currentContext!,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.5, // Center the message
    );

    // Optional: flash the message bubble?
    // We already have GlobalKeys, we could potentially trigger an animation if the widget supported it.
    // For now, let's just use the highlight logic used by search if possible.
  }

  // Builds a TextSpan with highlighted occurrences of the in-chat search query
  TextSpan _buildHighlightedText(
    String text,
    Color normalColor, {
    TextStyle? style,
    Color? highlightColor,
  }) {
    final query = _messageSearchQuery.trim();
    final baseStyle = (style ?? TextStyle(fontSize: 16, color: normalColor));
    final hlColor = highlightColor ?? Colors.yellow.withValues(alpha: 0.45);

    if (query.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final ranges = _computeMatchRanges(text, query);
    if (ranges.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final List<TextSpan> spans = [];
    int cursor = 0;
    for (final r in ranges) {
      final start = r.$1;
      final end = r.$2;
      if (start > cursor) {
        spans.add(
            TextSpan(text: text.substring(cursor, start), style: baseStyle));
      }
      spans.add(TextSpan(
        text: text.substring(start, end),
        style: baseStyle.copyWith(
          backgroundColor: hlColor,
          fontWeight: FontWeight.w600,
        ),
      ));
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }

    return TextSpan(children: spans, style: baseStyle);
  }

  // Compute ranges (start, end) in original text that match query ignoring Arabic diacritics and honoring advanced options
  List<(int, int)> _computeMatchRanges(String text, String query) {
    final source = text;
    if (query.trim().isEmpty) return const [];

    // Map positions from normalized string back to original indices
    final List<int> posMap = [];
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < source.length; i++) {
      final ch = source[i];
      if (_isArabicDiacritic(ch) || ch == '\u0640') {
        // Skip diacritics and tatweel in normalized
        continue;
      }
      sb.write(ch);
      posMap.add(i);
    }
    final normalized = sb.toString();

    final matches = _findMatchesNormalized(normalized, query);
    final List<(int, int)> ranges = [];
    for (final m in matches) {
      final startOrig = posMap[m.start];
      final endOrig = posMap[m.end - 1] + 1; // exclusive
      ranges.add((startOrig, endOrig));
    }
    return ranges;
  }

  String _stripArabicDiacritics(String input) {
    // Arabic diacritics ranges and tatweel
    final diacritics =
        RegExp('[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]');
    return input.replaceAll(diacritics, '');
  }

  String _normalizeText(String input, {required bool toLower}) {
    var s = _stripArabicDiacritics(input);
    if (toLower) s = s.toLowerCase();
    return s;
  }

  bool _isArabicDiacritic(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 0x0610 && code <= 0x061A) ||
        (code >= 0x064B && code <= 0x065F) ||
        (code == 0x0670) ||
        (code >= 0x06D6 && code <= 0x06ED);
  }

  // Returns filtered messages according to diacritic-insensitive search and advanced options
  List<MessageModel> _getFilteredMessages() {
    // Access reactive map to ensure Obx rebuilds on updates
    final messages = (chatController.chatMessagesRx[widget.chat.id] ??
            const <MessageModel>[])
        .toList();
    final q = _messageSearchQuery.trim();
    if (q.isEmpty) return messages;
    final filtered = <MessageModel>[];
    for (final m in messages) {
      final normText = _normalizeText(
          m.getDisplayContent(AppLocalizations.of(context)),
          toLower: !_searchMatchCase);
      if (_hasMatchNormalized(normText, q)) {
        filtered.add(m);
      }
    }
    return filtered;
  }

  void _scrollToMatchAt(int index) {
    if (!_isSearching) return;
    final messages = _getFilteredMessages();
    if (messages.isEmpty) return;
    final safeIndex = index.clamp(0, messages.length - 1);
    final target = messages[safeIndex];
    final key = _messageKeys[target.id];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: 0.2,
      );
    }
  }

  Widget _buildMessageInput() {
    return Obx(() {
      if (chatController.isInputLocked) {
        return _buildLockedInputView();
      }
      return _buildActiveInputView();
    });
  }

  Widget _buildLockedInputView() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 20,
                color: theme.colorScheme.secondary.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Text(
              chatController.lockReason,
              style: TextStyle(
                color: theme.colorScheme.secondary.withValues(alpha: 0.7),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveInputView() {
    final theme = Theme.of(context);
    final isNotEmpty = _messageController.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 26),
                onPressed: _showAttachmentOptions,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              if (_isRecordingAudio)
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, color: Colors.red, size: 12),
                        const SizedBox(width: 8),
                        Text(
                          _formatRecordingTime(_recordingSeconds),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Expanded(child: SizedBox()),
                        Text(
                          _recordingDragOffset < _cancelThreshold / 2
                              ? AppLocalizations.of(context).releaseToCancel
                              : AppLocalizations.of(context).swipeToCancel,
                          style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_back_ios, size: 12),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: Icon(
                            _showEmojiPicker
                                ? Icons.keyboard
                                : Icons.emoji_emotions_outlined,
                            color: theme.hintColor,
                            size: 24,
                          ),
                          onPressed: () => setState(
                              () => _showEmojiPicker = !_showEmojiPicker),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText:
                                  AppLocalizations.of(context).typeMessageHint,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 12),
                              isDense: true,
                            ),
                            maxLines: 5,
                            minLines: 1,
                            onChanged: _onMessageChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onLongPressStart: (_) => isNotEmpty ? null : _startRecording(),
                onLongPressMoveUpdate: (details) {
                  if (_isRecordingAudio) {
                    setState(() {
                      _recordingDragOffset = details.localPosition.dx;
                    });
                  }
                },
                onLongPressEnd: (details) {
                  if (_isRecordingAudio) {
                    if (_recordingDragOffset < _cancelThreshold) {
                      _stopRecording(cancel: true);
                    } else {
                      _stopRecording(cancel: false);
                    }
                  }
                },
                onTap: isNotEmpty ? _sendMessage : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: (isNotEmpty || _isRecordingAudio)
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      isNotEmpty
                          ? Icons.send_rounded
                          : (_isRecordingAudio
                              ? Icons.mic
                              : Icons.mic_none_rounded),
                      color: (isNotEmpty || _isRecordingAudio)
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.primary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(List<String> typingUsers) {
    final typingText = typingUsers.length == 1
        ? AppLocalizations.of(context).typingSingle(typingUsers.first)
        : typingUsers.length == 2
            ? AppLocalizations.of(context)
                .typingDouble(typingUsers[0], typingUsers[1])
            : AppLocalizations.of(context).typingMultiple(typingUsers.length);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  typingText,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final l10n = AppLocalizations.of(context);
    return DateFormat.Hm(l10n.localeName).format(dateTime);
  }

  void _onMessageChanged(String value) {
    // Show typing indicator while user is typing; hide after short delay
    if (!_isTyping) {
      setState(() => _isTyping = true);
      // Start typing indicator in Firestore
      chatController.startTyping(widget.chat.id);
    }

    // Keep typing indicator alive while typing (throttled by debounce below)
    chatController.notifyTyping(widget.chat.id);

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isTyping = false);
        // Stop typing indicator in Firestore
        chatController.stopTyping(widget.chat.id);
      }
    });

    // Save draft per chat
    _saveDraft(value);
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    // [Perceptual Anticipation]: Clear UI immediately ("Optimistic UI")
    _messageController.clear();
    setState(() {
      _replyToMessage = null;
      _showEmojiPicker = false;
      _isTyping = false;
    });

    // Scroll to bottom optimistically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent +
              60, // Add space for new bubble
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      await chatController.sendMessage(
        chatId: widget.chat.id,
        content: content,
        type: MessageType.text,
        replyToMessageId: _replyToMessage?.id,
      );

      // Save success is implicit via stream update

      // Stop typing indicator logic
      unawaited(chatController.stopTyping(widget.chat.id));
      await _clearDraft();
    } catch (e) {
      // [Graceful Failure]: Restore text if failed
      if (mounted) {
        _messageController.text = content; // Restore draft
        Get.snackbar(
          AppLocalizations.of(context).sendFailed,
          AppLocalizations.of(context).sendFailedDetail,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          colorText: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  // Local status simulation removed; ChatController handles status updates

  Future<void> _handleMenuAction(String action) async {
    switch (action) {
      case 'view_profile':
        if (!widget.chat.isGroup) {
          final me = authController.userId;
          final otherId = widget.chat.participantIds.firstWhere(
            (id) => id != me,
            orElse: () => '',
          );
          if (otherId.isNotEmpty) {
            unawaited(Get.to(() => ProfileScreen(userId: otherId)));
          }
        } else {
          unawaited(Get.to(() => group_management_ui.GroupManagementScreen(
              chatId: widget.chat.id)));
        }
        break;
      case 'search':
        setState(() {
          _isSearching = true;
          _messageSearchQuery = '';
        });
        break;
      case 'mute':
        final freshChat = chatController.chats
                .firstWhereOrNull((c) => c.id == widget.chat.id) ??
            widget.chat;
        if (freshChat.isMuted) {
          unawaited(chatController.muteChatUntil(freshChat.id, null));
          return;
        }

        final l10n = AppLocalizations.of(context);
        final duration = await showModalBottomSheet<DateTime>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    l10n.muteNotifications,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  title: Text('15 ${l10n.minutes(15)}'),
                  onTap: () => Navigator.pop(
                      context, DateTime.now().add(const Duration(minutes: 15))),
                ),
                ListTile(
                  title: Text('1 ${l10n.hours(1)}'),
                  onTap: () => Navigator.pop(
                      context, DateTime.now().add(const Duration(hours: 1))),
                ),
                ListTile(
                  title: Text('8 ${l10n.hours(8)}'),
                  onTap: () => Navigator.pop(
                      context, DateTime.now().add(const Duration(hours: 8))),
                ),
                ListTile(
                  title: Text('24 ${l10n.hours(24)}'),
                  onTap: () => Navigator.pop(
                      context, DateTime.now().add(const Duration(hours: 24))),
                ),
                ListTile(
                  title: Text(l10n.indefinitely),
                  onTap: () => Navigator.pop(context,
                      DateTime.now().add(const Duration(days: 365 * 100))),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );

        if (duration != null) {
          unawaited(chatController.muteChatUntil(freshChat.id, duration));
        }
        break;
      case 'clear':
        _showClearChatDialog();
        break;
      case 'delete_chat':
        unawaited(_showDeleteChatDialog());
        break;
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).attachFileTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 12,
              runSpacing: 16,
              children: [
                _buildAttachmentOption(
                  icon: Icons.photo,
                  label: AppLocalizations.of(context).photo,
                  onTap: () {
                    Navigator.pop(context);
                    _attachImage();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.videocam,
                  label: AppLocalizations.of(context).video,
                  onTap: () {
                    Navigator.pop(context);
                    _attachVideo();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.insert_drive_file,
                  label: AppLocalizations.of(context).file,
                  onTap: () {
                    Navigator.pop(context);
                    _attachFile();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.emoji_emotions,
                  label: AppLocalizations.of(context).stickerLabel,
                  onTap: () {
                    Navigator.pop(context);
                    _attachSticker();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.mic,
                  label: AppLocalizations.of(context).audioLabel,
                  onTap: () async {
                    Navigator.pop(context);
                    await _attachAudioQuick();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.location_on,
                  label: AppLocalizations.of(context).location,
                  onTap: () {
                    Navigator.pop(context);
                    _attachLocation();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: Theme.of(context).primaryColor),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _attachImage() {
    _ensurePhotoPermission().then((granted) async {
      if (!mounted) return;
      if (!granted) {
        Get.snackbar(AppLocalizations.of(context).permissions,
            AppLocalizations.of(context).mediaPermissionDetail);
        return;
      }
      final xfile = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);

      if (!mounted) return;
      if (xfile == null) return;

      final xfile2 = XFile(xfile.path);
      final progress = ValueNotifier<double>(0);

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              await chatController.uploadImageAndSend(
                chatId: widget.chat.id,
                file: xfile2,
                onProgress: (p) => progress.value = p,
                replyToMessageId: _replyToMessage?.id,
              );
              if (mounted) {
                setState(() => _replyToMessage = null);
              }
            } catch (e) {
              debugPrint('attachImage upload failed: $e');
              if (mounted) {
                Get.snackbar(
                  AppLocalizations.of(context).imageUploadFailed,
                  AppLocalizations.of(context).imageUploadDetail,
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            } finally {
              if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
                Navigator.of(dialogCtx).pop();
              }
            }
          });
          return ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, p, _) {
              final percent = (p * 100).clamp(0, 100).toStringAsFixed(0);
              return AlertDialog(
                title: Text(AppLocalizations.of(context).uploadingImage),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: p > 0 && p <= 1 ? p : null),
                    const SizedBox(height: 8),
                    Text('$percent%'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.of(context).cancel),
                  ),
                ],
              );
            },
          );
        },
      );
    }).catchError((e) {
      debugPrint('attachImage failed: $e');
      if (mounted) {
        Get.snackbar(AppLocalizations.of(context).error,
            AppLocalizations.of(context).imageUploadFailed);
      }
    });
  }

  void _attachVideo() {
    FilePicker.platform
        .pickFiles(type: FileType.video, allowMultiple: false)
        .then((res) async {
      final path = res?.files.single.path;
      if (path == null) return;
      final xf = XFile(path);
      final progress = ValueNotifier<double>(0);

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              await chatController.uploadVideoAndSend(
                chatId: widget.chat.id,
                file: xf,
                onProgress: (p) => progress.value = p,
                replyToMessageId: _replyToMessage?.id,
              );
              if (mounted) {
                setState(() => _replyToMessage = null);
              }
            } catch (e) {
              debugPrint('attachVideo upload failed: $e');
            } finally {
              if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
                Navigator.of(dialogCtx).pop();
              }
            }
          });
          return ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, p, _) {
              final percent = (p * 100).clamp(0, 100).toStringAsFixed(0);
              return AlertDialog(
                title: Text(AppLocalizations.of(context).uploadingVideo),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: p > 0 && p <= 1 ? p : null),
                    const SizedBox(height: 8),
                    Text('$percent%'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: Text(AppLocalizations.of(context).cancel),
                  ),
                ],
              );
            },
          );
        },
      );
    }).catchError((e) {
      debugPrint('attachVideo failed: $e');
      if (mounted) {
        Get.snackbar(AppLocalizations.of(context).error,
            AppLocalizations.of(context).uploadingVideo);
      }
    });
  }

  void _attachFile() {
    FilePicker.platform.pickFiles(allowMultiple: false).then((res) async {
      final path = res?.files.single.path;
      if (path == null) return;
      final xf = XFile(path);
      final progress = ValueNotifier<double>(0);

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              await chatController.uploadFileAndSend(
                chatId: widget.chat.id,
                file: xf,
                onProgress: (p) => progress.value = p,
                replyToMessageId: _replyToMessage?.id,
              );
              if (mounted) {
                setState(() => _replyToMessage = null);
              }
            } catch (e) {
              debugPrint('attachFile upload failed: $e');
            } finally {
              if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
                Navigator.of(dialogCtx).pop();
              }
            }
          });
          return ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, p, _) {
              final percent = (p * 100).clamp(0, 100).toStringAsFixed(0);
              return AlertDialog(
                title: Text(AppLocalizations.of(context).uploadingFile),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: p > 0 && p <= 1 ? p : null),
                    const SizedBox(height: 8),
                    Text('$percent%'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: Text(AppLocalizations.of(context).cancel),
                  ),
                ],
              );
            },
          );
        },
      );
    }).catchError((e) {
      debugPrint('attachFile failed: $e');
      if (mounted) {
        Get.snackbar(AppLocalizations.of(context).error,
            AppLocalizations.of(context).uploadingFile);
      }
    });
  }

  void _attachLocation() {
    final textController =
        TextEditingController(text: 'https://maps.google.com/?q=');
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).shareLocation),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context).shareLocationDetail),
            const SizedBox(height: 8),
            TextField(
              controller: textController,
              maxLines: 1,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).cancel)),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, textController.text.trim()),
              child: Text(AppLocalizations.of(context).send)),
        ],
      ),
    ).then((value) async {
      final link = value?.trim() ?? '';
      if (link.isEmpty) return;
      if (!mounted) return;
      await chatController.sendMessage(
          chatId: widget.chat.id,
          content: '${AppLocalizations.of(context).myLocationLabel}: $link',
          type: MessageType.text);
    });
  }

  String _formatRecordingTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  Future<void> _startRecording() async {
    try {
      _recorder ??= AudioRecorder();
      if (!await _ensureMicPermission()) {
        Get.snackbar('الأذونات', 'مطلوب إذن الميكروفون للتسجيل');
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      unawaited(AppAudioService.instance.play('audio_record_start.mp3'));

      if (!mounted) return;
      setState(() {
        _isRecordingAudio = true;
        _recordingSeconds = 0;
        _recordingDragOffset = 0;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _recordingSeconds++;
        });
      });

      // Haptic feedback could be added here
    } catch (e) {
      debugPrint('Start recording failed: $e');
      Get.snackbar('خطأ', 'تعذر بدء التسجيل');
    }
  }

  Future<void> _stopRecording({required bool cancel}) async {
    if (_recorder == null) return;
    try {
      _recordingTimer?.cancel();
      final path = await _recorder!.stop();
      unawaited(AppAudioService.instance.play('audio_record_stop.mp3'));

      if (!mounted) return;
      setState(() {
        _isRecordingAudio = false;
        _recordingSeconds = 0;
      });

      if (cancel || path == null) {
        if (path != null && !kIsWeb) {
          // Only attempt file deletion on native platforms
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (e) {
            debugPrint('Failed to delete cancelled audio file: $e');
          }
        }
        if (cancel) {
          Get.snackbar('تم الإلغاء', 'تم إلغاء التسجيل الصوتي',
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 1));
        }
        return;
      }

      final xFile = XFile(path);
      await chatController.sendAudio(
        chatId: widget.chat.id,
        file: xFile,
        replyToMessageId: _replyToMessage?.id,
      );
      setState(() => _replyToMessage = null);

      Get.snackbar('تم الإرسال', 'تم إرسال الرسالة الصوتية بنجاح',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 1));
    } catch (e) {
      debugPrint('Stop recording failed: $e');
      Get.snackbar('خطأ', 'تعذر إرسال التسجيل');
    }
  }

  Future<void> _attachAudioQuick() async {
    // This method is now replaced by the better Hold-to-Record logic
    // but kept for backward compatibility if needed in other places.
    await _startRecording();
    await Future.delayed(const Duration(seconds: 5));
    await _stopRecording(cancel: false);
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _bulkCopy() async {
    final messages = _getFilteredMessages()
        .where((m) => _selectedIds.contains(m.id))
        .toList();
    if (messages.isEmpty) return;

    final buffer = StringBuffer();
    for (final m in messages) {
      final senderName = m.senderId == authController.userId
          ? AppLocalizations.of(context).meLabel
          : (widget.otherUser?.displayName ??
              AppLocalizations.of(context).editorLabel);
      buffer.writeln(
          '$senderName [${DateFormat.Hm().format(m.timestamp)}]: ${m.content}');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    _exitSelectionMode();
    if (mounted) {
      Get.snackbar(AppLocalizations.of(context).copyLabelDetailed,
          AppLocalizations.of(context).messagesCopiedToClipboard,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _bulkForward() async {
    final messages = _getFilteredMessages()
        .where((m) => _selectedIds.contains(m.id))
        .toList();
    if (messages.isEmpty) return;

    // Show a simple dialog pick list of chats
    final result = await Get.dialog<String>(
      AlertDialog(
        title: Text(AppLocalizations.of(context).forwardToTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: chatController.chats.length,
            itemBuilder: (context, index) {
              final chat = chatController.chats[index];
              if (chat.id == widget.chat.id) return const SizedBox.shrink();
              return ListTile(
                title: Text(chat.getDisplayName(AppLocalizations.of(context))),
                onTap: () => Navigator.pop(context, chat.id),
              );
            },
          ),
        ),
      ),
    );

    if (result != null) {
      await chatController.forwardMessages(
        messages: messages,
        targetChatId: result,
      );
      _exitSelectionMode();
      if (mounted) {
        Get.snackbar(AppLocalizations.of(context).forwardLabelDetailed,
            AppLocalizations.of(context).messagesForwardedSuccess,
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<void> _bulkDelete() async {
    final selectedIds = _selectedIds.toList();
    if (selectedIds.isEmpty) return;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)
            .deleteMessagesTitle(selectedIds.length)),
        content: Text(AppLocalizations.of(context).deleteMessagesConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'me'),
            child: Text(AppLocalizations.of(context).deleteForMeLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'everyone'),
            child: Text(AppLocalizations.of(context).deleteForAllLabel,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == 'me') {
      await chatController.deleteMessagesForMe(
        chatId: widget.chat.id,
        messageIds: selectedIds,
      );
      _exitSelectionMode();
    } else if (result == 'everyone') {
      await chatController.softDeleteMessagesForAll(
        chatId: widget.chat.id,
        messageIds: selectedIds,
      );
      _exitSelectionMode();
    }
  }

  Future<void> _bulkStar() async {
    final selectedIds = _selectedIds.toList();
    if (selectedIds.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final me = authController.userId;
    final chatId = widget.chat.id;

    // We'll toggle based on the first selected item: if it's starred, unstar all. Else star all.
    final firstKey = 'star_${chatId}_${me}_${selectedIds.first}';
    final shouldStar = !(prefs.getBool(firstKey) ?? false);

    for (final id in selectedIds) {
      final key = 'star_${chatId}_${me}_$id';
      await prefs.setBool(key, shouldStar);
    }

    _exitSelectionMode();
    if (mounted) {
      Get.snackbar(
        shouldStar
            ? AppLocalizations.of(context).starLabelDetailed
            : AppLocalizations.of(context).removeStarLabelDetailed,
        shouldStar
            ? AppLocalizations.of(context).starMessagesSuccess
            : AppLocalizations.of(context).unstarMessagesSuccess,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).clearChatTitle),
        content: Text(AppLocalizations.of(context).clearChatConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              chatController.clearChatMessages(widget.chat.id);
              Get.snackbar(
                AppLocalizations.of(context).clearedTitle,
                AppLocalizations.of(context).chatCleared,
                snackPosition: SnackPosition.BOTTOM,
              );
            },
            child: Text(AppLocalizations.of(context).clear,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> _ensurePhotoPermission() async {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      final status = await Permission.photos.request();
      return status.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  // Helpers: open URL externally
  Future<void> _openUrl(String url, String messageId, String chatId) async {
    try {
      debugPrint('📂 [ChatScreen] FILE_OPEN_CLICK: messageId=$messageId');
      await MediaFileService.instance.openFile(
        url: url,
        messageId: messageId,
        chatId: chatId,
      );
    } catch (e) {
      debugPrint('openUrl failed: $e');
      if (mounted) {
        Get.snackbar(AppLocalizations.of(context).openLinkLabel,
            AppLocalizations.of(context).openLinkErrorGeneric,
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  // Helpers: format and infer
  String _formatBytes(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int i = 0;
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size < 10 && i > 0 ? 1 : 0)} ${suffixes[i]}';
  }

  String _inferFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : url;
      return Uri.decodeComponent(last);
    } catch (_) {
      return AppLocalizations.of(context).fileLabel;
    }
  }

  // Show a detailed list of reactions grouped by emoji, with user avatars
  void _showReactionsDetails(MessageModel message) {
    final reactionsMap =
        message.userReactions; // userId -> emoji mapping from V3 cache
    if (reactionsMap.isEmpty) return;

    // Build groups: emoji -> [userIds]
    final Map<String, List<String>> groups = {};
    reactionsMap.forEach((userId, emoji) {
      if (emoji.isEmpty) return;
      groups.putIfAbsent(emoji, () => []).add(userId);
    });

    // Flatten all unique userIds for a single fetch batch
    final userIds = groups.values.expand((v) => v).toSet().toList();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        final userRepo = Get.find<IUserRepository>();
        return SafeArea(
          child: FutureBuilder<List<data_user_models.AppUser?>>(
            future: Future.wait(userIds.map((id) => userRepo.getById(id))),
            builder: (context, snapshot) {
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              final users = snapshot.data ?? [];
              // Map id -> user
              final Map<String, data_user_models.AppUser?> userMap = {};
              for (var i = 0; i < userIds.length; i++) {
                userMap[userIds[i]] = (i < users.length) ? users[i] : null;
              }

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.emoji_emotions_outlined),
                        const SizedBox(width: 8),
                        Text(AppLocalizations.of(context).reactionsLabel,
                            style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        if (!loading)
                          Text(
                              AppLocalizations.of(context)
                                  .reactionsCount(reactionsMap.length),
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Center(
                          child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )),
                    if (!loading)
                      ...groups.entries.map((entry) {
                        final emoji = entry.key;
                        final ids = entry.value;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(emoji,
                                    style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 6),
                                Text('${ids.length}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ...ids.map((uid) {
                              final u = userMap[uid];
                              final name = u?.displayName ??
                                  AppLocalizations.of(context).userLabel;
                              final photo = u?.photoUrl;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                leading:
                                    _buildAvatar(photoUrl: photo, name: name),
                                title: Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(uid,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              );
                            }),
                            const Divider(height: 16),
                          ],
                        );
                      }),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAvatar({String? photoUrl, String? name}) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(photoUrl));
    }
    final initial = (name?.isNotEmpty == true)
        ? name!.trim().characters.first.toUpperCase()
        : '?';
    return CircleAvatar(child: Text(initial));
  }

  bool _hasMatchNormalized(String text, String query) {
    final q = _searchMatchCase ? query : query.toLowerCase();
    final t = _searchMatchCase ? text : text.toLowerCase();
    if (_searchRegex) {
      try {
        return RegExp(q, caseSensitive: _searchMatchCase).hasMatch(t);
      } catch (_) {
        return false;
      }
    }
    if (_searchWholeWord) {
      return RegExp('\\b${RegExp.escape(q)}\\b',
              caseSensitive: _searchMatchCase)
          .hasMatch(t);
    }
    return t.contains(q);
  }

  List<Match> _findMatchesNormalized(String text, String query) {
    final q = _searchMatchCase ? query : query.toLowerCase();
    final t = _searchMatchCase ? text : text.toLowerCase();
    String pattern = RegExp.escape(q);
    if (_searchRegex) pattern = q;
    if (_searchWholeWord) pattern = '\\b$pattern\\b';

    try {
      return RegExp(pattern, caseSensitive: _searchMatchCase)
          .allMatches(t)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _showMessageOptions(MessageModel message, bool isMe) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Quick Reactions Strip
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: ['❤️', '👍', '😂', '😮', '😢', '🙏', '🔥', '🎉']
                    .map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      chatController.addReaction(
                        chatId: widget.chat.id,
                        messageId: message.id,
                        emoji: emoji,
                      );
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Text(emoji,
                          style: const TextStyle(fontSize: 24, height: 1)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(AppLocalizations.of(context).reply),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyToMessage = message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(AppLocalizations.of(context).copy),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: message.content));
                Get.snackbar(
                  AppLocalizations.of(context).copiedTitle,
                  AppLocalizations.of(context).messageCopied,
                  snackPosition: SnackPosition.BOTTOM,
                );
              },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(AppLocalizations.of(context).delete,
                    style: const TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await _confirmDelete(
                    AppLocalizations.of(context).deleteMessageTitle,
                    AppLocalizations.of(context).deleteMessageConfirm,
                  );
                  if (ok) {
                    unawaited(chatController.deleteMessage(
                        widget.chat.id, message.id));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
