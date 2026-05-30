import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/config/notification_channels.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/core/communication/call_notification_manager.dart';
import 'package:talkmate_ai/core/communication/communication_live_screen.dart';
import 'package:talkmate_ai/core/communication/communication_session.dart';
import 'package:talkmate_ai/data/models/chat_model.dart' as data_chat_models;
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_notification_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/data/services/firebase_service.dart';
import 'package:talkmate_ai/models/chat_model.dart' as ui_models;
import 'package:talkmate_ai/screens/chat_screen.dart';
import 'package:talkmate_ai/services/call/call_bootstrapper.dart';
import 'package:talkmate_ai/services/observability/app_observability.dart';
import 'package:talkmate_ai/utils/device_identity.dart';
import 'package:talkmate_ai/utils/web_push_interop.dart';
import 'package:talkmate_ai/widgets/notifications/in_app_heads_up.dart';

@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.enableFirebase) {
    try {
      await FirebaseService.initialize();
    } catch (_) {}
  }
  debugPrint('Background message received');
  // [STABILIZATION]: Initialize local notifications for the background isolate
  await MessageNotificationHandler._ensureInitialized();
  // [SOVEREIGN]: Emergency bootstrap if this is a call signal
  final type = message.data['type']?.toString();
  if (type == 'call' || type == 'webrtc_call' || type == 'INCOMING_CALL') {
    await CallBootstrapper.ensureReady();
  }

  try {
    await NotificationRouter.handle(message.data, source: 'background');
  } catch (e) {
    debugPrint('❌ fcmBackgroundHandler internal error: $e');
  }
}

// --- 🛰️ UNIFIED NOTIFICATION SYSTEM (STAGE X) ---

class NotificationRouter {
  // STAGE R: Production Safety Guards
  static final Set<String> _processedIds = {};
  static const Duration _duplicateWindow = Duration(minutes: 5);
  static const Duration _staleThreshold = Duration(hours: 12);

  static Future<void> handle(
    Map<String, dynamic> data, {
    required String source,
  }) async {
    final type = data['type']?.toString();
    final messageId = data['message_id']?.toString();

    // 1. Duplicate Protection
    if (messageId != null) {
      if (_processedIds.contains(messageId)) {
        debugPrint('🛡️ Duplicate notification rejected: $messageId');
        return;
      }
      _processedIds.add(messageId);
      // Auto-cleanup
      unawaited(Future.delayed(
          _duplicateWindow, () => _processedIds.remove(messageId)));
    }

    // 2. Late Delivery Protection
    if (data['meta_timestamp'] != null) {
      final sentTime = DateTime.tryParse(data['meta_timestamp'].toString());
      if (sentTime != null) {
        final age = DateTime.now().difference(sentTime);
        if (age > _staleThreshold) {
          debugPrint(
              '🛡️ Stale notification suppressed: $messageId (Age: ${age.inHours} hours)');
          return;
        }
      }
    }

    debugPrint('🔔 Router handling $type from $source');
    try {
      if (Get.isRegistered<AppObservability>()) {
        AppObservability.instance.trackNotificationReceived(messageId, source);
      }
    } catch (_) {}

    switch (type) {
      case 'message':
      case 'chat':
        final messageId = data['message_id']?.toString();
        final decision = data['decision']?.toString() ?? 'sent';

        // Ack delivery in both cases (foreground/background) to ensure DB is updated
        if (messageId != null) {
          try {
            // Only attempt ACK if Supabase is actually initialized (usually true in foreground,
            // might need explicit init if we really want it in background)
            if (Supabase.instance.client.auth.currentSession != null) {
              unawaited(MessagingService.instance.sendAck(messageId));
            }
          } catch (_) {}
        }

        if (decision == 'throttled' || decision == 'silent') {
          debugPrint('🔇 $decision message received: Silent Update Only');
          final chatId = data['chat_id']?.toString();
          if (chatId != null && Get.isRegistered<ChatController>()) {
            if (decision == 'throttled') {
              Get.find<ChatController>().incrementThrottledCount(chatId);
            }
            // For both, local state updates happen via ackDelivered/sync
          }
          return;
        }

        // 3. Smart Foreground Suppression
        final currentOpenChatId = Get.isRegistered<ChatController>()
            ? Get.find<ChatController>().activeChatId
            : null;
        final incomingChatId =
            data['chat_id']?.toString() ?? data['chatId']?.toString();

        if (source == 'foreground') {
          // Log Delivery to Analytics
          if (messageId != null) {
            try {
              if (Get.isRegistered<INotificationRepository>()) {
                unawaited(
                    Get.find<INotificationRepository>().logNotificationEvent(
                  messageId: messageId,
                  eventType: 'delivered',
                  platform:
                      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
                ));
              }
            } catch (_) {}
          }

          if (currentOpenChatId == incomingChatId) {
            debugPrint(
                '🛡️ Foreground notification suppressed (Chat is open): $incomingChatId');
            return;
          }

          MessageNotificationHandler.showForeground(data);
        } else {
          // Background/Terminated: Show System Notification
          await MessageNotificationHandler.showBackground(data);
        }
        break;

      case 'INCOMING_CALL':
        // [SOVEREIGN]: Ensure system is ready to receive signaling even in background
        await CallBootstrapper.ensureReady();

        // [NATIVE HARDENING]: Calls on Android are handled by CallForegroundService (Native).
        // Skip Flutter-side local notifications on Android to avoid duplication.
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          debugPrint('🔇 Call notification received: Handled by Native Side');
          return;
        }

        // [WINDOWS UX]: On Desktop, we rely on DB signaling for the call UI.
        // We suppress the generic "New Notification" here to avoid showing it as a message.
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.linux)) {
          debugPrint(
              '🔇 Call notification received: Suppressed on Desktop (DB Signal overrides)');
          return;
        }

        await CallNotificationHandler.show(data, source);
        break;

      default:
        debugPrint('Unknown notification type: $type');
        break;
    }
  }
}

