import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/core/app_brain/app_brain.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/models/sync_action_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_local_message_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_message_repository.dart';
import 'package:talkmate_ai/services/observability/analytics_service.dart';
import 'package:talkmate_ai/services/observability/app_observability.dart';
import 'package:talkmate_ai/services/observability/performance_tracker.dart';
import 'package:uuid/uuid.dart';

class ChatSyncEngine extends GetxService {
  final ILocalMessageRepository _localRepo =
      Get.find<ILocalMessageRepository>();
  final IMessageRepository _remoteRepo = Get.find<IMessageRepository>();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _connectivitySub;

  bool _isProcessing = false;
  bool _isRecovering = false;
  int _retryCount = 0;
  static const int _maxRetries = 5;

  @override
  void onInit() {
    super.onInit();
    _connectivitySub =
        _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
    _initialSync();
  }

  @override
  void onClose() {
    _connectivitySub?.cancel();
    super.onClose();
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    if (results.any((r) => r != ConnectivityResult.none)) {
      AppLogger.d('ChatSyncEngine: Internet restored, triggering sync...');
      PerformanceTracker.instance.startTrace('offline_recovery');
      _isRecovering = true;
      _retryCount = 0;
      unawaited(syncPendingMessages());
      unawaited(syncPendingActions());
    }
  }

  Future<void> _initialSync() async {
    // Wait a bit for other services to initialize
    await Future.delayed(const Duration(seconds: 2));
    unawaited(syncPendingMessages());
    unawaited(syncPendingActions());
  }

  /// Entry point for UI to push a message into the sync engine
  Future<void> enqueueMessage(Message message) async {
    if (message.localId != null) {
      AppObservability.instance.trackMessageEnqueued(message.localId!);
    }
    await _localRepo
        .saveMessage(message.copyWith(status: MessageStatus.pending));
    unawaited(syncPendingMessages());
  }

  /// Entry point for UI to push a non-message action into the sync engine
  Future<void> enqueueAction(SyncActionType type,
      {String? chatId, Map<String, dynamic>? payload}) async {
    // Deduplication logic for read/delivered actions
    if (type == SyncActionType.markRead && chatId != null) {
      final pending = await _localRepo.getPendingSyncActions();
      final duplicate = pending
          .any((a) => a.type == SyncActionType.markRead && a.chatId == chatId);
      if (duplicate) return;
    }

    if (type == SyncActionType.markDelivered && chatId != null) {
      final messageId = payload?['messageId'] as String?;
      if (messageId != null) {
        final pending = await _localRepo.getPendingSyncActions();
        final duplicate = pending.any((a) =>
            a.type == SyncActionType.markDelivered &&
            a.chatId == chatId &&
            a.payload['messageId'] == messageId);
        if (duplicate) return;
      }
    }

    final action = SyncAction(
      id: const Uuid().v4(),
      type: type,
      chatId: chatId,
      payload: payload ?? {},
      createdAt: DateTime.now(),
    );
    await _localRepo.saveSyncAction(action);
    unawaited(syncPendingActions());
  }

  Future<void> syncPendingMessages() async {
    if (_isProcessing) return;

    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      AppLogger.d('ChatSyncEngine: No internet, sync deferred.');
      return;
    }

