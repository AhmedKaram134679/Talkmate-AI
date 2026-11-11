import 'dart:async';
import 'dart:io' show Platform, SocketException;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/services/firebase_service.dart';
import 'package:talkmate_ai/data/services/messaging_service.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/services/observability/analytics_service.dart';
import 'package:talkmate_ai/services/observability/app_observability.dart';
import 'package:talkmate_ai/utils/device_identity.dart';

import '../data/models/user_model.dart';
import '../data/repositories/contracts/i_user_repository.dart';
import '../services/auth/supabase_auth_service.dart';

class AuthController extends GetxController {
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';
  static const String _userEmailKey = 'user_email';
  static const String _userPhotoKey = 'user_photo';
  static const String _hasSeenOnboardingKey = 'has_seen_onboarding';

  final RxBool _isLoggedIn = false.obs;
  final RxBool _isLoading = false.obs;
  final RxString _userId = ''.obs;
  final RxString _userName = ''.obs;
  final RxString _userEmail = ''.obs;
  final RxString _userPhoto = ''.obs;
  final RxBool _hasSeenOnboarding = false.obs;

  final SupabaseAuthService _authService = SupabaseAuthService();
  StreamSubscription<AuthState>? _authSub;
  Timer? _heartbeatTimer;

  // Getters
  bool get isLoggedIn => _isLoggedIn.value;
  RxBool get isLoggedInRx => _isLoggedIn;
  bool get isLoading => _isLoading.value;
  String get userId => _userId.value;
  RxString get userIdRx => _userId;
  String get userName => _userName.value;
  String get userEmail => _userEmail.value;
  String get userPhoto => _userPhoto.value;
  bool get hasSeenOnboarding => _hasSeenOnboarding.value;
  RxBool get hasSeenOnboardingRx => _hasSeenOnboarding;

  // New user getter for UI compatibility
  AppUser? get user => _userId.value.isEmpty
      ? null
      : AppUser(
          id: _userId.value,
          email: _userEmail.value,
          displayName: _userName.value,
          photoUrl: _userPhoto.value,
          createdAt: DateTime.now(), // Fallback
        );

  // Dummy needsEmailVerification for UI compatibility during migration
  final RxBool needsEmailVerification = false.obs;
  bool get canResendEmailVerification => true;
  int get resendSecondsRemaining => 0;

