import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';

/// Sovereign Presence Engine (Stage C7).
/// Manages the real-time presence state of the current user based on device activity.
class SovereignPresenceEngine extends GetxService {
  static SovereignPresenceEngine get instance =>
      Get.find<SovereignPresenceEngine>();

  final _auth = Get.find<AuthController>();
  final _commEngine = SovereignCommunicationEngine.instance;
  final _userRepo = Get.find<IUserRepository>();

  final Rx<UserStatus> _currentStatus = UserStatus.offline.obs;
  UserStatus get currentStatus => _currentStatus.value;

  StreamSubscription? _commStatusSub;
  Timer? _heartbeatTimer;

  @override
  void onInit() {
    super.onInit();
    _startMonitoring();
  }

  @override
  void onClose() {
    _commStatusSub?.cancel();
    _heartbeatTimer?.cancel();
    super.onClose();
  }

  void _startMonitoring() {
    // 1. Initial State Sync
    _updateLocalStatus();

    // 2. Monitor Sovereign Communication Engine
    _commStatusSub = _commEngine.statusRx.listen((status) {
      _handleCommStatusChange(status);
    });

    // 3. Force INITIAL SYNC to clear stale states (e.g. Busy after crash)
    if (_auth.isLoggedIn) {
      unawaited(_updatePresence(UserStatus.online, force: true));
    }

    // 4. Periodic Heartbeat (Recovery mechanism)
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_auth.isLoggedIn) {
        debugPrint('🛡️ PresenceEngine: [HEARTBEAT] Re-syncing status...');
        _updatePresence(_currentStatus.value, force: true);
      }
    });
  }

  void _handleCommStatusChange(CommSessionStatus status) {
    UserStatus newStatus = UserStatus.online;

    switch (status) {
      case CommSessionStatus.activeAudio:
      case CommSessionStatus.activeVideo:
      case CommSessionStatus.connecting:
      case CommSessionStatus.dialing:
      case CommSessionStatus.ringingOutgoing:
      case CommSessionStatus.ringingIncoming:
      case CommSessionStatus.reconnecting:
        newStatus = UserStatus.busy;
        break;
      case CommSessionStatus.idle:
      case CommSessionStatus.ended:
      case CommSessionStatus.failed:
        newStatus = UserStatus.online;
        break;
    }

    _updatePresence(newStatus);
  }

  Future<void> _updatePresence(UserStatus status, {bool force = false}) async {
    if (!force && _currentStatus.value == status) {
      // debugPrint('🛡️ PresenceEngine: Update skipped (Status $status already set)');
      return;
    }

    final userId = _auth.userId;
    if (userId.isEmpty) return;

    _currentStatus.value = status;

    try {
      debugPrint(
          '🛡️ PresenceEngine: SYNCING state [$status] to repository...');
      await _userRepo.updateStatus(
        userId,
        status,
        lastSeen: DateTime.now(),
      );
    } catch (e) {
      debugPrint(
          '🚨 PresenceEngine: Persistent failure updating status (Retry exhausted): $e');
    }
  }

  void _updateLocalStatus() {
    if (_auth.isLoggedIn) {
      _currentStatus.value = UserStatus.online;
    } else {
      _currentStatus.value = UserStatus.offline;
    }
  }

  /// External trigger for custom states (if needed, within governance)
  Future<void> forceStatusUpdate(UserStatus status) async {
    await _updatePresence(status, force: true);
  }
}
