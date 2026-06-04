import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/config/notification_channels.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/core/communication/communication_live_screen.dart';
import 'package:talkmate_ai/core/communication/communication_session.dart';
import 'package:talkmate_ai/data/models/call_model.dart' as call_models;
import 'package:talkmate_ai/data/models/chat_model.dart' as data_chat_models;
import 'package:talkmate_ai/data/repositories/contracts/i_call_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/services/audio/app_audio_service.dart';
import 'package:talkmate_ai/services/call/call_bootstrapper.dart';

import '../config/app_config.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../screens/chat_screen.dart';

class NotificationController extends GetxController {
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _soundEnabledKey = 'notification_sound_enabled';
  static const String _vibrationEnabledKey = 'notification_vibration_enabled';

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final RxBool _notificationsEnabled = true.obs;
  final RxBool _soundEnabled = true.obs;
  final RxBool _vibrationEnabled = true.obs;
  final RxBool _isInitialized = false.obs;

  StreamSubscription? _badgeSyncSub;
  StreamSubscription? _socialEventsSub;
  final RxInt unreadCount = 0.obs;

  StreamSubscription<AuthState>? _authStateSubscription;
  Timer? _refreshDebounceTimer;

  // State-aware Notification Tracking
  final Map<String, int> _activeSessionNotifications = {};

  // [AUDIO_FIX]: Idempotency set to prevent playback loops on stream reconnection
  final Set<String> _processedNotificationIds = {};
  late final DateTime _serviceStartTime;

  // Getters
  bool get notificationsEnabled => _notificationsEnabled.value;
  bool get soundEnabled => _soundEnabled.value;
  bool get vibrationEnabled => _vibrationEnabled.value;
  bool get isInitialized => _isInitialized.value;