class MessageNotificationHandler {
  static final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localPlugin.initialize(initializationSettings);

      // [STABILIZATION]: Explicitly create channels in the background isolate
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin =
            _localPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          for (final channel in NotificationChannels.all) {
            await androidPlugin.createNotificationChannel(channel);
          }
          debugPrint(
              '✅ MessageNotificationHandler: Channels created in background');
        }
      }

      _isInitialized = true;
      debugPrint('✅ MessageNotificationHandler: Plugin initialized');
    } catch (e) {
      debugPrint('❌ MessageNotificationHandler: Initialization failed: $e');
    }
  }

  static void showForeground(Map<String, dynamic> data) {
    // Stage A: Lightweight in-app alert
    final title = data['title'] ?? 'رسالة جديدة';
    final body = data['body'] ?? data['message'] ?? '';
    final chatId =
        (data['chat_id'] ?? data['chatId'] ?? data['conversation_id'] ?? '')
            .toString();

    // SMART SUPPRESSION: Avoid interrupting if user is in the SAME chat
    try {
      if (Get.isRegistered<ChatController>()) {
        final activeChatId = Get.find<ChatController>().activeChatId;
        if (chatId.isNotEmpty && chatId == activeChatId) {
          if (AppConfig.isDebugMode) {
            debugPrint(
                'MessagingService: Suppressing heads-up for active chat $chatId');
          }
          return;
        }
      }
    } catch (_) {}

    final messageId = data['message_id']?.toString();
    final reasonKey = data['meta_ai_reason']?.toString() ?? 'NORMAL_ROUTING';
    final reasonText = _getLocalizedReason(reasonKey);

    InAppHeadsUp.show(
      title: title,
      body: body,
      messageId: messageId,
      reasonText: reasonText,
      onTap: () {
        AppObservability.instance.trackNotificationTapped(messageId);
        MessagingService.instance._onMessageOpenedApp(
            RemoteMessage(data: data, from: 'foreground_banner'));
      },
    );
  }

  static String _getLocalizedReason(String key) {
    switch (key) {
      case 'AI_HIGH_RELEVANCE':
        return 'أولوية عالية مخصصة لك';
      case 'AI_LOW_RELEVANCE':
        return 'محتوى هادئ';
      case 'CRITICAL_BYPASS':
        return 'إشعار عاجل';
      case 'GOV_CHAT_EXCLUSION':
        return 'مستثنى من التصفية';
      case 'GOV_SAFE_MODE':
        return 'وصول مضمون';
      case 'FATIGUE_GUARD_TRIGGERED':
        return 'حماية من التشتت';
      case 'SYSTEM_ERROR_FALLBACK':
        return 'توصيل احتياطي';
      default:
        return 'توصيل تلقائي';
    }
  }

  static Future<void> showBackground(Map<String, dynamic> data) async {
    final chatId = (data['chat_id'] ?? data['chatId'] ?? '').toString();
    final title = data['title'] ?? 'رسالة جديدة';
    final body = data['body'] ?? data['message'] ?? '';

    if (GetPlatform.isWindows) {
      unawaited(WindowsNotifier.show(data));
    } else {
      // Android / iOS logic
      final androidDetails = AndroidNotificationDetails(
        NotificationChannels.messageChannel.id,
        NotificationChannels.messageChannel.name,
        channelDescription: NotificationChannels.messageChannel.description,
        importance: NotificationChannels.messageChannel.importance,
        priority: Priority.high,
        ticker: 'new_message',
        category: AndroidNotificationCategory.message,
      );

      final NotificationDetails details =
          NotificationDetails(android: androidDetails);
      final payload = jsonEncode(data);

      await _localPlugin.show(
        chatId.hashCode,
        title,
        body,
        details,
        payload: payload,
      );
    }
  }
}

