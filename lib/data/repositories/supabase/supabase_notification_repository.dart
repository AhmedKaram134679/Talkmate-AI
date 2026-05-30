import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/ai_exclusion_model.dart';
import 'package:talkmate_ai/data/models/ai_policy_model.dart';
import 'package:talkmate_ai/data/models/ai_stability_model.dart';
import 'package:talkmate_ai/data/models/notification_ai_settings_model.dart';
import 'package:talkmate_ai/data/models/notification_experience_model.dart';
import 'package:talkmate_ai/data/models/notification_model.dart';
import 'package:talkmate_ai/data/models/notification_preference_model.dart';
import 'package:talkmate_ai/data/models/user_context_model.dart';
import 'package:talkmate_ai/data/models/user_learning_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_notification_repository.dart';

class SupabaseNotificationRepository implements INotificationRepository {
  SupabaseNotificationRepository();

  final _client = Supabase.instance.client;

  @override
  Future<void> sendNotification({
    required String toUserId,
    required String type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    DateTime? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now();
    await _client.from('notifications').insert({
      'user_id': toUserId,
      'type': type,
      'title': title,
      'body': body,
      'data': data,
      'read': false,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  @override
  Stream<List<AppNotification>> watchUserNotifications(String userId,
      {int limit = 50}) {
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((list) => list
            .map(
                (json) => AppNotification.fromJson(json, json['id'].toString()))
            .toList());
  }

  @override
  Future<void> markAsRead(String userId, String notificationId) async {
    await _client
        .from('notifications')
        .update({'read': true, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', notificationId)
        .eq('user_id', userId);
  }

  @override
  Future<NotificationPreference> getPreferences(String userId) async {
    final res = await _client
        .from('notification_preferences')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (res == null) {
      return NotificationPreference(id: '', userId: userId);
    }
    return NotificationPreference.fromJson(res);
  }

  @override
  Future<void> updatePreferences(
      String userId, NotificationPreference prefs) async {
    final data = prefs.toJson();
    await _client
        .from('notification_preferences')
        .update(data)
        .eq('user_id', userId);
  }

  @override
  Future<NotificationAiSettings> getAiSettings(String userId) async {
    final res = await _client
        .from('notification_ai_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (res == null) {
      return NotificationAiSettings(id: '', userId: userId);
    }
    return NotificationAiSettings.fromJson(res);
  }

  @override
  Future<void> updateAiSettings(
      String userId, NotificationAiSettings settings) async {
    await _client
        .from('notification_ai_settings')
        .update(settings.toJson())
        .eq('user_id', userId);
  }

  @override
  Future<Map<String, dynamic>> getAiEfficiencyStats(String userId) async {
    final res = await _client
        .from('routing_logs')
        .select('decision, reason')
        .eq('recipient_id', userId)
        .limit(100);

    int aiSilenced = 0;
    final int total = res.length;

    for (var log in res) {
      if (log['reason']?.toString().startsWith('AI_') ?? false) {
        aiSilenced++;
      }
    }

    return {
      'total_processed': total,
      'ai_silenced': aiSilenced,
      'efficiency_rate': total > 0 ? (aiSilenced / total) : 0.0,
    };
  }

  // --- GOVERNANCE & TRUST (Stage D) ---

  @override
  Future<List<AiExclusion>> getAiExclusions(String userId) async {
    final res = await _client
        .from('notification_ai_exclusions')
        .select()
        .eq('user_id', userId);
    return (res as List).map((json) => AiExclusion.fromJson(json)).toList();
  }

  @override
  Future<void> addAiExclusion(AiExclusion exclusion) async {
    await _client.from('notification_ai_exclusions').insert(exclusion.toJson());
  }

  @override
  Future<void> removeAiExclusion(String userId, String chatId) async {
    await _client
        .from('notification_ai_exclusions')
        .delete()
        .eq('user_id', userId)
        .eq('chat_id', chatId);
  }

  @override
  Future<void> toggleSafeMode(String userId, bool enabled) async {
    await _client
        .from('notification_ai_settings')
        .update({'is_safe_mode': enabled}).eq('user_id', userId);
  }

  @override
  Future<void> pauseAi(String userId, Duration duration) async {
    final pausedUntil = DateTime.now().add(duration).toIso8601String();
    await _client
        .from('notification_ai_settings')
        .update({'paused_until': pausedUntil}).eq('user_id', userId);
  }

  @override
  Future<UserContextSettings> getContextSettings(String userId) async {
    final response = await _client
        .from('user_context_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) throw Exception('No context settings found');
    return UserContextSettings.fromJson(response);
  }

  @override
  Future<void> updateContextSettings(UserContextSettings settings) async {
    await _client.from('user_context_settings').upsert(settings.toJson());
  }

  @override
  Future<UserContextProfile> getContextProfile(String userId) async {
    final response = await _client
        .from('user_context_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) throw Exception('No context profile found');
    return UserContextProfile.fromJson(response);
  }

  @override
  Future<LearningWeights> getLearningWeights(String userId) async {
    final response = await _client
        .from('ai_learning_weights')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) throw Exception('No learning weights found');
    return LearningWeights.fromJson(response);
  }

  @override
  Future<void> submitFeedback(UserFeedback feedback) async {
    await _client.from('user_feedback_logs').insert(feedback.toJson());
  }

  // --- STAGE G: GOVERNANCE & STABILITY ---

  @override
  Future<List<LearningWeightSnapshot>> getWeightSnapshots(String userId) async {
    final response = await _client
        .from('ai_weight_snapshots')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((e) => LearningWeightSnapshot.fromJson(e))
        .toList();
  }

  @override
  Future<String> createWeightSnapshot(String userId, String tag) async {
    final response = await _client.rpc('create_ai_weight_snapshot', params: {
      'p_user_id': userId,
      'p_tag': tag,
    });
    return response as String;
  }

  @override
  Future<void> rollbackToSnapshot(String userId, String snapshotId) async {
    // 1. Update the current version in settings
    await _client.from('notification_ai_settings').update({
      'weight_version_id': snapshotId,
      'stability_score': 1.0,
    }).eq('user_id', userId);

    // 2. Log the rollback in governance audit
    await _client.from('ai_governance_audit').insert({
      'user_id': userId,
      'action_type': 'manual_rollback',
      'details': {'snapshot_id': snapshotId},
      'severity': 'warning',
    });
  }

  @override
  Future<List<GovernanceAudit>> getGovernanceAudit(String userId) async {
    final response = await _client
        .from('ai_governance_audit')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List).map((e) => GovernanceAudit.fromJson(e)).toList();
  }

  // --- STAGE H: POLICY & IDENTITY ---

  @override
  Future<List<AiScope>> getScopes(String userId) async {
    // We assume RLS handles the filtering based on auth.uid()
    // or we can explicitly join user_roles if we moved to rpc.
    // For now, simple query on ai_scopes is enough due to RLS "visible to members".
    final res = await _client.from('ai_scopes').select();
    return (res as List).map((e) => AiScope.fromJson(e)).toList();
  }

  @override
  Future<List<AiPolicy>> getPolicies(String userId, String scopeId) async {
    final res = await _client
        .from('ai_policies')
        .select()
        .eq('scope_id', scopeId)
        .eq('is_active', true)
        .order('priority', ascending: false);
    return (res as List).map((e) => AiPolicy.fromJson(e)).toList();
  }

  @override
  Future<void> logNotificationEvent({
    required String messageId,
    required String eventType,
    String? platform,
    Map<String, dynamic>? metadata,
  }) async {
    await _client.rpc('fn_log_notification_event', params: {
      'p_message_id': messageId,
      'p_event_type': eventType,
      'p_platform': platform,
      'p_metadata': metadata ?? {},
    });
  }

  @override
  Future<NotificationExperiencePrefs> getExperiencePrefs(String userId) async {
    final res = await _client
        .from('user_notification_experience_prefs')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (res == null) {
      return NotificationExperiencePrefs(userId: userId);
    }
    return NotificationExperiencePrefs.fromJson(res);
  }

  @override
  Future<void> updateExperiencePrefs(NotificationExperiencePrefs prefs) async {
    await _client
        .from('user_notification_experience_prefs')
        .upsert(prefs.toJson()..addAll({'user_id': prefs.userId}))
        .eq('user_id', prefs.userId);
  }

  @override
  Future<void> reportInteractionSignal({
    required String userId,
    required String signalType,
    String? messageId,
    Map<String, dynamic>? metadata,
  }) async {
    await _client.from('notification_interaction_signals').insert({
      'user_id': userId,
      'signal_type': signalType,
      'message_id': messageId,
      'metadata': metadata ?? {},
    });
  }
}
