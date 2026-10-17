import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/utils/device_identity.dart';

class BadgeService extends GetxService with WidgetsBindingObserver {
  static BadgeService get instance => Get.find<BadgeService>();

  RealtimeChannel? _statusChannel;
  bool _isInitialized = false;
  final RxInt unreadCount = 0.obs;

  Future<BadgeService> init() async {
    if (_isInitialized) return this;

    WidgetsBinding.instance.addObserver(this);

    // Initialize notification counts and listener
    await updateBadge();
    unawaited(_startRealtimeListener());

    _isInitialized = true;
    return this;
  }

  /// Updates the app badge count by fetching unread messages for this device
  Future<void> updateBadge() async {
    try {
      final deviceId = await DeviceIdentity.getId();
      final supabase = Supabase.instance.client;

      // Efficiently fetch only the count of unread messages for this device
      final count = await supabase
          .from('message_delivery')
          .count(CountOption.exact)
          .eq('device_id', deviceId)
          .neq('status', 'read');

      unreadCount.value = count;
      await setBadgeCount(count);
    } catch (e) {
      debugPrint('BadgeService: Failed to update badge from Supabase: $e');
    }
  }

  /// Sets the badge count on the app icon using flutter_app_badge_control
  Future<void> setBadgeCount(int count) async {
    if (GetPlatform.isWindows || GetPlatform.isLinux) return;

    try {
      // Library removed to resolve JVM target conflicts.
      // Badge counts are now managed via Supabase and Local Notifications.
      if (count > 0) {
        debugPrint('BadgeService: Unread count tracked at $count');
      } else {
        debugPrint('BadgeService: Unread count cleared');
      }
    } catch (e) {
      debugPrint('BadgeService: Error tracking count: $e');
    }
  }

  /// Clears the badge count
  Future<void> clearBadge() async {
    await setBadgeCount(0);
  }

  Future<void> _startRealtimeListener() async {
    try {
      final deviceId = await DeviceIdentity.getId();

      await _statusChannel?.unsubscribe();

      _statusChannel = Supabase.instance.client
          .channel('public:message_delivery:badge')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'message_delivery',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'device_id',
              value: deviceId,
            ),
            callback: (payload) {
              // Recount whenever there's a change for this device
              updateBadge();
            },
          );

      _statusChannel?.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          debugPrint('BadgeService: Realtime channel error/timeout: $error');
          // Retry subscription after delay
          Timer(const Duration(seconds: 10), () {
            if (_isInitialized) {
              _startRealtimeListener();
            }
          });
        }
      });
    } catch (e) {
      debugPrint('BadgeService: Error setting up Realtime listener: $e');
      // Retry after delay
      Timer(const Duration(seconds: 15), () {
        if (_isInitialized) {
          _startRealtimeListener();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      updateBadge();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusChannel?.unsubscribe();
    super.onClose();
  }
}
