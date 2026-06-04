import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/rooms_controller.dart';
import 'package:talkmate_ai/core/communication/communication_controller.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/models/room_model.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final RoomsController _controller = Get.put(RoomsController());

  @override
  void initState() {
    super.initState();
    // Force refresh to clear any potential stale mock data from previous hot reloads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.refreshRooms();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.rooms),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_rounded),
            onPressed: () => _showCreateRoomSheet(context),
            tooltip: 'Create Room',
          ),
        ],
      ),
      body: Obx(() {
        if (_controller.rooms.isEmpty) {
          return Center(child: Text(l10n.noChatsYet));
        }

        return RefreshIndicator(
          onRefresh: () async {
            // Simulate re-loading rooms for C4 validation
            await Future.delayed(const Duration(seconds: 1));
            _controller.refreshRooms();
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _controller.rooms.length,
            itemBuilder: (context, index) {
              final room = _controller.rooms[index];
              return _buildRoomCard(room, theme);
            },
          ),
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'rooms_fab',
        onPressed: () => _showCreateRoomSheet(context),
        label: const Text('Create Room'),
        icon: const Icon(Icons.add),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
      ),
    );
  }

  Widget _buildRoomCard(RoomModel room, ThemeData theme) {
    final isInRoom = _controller.isInRoom(room.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: isInRoom ? 4 : 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: room.type == RoomType.video
              ? Colors.deepPurple.withValues(alpha: 0.2)
              : Colors.blue.withValues(alpha: 0.2),
          child: Icon(
            room.type == RoomType.video
                ? Icons.videocam_rounded
                : Icons.mic_rounded,
            color:
                room.type == RoomType.video ? Colors.deepPurple : Colors.blue,
          ),
        ),
        title: Text(
          room.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: room.status == RoomStatus.active
                    ? Colors.green
                    : Colors.grey,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              room.status == RoomStatus.active ? 'Active' : 'Empty',
              style: TextStyle(color: theme.disabledColor, fontSize: 12),
            ),
            const SizedBox(width: 12),
            Icon(Icons.people_alt_rounded,
                size: 14, color: theme.disabledColor),
            const SizedBox(width: 4),
            Text(
              '${room.participantCount}',
              style: TextStyle(color: theme.disabledColor, fontSize: 12),
            ),
          ],
        ),
        trailing: Obx(() {
          final isActing = _controller.actionRoomId.value == room.id;
          // [Unified]: Use CommunicationController
          final commCtrl = CommunicationController.instance;

          return ElevatedButton(
            onPressed: isActing
                ? null
                : () async {
                    if (isInRoom) {
                      await commCtrl.leaveSession();
                      _controller.refreshRooms();
                    } else {
                      await commCtrl.joinSession(room.id,
                          isVideo: room.type == RoomType.video);
                      // Navigation is now handled by Sovereign state observer in MainWrapper
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: isInRoom
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              foregroundColor: isInRoom
                  ? theme.colorScheme.onError
                  : theme.colorScheme.onPrimary,
              elevation: 0,
              minimumSize: const Size(80, 40),
            ),
            child: isActing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(isInRoom ? 'Leave' : 'Join'),
          );
        }),
      ),
    );
  }

  void _showCreateRoomSheet(BuildContext context) {
    final nameController = TextEditingController();
    final selectedType = RoomType.voice.obs;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create Sovereign Room',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                hintText: 'Room Name',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Room Type',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Obx(() => Row(
                  children: [
                    _typeOption(RoomType.voice, Icons.mic_rounded, 'Voice Room',
                        selectedType),
                    const SizedBox(width: 16),
                    _typeOption(RoomType.video, Icons.videocam_rounded,
                        'Video Room', selectedType),
                  ],
                )),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    _controller.createRoom(
                        nameController.text, selectedType.value);
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: const Text('Initialize Room'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeOption(
      RoomType type, IconData icon, String label, Rx<RoomType> selected) {
    final isSelected = selected.value == type;
    return Expanded(
      child: InkWell(
        onTap: () => selected.value = type,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor.withValues(alpha: 0.3),
                width: 2),
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).disabledColor,
                      fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
