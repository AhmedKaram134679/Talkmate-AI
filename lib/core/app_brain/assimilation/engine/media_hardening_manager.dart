import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import '../models/secure_media_models.dart';

/// Media Session Hardening Manager (G4).
/// Ensures that media sessions are bound to active user identity and valid JWT.
class MediaSessionHardeningManager extends GetxService {
  final _secureState = MediaSecureState.initializing.obs;
  Timer? _jwtWatchdog;
  String? _currentSessionId;
  DateTime? _lastRequestTime;

  MediaSecureState get currentState => _secureState.value;
  String? get currentSessionId => _currentSessionId;

  /// Binds a session to the current user and starts the security watchdog.
  Future<bool> secureSession(String sessionId) async {
    // Stage G4-Secure: Rate Limiting (Attack Surface Reduction)
    final now = DateTime.now();
    if (_lastRequestTime != null &&
        now.difference(_lastRequestTime!).inSeconds < 1) {
      debugPrint('🛑 MediaHardening: Rate limit triggered for $sessionId');
      return false;
    }
    _lastRequestTime = now;

    _currentSessionId = sessionId;
    _secureState.value = MediaSecureState.authenticating;

    final auth = Get.find<AuthController>();
    if (!auth.isLoggedIn) {
      _terminateSovereignly('Unauthorized Access: No user logged in.');
      return false;
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || session.isExpired) {
      _terminateSovereignly('Security Violation: JWT Expired or Missing.');
      return false;
    }

    _secureState.value = MediaSecureState.active;
    _startJwtWatchdog();
    debugPrint(
        '🔒 MediaHardening: Session $sessionId is now SECURED and BOUND to ${auth.userId}');
    return true;
  }

  void _startJwtWatchdog() {
    _jwtWatchdog?.cancel();
    _jwtWatchdog = Timer.periodic(const Duration(seconds: 10), (timer) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null || session.isExpired) {
        _terminateSovereignly(
            'JWT Watchdog: Token Expired during active session.');
      }
    });
  }

  void _terminateSovereignly(String reason) {
    debugPrint('🛑 MediaHardening TERMINATION: $reason');
    _secureState.value = MediaSecureState.terminated;
    _jwtWatchdog?.cancel();

    // Broadcast emergency kill signal inside the client
    // Note: This relies on the client listening to the state or being explicitly called.
  }

  /// Releases security locks for a session.
  void releaseSession() {
    _jwtWatchdog?.cancel();
    _secureState.value = MediaSecureState.terminated;
    _currentSessionId = null;
    debugPrint('🔒 MediaHardening: Security locks released.');
  }

  @override
  void onClose() {
    _jwtWatchdog?.cancel();
    super.onClose();
  }
}
