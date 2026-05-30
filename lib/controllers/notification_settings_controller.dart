import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/notification_experience_model.dart';
import 'package:talkmate_ai/data/models/notification_preference_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_notification_repository.dart';

class NotificationSettingsController extends GetxController {
  final INotificationRepository _repository =
      Get.find<INotificationRepository>();
  final AuthController _authController = Get.find<AuthController>();

  final Rxn<NotificationPreference> preferences = Rxn<NotificationPreference>();
  final Rxn<NotificationExperiencePrefs> experiencePreferences =
      Rxn<NotificationExperiencePrefs>();
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadPreferences();
    loadExperiencePrefs();
  }

  Future<void> loadPreferences() async {
    isLoading.value = true;
    try {
      final uid = _authController.userId;
      if (uid.isNotEmpty) {
        final prefs = await _repository.getPreferences(uid);
        preferences.value = prefs;
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadExperiencePrefs() async {
    try {
      final uid = _authController.userId;
      if (uid.isNotEmpty) {
        final prefs = await _repository.getExperiencePrefs(uid);
        experiencePreferences.value = prefs;
      }
    } catch (e) {
      debugPrint('Error loading experience preferences: $e');
    }
  }

  Future<void> updatePreference(NotificationPreference newPrefs) async {
    try {
      final uid = _authController.userId;
      if (uid.isNotEmpty) {
        await _repository.updatePreferences(uid, newPrefs);
        preferences.value = newPrefs;
      }
    } catch (e) {
      debugPrint('Error updating preferences: $e');
      Get.snackbar('خطأ', 'فشل في تحديث الإعدادات');
    }
  }

  void toggleChats(bool val) {
    if (preferences.value != null) {
      updatePreference(preferences.value!.copyWith(chatsEnabled: val));
    }
  }

  void toggleGroups(bool val) {
    if (preferences.value != null) {
      updatePreference(preferences.value!.copyWith(groupsEnabled: val));
    }
  }

  void toggleCalls(bool val) {
    if (preferences.value != null) {
      updatePreference(preferences.value!.copyWith(callsEnabled: val));
    }
  }

  void toggleMentions(bool val) {
    if (preferences.value != null) {
      updatePreference(preferences.value!.copyWith(mentionsEnabled: val));
    }
  }

  void updateStyle(String style) {
    if (preferences.value != null) {
      updatePreference(preferences.value!.copyWith(style: style));
    }
  }

  void toggleDnd(bool val) {
    if (preferences.value != null) {
      updatePreference(preferences.value!.copyWith(dndEnabled: val));
    }
  }

  void updateDndStart(String time) {
    if (preferences.value != null) {
      updatePreference(preferences.value!.copyWith(dndStart: time));
    }
  }

  void updateDndEnd(String time) {
    if (preferences.value != null) {
      updatePreference(preferences.value!.copyWith(dndEnd: time));
    }
  }

  // Stage S methods
  Future<void> updateExperienceMode(String mode) async {
    if (experiencePreferences.value != null) {
      final newPrefs =
          experiencePreferences.value!.copyWith(experienceMode: mode);
      await _repository.updateExperiencePrefs(newPrefs);
      experiencePreferences.value = newPrefs;
    }
  }

  Future<void> toggleSnooze(bool val,
      {Duration duration = const Duration(hours: 1)}) async {
    if (experiencePreferences.value != null) {
      final snoozeUntil = val ? DateTime.now().add(duration) : null;
      final newPrefs = experiencePreferences.value!.copyWith(
        isSnoozed: val,
        snoozeUntil: snoozeUntil,
      );
      await _repository.updateExperiencePrefs(newPrefs);
      experiencePreferences.value = newPrefs;
    }
  }

  Future<void> reportSignal(String signalType, {String? messageId}) async {
    final uid = _authController.userId;
    if (uid.isNotEmpty) {
      await _repository.reportInteractionSignal(
        userId: uid,
        signalType: signalType,
        messageId: messageId,
      );
    }
  }
}
