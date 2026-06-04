import 'dart:async';
import 'package:talkmate_ai/data/models/device_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';

class MockUserRepository implements IUserRepository {
  MockUserRepository._();
  static final MockUserRepository instance = MockUserRepository._();

  final Map<String, AppUser> _users = {};
  final Map<String, StreamController<AppUser?>> _controllers = {};

  StreamController<AppUser?> _controllerFor(String id) {
    return _controllers.putIfAbsent(
      id,
      () => StreamController<AppUser?>.broadcast(),
    );
  }

  void _emit(String id) {
    _controllerFor(id).add(_users[id]);
  }

  @override
  Future<void> upsertUser(AppUser user) async {
    _users[user.id] = user;
    _emit(user.id);
  }

  @override
  Future<AppUser?> getById(String userId) async => _users[userId];

  @override
  Stream<AppUser?> watchById(String userId) {
    Future.microtask(() => _emit(userId));
    return _controllerFor(userId).stream;
  }

  @override
  Future<void> updateStatus(String userId, UserStatus status,
      {DateTime? lastSeen}) async {
    final u = _users[userId];
    if (u == null) return;
    _users[userId] = u.copyWith(
      status: status,
      lastSeen: lastSeen ?? DateTime.now(),
    );
    _emit(userId);
  }

  @override
  Future<List<AppUser>> searchByNameOrEmail(String query,
      {int limit = 20, List<String>? userIds}) async {
    final q = query.toLowerCase();
    return _users.values
        .where((u) {
          if (userIds != null && !userIds.contains(u.id)) return false;
          final name = (u.displayName ?? '').toLowerCase();
          final email = u.email.toLowerCase();
          return name.contains(q) || email.contains(q);
        })
        .take(limit)
        .toList();
  }

  @override
  Future<void> updatePrivacy(
    String userId, {
    bool? showLastSeen,
    bool? showProfilePhoto,
    bool? showStatus,
  }) async {
    final u = _users[userId];
    if (u == null) return;
    _users[userId] = u.copyWith(
      privacyShowLastSeen: showLastSeen,
      privacyShowProfilePhoto: showProfilePhoto,
      privacyShowStatus: showStatus,
    );
    _emit(userId);
  }

  @override
  Future<void> updateProfile(
    String userId, {
    String? displayName,
    String? about,
    String? photoUrl,
  }) async {
    final u = _users[userId];
    if (u == null) return;
    _users[userId] = u.copyWith(
      displayName: displayName,
      about: about,
      photoUrl: photoUrl,
    );
    _emit(userId);
  }

  @override
  Future<void> addFcmToken(String userId, String token,
      {String? deviceId,
      String? platform,
      DateTime? lastUpdate,
      Map<String, dynamic>? webPushSubscription}) async {}

  @override
  Future<void> updateWebPushSubscription(String userId, String subscriptionJson,
      {String? deviceId}) async {}

  @override
  Future<void> updateDevicePresence(String userId, String deviceId,
      {bool? isOnline, String? appState}) async {}

  @override
  Future<List<DeviceModel>> getUserDevices(String userId) async => [];

  @override
  Future<void> revokeDevice(String userId, String deviceId) async {}

  @override
  Future<void> revokeAllOtherDevices(
      String userId, String currentDeviceId) async {}
}
