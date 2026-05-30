import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart'; // Provides XFile
import 'package:rxdart/rxdart.dart' as rx_dart;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';
import 'package:talkmate_ai/data/models/chat_model.dart' as data_chat_models;
import 'package:talkmate_ai/data/models/message_model.dart' as data_msg_models;
import 'package:talkmate_ai/data/models/sync_action_model.dart';
import 'package:talkmate_ai/data/models/typing_indicator_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart' as user_models;
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_local_message_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_message_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_typing_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/data/services/chat_sync_engine.dart';
import 'package:talkmate_ai/data/services/storage_service.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/models/chat_model.dart';
import 'package:talkmate_ai/models/message_model.dart';
import 'package:talkmate_ai/services/audio/app_audio_service.dart';
import 'package:talkmate_ai/services/observability/analytics_service.dart';
import 'package:talkmate_ai/services/observability/performance_tracker.dart';
import 'package:talkmate_ai/utils/device_identity.dart';
import 'package:uuid/uuid.dart';

enum MessageState { pending, sent, delivered, read, failed }

MessageState _mapMessageState(String? status) {
  switch (status) {
    case 'pending':
      return MessageState.pending;
    case 'delivered':
      return MessageState.delivered;
    case 'read':
      return MessageState.read;
    case 'failed':
      return MessageState.failed;
    default:
      return MessageState.sent;
  }
}

class ChatController extends GetxController with WidgetsBindingObserver {
  static const String _chatsKey = 'cached_chats';
  // static const String _messagesKey = 'cached_messages'; // Reserved for future use
  static const String _hasSentFirstMessageKey = 'has_sent_first_message';
  static const String _lastActiveChatKey = 'last_active_chat_id';

  final RxList<ChatModel> _chats = <ChatModel>[].obs;
  final RxMap<String, List<MessageModel>> _chatMessages =
      <String, List<MessageModel>>{}.obs;
  final RxMap<String, MessageState> _messageStates =
      <String, MessageState>{}.obs;
  final RxMap<String, int> _throttledCounter = <String, int>{}.obs;
  final RxBool _isLoading = false.obs;
  final RxString _searchQuery = ''.obs;
  final RxBool _initialized = false.obs;
  final RxString _activeChatId = ''.obs;
  final RxBool _hasSentFirstMessage = false.obs;
  final RxString _lastActiveChatId = ''.obs;
  final RxBool _isAppInForeground = true.obs;
  final RxBool showFirstMessageSuccess = false.obs;
  final RxBool _isInputLocked = false.obs;
  final RxString _lockReason = ''.obs;
  // Cache of userId -> displayName to resolve chat titles for individual chats
  final Map<String, String> _userNameCache = {};
  // [Stage S1] Track last message ID per chat to trigger receive sound
  final Map<String, String> _lastAcknowledgedMessageId = {};
  String _shortId(String id) {
    if (id.isEmpty) return 'محادثة';
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
  }

  // Realtime subscriptions (Phase 3)
  StreamSubscription<List<data_chat_models.Chat>>? _chatsSub;
  final Map<String, StreamSubscription<List<MessageModel>>> _messagesSubs = {};
  final Map<String, StreamSubscription<List<TypingIndicator>>> _typingSubs = {};
  final RxMap<String, List<TypingIndicator>> _typingIndicators =
      <String, List<TypingIndicator>>{}.obs;
  final Map<String, Timer?> _typingTimers = {};
  RealtimeChannel? _statesChannel;
  Worker? _authWorker;
  Worker? _uidWorker;
  Timer? _chatsRetryTimer;
  bool _useChatsFallback = false; // use no-order query while index is building

  // Core Foundation repositories & services
  final IChatRepository _chatRepo = Get.find<IChatRepository>();
  final IMessageRepository _messageRepo = Get.find<IMessageRepository>();
  final ILocalMessageRepository _localRepo =
      Get.find<ILocalMessageRepository>();
  final ITypingRepository _typingRepo = Get.find<ITypingRepository>();
  final ChatSyncEngine _syncEngine = Get.find<ChatSyncEngine>();

  // Getters
  List<ChatModel> get chats => _chats;
  bool get isLoading => _isLoading.value;
  Map<String, MessageState> get messageStates => _messageStates;
  List<MessageModel> getMessages(String chatId) => _chatMessages[chatId] ?? [];
  int getThrottledCount(String chatId) => _throttledCounter[chatId] ?? 0;
  String get activeChatId => _activeChatId.value;
  bool get isAppInForeground => _isAppInForeground.value;
  String get lastActiveChatId => _lastActiveChatId.value;
  RxString get lastActiveChatIdRx => _lastActiveChatId;
  bool get isInputLocked => _isInputLocked.value;
  String get lockReason => _lockReason.value;

  List<ChatModel> get filteredChats {
    if (_searchQuery.value.isEmpty) return _chats;
    return _chats
        .where(
          (chat) =>
              chat
                  .getDisplayName(AppLocalizations.of(Get.context!))
                  .toLowerCase()
                  .contains(
                    _searchQuery.value.toLowerCase(),
                  ) ||
              (chat.lastMessage?.content.toLowerCase().contains(
                        _searchQuery.value.toLowerCase(),
                      ) ??
                  false),
        )
        .toList();
  }

