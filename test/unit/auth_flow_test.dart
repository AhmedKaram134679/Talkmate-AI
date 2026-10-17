import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/device_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';

class MockUserRepository implements IUserRepository {
  final Map<String, AppUser> _users = {};

  @override
  Future<AppUser?> getById(String id) async => _users[id];

  @override
  Future<void> upsertUser(AppUser user) async {
    _users[user.id] = user;
  }

  @override
  Future<void> updateStatus(String userId, UserStatus status, {DateTime? lastSeen}) async {
    final existing = _users[userId];
    if (existing != null) {
      _users[userId] = existing.copyWith(status: status, lastSeen: lastSeen);
    }
  }

  @override
  Future<List<AppUser>> searchByNameOrEmail(String query,
      {int limit = 20, List<String>? userIds}) async {
    return _users.values
        .where((u) =>
            (u.displayName?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
            u.email.toLowerCase().contains(query.toLowerCase()))
        .take(limit)
        .toList();
  }

  @override
  Stream<AppUser?> watchById(String id) {
    return Stream.value(_users[id]);
  }

  @override
  Future<void> updatePrivacy(
    String userId, {
    bool? showLastSeen,
    bool? showProfilePhoto,
    bool? showStatus,
  }) async {}

  @override
  Future<void> updateProfile(
    String userId, {
    String? displayName,
    String? about,
    String? photoUrl,
  }) async {
    final existing = _users[userId];
    if (existing != null) {
      _users[userId] = existing.copyWith(
        displayName: displayName ?? existing.displayName,
        about: about ?? existing.about,
        photoUrl: photoUrl ?? existing.photoUrl,
      );
    }
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
  Future<void> revokeAllOtherDevices(String userId, String currentDeviceId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unit: AuthController Flow & State Tests', () {
    late AuthController authController;
    late MockUserRepository mockUserRepo;

    setUp(() {
      Get.testMode = true;
      mockUserRepo = MockUserRepository();
      Get.put<IUserRepository>(mockUserRepo);
      authController = Get.put(AuthController());
    });

    tearDown(() {
      Get.reset();
    });

    test('Initial auth state should be unauthenticated', () {
      expect(authController.isLoggedIn, false);
      expect(authController.userId, isEmpty);
      expect(authController.userEmail, isEmpty);
      expect(authController.hasSeenOnboarding, false);
    });

    test('setMockUser updates reactive state and preserves profile fields', () {
      const testId = 'auth_usr_123';
      const testName = 'Jane Developer';
      const testEmail = 'jane.dev@talkmate.ai';
      const testPhoto = 'https://talkmate.ai/avatars/jane.png';

      authController.setMockUser(testId, testName, testEmail, photoUrl: testPhoto);

      expect(authController.isLoggedIn, true);
      expect(authController.userId, testId);
      expect(authController.userName, testName);
      expect(authController.userEmail, testEmail);
      expect(authController.userPhoto, testPhoto);
    });

    test('MockUserRepository handles user profile persistence & lookup', () async {
      final user = AppUser(
        id: 'usr_repo_1',
        email: 'repo_user@talkmate.ai',
        displayName: 'Repo User',
        createdAt: DateTime.now(),
        status: UserStatus.online,
        fcmTokens: const ['fcm_token_sample'],
      );

      await mockUserRepo.upsertUser(user);
      final fetched = await mockUserRepo.getById('usr_repo_1');

      expect(fetched, isNotNull);
      expect(fetched!.email, 'repo_user@talkmate.ai');
      expect(fetched.displayName, 'Repo User');
      expect(fetched.status, UserStatus.online);
      expect(fetched.fcmTokens, contains('fcm_token_sample'));

      // Update online status
      await mockUserRepo.updateStatus('usr_repo_1', UserStatus.offline);
      final updated = await mockUserRepo.getById('usr_repo_1');
      expect(updated?.status, UserStatus.offline);
    });

    test('MockUserRepository search handles queries accurately', () async {
      await mockUserRepo.upsertUser(AppUser(
        id: 'user_alice',
        email: 'alice@talkmate.ai',
        displayName: 'Alice Smith',
        createdAt: DateTime.now(),
      ));
      await mockUserRepo.upsertUser(AppUser(
        id: 'user_bob',
        email: 'bob@talkmate.ai',
        displayName: 'Bob Builder',
        createdAt: DateTime.now(),
      ));

      final aliceResults = await mockUserRepo.searchByNameOrEmail('Alice');
      expect(aliceResults.length, 1);
      expect(aliceResults.first.id, 'user_alice');

      final emailResults = await mockUserRepo.searchByNameOrEmail('@talkmate');
      expect(emailResults.length, 2);
    });
  });
}
