import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/ai_exclusion_model.dart';
import 'package:talkmate_ai/data/models/ai_policy_model.dart';
import 'package:talkmate_ai/data/models/ai_stability_model.dart';
import 'package:talkmate_ai/data/models/notification_ai_settings_model.dart';
import 'package:talkmate_ai/data/models/user_context_model.dart';
import 'package:talkmate_ai/data/models/user_learning_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_notification_repository.dart';

class NotificationAiSettingsController extends GetxController {
  final INotificationRepository _repository =
      Get.find<INotificationRepository>();
  final AuthController _authController = Get.find<AuthController>();

  final Rxn<NotificationAiSettings> aiSettings = Rxn<NotificationAiSettings>();
  final Rxn<UserContextSettings> contextSettings = Rxn<UserContextSettings>();
  final Rxn<UserContextProfile> contextProfile = Rxn<UserContextProfile>();
  final Rxn<LearningWeights> learningWeights = Rxn<LearningWeights>();
  final RxList<LearningWeightSnapshot> weightSnapshots =
      <LearningWeightSnapshot>[].obs;
  final RxList<GovernanceAudit> governanceAudit = <GovernanceAudit>[].obs;

  final RxList<AiScope> aiScopes = <AiScope>[].obs;
  final RxMap<String, List<AiPolicy>> aiPolicies =
      <String, List<AiPolicy>>{}.obs; // ScopeId -> Policies

  final RxBool isLoading = true.obs;
  final RxMap efficiencyStats = {}.obs;
  final RxList<AiExclusion> aiExclusions = <AiExclusion>[].obs;

  String get userId => _authController.user?.id ?? '';

  NotificationAiSettingsController();

  @override
  void onInit() {
    super.onInit();
    loadAllData();
  }

