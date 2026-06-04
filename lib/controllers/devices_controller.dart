import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/device_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/utils/device_identity.dart';

class DevicesController extends GetxController {
  final IUserRepository _userRepo = Get.find<IUserRepository>();
  final AuthController _authController = Get.find<AuthController>();

  final RxList<DeviceModel> devices = <DeviceModel>[].obs;
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchDevices();
  }

  Future<void> fetchDevices() async {
    final uid = _authController.userId;
    if (uid.isEmpty) return;

    isLoading.value = true;
    try {
      final res = await _userRepo.getUserDevices(uid);
      devices.assignAll(res);
    } catch (e) {
      Get.snackbar('خطأ', 'تعذر تحميل قائمة الأجهزة');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> revokeDevice(String deviceId) async {
    final uid = _authController.userId;
    if (uid.isEmpty) return;

    try {
      await _userRepo.revokeDevice(uid, deviceId);
      devices.removeWhere((d) => d.deviceId == deviceId);
      Get.snackbar('نجاح', 'تم تسجيل خروج الجهاز بنجاح');
    } catch (e) {
      Get.snackbar('خطأ', 'تعذر حذف الجهاز');
    }
  }

  Future<void> revokeAllOtherDevices() async {
    final uid = _authController.userId;
    if (uid.isEmpty) return;

    isLoading.value = true;
    try {
      final currentDeviceId = await DeviceIdentity.getId();
      await _userRepo.revokeAllOtherDevices(uid, currentDeviceId);

      // Update local list: keep only current device
      devices.removeWhere((d) => d.deviceId != currentDeviceId);

      Get.snackbar('نجاح', 'تم تسجيل خروج جميع الأجهزة الأخرى بنجاح');
    } catch (e) {
      Get.snackbar('خطأ', 'تعذر إخلاء الجلسات الأخرى');
    } finally {
      isLoading.value = false;
    }
  }
}
