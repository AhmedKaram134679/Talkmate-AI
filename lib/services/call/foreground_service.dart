import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Service to manage Android Foreground Task for active calls.
class CallForegroundService {
  static void init() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    debugPrint('📞 CallForegroundService: Initializing...');
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'call_service',
        channelName: 'Active Call Service',
        channelDescription: 'Maintains call connection in background',
        channelImportance: NotificationChannelImportance
            .DEFAULT, // [STRICT]: Lower to avoid sound enforcement
        priority: NotificationPriority.DEFAULT,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    debugPrint('✅ CallForegroundService: Init call sent to plugin.');
  }

  static Future<void> start(String callerName, bool isVideo) async {
    if (kIsWeb || !Platform.isAndroid) return;
    debugPrint(
        '🚀 CallForegroundService: Requesting START for $callerName (Video: $isVideo)');

    try {
      if (await FlutterForegroundTask.isRunningService) {
        debugPrint(
            '🔄 CallForegroundService: Service already running, restarting...');
        await FlutterForegroundTask.restartService();
      } else {
        debugPrint('🎬 CallForegroundService: Starting service...');
        final bool success = await FlutterForegroundTask.startService(
          notificationTitle:
              isVideo ? 'مكالمة فيديو نشطة' : 'مكالمة صوتية نشطة',
          notificationText: 'مع: $callerName',
          callback: startCallback,
        );
        debugPrint(
            '🏁 CallForegroundService: startService called. Success: $success');
      }
    } catch (e) {
      debugPrint('❌ CallForegroundService Error: $e');
      rethrow;
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await FlutterForegroundTask.stopService();
  }
}

/// The callback function for the foreground task.
/// Must be a top-level function or a static method.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(CallTaskHandler());
}

class CallTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {
    debugPrint('Foreground Service Started');
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // Keep alive logic if needed
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
    debugPrint('Foreground Service Destroyed');
  }
}