  Future<void> loadAllData() async {
    isLoading.value = true;
    try {
      await Future.wait([
        loadAiSettings(),
        loadEfficiencyStats(),
        loadAiExclusions(),
        loadContextData(),
        loadLearningWeights(),
        loadStabilityData(),
        loadScopes(),
      ]);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadScopes() async {
    try {
      final scopes = await _repository.getScopes(userId);
      aiScopes.assignAll(scopes);
      // Pre-load policies for all scopes
      for (final s in scopes) {
        await loadPolicies(s.id);
      }
    } catch (e) {
      // Log error
    }
  }

  Future<void> loadPolicies(String scopeId) async {
    try {
      final policies = await _repository.getPolicies(userId, scopeId);
      aiPolicies[scopeId] = policies;
    } catch (e) {
      // Log error
    }
  }

  Future<void> loadAiSettings() async {
    final settings = await _repository.getAiSettings(userId);
    aiSettings.value = settings;
  }

  Future<void> loadAiExclusions() async {
    try {
      final list = await _repository.getAiExclusions(userId);
      aiExclusions.assignAll(list);
    } catch (e) {
      // Log error
    }
  }

  Future<void> loadEfficiencyStats() async {
    try {
      final stats = await _repository.getAiEfficiencyStats(userId);
      efficiencyStats.addAll(stats);
    } catch (e) {
      // Log error silently
    }
  }

  Future<void> loadContextData() async {
    try {
      contextSettings.value = await _repository.getContextSettings(userId);
      contextProfile.value = await _repository.getContextProfile(userId);
    } catch (e) {
      // Log error
    }
  }

  Future<void> loadLearningWeights() async {
    try {
      learningWeights.value = await _repository.getLearningWeights(userId);
    } catch (e) {
      // Log error
    }
  }

  Future<void> loadStabilityData() async {
    try {
      final snapshots = await _repository.getWeightSnapshots(userId);
      weightSnapshots.assignAll(snapshots);

      final audits = await _repository.getGovernanceAudit(userId);
      governanceAudit.assignAll(audits);
    } catch (e) {
      // Log error
    }
  }

  Future<void> createSnapshot(String tag) async {
    try {
      await _repository.createWeightSnapshot(userId, tag);
      await loadStabilityData();
      Get.snackbar('تم الحفظ', 'تم إنشاء نسخة احتياطية من الأوزان الحالية');
    } catch (e) {
      Get.snackbar('خطأ', 'فشل إنشاء نسخة الأوزان');
    }
  }

  Future<void> rollbackToSnapshot(String snapshotId) async {
    try {
      await _repository.rollbackToSnapshot(userId, snapshotId);
      await loadAllData();
      Get.snackbar('تم الاسترجاع', 'تم العودة للنسخة المحددة من الأوزان');
    } catch (e) {
      Get.snackbar('خطأ', 'فشل عملية التراجع');
    }
  }

  Future<void> updateContextSettings(UserContextSettings settings) async {
    try {
      await _repository.updateContextSettings(settings);
      contextSettings.value = settings;
      Get.snackbar('تم التحديث', 'تم حفظ إعدادات الذكاء السياقي بنجاح');
    } catch (e) {
      Get.snackbar('خطأ', 'فشل حفظ إعدادات السياق');
    }
  }

  // --- Governance Methods ---

  Future<void> addAiExclusion(String chatId) async {
    try {
      await _repository.addAiExclusion(AiExclusion(
        id: '',
        userId: userId,
        chatId: chatId,
        createdAt: DateTime.now(),
      ));
      await loadAiExclusions();
    } catch (e) {
      Get.snackbar('Error', 'Failed to exclude chat');
    }
  }

  Future<void> removeAiExclusion(String chatId) async {
    try {
      await _repository.removeAiExclusion(userId, chatId);
      await loadAiExclusions();
    } catch (e) {
      Get.snackbar('Error', 'Failed to remove exclusion');
    }
  }

  Future<void> toggleSafeMode(bool value) async {
    try {
      await _repository.toggleSafeMode(userId, value);
      await loadAiSettings();
    } catch (e) {
      Get.snackbar('Error', 'Failed to toggle Safe Mode');
    }
  }

  Future<void> pauseAi(Duration duration) async {
    try {
      await _repository.pauseAi(userId, duration);
      await loadAiSettings();
    } catch (e) {
      Get.snackbar('Error', 'Failed to pause AI');
    }
  }

  Future<void> submitFeedback(String decisionId, String type,
      {String? comment}) async {
    try {
      await _repository.submitFeedback(UserFeedback(
        userId: userId,
        decisionId: decisionId,
        feedbackType: type,
        comment: comment,
      ));
      Get.snackbar('شكراً لك', 'تم تسجيل ملاحظتك لتحسين النظام');
      await loadLearningWeights();
    } catch (e) {
      Get.snackbar('خطأ', 'فشل إرسال التغذية الراجعة');
    }
  }

  Future<void> toggleAiEnabled(bool value) async {
    if (aiSettings.value == null) return;
    aiSettings.value = aiSettings.value!.copyWith(isEnabled: value);
    await _saveSettings();
  }

  Future<void> toggleAdaptiveMode(bool value) async {
    if (aiSettings.value == null) return;
    aiSettings.value = aiSettings.value!.copyWith(adaptiveMode: value);
    await _saveSettings();
  }

  Future<void> updateSensitivity(double value) async {
    if (aiSettings.value == null) return;
    aiSettings.value = aiSettings.value!.copyWith(sensitivity: value);
    await _saveSettings();
  }

  Future<void> toggleLearningEnabled(bool value) async {
    if (aiSettings.value == null) return;
    aiSettings.value = aiSettings.value!.copyWith(learningEnabled: value);
    await _saveSettings();
  }

  Future<void> toggleSandboxMode(bool value) async {
    if (aiSettings.value == null) return;
    aiSettings.value = aiSettings.value!.copyWith(sandboxModeEnabled: value);
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    if (aiSettings.value == null) return;
    try {
      await _repository.updateAiSettings(userId, aiSettings.value!);
    } catch (e) {
      Get.snackbar('Error', 'Failed to save settings');
    }
  }
}
