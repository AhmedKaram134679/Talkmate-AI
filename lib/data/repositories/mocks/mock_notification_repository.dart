import 'dart:async';

import 'package:flutter/material.dart';
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

class MockNotificationRepository implements INotificationRepository {
  MockNotificationRepository._();
  static final MockNotificationRepository instance =
      MockNotificationRepository._();

  final Map<String, List<AppNotification>> _byUser = {}; // userId -> list
  final Map<String, StreamController<List<AppNotification>>> _ctrls =
      {}; // userId -> ctrl

  final Map<String, UserContextSettings> _contextSettings = {};
  final Map<String, UserContextProfile> _contextProfiles = {};
  final Map<String, LearningWeights> _learningWeights = {};
  final Map<String, List<LearningWeightSnapshot>> _snapshots = {};
  final Map<String, List<GovernanceAudit>> _audits = {};

  StreamController<List<AppNotification>> _ctrl(String uid) =>
      _ctrls.putIfAbsent(
          uid, () => StreamController<List<AppNotification>>.broadcast());

  void _emit(String uid) {
    final list = List<AppNotification>.from(_byUser[uid] ?? const []);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _ctrl(uid).add(list);
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  Future<void> sendNotification({
    required String toUserId,
    required String type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    DateTime? createdAt,
  }) async {
    final t = _typeFromString(type);
    final n = AppNotification(
      id: _genId(),
      userId: toUserId,
      type: t,
      title: title ?? '',
      body: body ?? '',
      data: data,
      read: false,
      createdAt: createdAt ?? DateTime.now(),
    );
    final list = _byUser.putIfAbsent(toUserId, () => <AppNotification>[]);
    list.add(n);
    _emit(toUserId);
  }

  @override
  Stream<List<AppNotification>> watchUserNotifications(String userId,
      {int limit = 50}) {
    Future.microtask(() => _emit(userId));
    return _ctrl(userId).stream;
  }

  @override
  Future<void> markAsRead(String userId, String notificationId) async {
    final list = _byUser[userId];
    if (list == null) return;
    final idx = list.indexWhere((n) => n.id == notificationId);
    if (idx == -1) return;
    list[idx] = list[idx].markRead(true);
    _emit(userId);
  }

  @override
  Future<UserContextSettings> getContextSettings(String userId) async {
    return _contextSettings[userId] ?? UserContextSettings(userId: userId);
  }

  @override
  Future<void> updateContextSettings(UserContextSettings settings) async {
    _contextSettings[settings.userId] = settings;
  }

  @override
  Future<UserContextProfile> getContextProfile(String userId) async {
    return _contextProfiles[userId] ??
        UserContextProfile(
            userId: userId, activityMap: {}, peakInteractionHours: []);
  }

  NotificationType _typeFromString(String s) {
    switch (s) {
      case 'friendRequest':
        return NotificationType.friendRequest;
      case 'groupInvite':
        return NotificationType.groupInvite;
      case 'call':
        return NotificationType.call;
      case 'message':
      default:
        return NotificationType.message;
    }
  }

  final Map<String, NotificationPreference> _prefs = {};

  @override
  Future<NotificationPreference> getPreferences(String userId) async {
    return _prefs[userId] ??
        NotificationPreference(
          id: 'mock_pref',
          userId: userId,
        );
  }

  @override
  Future<void> updatePreferences(
      String userId, NotificationPreference prefs) async {
    _prefs[userId] = prefs;
  }

  final Map<String, NotificationAiSettings> _aiSettings = {};

  @override
  Future<NotificationAiSettings> getAiSettings(String userId) async {
    return _aiSettings[userId] ??
        NotificationAiSettings(
          id: 'mock_ai_pref',
          userId: userId,
        );
  }

  @override
  Future<void> updateAiSettings(
      String userId, NotificationAiSettings settings) async {
    _aiSettings[userId] = settings;
  }

  @override
  Future<Map<String, dynamic>> getAiEfficiencyStats(String userId) async {
    return {
      'total_processed': 150,
      'ai_silenced': 45,
      'efficiency_rate': 0.3,
    };
  }

  // --- GOVERNANCE & TRUST (Stage D) ---
  final Map<String, List<AiExclusion>> _exclusions = {};

  @override
  Future<List<AiExclusion>> getAiExclusions(String userId) async {
    return _exclusions[userId] ?? [];
  }

  @override
  Future<void> addAiExclusion(AiExclusion exclusion) async {
    final list = _exclusions.putIfAbsent(exclusion.userId, () => []);
    if (!list.any((e) => e.chatId == exclusion.chatId)) {
      list.add(exclusion);
    }
  }

  @override
  Future<void> removeAiExclusion(String userId, String chatId) async {
    _exclusions[userId]?.removeWhere((e) => e.chatId == chatId);
  }

  @override
  Future<void> toggleSafeMode(String userId, bool enabled) async {
    final settings = await getAiSettings(userId);
    _aiSettings[userId] = settings.copyWith(isSafeMode: enabled);
  }

  @override
  Future<void> pauseAi(String userId, Duration duration) async {
    final settings = await getAiSettings(userId);
    _aiSettings[userId] = settings.copyWith(
      pausedUntil: DateTime.now().add(duration),
    );
  }

  @override
  Future<LearningWeights> getLearningWeights(String userId) async {
    return _learningWeights[userId] ??
        LearningWeights(userId: userId, lastUpdated: DateTime.now());
  }

  @override
  Future<void> submitFeedback(UserFeedback feedback) async {
    // In mock, feedback is received but not persisted
  }

  // --- STAGE G: GOVERNANCE & STABILITY ---

  @override
  Future<List<LearningWeightSnapshot>> getWeightSnapshots(String userId) async {
    return _snapshots[userId] ?? [];
  }

  @override
  Future<String> createWeightSnapshot(String userId, String tag) async {
    final settings = await getAiSettings(userId);
    final lw = await getLearningWeights(userId);

    final snap = LearningWeightSnapshot(
      id: _genId(),
      userId: userId,
      engagementWeight: lw.engagementWeight,
      contextWeight: lw.contextWeight,
      urgencyWeight: lw.urgencyWeight,
      trustScore: settings.systemTrustIndex,
      versionTag: tag,
      createdAt: DateTime.now(),
    );

    final list = _snapshots.putIfAbsent(userId, () => []);
    list.insert(0, snap);
    return snap.id;
  }

  @override
  Future<void> rollbackToSnapshot(String userId, String snapshotId) async {
    final settings = await getAiSettings(userId);
    _aiSettings[userId] = settings.copyWith(
      weightVersionId: snapshotId,
      stabilityScore: 1.0,
    );

    final audits = _audits.putIfAbsent(userId, () => []);
    audits.insert(
        0,
        GovernanceAudit(
          id: _genId(),
          userId: userId,
          actionType: 'manual_rollback',
          details: {'snapshot_id': snapshotId},
          severity: 'warning',
          createdAt: DateTime.now(),
        ));
  }

  @override
  Future<List<GovernanceAudit>> getGovernanceAudit(String userId) async {
    return _audits[userId] ?? [];
  }

  // --- STAGE H: POLICY & IDENTITY ---
  final Map<String, List<AiScope>> _scopes = {};
  final Map<String, List<AiPolicy>> _policies = {};

  @override
  Future<List<AiScope>> getScopes(String userId) async {
    return _scopes[userId] ??
        [
          AiScope(id: 's1', name: 'Smart Personal', type: 'personal'),
          AiScope(id: 's2', name: 'Work Team', type: 'team'),
        ];
  }

  @override
  Future<List<AiPolicy>> getPolicies(String userId, String scopeId) async {
    return _policies[scopeId] ??
        [
          AiPolicy(
            id: 'p1',
            scopeId: scopeId,
            name: 'Block Marketing',
            action: 'BLOCK',
            priority: 10,
            rules: {'source_type': 'marketing'},
            isActive: true,
            createdAt: DateTime.now(),
          ),
        ];
  }

  @override
  Future<void> logNotificationEvent({
    required String messageId,
    required String eventType,
    String? platform,
    Map<String, dynamic>? metadata,
  }) async {
    // In mock, we just log to console
    debugPrint(
        '📊 [Mock] Notification Event: $eventType for message $messageId (Platform: $platform)');
  }

  final Map<String, NotificationExperiencePrefs> _experiencePrefs = {};

  @override
  Future<NotificationExperiencePrefs> getExperiencePrefs(String userId) async {
    return _experiencePrefs[userId] ??
        NotificationExperiencePrefs(userId: userId);
  }

  @override
  Future<void> updateExperiencePrefs(NotificationExperiencePrefs prefs) async {
    _experiencePrefs[prefs.userId] = prefs;
  }

  @override
  Future<void> reportInteractionSignal({
    required String userId,
    required String signalType,
    String? messageId,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint(
        '📊 [Mock] Interaction Signal: $signalType for user $userId (Message: $messageId)');
  }
}
