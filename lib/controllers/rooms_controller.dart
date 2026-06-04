import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/group_call_session_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/models/group_call_models.dart';
import 'package:talkmate_ai/models/room_model.dart';

class RoomsController extends GetxController {
  static RoomsController get instance => Get.find<RoomsController>();

  final _groupSession = Get.find<GroupCallSessionController>();
  final _auth = Get.find<AuthController>();

  final RxList<RoomModel> rooms = <RoomModel>[].obs;
  final RxString currentRoomId = ''.obs;
  final RxString actionRoomId = ''.obs;
  final RxBool isLoading = false.obs;

  // Supabase
  final _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;

  @override
  void onInit() {
    super.onInit();
    _fetchRooms();
    _subscribeToRooms();

    // Sync current room ID with group session controller
    ever(_groupSession.activeRoomId.obs, (String? roomId) {
      currentRoomId.value = roomId ?? '';
    });

    // Handle token refreshes
    // [Stage R]: Debounced re-subscription
    Timer? refreshDebounce;
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.tokenRefreshed) {
        refreshDebounce?.cancel();
        refreshDebounce = Timer(const Duration(seconds: 3), () {
          debugPrint(
              '🏢 Rooms: Token refreshed, re-subscribing (Debounced)...');
          _subscribeToRooms();
        });
      }
    }, onError: (e) {
      debugPrint('RoomsController: Auth state error: $e');
    });
  }

  @override
  void onClose() {
    _authSub?.cancel();
    super.onClose();
  }

  Future<void> _fetchRooms() async {
    isLoading.value = true;
    try {
      final response = await _supabase
          .from('rooms')
          .select()
          .order('created_at', ascending: false);

      final List<RoomModel> fetched = [];
      for (var row in response) {
        fetched.add(_mapRoomFromData(row));
      }
      rooms.assignAll(fetched);
    } catch (e) {
      debugPrint('Error fetching rooms: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _subscribeToRooms() {
    debugPrint('🏢 Rooms: Initializing realtime subscription...');
    _supabase
        .channel('public:rooms')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rooms',
          callback: (payload) {
            debugPrint(
                '🏢 Rooms: Received realtime event - ${payload.eventType}');
            if (payload.eventType == PostgresChangeEvent.insert) {
              final newRoom = _mapRoomFromData(payload.newRecord);
              if (!rooms.any((r) => r.id == newRoom.id)) {
                debugPrint('🏢 Rooms: Adding new room ${newRoom.name}');
                rooms.insert(0, newRoom);
              }
            } else if (payload.eventType == PostgresChangeEvent.update) {
              final updatedRoom = _mapRoomFromData(payload.newRecord);
              final index = rooms.indexWhere((r) => r.id == updatedRoom.id);
              if (index != -1) {
                // Update specific fields or replace model to ensure UI refreshes correctly
                rooms[index] = updatedRoom;
                debugPrint(
                    '🏢 Rooms: Updated room ${updatedRoom.name} count: ${updatedRoom.participantCount}');
              }
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              final deletedId = payload.oldRecord['id'];
              rooms.removeWhere((r) => r.id == deletedId);
            }
          },
        )
        .subscribe((status, [error]) {
      debugPrint('🏢 Rooms: Subscription status changed to $status');
      if (error != null) {
        debugPrint('🏢 Rooms: Subscription error: $error');
      }
    });
  }

  RoomModel _mapRoomFromData(Map<String, dynamic> row) {
    final typeStr = row['type'] as String? ?? 'voice';
    final roomType = typeStr == 'video' ? RoomType.video : RoomType.voice;
    final count = row['participant_count'] as int? ?? 0;

    return RoomModel(
      id: row['id'],
      name: row['name'],
      type: roomType,
      status: count > 0 ? RoomStatus.active : RoomStatus.empty,
      createdBy: row['created_by'],
      topic: row['topic'],
      metadata: row['metadata'] as Map<String, dynamic>? ?? {},
      participantCount: count,
    );
  }

  void refreshRooms() => _fetchRooms();

  Future<void> createRoom(String name, RoomType type) async {
    try {
      final userId = _auth.userId;
      if (userId.isEmpty) return;

      final res = await _supabase
          .from('rooms')
          .insert({
            'name': name,
            'created_by': userId,
            'is_active': true,
            'type': type.name,
            'is_private': false // Future: add private room UI
          })
          .select()
          .single();

      final newRoom = RoomModel(
        id: res['id'],
        name: res['name'],
        type: type,
        status: RoomStatus.empty,
        participantCount: 0,
      );
      rooms.insert(0, newRoom);
      debugPrint('🏢 Rooms: New room created - ${newRoom.name}');
    } catch (e) {
      debugPrint('Error creating room: $e');
      Get.snackbar('Error', 'Failed to create room');
    }
  }

  Future<bool> joinRoom(RoomModel room) async {
    if (actionRoomId.value.isNotEmpty) return false;
    actionRoomId.value = room.id;

    if (currentRoomId.value.isNotEmpty) {
      await leaveRoom();
    }

    final userId = _auth.userId;
    final userName = _auth.userName.isNotEmpty
        ? _auth.userName
        : 'User_${userId.substring(0, 4)}';

    final success = await _groupSession.joinRoom(
        room.id, userId, userName, ParticipantRole.member);

    if (success) {
      currentRoomId.value = room.id;
    }
    actionRoomId.value = '';
    return success;
  }

  Future<void> leaveRoom() async {
    if (currentRoomId.value.isEmpty ||
        actionRoomId.value == currentRoomId.value) {
      return;
    }
    final leavingId = currentRoomId.value;
    actionRoomId.value = leavingId;

    final userId = _auth.userId;
    unawaited(_groupSession.leaveRoom(userId));

    currentRoomId.value = '';
    actionRoomId.value = '';
    debugPrint('🏢 Rooms: Left room session.');
  }

  Future<void> updateRoom(String id, String newName) async {
    try {
      final userId = _auth.userId;
      await _supabase
          .from('rooms')
          .update({'name': newName})
          .eq('id', id)
          .eq('created_by', userId);

      final index = rooms.indexWhere((r) => r.id == id);
      if (index != -1) {
        rooms[index] = rooms[index].copyWith(name: newName);
      }
      debugPrint('🏢 Rooms: Room $id renamed to $newName');
    } catch (e) {
      debugPrint('Error updating room: $e');
      Get.snackbar('Error', 'Failed to update room');
    }
  }

  Future<void> deleteRoom(String id) async {
    try {
      final userId = _auth.userId;
      // Also leave if we are in it
      if (currentRoomId.value == id) {
        await leaveRoom();
      }

      await _supabase
          .from('rooms')
          .delete()
          .eq('id', id)
          .eq('created_by', userId);

      rooms.removeWhere((r) => r.id == id);
      debugPrint('🏢 Rooms: Room $id deleted');
    } catch (e) {
      debugPrint('Error deleting room: $e');
      Get.snackbar('Error', 'Failed to delete room');
    }
  }

  bool isCreator(String? createdBy) {
    if (createdBy == null) return false;
    return _auth.userId == createdBy;
  }

  bool isInRoom(String roomId) => currentRoomId.value == roomId;
}
