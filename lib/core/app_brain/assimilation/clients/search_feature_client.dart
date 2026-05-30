import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../app_events.dart';
import '../../contracts/specific_contracts.dart';

class SearchFeatureClient extends GetxService implements ISearchFeature {
  @override
  String get featureId => 'search_v1';

  @override
  bool get isHealthy => true;

  bool _liveSearchAllowed = true;
  // ignore: unused_field
  bool _localOnly = false;

  @override
  bool get allowLiveSearch => _liveSearchAllowed;

  @override
  Future<void> boot() async {
    debugPrint('SearchFeatureClient: Booting up...');
  }

  @override
  void handleGlobalEvent(AppBrainEvent event) {}

  @override
  Future<void> applyPolicy(Map<String, dynamic> constraints) async {
    debugPrint('SearchFeatureClient: Applying policy $constraints');

    if (constraints.containsKey('live_search')) {
      _liveSearchAllowed = constraints['live_search'] as bool;
    }
  }

  @override
  Future<void> setLocalOnly(bool enabled) async {
    _localOnly = enabled;
  }
}
