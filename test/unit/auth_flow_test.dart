import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/device_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/services/auth/supabase_auth_service.dart';

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

class MockAuthService extends SupabaseAuthService {
  @override
  Future<void> signOut() async {}

  @override
  Future<AuthResponse> signIn({required String email, required String password}) async {
    return AuthResponse();
  }
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

    test('deleteAccount transport failure (SocketException) rethrows error, resets isLoading, and directly preserves SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_id': 'user_socket_fail',
        'user_email': 'socket@talkmate.ai',
        'user_name': 'Socket Test',
        'auth_token': 'persisted_bearer_jwt_123',
      });
      authController.setMockUser('user_socket_fail', 'Socket Test', 'socket@talkmate.ai');
      authController.authService = MockAuthService();
      expect(authController.isLoggedIn, true);

      // Injected functionsInvoker throws genuine SocketException
      authController.functionsInvoker = (fn) async {
        throw const SocketException('Connection refused to Supabase Functions Gateway');
      };

      await expectLater(
        authController.deleteAccount(password: ''),
        throwsA(isA<SocketException>()),
      );

      // Verify controller state
      expect(authController.isLoading, false);
      expect(authController.isLoggedIn, true);
      expect(authController.userId, 'user_socket_fail');

      // Verify SharedPreferences directly: NO PREMATURE CREDENTIAL WIPE
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), true);
      expect(prefs.getString('user_id'), 'user_socket_fail');
      expect(prefs.getString('user_email'), 'socket@talkmate.ai');
      expect(prefs.getString('auth_token'), 'persisted_bearer_jwt_123');
    });

    test('deleteAccount server-side HTTP 500 error rethrows error, resets isLoading, and directly preserves SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_id': 'user_500_fail',
        'user_email': 'err500@talkmate.ai',
        'auth_token': 'persisted_jwt_500',
      });
      authController.setMockUser('user_500_fail', 'Err 500', 'err500@talkmate.ai');
      authController.authService = MockAuthService();
      expect(authController.isLoggedIn, true);

      // Injected functionsInvoker returns 500 with server error payload
      authController.functionsInvoker = (fn) async {
        return FunctionResponse(
          status: 500,
          data: {'error': 'Failed to clean up user database records. Account deletion aborted.'},
        );
      };

      await expectLater(
        authController.deleteAccount(password: ''),
        throwsA(predicate((e) =>
            e is Exception &&
            e.toString().contains('Failed to clean up user database records'))),
      );

      // Verify controller state
      expect(authController.isLoading, false);
      expect(authController.isLoggedIn, true);
      expect(authController.userId, 'user_500_fail');

      // Verify SharedPreferences directly: CREDENTIALS PRESERVED
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), true);
      expect(prefs.getString('user_id'), 'user_500_fail');
      expect(prefs.getString('auth_token'), 'persisted_jwt_500');
    });

    test('deleteAccount authentication failure (HTTP 401) rethrows error, resets isLoading, and directly preserves SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_id': 'user_401_fail',
        'user_email': 'err401@talkmate.ai',
        'auth_token': 'expired_jwt_sample',
      });
      authController.setMockUser('user_401_fail', 'Err 401', 'err401@talkmate.ai');
      authController.authService = MockAuthService();
      expect(authController.isLoggedIn, true);

      authController.functionsInvoker = (fn) async {
        return FunctionResponse(
          status: 401,
          data: {'error': 'Unauthorized: Invalid or expired session'},
        );
      };

      await expectLater(
        authController.deleteAccount(password: ''),
        throwsA(predicate((e) =>
            e is Exception &&
            e.toString().contains('Unauthorized: Invalid or expired session'))),
      );

      expect(authController.isLoading, false);
      expect(authController.isLoggedIn, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), true);
      expect(prefs.getString('user_id'), 'user_401_fail');
    });

    test('deleteAccount connection timeout (TimeoutException) rethrows error, resets isLoading, and directly preserves SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_id': 'user_timeout',
        'auth_token': 'persisted_jwt_timeout',
      });
      authController.setMockUser('user_timeout', 'Timeout Test', 'timeout@talkmate.ai');
      authController.authService = MockAuthService();

      authController.functionsInvoker = (fn) async {
        throw TimeoutException('Client network connection timed out waiting for gateway');
      };

      await expectLater(
        authController.deleteAccount(password: ''),
        throwsA(isA<TimeoutException>()),
      );

      expect(authController.isLoading, false);
      expect(authController.isLoggedIn, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), true);
      expect(prefs.getString('user_id'), 'user_timeout');
    });

    test('deleteAccount confirmed server-side HTTP 200 success resets isLoading, sets isLoggedIn=false, and directly wipes SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_id': 'user_success_wipe',
        'user_email': 'wipe@talkmate.ai',
        'user_name': 'Wipe Test',
        'auth_token': 'to_be_deleted_token',
      });
      authController.setMockUser('user_success_wipe', 'Wipe Test', 'wipe@talkmate.ai');
      authController.authService = MockAuthService();
      expect(authController.isLoggedIn, true);

      // Injected functionsInvoker returns 200 success
      authController.functionsInvoker = (fn) async {
        return FunctionResponse(
          status: 200,
          data: {'success': true, 'message': 'Account and authentication identity successfully deleted'},
        );
      };

      await authController.deleteAccount(password: '');

      // Controller state must be fully cleared
      expect(authController.isLoading, false);
      expect(authController.isLoggedIn, false);
      expect(authController.userId, isEmpty);
      expect(authController.userEmail, isEmpty);
      expect(authController.userName, isEmpty);

      // Verify persistent SharedPreferences directly: FULLY WIPED
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), isNull);
      expect(prefs.getString('user_id'), isNull);
      expect(prefs.getString('user_email'), isNull);
      expect(prefs.getString('auth_token'), isNull);
    });
  });
}
