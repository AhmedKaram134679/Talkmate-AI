import 'package:talkmate_ai/data/models/device_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart';

abstract class IUserRepository {
  Future<void> upsertUser(AppUser user);
  Future<AppUser?> getById(String userId);
  Stream<AppUser?> watchById(String userId);
  Future<void> updateStatus(String userId, UserStatus status,
      {DateTime? lastSeen});
  Future<List<AppUser>> searchByNameOrEmail(String query,
      {int limit = 20, List<String>? userIds});
  Future<void> updatePrivacy(
    String userId, {
    bool? showLastSeen,
    bool? showProfilePhoto,
    bool? showStatus,
  });
  Future<void> updateProfile(
    String userId, {
    String? displayName,
    String? about,
    String? photoUrl,
  });
  Future<void> addFcmToken(String userId, String token,
      {String? deviceId,
      String? platform,
      DateTime? lastUpdate,
      Map<String, dynamic>? webPushSubscription});
  Future<void> updateWebPushSubscription(String userId, String subscriptionJson,
      {String? deviceId});
  Future<void> updateDevicePresence(String userId, String deviceId,
      {bool? isOnline, String? appState});

  Future<List<DeviceModel>> getUserDevices(String userId);
  Future<void> revokeDevice(String userId, String deviceId);
  Future<void> revokeAllOtherDevices(String userId, String currentDeviceId);
}
