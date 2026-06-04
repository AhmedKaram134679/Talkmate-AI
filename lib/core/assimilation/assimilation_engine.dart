import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'contracts/implementations/call_feature_contract.dart';
import 'contracts/implementations/chat_feature_contract.dart';
import 'gatekeeper/feature_gatekeeper.dart';

/// AssimilationEngine: Managing the integration of existing features into the App Brain.
///
/// This service is responsible for:
/// 1. Initializing the FeatureGatekeeper (if needed).
/// 2. Registering all Feature Contracts.
/// 3. Providing a central point for Assimilation status.
class AssimilationEngine extends GetxService {
  static AssimilationEngine get instance => Get.find<AssimilationEngine>();

  final FeatureGatekeeper _gatekeeper = FeatureGatekeeper.instance;

  @override
  void onInit() {
    super.onInit();
    debugPrint('AssimilationEngine: Initializing...');
    _registerContracts();
  }

  void _registerContracts() {
    _gatekeeper.register(CallFeatureContract());
    _gatekeeper.register(ChatFeatureContract());
    debugPrint('AssimilationEngine: Feature Contracts registered.');
  }
}