  void setActiveChat(String? chatId) {
    // Avoid "setState() or markNeedsBuild() called during build" by wrapping in microtask
    // especially when called from initState during navigation.
    Future.microtask(() {
      _activeChatId.value = chatId ?? '';
      if (chatId != null && chatId.isNotEmpty) {
        _lastActiveChatId.value = chatId;
        _attachMessagesStream(chatId);
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(_lastActiveChatKey, chatId);
        });
      }
    });
  }

  // --- Utilities ---
  /// Extract the first URL from a given text. Returns empty string if none found.
  static String extractFirstUrl(String text) {
    if (text.isEmpty) return '';
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);
    final m = urlRegex.firstMatch(text);
    return m != null ? (m.group(0) ?? '') : '';
  }

  String? _getUserId() {
    try {
      final uid = Get.find<AuthController>().userId;
      if (uid.isEmpty) {
        debugPrint(
            'ChatController: User ID is empty. User might be logged out.');
        return null;
      }
      return uid;
    } catch (e) {
      debugPrint('ChatController: Error getting user ID: $e');
      return null;
    }
  }

  void _setLoading(bool value) {
    if (_isLoading.value != value) {
      _isLoading.value = value;
    }
  }

  // ---- Star (per-user) using SharedPreferences ----
  Future<bool> isStarred(String chatId, String messageId) async {
    final me = Get.find<AuthController>().userId;
    if (me.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('star_${chatId}_${me}_$messageId') ?? false;
  }

  Future<void> toggleStar(String chatId, String messageId) async {
    if (chatId.isEmpty || messageId.isEmpty) return;
    final me = _getUserId();
    if (me == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'star_${chatId}_${me}_$messageId';
    final current = prefs.getBool(key) ?? false;
    await prefs.setBool(key, !current);
    _chatMessages.refresh(); // refresh UI list
  }

  // ---- Pin (per chat) ----
  Future<String?> getPinnedId(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('pin_$chatId');
  }

  Future<void> pinMessage(String chatId, String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pin_$chatId', messageId);
    _chatMessages.refresh();
  }

  Future<void> unpinMessage(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pin_$chatId');
    _chatMessages.refresh();
  }

  Future<void> uploadVideoAndSend({
    required String chatId,
    required XFile file,
    void Function(double progress)? onProgress,
    String? replyToMessageId,
  }) async {
    if (_isInputLocked.value) {
      Get.snackbar('تنبيه سيادي', _lockReason.value);
      return;
    }
    if (chatId.isEmpty) return;
    final me = _getUserId();
    if (me == null) return;
    final fileName = file.name;
    final storagePath =
        'chats/$chatId/users/$me/videos/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    try {
      _setLoading(true);
      final (url, size) = await StorageService.instance.uploadFile(
        file: file,
        path: storagePath,
        onProgress: onProgress,
      );

      final dataMsg = data_msg_models.Message(
        id: const Uuid().v4(),
        localId: const Uuid().v4(),
        chatId: chatId,
        senderId: me,
        type: data_msg_models.MessageType.video,
        mediaUrl: url,
        mediaSize: size,
        replyToMessageId: replyToMessageId,
        status: data_msg_models.MessageStatus.pending,
        createdAt: DateTime.now(),
      );

      await _syncEngine.enqueueMessage(dataMsg);
    } catch (e) {
      debugPrint('uploadVideoAndSend failed: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ... (some lines here) ...

  Future<void> uploadImageAndSend({
    required String chatId,
    required XFile file,
    void Function(double progress)? onProgress,
    String? replyToMessageId,
  }) async {
    if (_isInputLocked.value) {
      Get.snackbar('تنبيه سيادي', _lockReason.value);
      return;
    }
    if (chatId.isEmpty) return;
    final me = _getUserId();
    if (me == null) return;
    final fileName = file.name;
    final storagePath =
        'chats/$chatId/users/$me/images/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    try {
      _setLoading(true);
      final (url, size) = await StorageService.instance.uploadFile(
        file: file,
        path: storagePath,
        onProgress: onProgress,
      );

      final dataMsg = data_msg_models.Message(
        id: const Uuid().v4(),
        localId: const Uuid().v4(),
        chatId: chatId,
        senderId: me,
        type: data_msg_models.MessageType.image,
        mediaUrl: url,
        mediaSize: size,
        replyToMessageId: replyToMessageId,
        status: data_msg_models.MessageStatus.pending,
        createdAt: DateTime.now(),
      );

      await _syncEngine.enqueueMessage(dataMsg);
    } catch (e) {
      debugPrint('uploadImageAndSend failed: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> uploadFileAndSend({
    required String chatId,
    required XFile file,
    void Function(double progress)? onProgress,
    String? replyToMessageId,
  }) async {
    if (_isInputLocked.value) {
      Get.snackbar('تنبيه سيادي', _lockReason.value);
      return;
    }
    if (chatId.isEmpty) return;
    final me = _getUserId();
    if (me == null) return;
    final fileName = file.name;
    final storagePath =
        'chats/$chatId/users/$me/files/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    try {
      _setLoading(true);
      final (url, size) = await StorageService.instance.uploadFile(
        file: file,
        path: storagePath,
        onProgress: onProgress,
      );

      final dataMsg = data_msg_models.Message(
        id: const Uuid().v4(),
        localId: const Uuid().v4(),
        chatId: chatId,
        senderId: me,
        type: data_msg_models.MessageType.file,
        mediaUrl: url,
        mediaSize: size,
        replyToMessageId: replyToMessageId,
        status: data_msg_models.MessageStatus.pending,
        createdAt: DateTime.now(),
      );

      await _syncEngine.enqueueMessage(dataMsg);
    } catch (e) {
      debugPrint('uploadFileAndSend failed: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // --- Phase 6: Media helpers ---
  Future<void> sendImageFile({
    required String chatId,
    required XFile file,
    String? replyToMessageId,
  }) async {
    if (_isInputLocked.value) {
      Get.snackbar('تنبيه سيادي', _lockReason.value);
      return;
    }
    if (AppConfig.useMockData || chatId.isEmpty) return;
    final senderId = _getUserId();
    if (senderId == null) return;
    final fileName = file.name;
    final path =
        'chats/$chatId/users/$senderId/images/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      _setLoading(true);
      final (url, size) = await StorageService.instance.uploadFile(
        file: file,
        path: path,
      );
      final sent = await Get.find<IMessageRepository>().sendMessage(
        type: _mapMessageTypeToData(MessageType.image),
        chatId: chatId,
        senderId: senderId,
        mediaUrl: url,
        mediaSize: size,
        replyToMessageId: replyToMessageId,
      );
      await Get.find<IChatRepository>().updateLastMessage(
        chatId: chatId,
        message: sent,
      );
      unawaited(stopTyping(chatId));
    } catch (e) {
      AppLogger.e('sendImageFile failed', e);
    } finally {
      _setLoading(false);
    }
  }

  // --- File sending helpers ---

  // --- File sending helpers ---
  Future<void> sendFile({
    required String chatId,
    required XFile file,
    String? replyToMessageId,
  }) async {
    if (_isInputLocked.value) {
      Get.snackbar('تنبيه سيادي', _lockReason.value);
      return;
    }
    if (AppConfig.useMockData || chatId.isEmpty) return;
    final senderId = _getUserId();
    if (senderId == null) return;
    // Use named property of XFile which is safer for Web
    final fileName = file.name;
    final path =
        'chats/$chatId/users/$senderId/files/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      _setLoading(true);
      final (url, size) = await StorageService.instance.uploadFile(
        file: file,
        path: path,
      );
      final sent = await Get.find<IMessageRepository>().sendMessage(
        chatId: chatId,
        senderId: senderId,
        type: _mapMessageTypeToData(MessageType.file),
        mediaUrl: url,
        mediaSize: size,
        replyToMessageId: replyToMessageId,
      );
      await Get.find<IChatRepository>().updateLastMessage(
        chatId: chatId,
        message: sent,
      );
      unawaited(stopTyping(chatId));
    } catch (e) {
      AppLogger.e('sendFile failed', e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> sendAudio({
    required String chatId,
    required XFile file,
    String? replyToMessageId,
  }) async {
    if (_isInputLocked.value) {
      Get.snackbar('تنبيه سيادي', _lockReason.value);
      return;
    }
    if (AppConfig.useMockData || chatId.isEmpty) return;
    final senderId = _getUserId();
    if (senderId == null) return;
    final fileName = file.name;
    final path =
        'chats/$chatId/users/$senderId/audio/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      _setLoading(true);
      final (url, size) = await StorageService.instance.uploadFile(
        file: file,
        path: path,
      );
      final dataMsg = data_msg_models.Message(
        id: const Uuid().v4(),
        localId: const Uuid().v4(),
        chatId: chatId,
        senderId: senderId,
        type: data_msg_models.MessageType.audio,
        mediaUrl: url,
        mediaSize: size,
        replyToMessageId: replyToMessageId,
        status: data_msg_models.MessageStatus.pending,
        createdAt: DateTime.now(),
      );

      await _syncEngine.enqueueMessage(dataMsg);
      unawaited(stopTyping(chatId));
    } catch (e) {
      debugPrint('sendAudio failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  // --- Thumbnails & Stickers helpers (future-proof) ---
  /// Upload a thumbnail file and return its download URL.
  Future<String> uploadThumbnailFile({
    required String chatId,
    required XFile file,
  }) async {
    if (_isInputLocked.value) return '';
    if (AppConfig.useMockData || chatId.isEmpty) return '';
    final senderId = _getUserId();
    if (senderId == null) return '';
    final fileName = file.name;
    final path =
        'chats/$chatId/users/$senderId/thumbnails/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      _setLoading(true);
      final (url, _) = await StorageService.instance.uploadFile(
        file: file,
        path: path,
      );
      // 5. Success Moment Trigger (Activation)
      if (!_hasSentFirstMessage.value) {
        _hasSentFirstMessage.value = true;
        showFirstMessageSuccess.value = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_hasSentFirstMessageKey, true);
      }

      return url;
    } catch (e) {
      debugPrint('uploadThumbnailFile failed: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Upload thumbnail from raw bytes and return its download URL.
  Future<String> uploadThumbnailBytes({
    required String chatId,
    required List<int> bytes,
    String fileName = 'thumb.jpg',
  }) async {
    if (AppConfig.useMockData || chatId.isEmpty || bytes.isEmpty) return '';
    final senderId = _getUserId();
    if (senderId == null) return '';
    final path =
        'chats/$chatId/users/$senderId/thumbnails/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      _setLoading(true);
      final urlSize = await StorageService.instance.uploadBytes(
        bytes: bytes,
        path: path,
      );
      return urlSize.$1; // url
    } catch (e) {
      debugPrint('uploadThumbnailBytes failed: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Upload a sticker file and send it as an image message.
  Future<void> sendStickerFile({
    required String chatId,
    required XFile file,
    String? replyToMessageId,
  }) async {
    if (_isInputLocked.value) {
      Get.snackbar('تنبيه سيادي', _lockReason.value);
      return;
    }
    if (AppConfig.useMockData || chatId.isEmpty) return;
    final senderId = _getUserId();
    if (senderId == null) return;
    final fileName = file.name;
    final path =
        'chats/$chatId/users/$senderId/stickers/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      _setLoading(true);
      final (url, size) = await StorageService.instance.uploadFile(
        file: file,
        path: path,
      );
      final sent = await Get.find<IMessageRepository>().sendMessage(
        type: _mapMessageTypeToData(MessageType.image),
        chatId: chatId,
        senderId: senderId,
        mediaUrl: url,
        mediaSize: size,
        replyToMessageId: replyToMessageId,
      );
      await Get.find<IChatRepository>().updateLastMessage(
        chatId: chatId,
        message: sent,
      );
      unawaited(stopTyping(chatId));
    } catch (e) {
      debugPrint('sendStickerFile failed: $e');
    }
  }

  /// Upload sticker from raw bytes and send it as an image message.
  Future<void> sendStickerBytes({
    required String chatId,
    required List<int> bytes,
    String fileName = 'sticker.png',
  }) async {
    if (_isInputLocked.value) {
      Get.snackbar('تنبيه سيادي', _lockReason.value);
      return;
    }
    if (AppConfig.useMockData) return;
    final senderId = Get.find<AuthController>().userId;
    final path =
        'chats/$chatId/users/$senderId/stickers/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      final (url, size) = await StorageService.instance.uploadBytes(
        bytes: bytes,
        path: path,
      );
      final dataMsg = data_msg_models.Message(
        id: const Uuid().v4(),
        localId: const Uuid().v4(),
        chatId: chatId,
        senderId: senderId,
        type: data_msg_models.MessageType.image,
        mediaUrl: url,
        mediaSize: size,
        status: data_msg_models.MessageStatus.pending,
        createdAt: DateTime.now(),
      );

      await _syncEngine.enqueueMessage(dataMsg);
      unawaited(stopTyping(chatId));
    } catch (e) {
      debugPrint('sendStickerBytes failed: $e');
    }
  }

  // --- Reactions, edit, delete ---
  final Map<String, DateTime> _lastReactionTime = {};

  Future<void> addReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    if (_isInputLocked.value) return;
    if (AppConfig.useMockData ||
        chatId.isEmpty ||
        messageId.isEmpty ||
        emoji.isEmpty) {
      return;
    }
    // Stage R: Local debounce to prevent rapid double-taps before network response
    final now = DateTime.now();
    final key = '$messageId-$emoji';
    if (_lastReactionTime.containsKey(key) &&
        now.difference(_lastReactionTime[key]!).inMilliseconds < 500) {
      return;
    }
    _lastReactionTime[key] = now;

    try {
      await Get.find<IMessageRepository>().addReaction(
        chatId,
        messageId,
        '', // userId handled by RPC internally
        emoji,
      );
    } catch (e) {
      debugPrint('addReaction (toggle) failed: $e');
      if (e.toString().contains('Rate limit exceeded')) {
        Get.snackbar(
          'تنبيه',
          'لقد قمت بإضافة تفاعلات كثيرة جداً. يرجى الانتظار قليلاً.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.orange.withValues(alpha: 0.9),
          colorText: Colors.white,
        );
      }
    }
  }

  void incrementThrottledCount(String chatId) {
    _throttledCounter[chatId] = (_throttledCounter[chatId] ?? 0) + 1;
  }

  void clearThrottledCount(String chatId) {
    _throttledCounter.remove(chatId);
  }

  Future<void> removeReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    if (chatId.isEmpty || messageId.isEmpty || emoji.isEmpty) return;
    // Stage R: Explicit remove if needed, though addReaction handles toggle.
    try {
      await Get.find<IMessageRepository>().removeReaction(
        chatId,
        messageId,
        '',
        emoji,
      );
    } catch (e) {
      debugPrint('removeReaction failed: $e');
    }
  }

  Future<void> editMessageText({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {
    if (chatId.isEmpty || messageId.isEmpty || newText.trim().isEmpty) return;
    try {
      await Get.find<IMessageRepository>().editMessageText(
        chatId,
        messageId,
        newText,
      );
      // Optimistic update
      final msgs = _chatMessages[chatId];
      if (msgs != null) {
        final idx = msgs.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          msgs[idx] = msgs[idx].copyWith(
            content: newText,
            isEdited: true,
            editedAt: DateTime.now(),
          );
          _chatMessages[chatId] = List.from(msgs);
          _chatMessages.refresh();
        }
      }
    } catch (e) {
      debugPrint('editMessageText failed: $e');
    }
  }

  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    if (chatId.isEmpty || messageId.isEmpty || emoji.isEmpty) return;
    final uid = _getUserId();
    if (uid == null) return;

    // 1. Find message in local cache
    final msgs = _chatMessages[chatId] ?? [];
    final idx = msgs.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    final originalMessage = msgs[idx];

    // 2. Optimistic Update (O(1) Instant UI)
    // Use the new fields: userReactions (User->Emoji) and reactionCounts (Emoji->Count)
    final currentUserReactions =
        Map<String, String>.from(originalMessage.userReactions);
    final currentReactionCounts =
        Map<String, int>.from(originalMessage.reactionCounts);

    final existingEmoji = currentUserReactions[uid];

    if (existingEmoji == emoji) {
      // Untoggle (Remove)
      currentUserReactions.remove(uid);
      currentReactionCounts[emoji] = (currentReactionCounts[emoji] ?? 1) - 1;
      if (currentReactionCounts[emoji]! <= 0) {
        currentReactionCounts.remove(emoji);
      }
    } else {
      // Toggle New (and potentially remove old if existed)
      if (existingEmoji != null) {
        // Remove old emoji count
        currentReactionCounts[existingEmoji] =
            (currentReactionCounts[existingEmoji] ?? 1) - 1;
        if (currentReactionCounts[existingEmoji]! <= 0) {
          currentReactionCounts.remove(existingEmoji);
        }
      }
      // Add new emoji
      currentUserReactions[uid] = emoji;
      currentReactionCounts[emoji] = (currentReactionCounts[emoji] ?? 0) + 1;
    }

    final optimisticMessage = originalMessage.copyWith(
      userReactions: currentUserReactions,
      reactionCounts: currentReactionCounts,
      syncingReactions: Set<String>.from(originalMessage.syncingReactions)
        ..add(emoji),
    );

    // Apply to UI immediately
    msgs[idx] = optimisticMessage;
    _chatMessages[chatId] = List.from(msgs);
    _chatMessages.refresh();

    try {
      // 3. Fire & Forget
      await Get.find<IMessageRepository>().toggleReaction(
        messageId: messageId,
        chatId: chatId,
        emoji: emoji,
      );

      // Remove from syncing on success
      final successIdx = msgs.indexWhere((m) => m.id == messageId);
      if (successIdx != -1) {
        final currentMsg = msgs[successIdx];
        msgs[successIdx] = currentMsg.copyWith(
          syncingReactions: Set<String>.from(currentMsg.syncingReactions)
            ..remove(emoji),
        );
        _chatMessages[chatId] = List.from(msgs);
        _chatMessages.refresh();
      }
    } catch (e) {
      // 4. Rollback on Failure
      debugPrint('Reaction failed, rolling back: $e');
      final rollbackIdx = msgs.indexWhere((m) => m.id == messageId);
      if (rollbackIdx != -1) {
        // Rollback to original, which also removes the 'syncing' flag
        msgs[rollbackIdx] = originalMessage;
        _chatMessages[chatId] = List.from(msgs);
        _chatMessages.refresh();
      }

      Get.snackbar('خطأ', 'فشل إضافة التفاعل');
    }
  }
  // Note: deletion handled by existing deleteMessage below (local + remote)

  void _detachRealtime() {
    // Cancel chats subscription
    _chatsSub?.cancel();
    _chatsSub = null;
    // Cancel any pending retry timers
    _chatsRetryTimer?.cancel();
    _chatsRetryTimer = null;
    // Cancel all messages subscriptions
    for (final sub in _messagesSubs.values) {
      sub.cancel();
    }
    _messagesSubs.clear();
    // Cancel all typing subscriptions
    for (final sub in _typingSubs.values) {
      sub.cancel();
    }
    _typingSubs.clear();
    _typingIndicators.clear();
    // Cancel typing timers
    for (final timer in _typingTimers.values) {
      timer?.cancel();
    }
    _typingTimers.clear();
    if (AppConfig.isDebugMode) {
      debugPrint(
          'detachRealtime: canceled chats/messages/typing subscriptions');
    }
  }

  // Mapping helpers between data models and UI models
  ChatModel _mapChatFromData(data_chat_models.Chat c) {
    final isGroup = c.isGroup;
    final resolvedName =
        isGroup ? (c.groupName ?? 'مجموعة') : _resolveIndividualName(c);
    return ChatModel(
      id: c.id,
      name: resolvedName,
      type: isGroup ? ChatType.group : ChatType.individual,
      participantIds: c.participantIds,
      avatar: c.groupPhotoUrl,
      lastActivity: c.lastMessageAt ?? c.updatedAt,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt ?? c.createdAt,
      isMuted: c.isMuted ?? false,
      muteUntil: c.muteUntil,
      isPinned: c.isPinned ?? false,
      isArchived: false, // Not in data model yet, assumes active
      unreadCount: 0, // Not yet implemented in data model
    );
  }

  // --- Deletion APIs ---
  Future<void> deleteMessageForMe({
    required String chatId,
    required String messageId,
  }) async {
    if (chatId.isEmpty || messageId.isEmpty) return;
    // Stage R: Secure deletion using record append in JSONB
    final me = _getUserId();
    if (me == null) return;
    try {
      // Local optimistic hide
      final messages = _chatMessages[chatId];
      if (messages != null) {
        final idx = messages.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          final updatedMd =
              Map<String, dynamic>.from(messages[idx].metadata ?? {});
          final df = (updatedMd['deletedFor'] is Map)
              ? Map<String, dynamic>.from(updatedMd['deletedFor'])
              : <String, dynamic>{};
          df[me] = true;
          updatedMd['deletedFor'] = df;

          _chatMessages[chatId]![idx] =
              messages[idx].copyWith(metadata: updatedMd);
          _chatMessages.refresh();
        }
      }

      if (!AppConfig.useMockData) {
        await Get.find<IMessageRepository>().deleteMessageForMe(
          chatId: chatId,
          messageId: messageId,
          userId: me,
        );
      }
    } catch (e) {
      debugPrint('deleteMessageForMe failed: $e');
      Get.snackbar('تعذر الحذف', 'حدث خطأ أثناء حذف الرسالة لديك');
    }
  }

  Future<void> deleteMessageForAll({
    required String chatId,
    required String messageId,
  }) async {
    if (chatId.isEmpty || messageId.isEmpty) return;
    try {
      final deleterName = Get.find<AuthController>().userName.isNotEmpty
          ? Get.find<AuthController>().userName
          : 'مستخدم';
      await Get.find<IMessageRepository>().softDeleteForAll(
        chatId: chatId,
        messageId: messageId,
        deletedByName: deleterName,
      );
    } catch (e) {
      debugPrint('deleteMessageForAll failed: $e');
      Get.snackbar(
          'تعذر الحذف للجميع', 'ليست لديك صلاحية أو حدث خطأ غير متوقع');
    }
  }

  // --- Bulk Operations ---

  Future<void> deleteMessagesForMe({
    required String chatId,
    required List<String> messageIds,
  }) async {
    if (chatId.isEmpty || messageIds.isEmpty) return;
    final me = _getUserId();
    if (me == null) return;
    for (final id in messageIds) {
      try {
        await Get.find<IMessageRepository>().deleteMessageForMe(
          chatId: chatId,
          messageId: id,
          userId: me,
        );
      } catch (e) {
        debugPrint('Bulk deleteForMe failed for $id: $e');
      }
    }
  }

  Future<void> softDeleteMessagesForAll({
    required String chatId,
    required List<String> messageIds,
  }) async {
    if (chatId.isEmpty || messageIds.isEmpty) return;
    final auth = Get.find<AuthController>();
    final deleterName = auth.userName.isNotEmpty ? auth.userName : 'مستخدم';
    for (final id in messageIds) {
      try {
        await Get.find<IMessageRepository>().softDeleteForAll(
          chatId: chatId,
          messageId: id,
          deletedByName: deleterName,
        );
      } catch (e) {
        debugPrint('Bulk softDeleteForAll failed for $id: $e');
      }
    }
  }

  Future<void> markChatAsRead(String chatId) async {
    if (AppConfig.useMockData || chatId.isEmpty) return;
    try {
      final me = _getUserId();
      if (me == null) return;

      // 1. Sync to remote via engine (deduplicated)
      await _syncEngine.enqueueAction(SyncActionType.markRead, chatId: chatId);

      // 2. Optimistically clear unread counts locally
      final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
      if (chatIndex != -1) {
        _chats[chatIndex] = _chats[chatIndex].copyWith(unreadCount: 0);
      }
      debugPrint('ChatController: markChatAsRead signal sent for $chatId');
    } catch (e) {
      debugPrint('markChatAsRead failed: $e');
    }
  }

  Future<void> forwardMessages({
    required List<MessageModel> messages,
    required String targetChatId,
  }) async {
    if (targetChatId.isEmpty || messages.isEmpty) return;
    for (final msg in messages) {
      try {
        // We forward by re-sending. Basic text/media forwarding.
        if (msg.type == MessageType.text) {
          await sendMessage(chatId: targetChatId, content: msg.content);
        } else if (msg.metadata?['mediaUrl'] != null) {
          // Re-send with existing remote URL if possible, or download/re-upload?
          // For now, let's assume we can pass the URL to repository as a new message.
          // SupabaseMessageRepository.sendMessage normally handles local files,
          // but we might need a way to forward existing URLs.
          // Simplest: send as text with URL for now, or use a specific forward method if it exists.

          // Actually, our repository.sendMessage takes a File? or just raw text.
          // Let's just send the URL as text if it's media, until repository supports remote forwards.
          await sendMessage(
            chatId: targetChatId,
            content: '[معاد توجيهها]: ${msg.metadata!['mediaUrl']}',
          );
        }
      } catch (e) {
        debugPrint('Forward failed for ${msg.id}: $e');
      }
    }
  }

  // Resolve name for individual chats using other participant's displayName (cached),
  // and trigger async fetch if not present.
  String _resolveIndividualName(data_chat_models.Chat c) {
    final me = Get.find<AuthController>().userId;
    final otherId = c.participantIds.firstWhere(
      (id) => id != me,
      orElse: () => '',
    );
    if (otherId.isEmpty) return 'محادثة';
    final cached = _userNameCache[otherId];
    if (cached != null && cached.isNotEmpty) return cached;
    // Fire and forget fetch; will update the chat item when available
    _fetchAndApplyUserName(otherId, c.id);
    // Show a better immediate fallback instead of generic text
    return _shortId(otherId);
  }

  Future<void> _fetchAndApplyUserName(String userId, String chatId) async {
    try {
      final user = await Get.find<IUserRepository>().getById(userId);
      String name = '';
      if (user is user_models.AppUser) {
        if ((user.displayName?.isNotEmpty ?? false)) {
          name = user.displayName!;
        } else if (user.email.isNotEmpty) {
          name = user.email;
        }
      }
      if (name.isEmpty) {
        name = _shortId(userId);
      }
      if (name.isNotEmpty) {
        _userNameCache[userId] = name;
        final idx = _chats.indexWhere((c) => c.id == chatId);
        if (idx != -1) {
          _chats[idx] = _chats[idx].copyWith(name: name);
          await _saveCachedData();
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve user name for $userId: $e');
    }
  }

  MessageModel _mapMessageFromData(data_msg_models.Message m) {
    // Build metadata map for UI rendering (media/reactions/etc.)
    final md = <String, dynamic>{};
    if (m.mediaUrl != null) md['mediaUrl'] = m.mediaUrl;
    if (m.thumbnailUrl != null) md['thumbnailUrl'] = m.thumbnailUrl;
    if (m.mediaSize != null) md['mediaSize'] = m.mediaSize;
    if (m.reactions != null) md['reactions'] = m.reactions;
    if (m.deleted != null) md['deleted'] = m.deleted;
    if (m.deletedByName != null) md['deletedByName'] = m.deletedByName;
    if (m.deletedFor != null) md['deletedFor'] = m.deletedFor;
    if (m.editedAt != null) md['editedAt'] = m.editedAt!.toIso8601String();

    return MessageModel(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      content: m.text ?? '',
      type: _mapMessageTypeFromData(m.type),
      status: _mapMessageStatusFromData(m.status),
      timestamp: m.createdAt,
      replyToMessageId: m.replyToMessageId,
      metadata: md.isEmpty ? null : md,
      userReactions: m.reactions ?? {},
      reactionCounts: m.reactionCounts ?? {},
    );
  }

  data_msg_models.MessageType _mapMessageTypeToData(MessageType t) {
    switch (t) {
      case MessageType.text:
        return data_msg_models.MessageType.text;
      case MessageType.image:
        return data_msg_models.MessageType.image;
      case MessageType.video:
        return data_msg_models.MessageType.video;
      case MessageType.audio:
        return data_msg_models.MessageType.audio;
      case MessageType.file:
        return data_msg_models.MessageType.file;
      case MessageType.chat:
        return data_msg_models.MessageType.chat;
      case MessageType.call:
        return data_msg_models.MessageType.call;
      case MessageType.location:
      case MessageType.contact:
        return data_msg_models.MessageType.text; // fallback
    }
  }

  MessageType _mapMessageTypeFromData(data_msg_models.MessageType t) {
    switch (t) {
      case data_msg_models.MessageType.text:
        return MessageType.text;
      case data_msg_models.MessageType.image:
        return MessageType.image;
      case data_msg_models.MessageType.video:
        return MessageType.video;
      case data_msg_models.MessageType.audio:
        return MessageType.audio;
      case data_msg_models.MessageType.file:
        return MessageType.file;
      case data_msg_models.MessageType.chat:
        return MessageType.chat;
      case data_msg_models.MessageType.call:
        return MessageType.call;
      case data_msg_models.MessageType.system:
        return MessageType.text;
      case data_msg_models.MessageType.location:
        return MessageType.location;
      case data_msg_models.MessageType.contact:
        return MessageType.contact;
    }
  }

  MessageStatus _mapMessageStatusFromData(data_msg_models.MessageStatus s) {
    switch (s) {
      case data_msg_models.MessageStatus.pending:
        return MessageStatus.pending;
      case data_msg_models.MessageStatus.sent:
        return MessageStatus.sent;
      case data_msg_models.MessageStatus.delivered:
        return MessageStatus.delivered;
      case data_msg_models.MessageStatus.read:
        return MessageStatus.read;
      case data_msg_models.MessageStatus.failed:
        return MessageStatus.failed;
    }
  }

  // --- Test helpers (safe to call from unit tests) ---
  // These expose the mapping logic to allow verifying consistency without
  // reaching into private members in tests.
  static MessageType mapMessageTypeFromData(data_msg_models.MessageType t) {
    switch (t) {
      case data_msg_models.MessageType.text:
        return MessageType.text;
      case data_msg_models.MessageType.image:
        return MessageType.image;
      case data_msg_models.MessageType.video:
        return MessageType.video;
      case data_msg_models.MessageType.audio:
        return MessageType.audio;
      case data_msg_models.MessageType.file:
        return MessageType.file;
      case data_msg_models.MessageType.chat:
        return MessageType.chat;
      case data_msg_models.MessageType.call:
        return MessageType.call;
      case data_msg_models.MessageType.system:
        return MessageType.text;
      case data_msg_models.MessageType.location:
        return MessageType.location;
      case data_msg_models.MessageType.contact:
        return MessageType.contact;
    }
  }

  static MessageStatus mapMessageStatusFromData(
      data_msg_models.MessageStatus s) {
    switch (s) {
      case data_msg_models.MessageStatus.pending:
        return MessageStatus.pending;
      case data_msg_models.MessageStatus.sent:
        return MessageStatus.sent;
      case data_msg_models.MessageStatus.delivered:
        return MessageStatus.delivered;
      case data_msg_models.MessageStatus.read:
        return MessageStatus.read;
      case data_msg_models.MessageStatus.failed:
        return MessageStatus.failed;
    }
  }

  /// Debug-only: seed messages for tests to validate Delivered/Read flows.
  /// Wrapped in assert to ensure it's not used in release builds.
  void injectMessagesForTest(String chatId, List<MessageModel> messages) {
    assert(() {
      _chatMessages[chatId] = List<MessageModel>.from(messages);
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx != -1 && messages.isNotEmpty) {
        final last = messages.last;
        _chats[idx] = _chats[idx].copyWith(
          lastMessage: last,
          lastMessageId: last.id,
          lastActivity: last.timestamp,
          updatedAt: DateTime.now(),
        );
      }
      return true;
    }());
  }

  String get searchQuery => _searchQuery.value;
  bool get isInitialized => _initialized.value;

  List<MessageModel> getMessagesForChat(String chatId) {
    return _chatMessages[chatId] ?? [];
  }

  // Expose reactive messages map for UI (e.g., ChatScreen) to listen via Obx
  RxMap<String, List<MessageModel>> get chatMessagesRx => _chatMessages;
  RxMap<String, List<MessageModel>> get chatMessages => _chatMessages;

  // Expose reactive typing indicators for UI
  RxMap<String, List<TypingIndicator>> get typingIndicatorsRx =>
      _typingIndicators;

  // Get typing indicators for a specific chat
  List<TypingIndicator> getTypingIndicators(String chatId) {
    return _typingIndicators[chatId] ?? [];
  }

  // Get typing users display names for a chat (excluding current user)
  List<String> getTypingUserNames(String chatId) {
    final indicators = getTypingIndicators(chatId);
    final currentUserId = Get.find<AuthController>().userId;
    final typingUserIds = indicators
        .where((indicator) => indicator.userId != currentUserId)
        .map((indicator) => indicator.userId)
        .toList();

    // Resolve user names from cache
    final names = <String>[];
    for (final userId in typingUserIds) {
      final name = _userNameCache[userId];
      if (name != null && name.isNotEmpty) {
        names.add(name);
      } else {
        names.add('مستخدم');
        // Trigger async name resolution
        _fetchAndApplyUserName(userId, chatId);
      }
    }
    return names;
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _setupSovereignLockdown();
    // Re-attach realtime when auth state becomes logged in
    try {
      final auth = Get.find<AuthController>();
      _authWorker = ever<bool>(auth.isLoggedInRx, (loggedIn) {
        if (!AppConfig.useMockData) {
          if (loggedIn) {
            _detachRealtime();
            _attachRealtime();
          } else {
            _detachRealtime();
          }
        }
      });
      // React to UID changes (account switch)
      _uidWorker = ever<String>(auth.userIdRx, (uid) {
        if (!AppConfig.useMockData) {
          _detachRealtime();
          if (uid.isNotEmpty) {
            _attachRealtime();
          }
        }
      });
      // React to token refresh to update Realtime subscriptions
      // [Stage R]: Debounced Realtime Restart
      Timer? refreshDebounce;
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.tokenRefreshed) {
          if (!AppConfig.useMockData && auth.isLoggedIn) {
            refreshDebounce?.cancel();
            refreshDebounce = Timer(const Duration(seconds: 2), () {
              if (AppConfig.isDebugMode) {
                debugPrint(
                    'ChatController: Token refreshed, re-attaching Realtime (Debounced)');
              }
              _detachRealtime();
              _attachRealtime();
            });
          }
        }
      }, onError: (e) {
        debugPrint('ChatController: onAuthStateChange error: $e');
      });
    } catch (_) {}
  }

  Future<void> _initialize() async {
    await _loadCachedData();
    _generateMockData();
    _ensureMockMessagesForExistingChats();
    // Attach realtime if not using mock data
    if (!AppConfig.useMockData) {
      _isLoading.value = false;
      _initialized.value = true;

      // Load activation/retention states
      final prefs = await SharedPreferences.getInstance();
      _hasSentFirstMessage.value =
          prefs.getBool(_hasSentFirstMessageKey) ?? false;
      _lastActiveChatId.value = prefs.getString(_lastActiveChatKey) ?? '';
    }
  }

  void _setupSovereignLockdown() {
    try {
      final engine = SovereignCommunicationEngine.instance;
      ever<CommSessionStatus>(engine.statusRx, (status) {
        final locked = status != CommSessionStatus.idle;
        _isInputLocked.value = locked;
        if (locked) {
          _lockReason.value = 'الدردشة معطلة أثناء الجلسة';
        } else {
          _lockReason.value = '';
        }
      });
      // Initial check
      _isInputLocked.value = engine.status != CommSessionStatus.idle;
      if (_isInputLocked.value) {
        _lockReason.value = 'الدردشة معطلة أثناء الجلسة';
      }
    } catch (e) {
      debugPrint(
          'ChatController: SovereignCommunicationEngine not found yet: $e');
    }
  }

  void setInputLocked(bool locked, {String? reason}) {
    _isInputLocked.value = locked;
    if (locked) {
      _lockReason.value = reason ?? 'الدردشة معطلة بأمر النظام';
    } else {
      // If we are unlocking, check if there's still a session active
      final engine = SovereignCommunicationEngine.instance;
      if (engine.status != CommSessionStatus.idle) {
        _isInputLocked.value = true;
        _lockReason.value = 'الدردشة معطلة أثناء الجلسة';
      } else {
        _lockReason.value = '';
      }
    }
  }

  void _attachRealtime() {
    // Ensure Firebase-enabled flow and auth readiness
    if (!AppConfig.enableFirebase) return;
    final uid = Get.find<AuthController>().userId;
    if (uid.isEmpty) {
      debugPrint('skip _attachRealtime: empty uid (user not logged in yet)');
      return;
    }
    if (AppConfig.isDebugMode) {
      debugPrint('attachRealtime: watching chats for uid=$uid');
    }
    // G1 Guard: Prevent redundant subscriptions
    if (_chatsSub != null) {
      if (AppConfig.isDebugMode) {
        debugPrint('attachRealtime: subscription already exists, skipping');
      }
      return;
    }

    // Watch user's chats
    final chatsStream = _useChatsFallback
        ? Get.find<IChatRepository>().watchUserChatsNoOrder(uid)
        : Get.find<IChatRepository>().watchUserChats(uid);
    _chatsSub = chatsStream.listen((remoteChats) {
      // Map data models to UI models
      final mapped = remoteChats.map(_mapChatFromData).toList();
      // Sort by lastActivity desc (if provided)
      mapped.sort((a, b) => (b.lastActivity ?? b.updatedAt)
          .compareTo(a.lastActivity ?? a.updatedAt));
      _chats.value = mapped;
      if (AppConfig.isDebugMode) {
        debugPrint('watchUserChats emitted ${remoteChats.length} chats');
      }
      // Ensure message streams are attached for each chat
      for (final c in remoteChats) {
        _attachMessagesStream(c.id);
        _attachTypingStream(c.id);
      }
      _saveCachedData();
    }, onError: (e) {
      final errStr = e.toString();
      debugPrint('watchUserChats error: $errStr');
      // Cancel current subscription
      try {
        _chatsSub?.cancel();
      } catch (_) {}
      _chatsSub = null;
      // If index not ready, switch to fallback immediately and schedule a switch-back attempt
      if (errStr.contains('failed-precondition')) {
        if (!_useChatsFallback) {
          _useChatsFallback = true;
          if (AppConfig.isDebugMode) {
            debugPrint(
                'watchUserChats: enabling fallback (no orderBy) while index builds');
          }
          _attachRealtime();
        }
        // Try to switch back to indexed query after delay
        _chatsRetryTimer?.cancel();
        _chatsRetryTimer = Timer(const Duration(seconds: 30), () {
          if (AppConfig.isDebugMode) {
            debugPrint('attempting to switch back to indexed watchUserChats');
          }
          final auth = Get.find<AuthController>();
          if (auth.userId.isNotEmpty) {
            _useChatsFallback = false;
            _attachRealtime();
          }
        });
      } else {
        // Handle expired JWT or Timeout by attempting a manual session refresh
        if (AppConfig.isStaleSessionError(errStr)) {
          if (AppConfig.isDebugMode) {
            debugPrint(
                'watchUserChats: detected expired token, unauthorized, or channelError, refreshing session...');
          }
          // Debounce manual refresh to avoid spamming if multiple streams fail at once
          _chatsRetryTimer?.cancel();
          _chatsRetryTimer = Timer(const Duration(seconds: 2), () async {
            await Get.find<AuthController>().recoverSession();

            // [C6 Recovery]: Reserve a backup retry in case auth change listener is slow
            Future.delayed(const Duration(seconds: 3), () {
              if (_chatsSub == null) {
                debugPrint('Backup retry for attachRealtime activating...');
                _attachRealtime();
              }
            });
          });
          return;
        }
        // Schedule a delayed retry to allow transient issues to resolve
        _attachRealtimeAfterDelay(const Duration(seconds: 10));
      }
    });
  }

  void _attachRealtimeAfterDelay(Duration delay) {
    _chatsRetryTimer?.cancel();
    _chatsRetryTimer = Timer(delay, () {
      if (AppConfig.isDebugMode) {
        debugPrint(
            'retry attachRealtime after delay of ${delay.inSeconds}s...');
      }
      final auth = Get.find<AuthController>();
      if (auth.userId.isNotEmpty && _chatsSub == null) {
        _attachRealtime();
      }
    });
  }

  void _attachMessagesStream(String chatId) {
    if (_messagesSubs.containsKey(chatId)) return;
    if (AppConfig.isDebugMode) {
      debugPrint('attachMessagesStream: chatId=$chatId');
    }
    final remoteStream = rx_dart.RetryWhenStream(
      () =>
          Get.find<IMessageRepository>().watchChatMessages(chatId, limit: 100),
      (error, stackTrace) {
        final errStr = error.toString();
        debugPrint('watchChatMessages($chatId) retry due to error: $errStr');

        // If we see channelError, it might be due to a dropped socket or expired session
        if (errStr.contains('channelError') || errStr.contains('1006')) {
          unawaited(Get.find<AuthController>().recoverSession());
        }

        return Stream.value(null).delay(const Duration(seconds: 3));
      },
    );
    final localStream = _localRepo.watchChatMessages(chatId);

    final sub = rx_dart.Rx.combineLatest2<List<data_msg_models.Message>,
            List<data_msg_models.Message>, List<MessageModel>>(
      remoteStream,
      localStream,
      (remoteBatch, localBatch) {
        // 1. Map remote messages
        final mappedRemote = remoteBatch.map(_mapMessageFromData).toList();

        // 2. Filter out local messages that have already been synced
        final serverIds = remoteBatch.map((m) => m.id).toSet();
        final localIds =
            remoteBatch.map((m) => m.localId).whereType<String>().toSet();

        final pendingMessages = localBatch
            .where((m) {
              // Keep if it's pending/failed, or if neither its ID nor localId is in the remote batch
              final isPending =
                  m.status == data_msg_models.MessageStatus.pending ||
                      m.status == data_msg_models.MessageStatus.failed;
              final notInRemote =
                  !serverIds.contains(m.id) && !localIds.contains(m.localId);
              return isPending || notInRemote;
            })
            .map(_mapMessageFromData)
            .toList();

        // 3. Combine and Sort
        final combined = [...mappedRemote, ...pendingMessages];
        combined.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        return combined;
      },
    )
        .throttleTime(const Duration(milliseconds: 300),
            trailing: true, leading: true)
        .listen((combinedMsgs) {
      _chatMessages[chatId] = combinedMsgs;

      // [Stage S2] Trigger Receive Sound
      if (combinedMsgs.isNotEmpty) {
        final last = combinedMsgs.last;
        final me = Get.find<AuthController>().userId;
        if (last.senderId != me &&
            _lastAcknowledgedMessageId[chatId] != last.id) {
          // New incoming message!
          if (_initialized.value) {
            // Don't play on initial sync
            unawaited(AppAudioService.instance.play('message_receive.mp3'));
          }
          _lastAcknowledgedMessageId[chatId] = last.id;
        }
      }

      // --- Sync Layer: Smart Delivered Signal ---
      if (!AppConfig.useMockData && combinedMsgs.isNotEmpty) {
        final me = Get.find<AuthController>().userId;
        final lastIncoming = combinedMsgs.lastWhere(
          (m) => m.senderId != me,
          orElse: () =>
              combinedMsgs.first, // fallback, though condition checks above
        );

        if (lastIncoming.senderId != me &&
            lastIncoming.status != MessageStatus.read &&
            lastIncoming.status != MessageStatus.delivered) {
          _syncEngine.enqueueAction(
            SyncActionType.markDelivered,
            chatId: chatId,
            payload: {'messageId': lastIncoming.id},
          );
        }
      }

      if (AppConfig.isDebugMode) {
        debugPrint(
            'watchChatMessages[$chatId] received ${combinedMsgs.length} msgs');
      }

      // Update last message fields in chats list
      final last = combinedMsgs.isNotEmpty ? combinedMsgs.last : null;
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx != -1) {
        _chats[idx] = _chats[idx].copyWith(
          lastMessage: last,
          lastMessageId: last?.id,
          lastActivity: last?.timestamp,
          updatedAt: DateTime.now(),
        );
        // Move to top
        final chat = _chats.removeAt(idx);
        _chats.insert(0, chat);
      }
      _saveCachedData();
    }, onError: (e) {
      // Cancel and remove the subscription on errors to avoid stale listeners
      final errStr = e.toString();
      debugPrint('watchChatMessages($chatId) error: $errStr');
      try {
        _messagesSubs[chatId]?.cancel();
      } catch (_) {}
      _messagesSubs.remove(chatId);

      // Sovereign Recovery Plan (C6): Schedule a re-attachment attempt
      if (errStr.contains('channelError') ||
          errStr.contains('1006') ||
          errStr.contains('JWT') ||
          errStr.contains('expired')) {
        Timer(const Duration(seconds: 5), () {
          final auth = Get.find<AuthController>();
          if (auth.userId.isNotEmpty && !_messagesSubs.containsKey(chatId)) {
            debugPrint(
                'attachMessagesStream[$chatId]: Attempting recovery re-attachment...');
            _attachMessagesStream(chatId);
          }
        });
      }
      if (AppConfig.isDebugMode) {
        if (errStr.contains('permission-denied')) {
          debugPrint(
              'attachMessagesStream[$chatId]: permission-denied; detached listener');
        } else if (errStr.contains('failed-precondition')) {
          debugPrint(
              'attachMessagesStream[$chatId]: failed-precondition (index building?); detached listener');
        } else {
          debugPrint(
              'attachMessagesStream[$chatId]: detached listener due to error');
        }
      }
    });
    _messagesSubs[chatId] = sub;
  }

  void _attachTypingStream(String chatId) {
    if (_typingSubs.containsKey(chatId)) return;
    if (AppConfig.isDebugMode) {
      debugPrint('attachTypingStream: chatId=$chatId');
    }
    final sub =
        Get.find<ITypingRepository>().watchTyping(chatId).listen((indicators) {
      _typingIndicators[chatId] = indicators;
      if (AppConfig.isDebugMode) {
        debugPrint(
            'watchTyping[$chatId] received ${indicators.length} indicators');
      }
    }, onError: (e) {
      final errStr = e.toString();
      debugPrint('watchTyping($chatId) error: $errStr');
      try {
        _typingSubs[chatId]?.cancel();
      } catch (_) {}
      _typingSubs.remove(chatId);

      // Sovereign Recovery Plan (C6): Schedule a re-attachment attempt
      if (errStr.contains('channelError') ||
          errStr.contains('1006') ||
          errStr.contains('JWT') ||
          errStr.contains('expired')) {
        Timer(const Duration(seconds: 7), () {
          final auth = Get.find<AuthController>();
          if (auth.userId.isNotEmpty && !_typingSubs.containsKey(chatId)) {
            debugPrint(
                'attachTypingStream[$chatId]: Attempting recovery re-attachment...');
            _attachTypingStream(chatId);
          }
        });
      }
    });
    _typingSubs[chatId] = sub;
  }

  // --- Typing indicator API (Phase 4) ---
  /// Call when user starts typing in a chat input field
  Future<void> startTyping(String chatId) async {
    if (!AppConfig.enableFirebase) return;
    final me = Get.find<AuthController>().userId;
    if (me.isEmpty) return;
    try {
      // Create/refresh repo document
      await Get.find<ITypingRepository>().startTyping(chatId, me);
      // Start local refresh timer for periodic update while typing
      _typingTimers[chatId]?.cancel();
      _typingTimers[chatId] =
          Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          await Get.find<ITypingRepository>().updateTyping(chatId, me);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('startTyping failed: $e');
    }
  }

  /// Call repeatedly on each key stroke (throttled by periodic timer)
  Future<void> notifyTyping(String chatId) async {
    if (!AppConfig.enableFirebase) return;
    final me = Get.find<AuthController>().userId;
    if (me.isEmpty) return;
    // Ensure a timer exists to keep the indicator alive while typing
    _typingTimers[chatId] ??=
        Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await Get.find<ITypingRepository>().updateTyping(chatId, me);
      } catch (_) {}
    });
  }

  /// Call when user stops typing or sends a message, or when input loses focus
  Future<void> stopTyping(String chatId) async {
    final me = Get.find<AuthController>().userId;
    if (me.isEmpty) return;
    try {
      _typingTimers[chatId]?.cancel();
      _typingTimers.remove(chatId);
      if (AppConfig.enableFirebase) {
        await Get.find<ITypingRepository>().stopTyping(chatId, me);
      }
    } catch (e) {
      debugPrint('stopTyping failed: $e');
    }
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load cached chats (JSON encoded)
      final chatsJson = prefs.getStringList(_chatsKey);
      if (chatsJson != null) {
        final loaded = <ChatModel>[];
        var migrated = false;
        for (final jsonStr in chatsJson) {
          if (jsonStr.isEmpty) continue;
          try {
            final map = jsonDecode(jsonStr) as Map<String, dynamic>;
            loaded.add(ChatModel.fromJson(map));
          } catch (_) {
            // Try legacy query-string format
            try {
              final map =
                  Map<String, dynamic>.from(Uri.splitQueryString(jsonStr));
              loaded.add(ChatModel.fromJson(map));
              migrated = true;
            } catch (e) {
              debugPrint('Skip malformed cached chat: $e');
            }
          }
        }
        _chats.value = loaded;
        if (migrated) {
          // Save back in new JSON format
          await _saveCachedData();
        }
      }

      if (AppConfig.isDebugMode) {
        debugPrint('Loaded ${_chats.length} cached chats');
      }
    } catch (e) {
      debugPrint('Error loading cached data: $e');
    }
  }

  Future<void> _saveCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save chats as JSON strings
      final chatsJson =
          _chats.map((chat) => jsonEncode(chat.toJson())).toList();

      await prefs.setStringList(_chatsKey, chatsJson);

      if (AppConfig.isDebugMode) {
        debugPrint('Saved ${_chats.length} chats to cache');
      }
    } catch (e) {
      debugPrint('Error saving cached data: $e');
    }
  }

  void _generateMockData() {
    if (AppConfig.useMockData && _chats.isEmpty) {
      final mockChats = [
        ChatModel.mock(
          name: 'أحمد محمد',
          type: ChatType.individual,
          unreadCount: 3,
        ),
        ChatModel.mock(
          name: 'فريق العمل',
          type: ChatType.group,
          unreadCount: 1,
        ),
        ChatModel.mock(
          name: 'سارة أحمد',
          type: ChatType.individual,
          unreadCount: 0,
        ),
        ChatModel.mock(
          name: 'مجموعة الأصدقاء',
          type: ChatType.group,
          unreadCount: 5,
        ),
        ChatModel.mock(
          name: 'محمد علي',
          type: ChatType.individual,
          unreadCount: 0,
        ),
        ChatModel.mock(
          name: 'مجموعة العائلة',
          type: ChatType.group,
          unreadCount: 2,
        ),
      ];

      _chats.addAll(mockChats);

      // Generate mock messages for each chat
      for (final chat in mockChats) {
        _generateMockMessagesForChat(chat.id);
      }

      _saveCachedData();
    }
  }

  void _generateMockMessagesForChat(String chatId) {
    final messages = [
      MessageModel.mock(
        chatId: chatId,
        content: 'مرحباً! كيف حالك؟',
        status: MessageStatus.read,
      ),
      MessageModel.mock(
        chatId: chatId,
        content: 'أهلاً وسهلاً! بخير والحمد لله',
        status: MessageStatus.read,
      ),
      MessageModel.mock(
        chatId: chatId,
        content: 'هل أنت مستعد للاجتماع غداً؟',
        status: MessageStatus.delivered,
      ),
    ];

    _chatMessages[chatId] = messages;

    // Update chat's last message fields so search by lastMessage works
    final last = messages.isNotEmpty ? messages.last : null;
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1 && last != null) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(
        lastMessage: last,
        lastMessageId: last.id,
        lastActivity: last.timestamp,
        updatedAt: last.timestamp,
      );
    }
  }

  void _ensureMockMessagesForExistingChats() {
    if (!AppConfig.useMockData) return;
    for (final chat in _chats) {
      final hasMessages = _chatMessages[chat.id]?.isNotEmpty ?? false;
      if (!hasMessages) {
        _generateMockMessagesForChat(chat.id);
      }
    }
  }

  void setSearchQuery(String query) {
    _searchQuery.value = query;
  }

  void clearSearch() {
    _searchQuery.value = '';
  }

  Future<void> refreshChats() async {
    _isLoading.value = true;

    try {
      // Simulate network delay
      await Future.delayed(const Duration(seconds: 1));

      // In a real app, this would fetch from server
      if (AppConfig.useMockData) {
        // Refresh mock data
        _generateMockData();
      }

      final l10n = AppLocalizations.of(Get.context!);
      Get.snackbar(
        l10n.updated,
        l10n.chatsUpdatedSuccessfully,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      debugPrint('Error refreshing chats: $e');
      final l10n = AppLocalizations.of(Get.context!);
      Get.snackbar(
        l10n.error,
        l10n.updateChatsError,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      _isLoading.value = false;
    }
  }

  Future<ChatModel> createIndividualChat({
    required String otherUserId,
    required String otherUserName,
  }) async {
    // 1. Check local cache first to prevent duplicates
    final currentUserIdx = Get.find<AuthController>().userId;
    final existingChat = _chats.firstWhereOrNull((c) =>
        c.type == ChatType.individual &&
        c.participantIds.contains(otherUserId) &&
        c.participantIds.contains(currentUserIdx));

    if (existingChat != null) {
      debugPrint('Found existing individual chat: ${existingChat.id}');
      return existingChat;
    }

    if (AppConfig.useMockData) {
      final chat = ChatModel.individual(
        participant1Id: currentUserIdx,
        participant2Id: otherUserId,
        name: otherUserName,
      );
      _chats.insert(0, chat);
      _chatMessages[chat.id] = [];
      await _saveCachedData();
      final l10n = AppLocalizations.of(Get.context!);
      Get.snackbar(
        l10n.newChat,
        l10n.chatCreatedWithName(otherUserName),
        snackPosition: SnackPosition.BOTTOM,
      );
      return chat;
    }

    // 2. Create in Firestore
    final created = await Get.find<IChatRepository>().createChat(
      participantIds: [currentUserIdx, otherUserId],
      isGroup: false,
      groupName: null,
    );

    // 3. Map and cache
    final mapped = _mapChatFromData(created).copyWith(name: otherUserName);
    _chats.insert(0, mapped);
    _chatMessages[mapped.id] = [];
    _attachMessagesStream(mapped.id);
    _attachTypingStream(mapped.id);

    final l10n = AppLocalizations.of(Get.context!);
    Get.snackbar(
      l10n.newChat,
      l10n.chatCreatedWithName(otherUserName),
      snackPosition: SnackPosition.BOTTOM,
    );
    return mapped;
  }

  Future<ChatModel> createGroupChat({
    required String name,
    required List<String> participantIds,
    String? description,
  }) async {
    if (AppConfig.useMockData) {
      final chat = ChatModel.group(
        name: name,
        participantIds: participantIds,
        createdBy: Get.find<AuthController>().userId,
        description: description,
      );
      _chats.insert(0, chat);
      _chatMessages[chat.id] = [];
      await _saveCachedData();
      final l10n = AppLocalizations.of(Get.context!);
      Get.snackbar(
        l10n.newGroup,
        l10n.groupCreatedWithName(name),
        snackPosition: SnackPosition.BOTTOM,
      );
      return chat;
    }

    // Ensure the current user is included in participants and remove duplicates
    final me = Get.find<AuthController>().userId;
    final normalizedParticipants = <String>{...participantIds, me}.toList();

    final created = await Get.find<IChatRepository>().createChat(
      participantIds: normalizedParticipants,
      isGroup: true,
      groupName: name,
      groupPhotoUrl: null,
    );
    final mapped = _mapChatFromData(created);
    _chats.insert(0, mapped);
    _chatMessages[mapped.id] = [];
    _attachMessagesStream(mapped.id);
    _attachTypingStream(mapped.id);
    final l10n = AppLocalizations.of(Get.context!);
    Get.snackbar(
      l10n.newGroup,
      l10n.groupCreatedWithName(name),
      snackPosition: SnackPosition.BOTTOM,
    );
    return mapped;
  }

  Future<void> sendMessage({
    required String chatId,
    required String content,
    MessageType type = MessageType.text,
    String? replyToMessageId,
  }) async {
    if (_isInputLocked.value) {
      Get.snackbar('تنبيه سيادي', _lockReason.value);
      return;
    }
    if (AppConfig.useMockData) {
      final message = MessageModel(
        chatId: chatId,
        senderId: Get.find<AuthController>().userId,
        content: content,
        type: type,
        replyToMessageId: replyToMessageId,
      );
      if (_chatMessages[chatId] == null) {
        _chatMessages[chatId] = [];
      }
      _chatMessages[chatId]!.add(message);
      final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
      if (chatIndex != -1) {
        _chats[chatIndex] = _chats[chatIndex].copyWith(
          lastMessage: message,
          lastActivity: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final chat = _chats.removeAt(chatIndex);
        _chats.insert(0, chat);
      }
      await _saveCachedData();
      _simulateMessageStatusUpdates(message);
      return;
    }

    // Unified App Core Path
    final perf = PerformanceTracker.instance;
    await perf.startTrace('message_latency');

    final senderId = _getUserId();
    if (senderId == null) return;
    final localId = const Uuid().v4();
    final now = DateTime.now();

    final dataMsg = data_msg_models.Message(
      id: localId, // Optimistically use localId as id
      localId: localId,
      chatId: chatId,
      senderId: senderId,
      type: _mapMessageTypeToData(type),
      text: content,
      replyToMessageId: replyToMessageId,
      status: data_msg_models.MessageStatus.pending,
      createdAt: now,
    );

    try {
      // 1. Update status to online (Stage Z)
      if (senderId.isNotEmpty) {
        unawaited(Get.find<IUserRepository>()
            .updateStatus(
              senderId,
              user_models.UserStatus.online,
              lastSeen: now,
            )
            .catchError((_) {})); // No await needed, fire-and-forget
      }

      await _syncEngine.enqueueMessage(dataMsg);
      unawaited(AppAudioService.instance.play('message_send.mp3'));

      // Stop tracking latency (Stage Z)
      await perf.stopTrace('message_latency', attributes: {'chat_id': chatId});
      unawaited(AnalyticsService.instance
          .logEvent(name: 'message_sent', parameters: {'type': type.name}));

      // 3. Optimistic Chat List Update
      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      if (chatIndex != -1) {
        final uiMsg = _mapMessageFromData(dataMsg);
        _chats[chatIndex] = _chats[chatIndex].copyWith(
          lastMessage: uiMsg,
          lastActivity: now,
          updatedAt: now,
        );
        // Move to top if not already at top
        if (chatIndex > 0) {
          final chat = _chats.removeAt(chatIndex);
          _chats.insert(0, chat);
        }
      }

      // 4. Stop typing indicator
      unawaited(stopTyping(chatId));

      // 5. Success Moment Trigger (Activation)
      if (!_hasSentFirstMessage.value) {
        _hasSentFirstMessage.value = true;
        showFirstMessageSuccess.value = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_hasSentFirstMessageKey, true);
      }
    } catch (e) {
      debugPrint('sendMessage failed to enqueue: $e');
      Get.snackbar(
        'خطأ في الحفظ',
        'تعذر حفظ الرسالة محلياً',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // _sendMessageWithRetry removed in favor of ChatSyncEngine

  void _simulateMessageStatusUpdates(MessageModel message) {
    // Simulate sent status
    Future.delayed(const Duration(seconds: 1), () {
      _updateMessageStatus(message.id, MessageStatus.sent);
    });

    // Simulate delivered status
    Future.delayed(const Duration(seconds: 3), () {
      _updateMessageStatus(message.id, MessageStatus.delivered);
    });

    // Simulate read status (for demo purposes)
    Future.delayed(const Duration(seconds: 5), () {
      _updateMessageStatus(message.id, MessageStatus.read);
    });
  }

  void _updateMessageStatus(String messageId, MessageStatus status) {
    for (final chatId in _chatMessages.keys) {
      final messages = _chatMessages[chatId]!;
      final messageIndex = messages.indexWhere((m) => m.id == messageId);

      if (messageIndex != -1) {
        _chatMessages[chatId]![messageIndex] = messages[messageIndex].copyWith(
          status: status,
        );
        break;
      }
    }
  }

  // Mark all incoming (not mine) messages in a chat as delivered
  Future<void> markChatMessagesDelivered(String chatId) async {
    final uid = Get.find<AuthController>().userId;
    final list = _chatMessages[chatId] ?? const <MessageModel>[];
    for (final m in list) {
      if (m.senderId == uid) continue; // Only incoming messages
      if (m.status == MessageStatus.sent) {
        // Update locally first for instant UI feedback
        _updateMessageStatus(m.id, MessageStatus.delivered);
        if (!AppConfig.useMockData) {
          unawaited(_syncEngine.enqueueAction(SyncActionType.markDelivered,
              chatId: chatId, payload: {'messageId': m.id}));
        }
      }
    }
  }

  // Mark all incoming (not mine) messages in a chat as read
  Future<void> markChatMessagesRead(String chatId) async {
    if (AppConfig.useMockData) {
      final uid = Get.find<AuthController>().userId;
      final list = _chatMessages[chatId] ?? const <MessageModel>[];
      for (final m in list) {
        if (m.senderId == uid) continue;
        _updateMessageStatus(m.id, MessageStatus.read);
      }
      return;
    }

    try {
      // Use Sync Engine for durable ACK
      unawaited(
          _syncEngine.enqueueAction(SyncActionType.markRead, chatId: chatId));

      // Update local state for all relevant messages
      final uid = Get.find<AuthController>().userId;
      final list = _chatMessages[chatId] ?? const <MessageModel>[];
      for (final m in list) {
        if (m.senderId != uid && m.status != MessageStatus.read) {
          _updateMessageStatus(m.id, MessageStatus.read);
        }
      }
    } catch (e) {
      debugPrint('markChatMessagesRead failed for chat $chatId: $e');
    }
  }

  Future<void> deleteChat(String chatId) async {
    try {
      if (!AppConfig.useMockData) {
        final uid = Get.find<AuthController>().userId;
        await Get.find<IChatRepository>().removeUserFromChat(
          chatId: chatId,
          userId: uid,
        );
      }

      // Cancel messages subscription if any
      final sub = _messagesSubs.remove(chatId);
      await sub?.cancel();

      // Cancel typing subscription if any
      final typingSub = _typingSubs.remove(chatId);
      await typingSub?.cancel();

      // Remove from local state
      _chats.removeWhere((chat) => chat.id == chatId);
      _chatMessages.remove(chatId);
      _typingIndicators.remove(chatId);
      _typingTimers[chatId]?.cancel();
      _typingTimers.remove(chatId);

      await _saveCachedData();

      final l10n = AppLocalizations.of(Get.context!);
      Get.snackbar(
        l10n.deleted,
        l10n.chatDeleted,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint('deleteChat failed: $e');
      final l10n = AppLocalizations.of(Get.context!);
      Get.snackbar(
        l10n.error,
        'حدث خطأ غير متوقع',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> archiveChat(String chatId, bool archive) async {
    final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(isArchived: archive);
      await _saveCachedData();

      // Durable Sync
      unawaited(_syncEngine.enqueueAction(SyncActionType.updateMetadata,
          chatId: chatId, payload: {'isArchived': archive}));

      final l10n = AppLocalizations.of(Get.context!);
      Get.snackbar(
        archive ? l10n.archived : l10n.unarchived,
        archive ? l10n.chatArchived : l10n.chatUnarchived,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> muteChatUntil(String chatId, DateTime? until) async {
    final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      final isMuted = until != null;
      _chats[chatIndex] = _chats[chatIndex].copyWith(
        isMuted: isMuted,
        muteUntil: until,
      );
      await _saveCachedData();

      // Durable Sync
      unawaited(_syncEngine.enqueueAction(
        SyncActionType.updateMetadata,
        chatId: chatId,
        payload: {
          'isMuted': isMuted,
          'muteUntil': until?.toIso8601String(),
        },
      ));

      final l10n = AppLocalizations.of(Get.context!);
      if (isMuted) {
        String untilText = '';
        final diff = until.difference(DateTime.now());
        if (diff.inDays >= 3650) {
          untilText = l10n.indefinitely;
        } else if (diff.inHours >= 1) {
          untilText = l10n.hours(diff.inHours);
        } else {
          untilText = l10n.minutes(diff.inMinutes);
        }
        Get.snackbar(
          l10n.muted,
          '${l10n.chatMuted} ($untilText)',
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        Get.snackbar(
          l10n.unmuted,
          l10n.chatUnmuted,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  Future<void> pinChat(String chatId, bool pin) async {
    final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(isPinned: pin);

      // Durable Sync
      unawaited(_syncEngine.enqueueAction(SyncActionType.updateMetadata,
          chatId: chatId, payload: {'isPinned': pin}));

      // Sort chats: pinned chats first
      _chats.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.lastActivity?.compareTo(a.lastActivity ?? DateTime.now()) ?? 0;
      });

      await _saveCachedData();

      Get.snackbar(
        pin ? 'تم التثبيت' : 'تم إلغاء التثبيت',
        pin ? 'تم تثبيت المحادثة' : 'تم إلغاء تثبيت المحادثة',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> clearChatMessages(String chatId) async {
    _chatMessages[chatId] = [];

    // Update chat's last message
    final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(
        lastMessage: null,
        lastMessageId: null,
        unreadCount: 0,
      );
    }

    await _saveCachedData();

    final l10n = AppLocalizations.of(Get.context!);
    Get.snackbar(
      l10n.cleared,
      l10n.allChatMessagesCleared,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> deleteMessage(String chatId, String messageId) async {
    final messages = _chatMessages[chatId];
    if (messages == null) return;

    messages.removeWhere((m) => m.id == messageId);

    // Update chat's last message if needed
    final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      final last = messages.isNotEmpty ? messages.last : null;
      _chats[chatIndex] = _chats[chatIndex].copyWith(
        lastMessage: last,
        lastMessageId: last?.id,
      );
    }

    await _saveCachedData();

    final l10n = AppLocalizations.of(Get.context!);
    Get.snackbar(
      l10n.deleted,
      l10n.messageDeleted,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  int get totalUnreadCount {
    return _chats.fold(0, (sum, chat) => sum + chat.unreadCount);
  }

  List<ChatModel> get pinnedChats {
    return _chats.where((chat) => chat.isPinned).toList();
  }

  List<ChatModel> get archivedChats {
    return _chats.where((chat) => chat.isArchived).toList();
  }

  List<ChatModel> get activeChats {
    return _chats.where((chat) => !chat.isArchived).toList();
  }

  Future<void> forwardMessage(
      MessageModel message, List<String> chatIds) async {
    // Basic implementation for UI compatibility
    for (final chatId in chatIds) {
      await sendMessage(
        chatId: chatId,
        content: message.content,
        type: message.type,
      );
    }
  }

  Future<void> fetchMessageStates(List<String> messageIds) async {
    if (AppConfig.useMockData || messageIds.isEmpty) return;
    try {
      final deviceId = await DeviceIdentity.getId();
      final res = await Supabase.instance.client
          .from('message_delivery')
          .select('message_id, status')
          .filter('message_id', 'in', messageIds)
          .eq('device_id', deviceId);

      for (final r in res) {
        final msgId = r['message_id'] as String;
        final status = r['status'] as String;
        _messageStates[msgId] = _mapMessageState(status);
      }
    } catch (e) {
      debugPrint('fetchMessageStates failed: $e');
    }
  }

  Future<void> subscribeMessageState() async {
    if (AppConfig.useMockData) return;
    try {
      final deviceId = await DeviceIdentity.getId();

      await _statesChannel?.unsubscribe();

      _statesChannel = Supabase.instance.client
          .channel('ui-state:$deviceId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'message_delivery',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'device_id',
              value: deviceId,
            ),
            callback: (payload) {
              final msgId = payload.newRecord['message_id'] as String;
              final status = payload.newRecord['status'] as String;
              _messageStates[msgId] = _mapMessageState(status);
            },
          );

      _statesChannel?.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.channelError) {
          debugPrint('ChatController: message state channel error: $error');
        }
      });
      debugPrint('Subscribed to message state updates for device: $deviceId');
    } catch (e) {
      debugPrint('subscribeMessageState failed: $e');
    }
  }

  Future<void> retryMessage(String localId) async {
    await _syncEngine.retryMessage(localId);
  }

  @override
  void onClose() {
    _detachRealtime();
    _statesChannel?.unsubscribe();
    _authWorker?.dispose();
    _uidWorker?.dispose();
    WidgetsBinding.instance.removeObserver(this);

    // Close repositories to clean up sinks (Stage C4)
    unawaited(_chatRepo.close());
    unawaited(_messageRepo.close());
    unawaited(_localRepo.close());
    unawaited(_typingRepo.close());

    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInForeground.value = state == AppLifecycleState.resumed;
    super.didChangeAppLifecycleState(state);
  }
}
