import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/utils/circuit_breaker.dart';

class ComplianceRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static final _supabaseBreaker = CircuitBreaker(
    serviceName: 'ComplianceSupabase',
    failureThreshold: 3,
    resetTimeout: const Duration(seconds: 45),
  );

  // Fetch rejected logs matching compliance reasons
  Future<Map<String, int>> getRejectionStats() async {
    return _supabaseBreaker.execute(() async {
      try {
        final response = await _client
            .from('routing_logs')
            .select('reason')
            .inFilter('reason', [
              'CONSENT_MISSING',
              'DND_ACTIVE',
              'FLAG_DISABLED',
              'KILL_SWITCH_ACTIVE',
              'policy_skipped'
            ])
            .order('created_at', ascending: false)
            .limit(500);

        final List<dynamic> data = response as List<dynamic>;

        final stats = <String, int>{
          'CONSENT_MISSING': 0,
          'DND_ACTIVE': 0,
          'FLAG_DISABLED': 0,
          'OTHER': 0,
        };

        for (var log in data) {
          final logMap = log as Map<String, dynamic>;
          final reason = logMap['reason'] as String?;
          if (stats.containsKey(reason)) {
            stats[reason!] = (stats[reason] ?? 0) + 1;
          } else {
            stats['OTHER'] = (stats['OTHER'] ?? 0) + 1;
          }
        }
        return stats;
      } catch (_) {
        return {};
      }
    });
  }

  // Fetch User Consent Status counts
  Future<Map<String, bool>> getMyConsents() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return {};

      final response = await _client
          .from('user_consent')
          .select('notification_type, consent_status')
          .eq('user_id', userId);

      final Map<String, bool> map = {};
      for (var item in (response as List)) {
        final itemMap = item as Map<String, dynamic>;
        map[itemMap['notification_type'].toString()] =
            itemMap['consent_status'] as bool;
      }
      return map;
    } catch (e) {
      return {};
    }
  }

  // Get Last Purge Info
  Future<Map<String, dynamic>?> getLastPurgeLog() async {
    try {
      final response = await _client
          .from('routing_logs')
          .select('created_at, meta')
          .eq('decision', 'system')
          .eq('reason', 'DATA_PURGE')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      return null;
    }
  }
}