class CallNotificationHandler {
  static Future<void> show(Map<String, dynamic> data, String source) async {
    final callId = (data['call_id'] ?? data['callId'] ?? '').toString();
    final senderId = (data['sender_id'] ?? data['senderId'] ?? '').toString();
    final senderName =
        (data['sender_name'] ?? data['senderName'] ?? 'TalkMate User')
            .toString();
    final isVideo = (data['is_video'] ?? data['isVideo']?.toString() == 'true');

    debugPrint('📞 Incoming Call via Push: $callId from $senderName');

    if (callId.isNotEmpty && senderId.isNotEmpty) {
      await CallNotificationManager.instance.showIncomingCall(
        sessionId: callId,
        senderId: senderId,
        senderName: senderName,
        isVideo: isVideo,
      );
    }
  }
}

class WindowsNotifier {
  static final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> show(Map<String, dynamic> data) async {
    try {
      final title = data['title'] ?? 'TalkMate';
      final body = data['body'] ?? data['message'] ?? '';

      const WindowsNotificationDetails winDetails =
          WindowsNotificationDetails();
      const NotificationDetails details =
          NotificationDetails(windows: winDetails);

      await _localPlugin.show(
        data.hashCode,
        title,
        body,
        details,
        payload: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('Windows Notification failed: $e');
    }
  }
}

class WindowsBackgroundNotifier {
  static RealtimeChannel? _channel;

  static void start(String userId) {
    if (!GetPlatform.isWindows) return;
    if (_channel != null) return;

    debugPrint(
        '🪟 WindowsBackgroundNotifier: Starting Realtime listener for $userId');
    final supabase = Supabase.instance.client;

    _channel =
        supabase.channel('windows_notifications_$userId').onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'messages',
              callback: (payload) async {
                if (payload.newRecord.isEmpty) return;

                final senderId = payload.newRecord['sender_id']?.toString();
                if (senderId == userId) return; // Ignore own messages

                final chatId = payload.newRecord['chat_id']?.toString();
                final content =
                    payload.newRecord['content']?.toString() ?? 'رسالة جديدة';

                // Check if app is not in foreground of this chat
                if (Get.isRegistered<ChatController>()) {
                  if (Get.find<ChatController>().activeChatId == chatId &&
                      Get.find<ChatController>().isAppInForeground) {
                    return;
                  }
                }

                // [CONSTITUTIONAL HARDENING]: Windows ignores 'call' type in Notifications.
                // Call UI is triggered via DB signaling only.
                final type = payload.newRecord['type']?.toString();
                if (type == 'call' ||
                    type == 'INCOMING_CALL' ||
                    type == 'webrtc_call') {
                  return;
                }

                // Show local notification
                await WindowsNotifier.show({
                  'title': 'TalkMate AI',
                  'body': content,
                  'chat_id': chatId,
                  'type': 'message',
                });
              },
            );

    _channel?.subscribe();
  }

