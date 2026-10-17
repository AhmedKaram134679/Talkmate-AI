import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  /// Calls the Supabase Edge Function 'get-turn-credentials' with fallback to base STUN servers.
  Future<List<Map<String, dynamic>>> getConfiguration() async {
    if (_currentIceServers == null || needsRefresh()) {
      debugPrint(
          '🧊 [Carrier-Grade] Area 1: Fetching fresh TURN credentials...');

      try {
        final client = Supabase.instance.client;
        final session = client.auth.currentSession;
        
        // Attempt to fetch ephemeral credentials from Supabase Edge Function
        final response = await client.functions.invoke(
          'get-turn-credentials',
          headers: session != null
              ? {'Authorization': 'Bearer ${session.accessToken}'}
              : null,
        ).timeout(const Duration(seconds: 8));

        if (response.status == 200 && response.data != null) {
          final data = response.data;
          List<dynamic>? serversList;
          if (data is Map && data['iceServers'] is List) {
            serversList = data['iceServers'] as List;
          } else if (data is List) {
            serversList = data;
          }

          if (serversList != null && serversList.isNotEmpty) {
            _currentIceServers = serversList
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();

            final ttlSeconds = (data is Map && data['ttl'] is int)
                ? data['ttl'] as int
                : 3600; // 1-hour default TTL

            _expiryTime = DateTime.now().add(Duration(seconds: ttlSeconds));
            debugPrint(
                '✅ [Carrier-Grade] Production TURN Credentials acquired (${_currentIceServers!.length} servers). Expiry: $_expiryTime');
            return _currentIceServers!;
          }
        }
      } catch (e) {
        debugPrint('⚠️ [TurnCredentialManager] Edge Function fetch failed or unconfigured ($e). Falling back to AppConfig.');
      }

      // Fallback: AppConfig default STUN / configured ICE servers
      final now = DateTime.now();
      _expiryTime = now.add(const Duration(hours: 1));
      _currentIceServers =
          List<Map<String, dynamic>>.from(AppConfig.iceServers);

      debugPrint(
          '✅ [Carrier-Grade] Fallback TURN/STUN Credentials cached. Expiry: $_expiryTime');
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