    _isProcessing = true;
    try {
      final pending = await _localRepo.getPendingMessages();
      if (pending.isEmpty) {
        _isProcessing = false;
        return;
      }

      AppLogger.d(
          'ChatSyncEngine: Processing ${pending.length} pending messages...');

      for (final msg in pending) {
        await _processMessage(msg);
      }
    } catch (e) {
      AppLogger.e('ChatSyncEngine: Error during sync', e);
    } finally {
      _isProcessing = false;
      unawaited(_checkRecoveryComplete());
    }
  }

  /// Manually trigger a retry for a failed message
  Future<void> retryMessage(String localId) async {
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      AppLogger.d('ChatSyncEngine: Manual retry failed - no internet.');
      return;
    }

    try {
      // Actually, better to add a getMessageByLocalId in repository, but for now:
      final pending = await _localRepo.getPendingMessages();
      final msg = pending.firstWhereOrNull((m) => m.localId == localId);

      if (msg != null) {
        // Reset status to pending before retrying to ensure it's picked up
        await _localRepo.updateMessageStatus(localId, MessageStatus.pending);
        await _processMessage(msg);
      }
    } catch (e) {
      AppLogger.e('ChatSyncEngine: Manual retry failed for $localId', e);
    }
  }

  Future<void> syncPendingActions() async {
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    try {
      final actions = await _localRepo.getPendingSyncActions();
      if (actions.isEmpty) {
        unawaited(_checkRecoveryComplete());
        return;
      }

      AppLogger.d(
          'ChatSyncEngine: Processing ${actions.length} pending sync actions...');

      for (final action in actions) {
        await _processAction(action);
      }
      unawaited(_checkRecoveryComplete());
    } catch (e) {
      AppLogger.e('ChatSyncEngine: Error during sync actions', e);
    }
  }

  Future<void> _checkRecoveryComplete() async {
    if (!_isRecovering || _isProcessing) return;

    final pendingMsg = await _localRepo.getPendingMessages();
    final pendingActions = await _localRepo.getPendingSyncActions();

    if (pendingMsg.isEmpty && pendingActions.isEmpty) {
      _isRecovering = false;
      await PerformanceTracker.instance.stopTrace('offline_recovery');
      unawaited(AnalyticsService.instance
          .logEvent(name: 'offline_recovery_completed'));
    }
  }

  Future<void> _processAction(SyncAction action) async {
    try {
      switch (action.type) {
        case SyncActionType.markRead:
          if (action.chatId != null) {
            await _remoteRepo.markChatAsRead(action.chatId!);
          }
          break;
        case SyncActionType.markDelivered:
          final messageId = action.payload['messageId'] as String?;
          if (action.chatId != null && messageId != null) {
            await _remoteRepo.updateStatus(
              action.chatId!,
              messageId,
              MessageStatus.delivered,
            );
          }
          break;
        case SyncActionType.updateMetadata:
          if (action.chatId != null) {
            final userId = Get.find<AuthController>().userId;
            await Get.find<IChatRepository>().updateParticipantSettings(
              chatId: action.chatId!,
              userId: userId,
              isPinned: action.payload['isPinned'] as bool?,
              isMuted: action.payload['isMuted'] as bool?,
              isArchived: action.payload['isArchived'] as bool?,
            );
          }
          break;
      }

      // Success -> Delete action
      unawaited(_localRepo.deleteSyncAction(action.id));
    } catch (e) {
      AppLogger.e(
          'ChatSyncEngine: Failed to process sync action ${action.id}', e);
      // No explicit retry logic for actions yet, they will wait for next sync trigger
    }
  }

  Future<void> _processMessage(Message msg) async {
    try {
      // 1. Send to remote repo
      final sentMsg = await _remoteRepo.sendMessage(
        chatId: msg.chatId,
        senderId: msg.senderId,
        type: msg.type,
        text: msg.text,
        mediaUrl: msg.mediaUrl,
        thumbnailUrl: msg.thumbnailUrl,
        mediaSize: msg.mediaSize,
        replyToMessageId: msg.replyToMessageId,
        localId: msg.localId,
        createdAt: msg.createdAt,
      );

      // 2. Update local status to SENT
      await _localRepo.updateMessageStatus(msg.localId!, MessageStatus.sent,
          serverId: sentMsg.id);

      AppObservability.instance.trackMessageSent(msg.localId!, sentMsg.id);

      AppLogger.d(
          'ChatSyncEngine: Message ${msg.localId} synced successfully.');
      _retryCount = 0;
    } catch (e) {
      AppLogger.e('ChatSyncEngine: Failed to sync message ${msg.localId}', e);

      // Implement exponential backoff / retry limit
      if (_retryCount < _maxRetries) {
        _retryCount++;
        // 2, 4, 8, 16, 32 seconds
        final delaySeconds = (2 << (_retryCount - 1));
        final delay = Duration(seconds: delaySeconds);

        debugPrint(
            'ChatSyncEngine: Retrying in $delaySeconds seconds (attempt $_retryCount)');
        unawaited(Future.delayed(delay, () => syncPendingMessages()));
      } else {
        debugPrint(
            'ChatSyncEngine: Max retries reached for message ${msg.localId}. Marking as failed.');
        await _localRepo.updateMessageStatus(
            msg.localId!, MessageStatus.failed);

        // Stage C4: Trigger Brain Emergency only if it's a critical pattern
        Get.find<AppBrain>().enterEmergencyMode('Persistent sync failure');
      }
      rethrow;
    }
  }
}
