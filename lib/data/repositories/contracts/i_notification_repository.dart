import 'package:talkmate_ai/data/models/ai_exclusion_model.dart';
import 'package:talkmate_ai/data/models/ai_policy_model.dart';
import 'package:talkmate_ai/data/models/ai_stability_model.dart';
import 'package:talkmate_ai/data/models/notification_ai_settings_model.dart';
import 'package:talkmate_ai/data/models/notification_experience_model.dart';
import 'package:talkmate_ai/data/models/notification_model.dart';
import 'package:talkmate_ai/data/models/notification_preference_model.dart';
import 'package:talkmate_ai/data/models/user_context_model.dart';
import 'package:talkmate_ai/data/models/user_learning_model.dart';

abstract class INotificationRepository {
  Future<void> sendNotification({
    required String toUserId,
    required String type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    DateTime? createdAt,
  });

  Stream<List<AppNotification>> watchUserNotifications(String userId,
      {int limit = 50});

  Future<void> markAsRead(String userId, String notificationId);

  // Preferences (Stage B)
  Future<NotificationPreference> getPreferences(String userId);
  Future<void> updatePreferences(String userId, NotificationPreference prefs);

  // AI & Efficiency (Stage C)
  Future<NotificationAiSettings> getAiSettings(String userId);
  Future<void> updateAiSettings(String userId, NotificationAiSettings settings);
  Future<Map<String, dynamic>> getAiEfficiencyStats(String userId);

  // Governance & Trust (Stage D)
  Future<List<AiExclusion>> getAiExclusions(String userId);
  Future<void> addAiExclusion(AiExclusion exclusion);
  Future<void> removeAiExclusion(String userId, String chatId);
  Future<void> toggleSafeMode(String userId, bool enabled);
  Future<void> pauseAi(String userId, Duration duration);

  // Stage E: Contextual Intelligence
  Future<UserContextSettings> getContextSettings(String userId);
  Future<void> updateContextSettings(UserContextSettings settings);
  Future<UserContextProfile> getContextProfile(String userId);

  // Stage F: Autonomous Learning
  Future<LearningWeights> getLearningWeights(String userId);
  Future<void> submitFeedback(UserFeedback feedback);

  // Stage G: Governance & Stability
  Future<List<LearningWeightSnapshot>> getWeightSnapshots(String userId);
  Future<String> createWeightSnapshot(String userId, String tag);
  Future<void> rollbackToSnapshot(String userId, String snapshotId);
  Future<List<GovernanceAudit>> getGovernanceAudit(String userId);

  // Stage H: Policy & Identity
  Future<List<AiScope>> getScopes(String userId);
  Future<List<AiPolicy>> getPolicies(String userId, String scopeId);

  // Stage V: Professional Notification & Badge System
  Future<void> logNotificationEvent({
    required String messageId,
    required String eventType, // 'delivered', 'opened', 'dismissed', 'received'
    String? platform,
    Map<String, dynamic>? metadata,
  });

  // Stage S: Notification Experience
  Future<NotificationExperiencePrefs> getExperiencePrefs(String userId);
  Future<void> updateExperiencePrefs(NotificationExperiencePrefs prefs);
  Future<void> reportInteractionSignal({
    required String userId,
    required String
        signalType, // 'click', 'dismiss_fast', 'snooze', 'mute_category'
    String? messageId,
    Map<String, dynamic>? metadata,
  });
}