  static void stop() {
    _channel?.unsubscribe();
    _channel = null;
  }
}

@pragma('vm:entry-point')
Future<String> _bgDetectPreferredLanguage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('language_code');
    if (code != null && code.isNotEmpty) return code;
  } catch (_) {}
  return 'ar';
}

class MessagingService {
  MessagingService._();
  static final MessagingService instance = MessagingService._();

  FirebaseMessaging? get _fm {
    if (!_supportsMessaging) return null;
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  bool _initialized = false;
  bool get isInitialized => _initialized;
  bool _hasSyncedThisSession =
      false; // [STABILIZATION]: Force sync once per session

  Future<void> initialize() async {
    if (_initialized) return;
    if (!_supportsMessaging) {
      debugPrint(
          'Skipping FCM setup: platform not supported for Firebase Messaging');
    } else {
      await _initializeFCM();
    }

    _initialized = true;

    // Start Windows listener if logged in (Independent of FCM)
    if (GetPlatform.isWindows && Get.isRegistered<AuthController>()) {
      final uid = Get.find<AuthController>().userId;
      if (uid.isNotEmpty) {
        WindowsBackgroundNotifier.start(uid);
      }
    }

    // Web Push Registration (Independent of FCM)
    if (kIsWeb) {
      unawaited(registerWebPush());
    }
  }

  Future<void> _initializeFCM() async {
    try {
      final fm = _fm;
      if (fm == null) return;

      // Android 13+ and iOS/macOS request permissions
      if (GetPlatform.isAndroid || GetPlatform.isIOS || GetPlatform.isMacOS) {
        // [STABILIZATION]: Explicitly use permission_handler for reliable Android 13+ support
        // We import it via full path or ensure it's available in scope
        await fm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        if (GetPlatform.isAndroid) {
          try {
            await Permission.notification.request();
          } catch (e) {
            debugPrint('Permission request error: $e');
          }
        }
      }

      // Android Notification Channel (Step 5)
      if (GetPlatform.isAndroid) {
        final flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();

        // Setup all channels from NotificationChannels config
        for (final channel in NotificationChannels.all) {
          await flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.createNotificationChannel(channel);
        }
      }

      // Foreground presentation
      await fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Listeners
      FirebaseMessaging.onMessage.listen((message) {
        NotificationRouter.handle(message.data, source: 'foreground');
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

      // Token (optional) + save to user profile when logged in
      final token = await fm.getToken();
      debugPrint('FCM token: $token');
      unawaited(_maybeSaveToken(token));

      // Listen for token refresh
      fm.onTokenRefresh.listen((t) {
        debugPrint('FCM token refreshed: $t');
        _maybeSaveToken(t);
      });
    } catch (e) {
      debugPrint('FCM initialization failed: $e');
    }
  }

  Future<void> registerWebPush() async {
    if (!kIsWeb) return;

    try {
      debugPrint('🌐 Web Push: Initializing registration flow...');
      final subscriptionJson =
          await WebPushInterop.getSubscription(AppConfig.vapidPublicKey);

      if (subscriptionJson != null && Get.isRegistered<AuthController>()) {
        final auth = Get.find<AuthController>();
        final userId = auth.userId;
        final deviceId = await DeviceIdentity.getId();

        if (userId.isNotEmpty) {
          // [STABILIZATION]: Cache check for Web Push
          final prefs = await SharedPreferences.getInstance();
          final cacheKey = 'last_web_push_sub_$userId';
          final lastSub = prefs.getString(cacheKey);

          if (subscriptionJson != lastSub) {
            final Map<String, dynamic> subMap = jsonDecode(subscriptionJson);

            await Get.find<IUserRepository>().addFcmToken(
              userId,
              'web_push_placeholder',
              deviceId: deviceId,
              platform: 'web',
              webPushSubscription: subMap,
            );

            await prefs.setString(cacheKey, subscriptionJson);
            debugPrint(
                '🌐 Web Push registration completed and cached for $userId');
          } else {
            debugPrint(
                '🌐 Web Push subscription already in sync, skipping RPC.');
          }
        }
      }
    } catch (e) {
      debugPrint('🌐 Web Push registration failed: $e');
    }
  }

  Future<void> sendAck(String messageId) async {
    try {
      final deviceId = await DeviceIdentity.getId();
      final supabase = Supabase.instance.client;

      await supabase.from('message_delivery').upsert({
        'message_id': messageId,
        'device_id': deviceId,
        'status': 'delivered',
        'delivered_at': DateTime.now().toIso8601String(),
      }, onConflict: 'message_id, device_id');
      debugPrint('ACK Delivered sent for message: $messageId');
    } catch (e) {
      debugPrint('Failed to send Delivery ACK: $e');
    }
  }

  static const _callIntentChannel =
      MethodChannel('com.example.talkmate_ai/call_intent');

  /// Check if the app was opened from a terminated state by tapping an FCM notification
  /// and navigate accordingly (chat/call). Should be called once after initialization.
  Future<void> handleInitialMessageIfAny() async {
    if (GetPlatform.isWindows || GetPlatform.isLinux) return;
    try {
      // 1. Check for standard FCM initial message
      final msg = await FirebaseMessaging.instance.getInitialMessage();
      if (msg != null) {
        await _onMessageOpenedApp(msg);
        return;
      }

      // 2. [NATIVE HARDENING]: Check for our custom Call Intent (Native Data-only Push)
      if (GetPlatform.isAndroid) {
        final Map<dynamic, dynamic>? callData =
            await _callIntentChannel.invokeMapMethod('getCallIntent');

        if (callData != null && callData['callId'] != null) {
          debugPrint(
              '🚀 App opened via Native Call Intent: ${callData['callId']}');
          final route = callData['route']?.toString() ?? '/call_ringing';

          if (route == '/call_ringing') {
            unawaited(Get.offAllNamed('/call_ringing', arguments: {
              'callId': callData['callId'],
              'otherId': callData['otherId'],
              'isIncoming': callData['isIncoming'] ?? true,
              'isVideo': callData['isVideo'] ?? false,
            }));
          }
        }
      }
    } catch (e) {
      debugPrint('handleInitialMessageIfAny failed: $e');
    }
  }

  // Placeholder for internal listeners if needed

  Future<void> _onMessageOpenedApp(RemoteMessage message) async {
    try {
      final data = message.data;
      final messageId = data['message_id']?.toString();

      // Log Opened Event to Analytics
      if (messageId != null) {
        final userId = Get.find<AuthController>().userId;
        unawaited(Get.find<INotificationRepository>().reportInteractionSignal(
          userId: userId,
          signalType: 'click',
          messageId: messageId,
        ));
        unawaited(Get.find<INotificationRepository>().logNotificationEvent(
          messageId: messageId,
          eventType: 'opened',
          platform: kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
        ));
      }

      final deepLink = (data['deep_link'] ?? '').toString();
      if (deepLink.isNotEmpty) {
        // Handle deep link formats like talkmate://chat/<id> or talkmate://call/<id>
        if (deepLink.startsWith('talkmate://call/')) {
          final id = deepLink.substring('talkmate://call/'.length);
          if (id.isNotEmpty) {
            unawaited(Get.offAll(() => CommunicationLiveScreen(
                  sessionId: id,
                  type: CommunicationSessionType.call,
                )));
            return;
          }
        } else if (deepLink.startsWith('talkmate://webrtc_call/')) {
          final id = deepLink.substring('talkmate://webrtc_call/'.length);
          if (id.isNotEmpty) {
            unawaited(Get.offAll(() => CommunicationLiveScreen(
                  sessionId: id,
                  type: CommunicationSessionType.call,
                )));
            return;
          }
        } else if (deepLink.startsWith('talkmate://chat/')) {
          final id = deepLink.substring('talkmate://chat/'.length);
          if (id.isNotEmpty) {
            try {
              final data_chat_models.Chat? dc =
                  await Get.find<IChatRepository>().getById(id);
              if (dc != null) {
                final ui = ui_models.ChatModel(
                  id: dc.id,
                  name: dc.isGroup ? (dc.groupName ?? '') : '',
                  participantIds: dc.participantIds,
                  type: dc.isGroup
                      ? ui_models.ChatType.group
                      : ui_models.ChatType.individual,
                );
                unawaited(Get.offAll(() => ChatScreen(chat: ui)));
                return;
              }
            } catch (_) {}
            final chat = ui_models.ChatModel(
                id: id, name: data['chatName'] ?? '', participantIds: const []);
            unawaited(Get.offAll(() => ChatScreen(chat: chat)));
            return;
          }
        }
      }
      final type = (data['type'] ?? '').toString();
      if (type == 'call') {
        final callId = (data['callId'] ?? '').toString();

        if (callId.isNotEmpty) {
          unawaited(Get.offAll(() => CommunicationLiveScreen(
                sessionId: callId,
                type: CommunicationSessionType.call,
              )));
          return;
        }
      }
      final chatId =
          (data['chat_id'] ?? data['chatId'] ?? data['conversationId'] ?? '')
              .toString();
      if (chatId.isNotEmpty) {
        try {
          final data_chat_models.Chat? dc =
              await Get.find<IChatRepository>().getById(chatId);
          if (dc != null) {
            final ui = ui_models.ChatModel(
              id: dc.id,
              name: dc.isGroup ? (dc.groupName ?? '') : '',
              participantIds: dc.participantIds,
              type: dc.isGroup
                  ? ui_models.ChatType.group
                  : ui_models.ChatType.individual,
            );
            unawaited(Get.offAll(() => ChatScreen(chat: ui)));
            return;
          }
        } catch (_) {}
        final chat = ui_models.ChatModel(
            id: chatId,
            name: data['title'] ?? 'TalkMate',
            participantIds: const []);
        unawaited(Get.offAll(() => ChatScreen(chat: chat)));
      } else {
        debugPrint('Message opened app but chat_id missing');
      }
    } catch (e) {
      debugPrint('onMessageOpenedApp navigation failed: $e');
    }
  }

  static Future<void> ackDelivered(String messageId) async {
    try {
      final deviceId = await DeviceIdentity.getId();
      final supabase = Supabase.instance.client;
      // Resolve user_id if possible
      String? userId;
      try {
        if (Get.isRegistered<AuthController>()) {
          userId = Get.find<AuthController>().userId;
        }
      } catch (_) {}

      // If no user_id, we can't properly log to a table that requires it
      if (userId == null || userId.isEmpty) return;

      await supabase.from('message_delivery').update({
        'status': 'delivered',
        'delivered_at': DateTime.now().toIso8601String(),
        'user_id': userId,
      }).match({
        'message_id': messageId,
        'device_id': deviceId,
      });
      debugPrint('ACK Delivered sent for message: $messageId');
    } catch (e) {
      debugPrint('Failed to send Delivery ACK: $e');
    }
  }

  bool get _supportsMessaging => FirebaseService.supportsMessaging;

  // Save FCM token to the user's document when available
  Future<void> _maybeSaveToken(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      if (Get.isRegistered<AuthController>()) {
        final auth = Get.find<AuthController>();
        final uid = auth.userId;
        if (uid.isNotEmpty) {
          final deviceId = await DeviceIdentity.getId();

          // [STABILIZATION]: Use local cache to prevent redundant RPC calls
          final prefs = await SharedPreferences.getInstance();
          final cacheKey = 'last_fcm_token_$uid';
          final lastToken = prefs.getString(cacheKey);

          final currentToken = await _fm?.getToken();
          final effectiveToken = currentToken ?? token;

          // [STABILIZATION]: Force sync on startup (ignore cache once per session)
          final shouldForceSync = !_hasSyncedThisSession;

          if (effectiveToken.isNotEmpty &&
              (shouldForceSync || effectiveToken != lastToken)) {
            debugPrint(
                '🛰️ MessagingService: Starting sync (Force: $shouldForceSync)');

            await Get.find<IUserRepository>().addFcmToken(
              uid,
              effectiveToken,
              deviceId: deviceId,
              platform:
                  kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
              lastUpdate: DateTime.now(),
            );

            await prefs.setString(cacheKey, effectiveToken);
            _hasSyncedThisSession = true;
            debugPrint('✅ Token synced and cached for $uid');
          } else {
            debugPrint(
                'ℹ️ Token already in sync for $uid (Session Synced: $_hasSyncedThisSession)');
          }
        }
      }
    } catch (e) {
      debugPrint('Save FCM token failed: $e');
    }
  }
}
