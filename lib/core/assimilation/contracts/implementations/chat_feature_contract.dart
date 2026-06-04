import 'package:flutter/foundation.dart';
import '../definitions.dart';
import '../feature_contracts.dart';

/// ChatFeatureContract: Defines the rules for Messaging.
class ChatFeatureContract implements IFeatureContract {
  @override
  FeatureType get type => FeatureType.chat;

  @override
  String get name => 'Messaging';

  @override
  Set<FeatureRequirement> get requirements => {
        FeatureRequirement.internet,
        FeatureRequirement.storageWrite,
      };

  @override
  int get priorityLevel => 80;

  @override
  void applyDegradation(FeatureStateSignals signals) {
    if (signals.isNetworkUnstable) {
      debugPrint(
          'ChatFeatureContract: [Assimilation] Enabling "Store & Forward" mode.');
      // Future Integration: ChatController.enableOfflineMode(true);
    }
  }

  @override
  void restoreNormalOperation() {
    debugPrint(
        'ChatFeatureContract: [Assimilation] Resuming realtime socket mode.');
  }
}