  Future<void> updateProfile({
    String? displayName,
    String? about,
    String? photoUrl,
    UserStatus? status,
  }) async {
    try {
      _isLoading.value = true;
      final currentSessionUser = _authService.currentUser;
      if (currentSessionUser == null || currentSessionUser.id != _userId.value) {
        throw StateError('Unauthorized profile update attempt.');
      }

      final repo = Get.find<IUserRepository>();
      await repo.updateProfile(
        _userId.value,
        displayName: displayName,
        about: about,
        photoUrl: photoUrl,
      );

      if (status != null) {
        await repo.updateStatus(_userId.value, status);
      }

      // Update local state safely
      if (displayName != null) _userName.value = displayName;
      if (photoUrl != null) _userPhoto.value = photoUrl;
    } catch (e) {
      Get.snackbar('خطأ', 'تعذر تحديث الملف الشخصي: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  @override
  void onInit() {
    super.onInit();
    // Removed _loadAuthState() from here because it is explicitly awaited
    // in AppBootstrapper.init() to ensure it finishes before the app builds.

    // Intuitive Logic: Automatically redirect based on auth state changes
    // This handles Logout, Session Expiry, and Account Deletion scenarios
    ever(_isLoggedIn, (loggedIn) {
      if (!loggedIn) {
        // If logged out and not already on public screens, go to login
        // SAFETY: Only navigate if the app is fully initialized and navigator is ready
        if (Get.currentRoute.isEmpty || Get.key.currentState == null) return;

        final currentRoute = Get.currentRoute;
        if (currentRoute != '/login' &&
            currentRoute != '/register' &&
            currentRoute != '/onboarding') {
          Get.offAllNamed('/login');
        }
      } else {
        // If logged in and on public screens, go to main
        if (Get.currentRoute.isEmpty || Get.key.currentState == null) return;

        final currentRoute = Get.currentRoute;
        if (currentRoute == '/login' ||
            currentRoute == '/register' ||
            currentRoute == '/onboarding') {
          Get.offAllNamed('/main');
        }
      }
    });

    _authSub = _authService.authStateChanges.listen((state) {
      final session = state.session;
      final user = session?.user;

      if (user != null) {
        _isLoggedIn.value = true;
        _userId.value = user.id;
        _userEmail.value = user.email ?? '';
        _userName.value = user.userMetadata?['username'] ?? '';
        _userPhoto.value = user.userMetadata?['avatar_url'] ?? '';
        // Real Supabase verification check: emailConfirmedAt is null if unverified
        needsEmailVerification.value = user.emailConfirmedAt == null && (user.email != null && user.email!.isNotEmpty);
      } else {
        needsEmailVerification.value = false;
        _isLoggedIn.value = false;
        _userId.value = '';
        _userEmail.value = '';
        _userPhoto.value = '';
        // Stop Windows background listener on logout
        WindowsBackgroundNotifier.stop();
        _stopHeartbeat();
      }
      _saveAuthState();

      // Start Windows listener or Register Web Push if logged in
      if (_userId.value.isNotEmpty) {
        _startHeartbeat();
        if (GetPlatform.isWindows) {
          WindowsBackgroundNotifier.start(_userId.value);
        }
        if (kIsWeb) {
          MessagingService.instance.registerWebPush();
        }
      }
      // Register FCM token if logged in
      if (_userId.value.isNotEmpty) {
        // Debounce token registration slightly to let network settle
        Timer(const Duration(seconds: 2), () async {
          if (MessagingService.instance.isInitialized &&
              FirebaseService.supportsMessaging) {
            try {
              final token = await FirebaseMessaging.instance.getToken();
              if (token != null) {
                final deviceId = await DeviceIdentity.getId();
                // We use our robust addFcmToken which handles duplicates automatically
                await Get.find<IUserRepository>().addFcmToken(
                  _userId.value,
                  token,
                  deviceId: deviceId,
                  platform: kIsWeb ? 'web' : Platform.operatingSystem,
                  lastUpdate: DateTime.now(),
                );
              }
            } catch (e) {
              debugPrint('Error registering FCM token: $e');
              // Optional: Retry once after delay?
            }
          }
        });
      }
    }, onError: (e) {
      debugPrint('AuthController: authStateChanges error: $e');
    });
  }

  @override
  void onClose() {
    _authSub?.cancel();
    _stopHeartbeat();
    super.onClose();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // Log initial heartbeat
    AppObservability.instance.logHeartbeat(_userId.value);

    // Set up periodic heartbeat every 5 minutes
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_userId.value.isNotEmpty) {
        AppObservability.instance.logHeartbeat(_userId.value);

        // Proactive session check: Supabase tokens usually last 1 hour.
        // If we are within 5 minutes of expiry or already expired, refresh.
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          final expiresAt =
              DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000);
          final now = DateTime.now();
          if (expiresAt.difference(now).inMinutes < 10) {
            debugPrint(
                'AuthController: Session nearing expiry or expired. Triggering proactive refresh.');
            Supabase.instance.client.auth.refreshSession().catchError((e) {
              debugPrint('AuthController: Proactive refresh failed: $e');
              return AuthResponse();
            });
          }
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // --- STAGE R: REALTIME RESILIENCE ---
  bool _isRecovering = false;
  Completer<void>? _recoveryCompleter;

  /// Centralized session recovery to prevent "Reconnection Storms"
  Future<void> recoverSession() async {
    if (_isRecovering) {
      debugPrint(
          '🛡️ AuthController: Recovery already in progress, joining...');
      return _recoveryCompleter?.future;
    }

    _isRecovering = true;
    _recoveryCompleter = Completer<void>();

    try {
      debugPrint(
          '🚀 AuthController: Initiating Centralized Session Recovery...');
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null || session.isExpired) {
        await Supabase.instance.client.auth.refreshSession();
        debugPrint('✅ AuthController: Session refreshed successfully.');
      } else {
        debugPrint('ℹ️ AuthController: Session still valid, skip refresh.');
      }
    } catch (e) {
      debugPrint('❌ AuthController: Session recovery failed: $e');
    } finally {
      _isRecovering = false;
      _recoveryCompleter?.complete();
      _recoveryCompleter = null;
    }
  }

  Future<void> loadState() async {
    await _loadAuthState();
    // Stage G3 Fix: Sync Supabase session with local state to prevent JWT Expiry issues
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || session.isExpired) {
      debugPrint(
          'AuthController: Session expired or null. Clearing local state.');
      _isLoggedIn.value = false;
      _userId.value = '';
    } else {
      _isLoggedIn.value = true;
      _userId.value = session.user.id;
    }
  }

  Future<void> _loadAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn.value = prefs.getBool(_isLoggedInKey) ?? false;
    _userId.value = prefs.getString(_userIdKey) ?? '';
    _userName.value = prefs.getString(_userNameKey) ?? '';
    _userEmail.value = prefs.getString(_userEmailKey) ?? '';
    _userPhoto.value = prefs.getString(_userPhotoKey) ?? '';
    _hasSeenOnboarding.value = prefs.getBool(_hasSeenOnboardingKey) ?? false;
  }

