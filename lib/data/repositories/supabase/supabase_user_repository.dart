import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/device_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/utils/device_identity.dart';

class SupabaseUserRepository implements IUserRepository {
  SupabaseUserRepository();

  final SupabaseClient _client = Supabase.instance.client;

  // [Stage R22.5]: Resilience Helper
  Future<T> _retry<T>(Future<T> Function() action,
      {int maxAttempts = 3}) async {
    int attempts = 0;
    while (true) {
      try {
        attempts++;
        return await action();
      } catch (e) {
        if (attempts >= maxAttempts) rethrow;
        final bool isConnError = e.toString().contains('Connection closed') ||
            e.toString().contains('Connection terminated') ||
            e.toString().contains('Connection reset') ||
            e.toString().contains('SocketException');
        if (!isConnError) rethrow;

        debugPrint(
            '⚠️ SupabaseUserRepo: Retrying request (Attempt $attempts/$maxAttempts) due to: $e');
        await Future.delayed(Duration(seconds: 1 * attempts));
      }
    }
  }

  @override
  Future<void> upsertUser(AppUser user) async {
    await _retry(() async {
      await _client
          .from('profiles')
          .upsert(user.toJson())
          .timeout(const Duration(seconds: 15));
    });
  }

  @override
  Future<AppUser?> getById(String userId) async {
    int attempts = 0;
    while (attempts < 3) {
      try {
        final response = await _client
            .from('profiles')
            .select()
            .eq('id', userId)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));

        if (response == null) return null;
        return AppUser.fromJson(response);
      } catch (e) {
        attempts++;
        debugPrint(
            'SupabaseUserRepository: getById error (Attempt $attempts): $e');
        if (attempts >= 3) return null;
        await Future.delayed(Duration(seconds: 2 * attempts));
      }
    }
    return null;
  }

  @override
  Stream<AppUser?> watchById(String userId) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((data) => data.isNotEmpty ? AppUser.fromJson(data.first) : null);
  }

  @override
  Future<void> updateStatus(String userId, UserStatus status,
      {DateTime? lastSeen}) async {
    await _retry(() async {
      await _client.from('profiles').update({
        'status': status.name,
        'last_seen': lastSeen?.toIso8601String(),
      }).eq('id', userId);
    });
  }

  @override
  Future<List<AppUser>> searchByNameOrEmail(String query,
      {int limit = 20, List<String>? userIds}) async {
    var queryBuilder = _client
        .from('profiles')
        .select()
        .or('username.ilike.%$query%,email.ilike.%$query%');

    if (userIds != null && userIds.isNotEmpty) {
      queryBuilder = queryBuilder.filter('id', 'in', userIds);
    }

    final response = await queryBuilder.limit(limit);

    return (response as List).map((map) => AppUser.fromJson(map)).toList();
  }

  @override
  Future<void> updatePrivacy(
    String userId, {
    bool? showLastSeen,
    bool? showProfilePhoto,
    bool? showStatus,
  }) async {
    await _retry(() async {
      final Map<String, dynamic> data = {};
      if (showLastSeen != null) data['privacy_show_last_seen'] = showLastSeen;
      if (showProfilePhoto != null) {
        data['privacy_show_profile_photo'] = showProfilePhoto;
      }
      if (showStatus != null) data['privacy_show_status'] = showStatus;

      if (data.isNotEmpty) {
        await _client.from('profiles').update(data).eq('id', userId);
      }
    });
  }

  @override
  Future<void> updateProfile(
    String userId, {
    String? displayName,
    String? about,
    String? photoUrl,
  }) async {
    await _retry(() async {
      final Map<String, dynamic> data = {};
      if (displayName != null) data['username'] = displayName;
      if (about != null) data['about'] = about;
      if (photoUrl != null) data['avatar_url'] = photoUrl;

      if (data.isNotEmpty) {
        await _client
            .from('profiles')
            .update(data)
            .eq('id', userId)
            .timeout(const Duration(seconds: 15));
      }
    });
  }

  @override
  Future<void> addFcmToken(String userId, String token,
      {String? deviceId,
      String? platform,
      DateTime? lastUpdate,
      Map<String, dynamic>? webPushSubscription}) async {
    await _retry(() async {
      if (userId.isEmpty) {
        debugPrint('⚠️ addFcmToken called with empty userId, skipping RPC.');
        return;
      }
      debugPrint('✅ Calling RPC register_device_token via Retry Guard:');

      await _client.rpc('register_device_token', params: {
        'p_user_id': userId,
        'p_fcm_token': token,
        'p_device_id': deviceId ?? 'unknown',
        'p_platform': platform ?? (kIsWeb ? 'web' : Platform.operatingSystem),
        'p_web_push_subscription': webPushSubscription,
      });

      debugPrint('FCM token registered via RPC for $userId');
    });
  }

  @override
  Future<void> updateWebPushSubscription(String userId, String subscriptionJson,
      {String? deviceId}) async {
    await _retry(() async {
      final sub = Map<String, dynamic>.from(
          (Uri.decodeFull(subscriptionJson).startsWith('{'))
              ? (Uri.decodeFull(subscriptionJson)) as dynamic
              : (subscriptionJson) as dynamic);

      await _client.from('user_devices').upsert({
        'user_id': userId,
        'device_id': deviceId ?? 'web-unknown',
        'web_push_subscription': sub,
        'platform': 'web',
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, device_id');
      debugPrint('Web Push subscription saved for $userId');
    });
  }

  @override
  Future<void> updateDevicePresence(String userId, String deviceId,
      {bool? isOnline, String? appState}) async {
    await _retry(() async {
      final Map<String, dynamic> data = {
        'last_active_at': DateTime.now().toIso8601String(),
      };
      if (isOnline != null) data['is_online'] = isOnline;
      if (appState != null) data['app_state'] = appState;

      await _client
          .from('user_devices')
          .update(data)
          .match({'user_id': userId, 'device_id': deviceId});
    });
  }

  @override
  Future<List<DeviceModel>> getUserDevices(String userId) async {
    try {
      final currentDeviceId = await DeviceIdentity.getId();
      final response = await _client
          .from('user_devices')
          .select()
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('last_active_at', ascending: false);

      return (response as List)
          .map((data) =>
              DeviceModel.fromJson(data, currentDeviceId: currentDeviceId))
          .toList();
    } catch (e) {
      debugPrint('getUserDevices failed: $e');
      return [];
    }
  }

  @override
  Future<void> revokeDevice(String userId, String deviceId) async {
    try {
      await _client
          .from('user_devices')
          .delete()
          .match({'user_id': userId, 'device_id': deviceId});
    } catch (e) {
      debugPrint('revokeDevice failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> revokeAllOtherDevices(
      String userId, String currentDeviceId) async {
    try {
      await _client
          .from('user_devices')
          .delete()
          .match({'user_id': userId}).neq('device_id', currentDeviceId);
    } catch (e) {
      debugPrint('revokeAllOtherDevices failed: $e');
      rethrow;
    }
  }
}
