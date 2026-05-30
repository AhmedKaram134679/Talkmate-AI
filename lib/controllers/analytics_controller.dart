import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/device_analytics_model.dart';
import 'package:talkmate_ai/data/repositories/analytics_repository.dart';

class AnalyticsController extends GetxController {
  final AnalyticsRepository _repository = AnalyticsRepository();
  final AuthController _authController = Get.find<AuthController>();

  final RxList<DeviceAnalyticsModel> deviceStats = <DeviceAnalyticsModel>[].obs;
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchStats();
  }

  Future<void> fetchStats() async {
    if (!_authController.isLoggedIn) return;

    isLoading.value = true;
    try {
      final stats =
          await _repository.getDevicePerformance(_authController.userId);
      deviceStats.assignAll(stats);
    } finally {
      isLoading.value = false;
    }
  }
}
