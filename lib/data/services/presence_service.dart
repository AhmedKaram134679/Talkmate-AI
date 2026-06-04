import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/utils/device_identity.dart';

/// PresenceService: Keeps user's presence up-to-date in Supabase
/// - Sets status=online when app is resumed and user is logged in
/// - Sets status=offline and updates lastSeen when app goes to background/paused/detached
/// - Reacts to auth state changes
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  IUserRepository get _repo => Get.find<IUserRepository>();
  StreamSubscription<bool>? _authSub;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);

    // Attach to auth changes
    try {
      final auth = Get.find<AuthController>();
      _authSub = auth.isLoggedInRx.listen((loggedIn) async {
        if (loggedIn) {
          await _setOnline();
        } else {
          await _setOffline();
        }
      });

      // Set initial status if already logged in
      if (auth.isLoggedIn) {
        _setOnline();
      }
    } catch (_) {}
  }

  Future<void> _setOnline() async {
    try {
      final auth = Get.find<AuthController>();
      final uid = auth.userId;
      if (uid.isEmpty) return;

      // Legacy updates (optional, keeping for safety)
      // await _repo.updateStatus(uid, UserStatus.online);

      // New: Per-device presence
      final deviceId = await DeviceIdentity.getId();
      await _repo.updateDevicePresence(uid, deviceId,
          isOnline: true, appState: 'resumed');
    } catch (_) {}
  }

  Future<void> _setOffline() async {
    try {
      final auth = Get.find<AuthController>();
      final uid = auth.userId;
      if (uid.isEmpty) return;

      // Legacy updates
      // await _repo.updateStatus(uid, UserStatus.offline, lastSeen: DateTime.now());

      // New: Per-device presence
      final deviceId = await DeviceIdentity.getId();
      await _repo.updateDevicePresence(uid, deviceId,
          isOnline: false, appState: 'paused' // or detached/hidden
          );
    } catch (_) {}
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    final deviceId = await DeviceIdentity.getId();
    final auth = Get.find<AuthController>();
    final uid = auth.userId;
    if (uid.isEmpty) return;

    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_setOnline()); // Handles both legacy and new
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Explicit app state update
        await _repo.updateDevicePresence(uid, deviceId,
            isOnline: false, appState: state.name);
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _authSub = null;
    _initialized = false;
  }
}
