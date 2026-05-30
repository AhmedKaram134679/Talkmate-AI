import 'package:get/get.dart';

/// AdaptiveRuntimeProfiles: Tracks current environment to influence optimization.
class AdaptiveRuntimeProfiles extends GetxController {
  static AdaptiveRuntimeProfiles get instance =>
      Get.isRegistered<AdaptiveRuntimeProfiles>()
          ? Get.find<AdaptiveRuntimeProfiles>()
          : Get.put(AdaptiveRuntimeProfiles());

  final Rx<DevicePowerMode> powerMode = DevicePowerMode.normal.obs;
  final Rx<NetworkProfile> networkQuality = NetworkProfile.stable.obs;

  void updatePowerMode(DevicePowerMode mode) => powerMode.value = mode;
  void updateNetwork(NetworkProfile profile) => networkQuality.value = profile;
}

enum DevicePowerMode { normal, lowPower, critical }

enum NetworkProfile { stable, shaky, offline, limited }
