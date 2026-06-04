import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';

import '../../app_events.dart';
import '../../contracts/specific_contracts.dart';

class ChatFeatureClient extends GetxService implements IChatFeature {
  @override
  String get featureId => 'chat_v1';

  @override
  bool get isHealthy => true;

  bool _mediaAllowed = true;
  bool _realtimeEvents = true;
  // ignore: unused_field
  bool _readOnly = false;

  @override
  bool get allowMediaTransfer => _mediaAllowed;

  @override
  bool get enableRealtimeEvents => _realtimeEvents;

  @override
  Future<void> boot() async {
    debugPrint('ChatFeatureClient: Booting up...');
  }

  @override
  void handleGlobalEvent(AppBrainEvent event) {
    // e.g., If 'Emergency' event, disable chat
  }

  @override
  Future<void> applyPolicy(Map<String, dynamic> constraints) async {
    debugPrint('ChatFeatureClient: Applying policy $constraints');

    if (constraints.containsKey('realtime_typing')) {
      _realtimeEvents = constraints['realtime_typing'] as bool;
    }

    if (constraints.containsKey('read_only')) {
      _readOnly = constraints['read_only'] as bool;
    }

    if (constraints.containsKey('media_allowed')) {
      _mediaAllowed = constraints['media_allowed'] as bool;
    }
  }

  @override
  Future<void> setReadOnly(bool enabled) async {
    _readOnly = enabled;
    try {
      final chatController = Get.find<ChatController>();
      chatController.setInputLocked(enabled,
          reason: 'الدردشة في وضع القراءة فقط');
    } catch (_) {}
  }
}
