import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../config/app_config.dart';

/// [Carrier-Grade]: Area 1 - TURN Credential Lifecycle Management
class TurnCredentialManager {
  static final TurnCredentialManager instance =
      TurnCredentialManager._internal();
  TurnCredentialManager._internal();

  DateTime? _expiryTime;
  List<Map<String, dynamic>>? _currentIceServers;

  // Threshold to trigger refresh (80% of TTL elapsed)
  static const double refreshThreshold = 0.8;

  /// Fetches logic-wrapped TURN configuration.
  /// In a production environment, this would call an API (Xirsys, Twilio, etc.)
  Future<List<Map<String, dynamic>>> getConfiguration() async {
    if (_currentIceServers == null || needsRefresh()) {
      debugPrint(
          '🧊 [Carrier-Grade] Area 1: Fetching fresh TURN credentials...');

      // Simulate API call with a 1-hour TTL for this implementation
      final now = DateTime.now();
      _expiryTime = now.add(const Duration(hours: 1));

      // In production, we'd fetch from a secure endpoint.
      // For now, we use the AppConfig base but could extend with ephemeral credentials.
      _currentIceServers =
          List<Map<String, dynamic>>.from(AppConfig.iceServers);

      debugPrint(
          '✅ [Carrier-Grade] TURN Credentials cached. Expiry: $_expiryTime');
    }
    return _currentIceServers!;
  }

  /// Determines if the credentials are close to expiration
  bool needsRefresh() {
    if (_expiryTime == null) return true;

    final now = DateTime.now();
    final remaining = _expiryTime!.difference(now);
    final total = const Duration(hours: 1); // Expected TTL

    // Refresh if less than 20% remains (80% used)
    return remaining.inSeconds < (total.inSeconds * (1 - refreshThreshold));
  }

  /// Forces a clear to trigger immediate refresh on next get
  void forceReset() {
    _expiryTime = null;
    _currentIceServers = null;
  }
}
