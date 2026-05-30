import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/notification_controller.dart';
import '../../app_events.dart';
import '../../contracts/specific_contracts.dart';

class NotificationFeatureClient extends GetxService
    implements INotificationFeature {
  @override
  String get featureId => 'notifications';

  @override
  bool get isHealthy => true;

  bool _soundAllowed = true;
  bool _headsUpAllowed = true;

  @override
  bool get allowSound => _soundAllowed;

  @override
  bool get allowHeadsUp => _headsUpAllowed;

  @override
  Future<void> boot() async {
    debugPrint('NotificationFeatureClient: Booting up...');
  }

  @override
  void handleGlobalEvent(AppBrainEvent event) {
    // Check for high-priority events
  }

  @override
  Future<void> applyPolicy(Map<String, dynamic> constraints) async {
    debugPrint('NotificationFeatureClient: Applying policy $constraints');

    if (constraints.containsKey('sound')) {
      _soundAllowed = constraints['sound'] as bool;
    }
    if (constraints.containsKey('heads_up')) {
      _headsUpAllowed = constraints['heads_up'] as bool;
    }
  }

  @override
  Future<void> setQuietMode(bool enabled) async {
    _soundAllowed = !enabled;
    _headsUpAllowed = !enabled;
    try {
      final notificationController = Get.find<NotificationController>();
      await notificationController.setSoundEnabled(!enabled);
      // headsUp is handled by channel importance usually, but we can potentially
      // call a method if we want literal quiet mode.
    } catch (_) {}
  }
}