  Future<void> _saveAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, _isLoggedIn.value);
    await prefs.setString(_userIdKey, _userId.value);
    await prefs.setString(_userNameKey, _userName.value);
    await prefs.setString(_userEmailKey, _userEmail.value);
    await prefs.setString(_userPhotoKey, _userPhoto.value);
    await prefs.setBool(_hasSeenOnboardingKey, _hasSeenOnboarding.value);
  }

  Future<void> completeOnboarding() async {
    _hasSeenOnboarding.value = true;
    await _saveAuthState();
    unawaited(
        AnalyticsService.instance.logUserMilestone('onboarding_complete'));
  }

  Future<bool> login({required String email, required String password}) async {
    try {
      _isLoading.value = true;
      await _authService.signIn(email: email, password: password);
      unawaited(AnalyticsService.instance
          .logEvent(name: 'login', parameters: {'method': 'email'}));
      return true;
    } catch (e) {
      Get.snackbar(AppLocalizations.of(Get.context!).loginErrorTitle,
          _getAuthErrorMessage(e),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
      return false;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      _isLoading.value = true;
      final response = await _authService.signUp(
        email: email,
        password: password,
        data: {'username': name},
      );

      final user = response.user;
      if (user != null) {
        // Explicitly create profile record to ensure it is searchable immediately
        final newUser = AppUser(
          id: user.id,
          email: email,
          displayName: name,
          createdAt: DateTime.now(),
        );
        await Get.find<IUserRepository>().upsertUser(newUser);
      }

      await Get.defaultDialog(
        title: 'تحقق من بريدك الإلكتروني',
        middleText:
            'تم إرسال رابط تأكيد إلى بريدك الإلكتروني. يرجى الضغط عليه لتفعيل حسابك والتمكن من تسجيل الدخول.',
        textConfirm: 'موافق',
        confirmTextColor: Colors.white,
        onConfirm: () => Get.back(),
      );
      return true;
    } catch (e) {
      Get.snackbar(AppLocalizations.of(Get.context!).registrationErrorTitle,
          _getAuthErrorMessage(e),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
      return false;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> logout() async {
    // Stop this device from receiving the previous user's pushes. It must run
    // BEFORE signOut(), because the RPC needs the authenticated session.
    try {
      final deviceId = await DeviceIdentity.getId();
      await Supabase.instance.client
          .rpc('unregister_device_token', params: {'p_device_id': deviceId})
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('logout: unregister_device_token failed: $e');
    }
    try {
      if (MessagingService.instance.isInitialized &&
          FirebaseService.supportsMessaging) {
        await FirebaseMessaging.instance
            .deleteToken()
            .timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint('logout: deleteToken failed: $e');
    }
    await _authService.signOut();
  }

  Future<void> deleteAccount({required String password}) async {
    try {
      _isLoading.value = true;
      final email = _userEmail.value;
      if (email.isNotEmpty && password.isNotEmpty) {
        // Re-authenticate to verify identity before deletion
        await _authService.signIn(email: email, password: password);
      }

      // Invoke Supabase RPC to delete user account securely
      await Supabase.instance.client.rpc('delete_user_account');

      // Clear local caches and state
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Sign out and transition state
      await logout();

      _userId.value = '';
      _userName.value = '';
      _userEmail.value = '';
      _userPhoto.value = '';
      _isLoggedIn.value = false;

      await Get.offAllNamed('/auth/login');
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _authService.resetPassword(email);
      Get.snackbar('إعادة تعيين كلمة المرور', 'تم إرسال رابط إلى بريدك',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white);
    } catch (e) {
      Get.snackbar('خطأ', e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  Future<void> loginAsGuest() async {
    try {
      _isLoading.value = true;
      await _authService.signInAnonymously();
    } catch (e) {
      Get.snackbar('خطأ', 'تعذر تسجيل الدخول كضيف',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> resendEmailVerification() async {
    if (_userEmail.value.isEmpty) return;
    try {
      await _authService.resendOtp(_userEmail.value);
      Get.snackbar('تحقق من البريد', 'تم إعادة إرسال رمز التحقق',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white);
    } catch (e) {
      Get.snackbar('خطأ', 'تعذر إعادة إرسال الرمز: $e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  /// Helper for integration tests to set a mock user without real auth
  void setMockUser(String id, String name, String email, {String? photoUrl}) {
    _userId.value = id;
    _userName.value = name;
    _userEmail.value = email;
    if (photoUrl != null) _userPhoto.value = photoUrl;
    _isLoggedIn.value = true;
  }

  String _getAuthErrorMessage(Object e) {
    if (Get.context == null) return e.toString();
    final l10n = AppLocalizations.of(Get.context!);

    // Handle string errors or direct message access
    final String fullErrorMessage = e.toString().toLowerCase();

    // Mapping based on common Supabase/Auth keywords
    if (fullErrorMessage.contains('invalid login credentials') ||
        fullErrorMessage.contains('invalid credentials')) {
      return l10n.authErrorInvalidCredentials;
    }
    if (fullErrorMessage.contains('email not confirmed')) {
      return l10n.authErrorEmailNotConfirmed;
    }
    if (fullErrorMessage.contains('user already registered') ||
        fullErrorMessage.contains('already exists')) {
      return l10n.authErrorUserAlreadyExists;
    }
    if (fullErrorMessage.contains('rate limit') ||
        fullErrorMessage.contains('too many requests') ||
        fullErrorMessage.contains('429')) {
      return l10n.authErrorTooManyRequests;
    }

    if (e is SocketException) {
      return l10n.authErrorNetwork;
    }

    // Default to the message provided by the exception if it's an AuthException
    if (e is AuthException) {
      return e.message;
    }

    return l10n.authErrorUnknown;
  }
}
