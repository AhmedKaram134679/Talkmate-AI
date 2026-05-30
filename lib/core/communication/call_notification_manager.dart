import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart' as callkit;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/core/communication/communication_controller.dart';
import 'package:talkmate_ai/services/audio/app_audio_service.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';
import 'package:window_manager/window_manager.dart';

class CallNotificationManager {
  static final CallNotificationManager instance = CallNotificationManager._();
  CallNotificationManager._();

  final FlutterLocalNotificationsPlugin localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // Basic initialization
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open');

    const windowsSettings = WindowsInitializationSettings(
      appName: AppConfig.appName,
      appUserModelId: 'com.talkmate.ai',
      guid: '00000000-0000-0000-0000-000000000000',
    );

    await localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    // Central CallKit Event Listener
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent);
    }
  }

  void _onCallKitEvent(callkit.CallEvent? event) {
    if (event == null) return;
    final callkit.Event eventType = event.event;
    debugPrint('📞 CallKit Event: $eventType');
    switch (eventType) {
      case callkit.Event.actionCallAccept:
        final sessionId = event.body['id']?.toString();
        debugPrint('[NOTIF] Accept action received (CallKit) for $sessionId');
        unawaited(AppAudioService.instance.stop('call_ringtone.mp3'));
        unawaited(AppAudioService.instance.stop('call_incomming.mp3'));
        unawaited(CallManager.instance.acceptCall(callId: sessionId));
        break;
      case callkit.Event.actionCallDecline:
        if (Get.isRegistered<CommunicationController>()) {
          Get.find<CommunicationController>().declineCall();
        }
        break;
      case callkit.Event.actionCallEnded:
        if (Get.isRegistered<CommunicationController>()) {
          Get.find<CommunicationController>().leaveSession();
        }
        break;
      default:
        break;
    }
  }

  static void _onNotificationResponse(NotificationResponse details) {
    debugPrint('🔔 Notification Tapped: ${details.payload}');
    if (details.payload != null) {
      _handleAction(details.payload!, details.actionId);
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse details) {
    debugPrint('🔔 Background Notification Tapped: ${details.payload}');
    if (details.payload != null) {
      _handleAction(details.payload!, details.actionId);
    }
  }

  static Future<void> _handleAction(String payload, String? actionId) async {
    // Ensure window is shown/focused on Desktop
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await windowManager.show();
      await windowManager.focus();
    }

    // payload is the senderId
    if (actionId == 'accept') {
      debugPrint('[NOTIF] Accept action received (Local Notification)');
      debugPrint('[CALL] acceptCall invoked from notification');
      unawaited(AppAudioService.instance.stop('call_ringtone.mp3'));
      unawaited(AppAudioService.instance.stop('call_incomming.mp3'));
      await CallManager.instance.acceptCall();
    } else if (actionId == 'decline') {
      unawaited(AppAudioService.instance.stop('call_ringtone.mp3'));
      unawaited(AppAudioService.instance.stop('call_incomming.mp3'));
      if (Get.isRegistered<CommunicationController>()) {
        await Get.find<CommunicationController>().declineCall();
      }
    } else {
      // Just tap - open app (Already handled by windowManager.show() above)
    }
  }

  Future<void> showIncomingCall({
    required String sessionId,
    required String senderId,
    required String senderName,
    String? avatar,
    bool isVideo = false,
  }) async {
    // [CONSTITUTIONAL]: Block Android from CallKit (uses Native Service)
    if (Platform.isIOS) {
      final params = callkit.CallKitParams(
        id: sessionId,
        nameCaller: senderName,
        appName: 'TalkMate AI',
        avatar: avatar,
        handle: senderId,
        type: isVideo ? 1 : 0,
        duration: 30000,
        textAccept: 'Accept',
        textDecline: 'Decline',
        missedCallNotification: const callkit.NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed call',
          callbackText: 'Call back',
        ),
        extra: <String, dynamic>{'userId': senderId},
        android: const callkit.AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath:
              null, // [FIX]: Disable system ringtone for Android parity
          backgroundColor: '#09121C',
          actionColor: '#4CAF50',
          incomingCallNotificationChannelName: 'Incoming Call',
          missedCallNotificationChannelName: 'Missed Call',
        ),
        ios: const callkit.IOSParams(
          iconName: 'TalkMate',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 2,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          supportsHolding: true,
          supportsGrouping: true,
          supportsUngrouping: true,
          ringtonePath: null, // [FIX]: Disable system ringtone for parity
        ),
      );
      // Trigger AppAudioService for Android/iOS so we use our assets
      unawaited(AppAudioService.instance.play('call_ringtone.mp3', loop: true));
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } else {
      // Windows/Android Fallback with High Priority
      // [CONSTITUTIONAL]: Block Windows/Android Local Notifications.
      // Android uses Native Fullscreen Intent. Windows uses Direct UI.
      if (Platform.isAndroid) return;

      final androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'calls_channel_v2', // Unique channel for sovereignty
        'Incoming Calls',
        channelDescription: 'High priority alerts for incoming AI calls',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true, // Crucial for background wake on Android
        category: AndroidNotificationCategory.call,
        ongoing: true,
        autoCancel: false,
        timeoutAfter: 45000,
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction('accept', 'Accept Call ✅',
              showsUserInterface: true, cancelNotification: true),
          const AndroidNotificationAction('decline', 'Decline ❌',
              showsUserInterface: true, cancelNotification: true),
        ],
      );

      final platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        linux: const LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.critical,
        ),
      );

      await localNotifications.show(
        sessionId.hashCode, // Unique ID per session
        '📞 مكالمة واردة من $senderName',
        'اضغط للرد أو الرفض - TalkMate AI',
        platformChannelSpecifics,
        payload: senderId,
      );
      // Play ringtone for fallback/Windows
      unawaited(AppAudioService.instance.play('call_ringtone.mp3', loop: true));
    }
  }

  Future<void> endCall(String id) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await FlutterCallkitIncoming.endCall(id);
    }
    // No specific local notification 'end' since it's transient
  }

  Future<void> endAllCalls() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await FlutterCallkitIncoming.endAllCalls();
    }
    await localNotifications.cancelAll();
    unawaited(AppAudioService.instance.stop('call_ringtone.mp3'));
    unawaited(AppAudioService.instance.stop('call_incomming.mp3'));
  }
}
