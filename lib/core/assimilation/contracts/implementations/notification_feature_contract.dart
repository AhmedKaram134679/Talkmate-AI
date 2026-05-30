import 'package:flutter/foundation.dart';
import '../definitions.dart';
import '../feature_contracts.dart';

/// NotificationFeatureContract: Defines rules for Push/Local Notifications
class NotificationFeatureContract implements IFeatureContract {
  @override
  FeatureType get type => FeatureType.notification;

  @override
  String get name => 'Notifications';

  @override
  Set<FeatureRequirement> get requirements => {
        FeatureRequirement.internet,
        FeatureRequirement.backgroundExecution,
      };

  @override
  int get priorityLevel => 50;

  @override
  void applyDegradation(FeatureStateSignals signals) {
    if (signals.isLowPowerMode) {
      debugPrint(
          'NotificationFeatureContract: [Assimilation] Batching notifications due to Low Power.');
    } else if (signals.isSecurityLockdown) {
      debugPrint(
          'NotificationFeatureContract: [Assimilation] Hiding sensitive content.');
    }
  }

  @override
  void restoreNormalOperation() {
    debugPrint(
        'NotificationFeatureContract: [Assimilation] Resuming immediate delivery.');
  }
}
