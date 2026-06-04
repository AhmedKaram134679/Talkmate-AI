import 'package:flutter/foundation.dart';
import '../definitions.dart';
import '../feature_contracts.dart';

/// PresenceFeatureContract: Defines rules for Online/Typing status
class PresenceFeatureContract implements IFeatureContract {
  @override
  FeatureType get type => FeatureType.presence;

  @override
  String get name => 'Presence Sync';

  @override
  Set<FeatureRequirement> get requirements => {
        FeatureRequirement.internet,
      };

  @override
  int get priorityLevel => 20; // Low priority

  @override
  void applyDegradation(FeatureStateSignals signals) {
    if (signals.isNetworkUnstable || signals.isLowPowerMode) {
      debugPrint(
          'PresenceFeatureContract: [Assimilation] Pausing presence updates.');
    }
  }

  @override
  void restoreNormalOperation() {
    debugPrint(
        'PresenceFeatureContract: [Assimilation] Resuming presence updates.');
  }
}