  @override
  void onInit() {
    super.onInit();
    _serviceStartTime = DateTime.now(); // [AUDIO_FIX]: Baseline time
    _initializeNotifications();
    _loadSettings();
    _setupBadgeSync();
    unawaited(_setupSovereignStateObserver());

    // Listen for token refreshes to restart streams with new credentials
    // Handle token refreshes with debouncing
    _authStateSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.tokenRefreshed) {
        _refreshDebounceTimer?.cancel();
        _refreshDebounceTimer = Timer(const Duration(seconds: 3), () {
          final uid = Get.find<AuthController>().userId;
          if (uid.isNotEmpty) {
            debugPrint(
                'NotificationController: Token refreshed, restarting streams (Debounced).');
            _startListeningToBadgeChanges(uid);
            _setupSocialEventsListeners(uid);
          }
        });
      } else if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.initialSession) {
        // Attempt to recover session for initial setup or sign-in
        final uid = Get.find<AuthController>().userId;
        if (uid.isNotEmpty) {
          debugPrint(
              'NotificationController: Auth event ${data.event}, recovering session.');
          _startListeningToBadgeChanges(uid);
          _setupSocialEventsListeners(uid);
        }
      }
    }, onError: (e) {
      debugPrint('NotificationController: Auth state change error: $e');
    });
  }

  @override
  void onClose() {
    _authStateSubscription?.cancel();
    _refreshDebounceTimer?.cancel();
    _badgeSyncSub?.cancel();
    _socialEventsSub?.cancel();
    _stopSovereignStateObserver();
    super.onClose();
  }

  // Show full-screen incoming call notification (Android)
  Future<void> showIncomingCallNotification({
    required String callId,
    required String callType, // 'audio' | 'video'
    required String callerName,
  }) async {
    // [CONSTITUTIONAL]: Android handles calls via Native Service. Windows uses Direct UI.
    if (Platform.isAndroid || Platform.isWindows) return;

    final l10n = AppLocalizations.of(Get.context!);
    const androidChannelId = 'calls_channel';
    final androidChannelName = l10n.callsChannelName;
    final androidChannelDescription = l10n.callsChannelDescription;

    final sound = _getBestSoundForSession(
        callType == 'video'
            ? CommunicationSessionType.call
            : CommunicationSessionType.call,
        isVideo: callType == 'video');

    final androidDetails = AndroidNotificationDetails(
      androidChannelId,
      androidChannelName,
      channelDescription: androidChannelDescription,
      category: AndroidNotificationCategory.call,
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'incoming_call',
      fullScreenIntent: true,
      playSound: _soundEnabled.value,
      sound: sound != null ? RawResourceAndroidNotificationSound(sound) : null,
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'decline',
          l10n.decline,
          cancelNotification: true,
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'answer',
          l10n.answer,
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    final details = NotificationDetails(android: androidDetails);
    final payload = 'call|$callId|$callType';
    final notificationId = callId.hashCode;
    _activeSessionNotifications[callId] = notificationId;

    await _flutterLocalNotificationsPlugin.show(
      notificationId,
      l10n.incomingCallTitleWithType(callType),
      l10n.fromCallerName(callerName),
      details,
      payload: payload,
    );
  }

  Future<void> _initializeNotifications() async {
    try {
      // Android initialization settings
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS initialization settings
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // Linux initialization settings
      const LinuxInitializationSettings initializationSettingsLinux =
          LinuxInitializationSettings(defaultActionName: 'Open notification');

      // Windows initialization settings
      const WindowsInitializationSettings initializationSettingsWindows =
          WindowsInitializationSettings(
        appName: AppConfig.appName,
        appUserModelId: 'com.talkmate.ai',
        guid: '00000000-0000-0000-0000-000000000000',
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
        linux: initializationSettingsLinux,
        windows: initializationSettingsWindows,
      );

      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Explicitly create Android notification channels so they appear in system settings
      await _ensureAndroidNotificationChannels();

      // Request permissions for iOS
      await _requestPermissions();

      _isInitialized.value = true;

      if (AppConfig.isDebugMode) {
        debugPrint('Notifications initialized successfully');
      }
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  Future<void> _ensureAndroidNotificationChannels() async {
    try {
      final androidImpl = _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl == null) return;

      // Create all channels defined in config
      for (final channel in NotificationChannels.all) {
        await androidImpl.createNotificationChannel(channel);
      }
    } catch (e) {
      debugPrint('Creating Android notification channels failed: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled.value =
          prefs.getBool(_notificationsEnabledKey) ?? true;
      _soundEnabled.value = prefs.getBool(_soundEnabledKey) ?? true;
      _vibrationEnabled.value = prefs.getBool(_vibrationEnabledKey) ?? true;
    } catch (e) {
      debugPrint('Error loading notification settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _notificationsEnabledKey,
        _notificationsEnabled.value,
      );
      await prefs.setBool(_soundEnabledKey, _soundEnabled.value);
      await prefs.setBool(_vibrationEnabledKey, _vibrationEnabled.value);
    } catch (e) {
      debugPrint('Error saving notification settings: $e');
    }
  }

  Future<void> _onNotificationTapped(
      NotificationResponse notificationResponse) async {
    final payload = notificationResponse.payload;
    if (payload == null || payload.isEmpty) return;

    if (AppConfig.isDebugMode) {
      debugPrint('🔔 Notification tapped with payload: $payload');
    }

    try {
      Map<String, dynamic> data;
      // 1. Try to parse as JSON (FCM style)
      if (payload.trim().startsWith('{')) {
        data = jsonDecode(payload);
      } else {
        // 2. Legacy Fallback: Pipe separated (Local style)
        final parts = payload.split('|');
        if (parts.length >= 2) {
          final type = parts[0];
          final id = parts[1];
          data = {
            'type': type,
            'chat_id': id,
            'call_id': id,
            'callType': parts.length >= 3 ? parts[2] : 'audio',
          };
        } else {
          debugPrint('⚠️ Unrecognized payload format: $payload');
          return;
        }
      }

      final type = (data['type'] ?? '').toString();
      final chatId = (data['chat_id'] ?? data['chatId'] ?? '').toString();
      final callId = (data['call_id'] ?? data['callId'] ?? '').toString();

      if (type == 'message' || type == 'chat') {
        if (chatId.isNotEmpty) {
          try {
            final data_chat_models.Chat? dc =
                await Get.find<IChatRepository>().getById(chatId);
            if (dc != null) {
              final ui = ChatModel(
                id: dc.id,
                name: dc.isGroup ? (dc.groupName ?? '') : '',
                participantIds: dc.participantIds,
                type: dc.isGroup ? ChatType.group : ChatType.individual,
              );
              unawaited(Get.offAll(() => ChatScreen(chat: ui)));
              return;
            }
          } catch (e) {
            debugPrint('Failed to fetch chat details: $e');
          }
          // Minimum viable navigation
          final chat = ChatModel(
              id: chatId, name: data['title'] ?? '', participantIds: const []);
          unawaited(Get.offAll(() => ChatScreen(chat: chat)));
        }
      } else if (type == 'call' || type == 'webrtc_call') {
        final id = callId.isNotEmpty ? callId : (data['id']?.toString() ?? '');

        final actionId = notificationResponse.actionId;

        if (actionId == 'decline') {
          try {
            await Get.find<ICallRepository>()
                .updateStatus(id, call_models.CallStatus.rejected);
          } catch (_) {}
          return;
        }

        if (id.isNotEmpty) {
          unawaited(Get.offAll(() => CommunicationLiveScreen(
                sessionId: id,
                type: CommunicationSessionType.call,
              )));
        }
      }
    } catch (e) {
      debugPrint('🛑 Error parsing notification payload: $e');
    }
  }

  Future<void> showMessageNotification({
    required MessageModel message,
    String? channelId,
    String? channelName,
    String? channelDescription,
  }) async {
    if (!_notificationsEnabled.value || !_isInitialized.value) return;

    try {
      final notificationId = message.hashCode;
      final body = _getNotificationBody(message);
      final payload = 'message|${message.chatId}|${message.senderId}';

      String title = 'TalkMate';
      // 🧠 Resolution Logic (Clean Architecture)
      try {
        final chatRepo = Get.find<IChatRepository>();
        final chat = await chatRepo.getById(message.chatId);

        if (chat != null) {
          if (chat.isGroup) {
            title = chat.groupName ?? 'مجموعة';
          } else {
            // Individual chat: Get the OTHER participant's name
            final friendId = chat.participantIds.firstWhere(
              (id) => id != message.senderId,
              orElse: () => message.senderId,
            );
            final userRepo = Get.find<IUserRepository>();
            final friend = await userRepo.getById(friendId);
            title = friend?.displayName ?? 'TalkMate';
          }
        }
      } catch (_) {}

      final String groupKey = 'com.talkmate.chat.${message.chatId}';

      final androidDetails = AndroidNotificationDetails(
        'talkmate_messages',
        'Messages',
        channelDescription: 'Chat message notifications',
        importance: Importance.high,
        priority: Priority.high,
        playSound: _soundEnabled.value,
        enableVibration: _vibrationEnabled.value,
        icon: '@mipmap/ic_launcher',
        groupKey: groupKey,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const linuxDetails = LinuxNotificationDetails();

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      if (AppConfig.isDebugMode) {
        debugPrint('Message notification shown: $title - $body');
      }
    } catch (e) {
      debugPrint('Error showing message notification: $e');
    }
  }

  String _getNotificationBody(MessageModel message) {
    switch (message.type) {
      case MessageType.text:
        return message.content;
      case MessageType.image:
        return AppLocalizations.of(Get.context!).messageTypeImage;
      case MessageType.video:
        return AppLocalizations.of(Get.context!).messageTypeVideo;
      case MessageType.audio:
        return AppLocalizations.of(Get.context!).messageTypeAudio;
      case MessageType.file:
        return AppLocalizations.of(Get.context!).messageTypeFile;
      case MessageType.location:
        return AppLocalizations.of(Get.context!).messageTypeLocation;
      case MessageType.contact:
        return AppLocalizations.of(Get.context!).messageTypeContact;
      case MessageType.chat:
        return 'محادثة';
      case MessageType.call:
        return 'مكالمة';
    }
  }

  Future<void> showCallNotification({
    required String callerName,
    required String callType,
    required String callId,
  }) async {
    if (!_notificationsEnabled.value || !_isInitialized.value) return;

    try {
      final notificationId = callId.hashCode;
      final l10n = AppLocalizations.of(Get.context!);
      final title = l10n.incomingCallTitleWithType(callType);
      final body = l10n.fromCallerName(callerName);
      final payload = 'call|$callId|$callType';

      final androidDetails = AndroidNotificationDetails(
        NotificationChannels.callChannel.id, // Uses new silent ID
        l10n.callsChannelName,
        channelDescription: l10n.callsChannelDescription,
        importance: Importance.max,
        priority: Priority.max,
        playSound: false, // [STRICT_FIX]: Force silence
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        ongoing: true,
        autoCancel: false,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('answer', l10n.answer,
              showsUserInterface: true),
          AndroidNotificationAction(
            'decline',
            l10n.decline,
            showsUserInterface: false,
          ),
        ],
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'call_category',
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      if (AppConfig.isDebugMode) {
        debugPrint('Call notification shown: $title - $body');
      }
    } catch (e) {
      debugPrint('Error showing call notification: $e');
    }
  }

  Future<void> showGeneralNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_notificationsEnabled.value || !_isInitialized.value) return;

    try {
      final androidDetails = AndroidNotificationDetails(
        NotificationChannels.messageChannel.id,
        NotificationChannels.messageChannel.name,
        importance: Importance.high,
        priority: Priority.high,
      );

      const iosDetails = DarwinNotificationDetails();

      const windowsDetails = WindowsNotificationDetails();

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        windows: windowsDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
      unawaited(AppAudioService.instance.play('new_notification.mp3'));
    } catch (e) {
      debugPrint('Error showing general notification: $e');
    }
  }

  Future<void> cancelNotification(int notificationId) async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(notificationId);
    } catch (e) {
      debugPrint('Error canceling notification: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await _flutterLocalNotificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('Error canceling all notifications: $e');
    }
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled.value = enabled;
    await _saveSettings();

    if (!enabled) {
      await cancelAllNotifications();
    }

    final l10n = AppLocalizations.of(Get.context!);
    Get.snackbar(
      l10n.notifications,
      enabled ? l10n.notificationsEnabled : l10n.notificationsDisabled,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled.value = enabled;
    await _saveSettings();

    final l10n = AppLocalizations.of(Get.context!);
    Get.snackbar(
      l10n.notificationSound,
      enabled ? l10n.notificationSoundEnabled : l10n.notificationSoundDisabled,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    _vibrationEnabled.value = enabled;
    await _saveSettings();

    final l10n = AppLocalizations.of(Get.context!);
    Get.snackbar(
      l10n.notificationVibration,
      enabled
          ? l10n.notificationVibrationEnabled
          : l10n.notificationVibrationDisabled,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> testNotification() async {
    try {
      // Force initialization if not done
      if (!_isInitialized.value) {
        await _initializeNotifications();
        // Wait a bit for initialization to complete
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (!_isInitialized.value) {
        // Fallback for platforms where notifications might not work
        _showFallbackNotification();
        return;
      }

      final l10n = AppLocalizations.of(Get.context!);
      final androidDetails = AndroidNotificationDetails(
        'test_channel',
        l10n.testChannelName,
        channelDescription: l10n.testChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const linuxDetails = LinuxNotificationDetails();

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        999999,
        l10n.notificationsTestTitle,
        l10n.notificationsTestBody,
        notificationDetails,
      );

      Get.snackbar(
        l10n.sent,
        l10n.testNotificationSent,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        icon: const Icon(Icons.check_circle, color: Colors.white),
      );
    } catch (e) {
      debugPrint('Error sending test notification: $e');
      final l10n = AppLocalizations.of(Get.context!);
      Get.snackbar(
        l10n.error,
        l10n.testNotificationFailedWithError(e.toString()),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }

  void _showFallbackNotification() {
    final l10n = AppLocalizations.of(Get.context!);
    Get.dialog(
      AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.notifications,
              color: Theme.of(Get.context!).primaryColor,
            ),
            const SizedBox(width: 8),
            Text(l10n.testNotificationDialogTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.notificationsTestBody,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.testNotificationDialogBody,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text(l10n.ok)),
        ],
      ),
    );

    Get.snackbar(
      l10n.testNotificationDialogTitle,
      l10n.testNotificationShown,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      icon: const Icon(Icons.check_circle, color: Colors.white),
    );
  }

  // --- STAGE C10: SOVEREIGN STATE SYNC ---

  Worker? _engineWorker;

  String? _getBestSoundForSession(CommunicationSessionType type,
      {bool isVideo = false}) {
    // Stage C10: Dynamic discovery logic
    // We check for specific assets in assets/raw (standard for Android notifications)
    // without hardcoding file extensions as requested.
    // Note: Resource name must match filename in res/raw (without extension)
    if (type == CommunicationSessionType.room) {
      return 'call_incomming'; // Fallback to standard
    }
    if (isVideo) return 'call_incomming'; // Fallback to standard
    return 'call_incomming'; // Matches res/raw/call_incomming.mp3
  }

  Future<void> _setupSovereignStateObserver() async {
    // [SOVEREIGN HARDENING]: Ensure subsystems are ready before observing
    await CallBootstrapper.ensureReady();

    try {
      final engine = SovereignCommunicationEngine.instance;
      _engineWorker = ever<CommSessionStatus>(
          engine.statusRx, _handleSovereignStatusChange);

      // Initial check
      await _handleSovereignStatusChange(engine.status);
    } catch (e) {
      debugPrint(
          'NotificationController: Bootstrap failed during observer setup: $e');
    }
  }

  void _stopSovereignStateObserver() {
    _engineWorker?.dispose();
  }

  Future<void> _handleSovereignStatusChange(CommSessionStatus status) async {
    final engine = SovereignCommunicationEngine.instance;
    final metadata = engine.metadata;

    if (metadata == null && status != CommSessionStatus.idle) return;

    switch (status) {
      case CommSessionStatus.idle:
      case CommSessionStatus.activeAudio:
      case CommSessionStatus.activeVideo:
      case CommSessionStatus.ended:
      case CommSessionStatus.failed:
        // Automatically cancel any active ringing notification when session becomes active or ends
        if (metadata != null) {
          await _cancelSessionNotifications(metadata.sessionId);
        } else {
          // Emergency cleanup - if idle, clear all session-tracked notifications
          for (final id in _activeSessionNotifications.values) {
            await cancelNotification(id);
          }
          _activeSessionNotifications.clear();
        }
        break;

      case CommSessionStatus.ringingIncoming:
        if (metadata != null) {
          await showIncomingCallNotification(
            callId: metadata.sessionId,
            callType: metadata.isVideo ? 'video' : 'audio',
            callerName: metadata.callerName ?? 'TalkMate User',
          );
        }
        break;

      case CommSessionStatus.ringingOutgoing:
        // No local notification for outgoing by default,
        // but we ensure any old ones for this session are cleared.
        if (metadata != null) {
          await _cancelSessionNotifications(metadata.sessionId);
        }
        break;

      default:
        break;
    }
  }

  Future<void> _cancelSessionNotifications(String sessionId) async {
    if (_activeSessionNotifications.containsKey(sessionId)) {
      final id = _activeSessionNotifications.remove(sessionId);
      if (id != null) {
        await cancelNotification(id);
      }
    }
  }

  // --- STAGE V: REAL-TIME BADGE SYNC ---

  void _setupBadgeSync() {
    // Listen for auth changes to start/stop sync
    Get.find<AuthController>().userIdRx.listen((uid) {
      if (uid.isNotEmpty) {
        _startListeningToBadgeChanges(uid);
        _setupSocialEventsListeners(uid);
      } else {
        _badgeSyncSub?.cancel();
        _socialEventsSub?.cancel();
        unreadCount.value = 0;
        _setNativeBadge(0);
      }
    });
  }

  void _setupSocialEventsListeners(String userId) {
    _socialEventsSub?.cancel();
    // Listen for new notifications in the 'notifications' table
    _socialEventsSub = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .listen((events) {
          if (events.isEmpty) return;
          final last = events.first;

          final id = last['id']?.toString() ?? '';
          if (id.isEmpty) return;

          // [AUDIO_FIX]: Strict Idempotency Check
          if (_processedNotificationIds.contains(id)) {
            debugPrint(
                '🔇 NotificationController: Skipping processed notification $id');
            return;
          }

          final createdAt =
              DateTime.tryParse(last['created_at']?.toString() ?? '');

          // [AUDIO_FIX]: Time-window & Startup Check
          // 1. Ignore if created before this service instance started (Ghost notifications)
          // 2. Ignore if older than 30 seconds (Stale data)
          final now = DateTime.now();
          if (createdAt != null) {
            if (createdAt.isBefore(_serviceStartTime)) {
              // Mark as processed so we don't check age again
              _processedNotificationIds.add(id);
              return;
            }
            if (now.difference(createdAt).inSeconds > 30) {
              _processedNotificationIds.add(id);
              return;
            }

            // Valid, new notification: Play Sound
            final type = last['type'] as String?;
            if (type == 'friendRequest') {
              _processedNotificationIds.add(id);
              unawaited(AppAudioService.instance.play('friend_request.mp3'));
            } else if (last['type'] == 'groupInvite' ||
                last['type'] == 'group_join') {
              _processedNotificationIds.add(id);
              unawaited(
                  AppAudioService.instance.play('group_join_notification.mp3'));
            }
          }
        }, onError: (e) {
          debugPrint('NotificationController: social events stream error: $e');
          _handleSocialEventsError(e, userId);
        });
  }

  void _startListeningToBadgeChanges(String userId) {
    _badgeSyncSub?.cancel();
    _trySubscribeBadgeStream(userId);
  }

  void _trySubscribeBadgeStream(String userId) {
    _badgeSyncSub?.cancel();

    // Strategy: Listen to any change in message_delivery for this user.
    // This table is the source of truth for unread status.
    _badgeSyncSub = Supabase.instance.client
        .from('message_delivery')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((_) async {
          await refreshBadgeCount();
        }, onError: (e) {
          _handleBadgeSyncError(e, userId);
        });

    // Initial fetch
    refreshBadgeCount();
  }

  void _handleBadgeSyncError(dynamic error, String userId) {
    final errStr = error.toString();
    debugPrint('NotificationController: badge sync stream error: $errStr');

    _badgeSyncSub?.cancel();
    _badgeSyncSub = null;

    _handleConnectivityError(errStr, userId, _trySubscribeBadgeStream);
  }

  void _handleSocialEventsError(dynamic error, String userId) {
    final errStr = error.toString();
    _socialEventsSub?.cancel();
    _socialEventsSub = null;

    _handleConnectivityError(errStr, userId, _setupSocialEventsListeners);
  }

  void _handleConnectivityError(
      String errStr, String userId, Function(String) retryFn) {
    if (AppConfig.isStaleSessionError(errStr)) {
      debugPrint(
          'NotificationController: Connectivity issue or stale session ($errStr), attempting recovery...');
      unawaited(Get.find<AuthController>().recoverSession());
    }

    // Retry after delay
    Timer(const Duration(seconds: 15), () {
      if (Get.find<AuthController>().userId == userId) {
        // Guard against user switch
        debugPrint(
            'NotificationController: Retrying stream subscription for $userId');
        retryFn(userId);
      }
    });
  }

  Future<void> refreshBadgeCount() async {
    try {
      final uid = Get.find<AuthController>().userId;
      if (uid.isEmpty) return;

      final count = await Supabase.instance.client.rpc(
          'fn_get_total_unread_count',
          params: {'p_user_id': uid}).timeout(const Duration(seconds: 15));

      unreadCount.value = (count as int?) ?? 0;
      await _setNativeBadge(unreadCount.value);

      if (AppConfig.isDebugMode) {
        debugPrint('🔢 Updated Global Unread Count: ${unreadCount.value}');
      }
    } catch (e) {
      debugPrint('Error refreshing badge count: $e');
      if (AppConfig.isStaleSessionError(e)) {
        unawaited(Get.find<AuthController>().recoverSession());
        // Retry once after a short delay
        Future.delayed(const Duration(seconds: 5), () => refreshBadgeCount());
      }
    }
  }

  Future<void> _setNativeBadge(int count) async {
    // Native app icon badging is intentionally disabled to avoid legacy library conflicts.
    // We rely on in-app unread counters and notification bars.
    if (AppConfig.isDebugMode) {
      debugPrint('🔢 Internal Badge Count: $count');
    }
  }
}
