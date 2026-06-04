import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/data/services/storage_service.dart';
import 'package:talkmate_ai/models/chat_model.dart' as ui_models;
import 'package:talkmate_ai/screens/chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _auth = Get.find<AuthController>();
  final _friendshipRepo = Get.find<IFriendshipRepository>();
  final _userRepo = Get.find<IUserRepository>();
  final _chatRepo = Get.find<IChatRepository>();
  final _storage = StorageService.instance;

  final _nameCtrl = TextEditingController();
  final Set<String> _selectedUserIds = {};
  List<AppUser> _friends = [];
  bool _loading = true;
  bool _creating = false;
  XFile? _pickedImage;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final friendIds = await _friendshipRepo.getAllForUser(_auth.userId);
      final List<AppUser> friendUsers = [];
      for (final id in friendIds) {
        final u = await _userRepo.getById(id);
        if (u != null) friendUsers.add(u);
      }
      if (mounted) {
        setState(() {
          _friends = friendUsers;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      Get.snackbar('خطأ', 'تعذر تحميل قائمة الأصدقاء');
    }
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      Get.snackbar('تنبيه', 'يرجى إدخال اسم المجموعة');
      return;
    }
    if (_selectedUserIds.isEmpty) {
      Get.snackbar('تنبيه', 'يرجى اختيار عضو واحد على الأقل');
      return;
    }

    setState(() => _creating = true);
    try {
      String? groupPhotoUrl;
      if (_pickedImage != null) {
        final path = 'groups/temp_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final (url, _) = await _storage.uploadFile(
          file: _pickedImage!,
          path: path,
        );
        groupPhotoUrl = url;
      }

      final participantIds = _selectedUserIds.toList()..add(_auth.userId);
      final chat = await _chatRepo.createChat(
        participantIds: participantIds,
        isGroup: true,
        groupName: name,
        groupPhotoUrl: groupPhotoUrl,
      );

      final uiChat = ui_models.ChatModel(
        id: chat.id,
        name: chat.groupName ?? 'مجموعة',
        type: ui_models.ChatType.group,
        participantIds: chat.participantIds,
      );

      unawaited(Get.off(() => ChatScreen(chat: uiChat)));
    } catch (e) {
      setState(() => _creating = false);
      Get.snackbar('فشل الإنشاء', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء مجموعة جديدة'),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _creating ? null : _createGroup,
              child: _creating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('إنشاء'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 24),
                _buildAvatarPicker(theme),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المجموعة',
                      prefixIcon: Icon(Icons.group_outlined),
                    ),
                  ),
                ),
                const Divider(),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text('اختر الأعضاء',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${_selectedUserIds.length} مختارون',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Expanded(
                  child: _friends.isEmpty
                      ? const Center(child: Text('لا يوجد أصدقاء للإضافة'))
                      : ListView.separated(
                          itemCount: _friends.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemBuilder: (context, index) {
                            final friend = _friends[index];
                            final isSelected =
                                _selectedUserIds.contains(friend.id);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: (friend.photoUrl != null &&
                                        friend.photoUrl!.isNotEmpty)
                                    ? NetworkImage(friend.photoUrl!)
                                    : null,
                                child: friend.photoUrl == null
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Text(friend.displayName ?? 'مستخدم'),
                              subtitle: Text(friend.about ?? ''),
                              trailing: Checkbox(
                                value: isSelected,
                                onChanged: (_) => _toggleSelection(friend.id),
                                shape: const CircleBorder(),
                              ),
                              onTap: () => _toggleSelection(friend.id),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              tileColor: isSelected
                                  ? theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.3)
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildAvatarPicker(ThemeData theme) {
    ImageProvider? imageProvider;
    if (_pickedImage != null) {
      if (kIsWeb) {
        imageProvider = NetworkImage(_pickedImage!.path);
      } else {
        imageProvider = FileImage(File(_pickedImage!.path));
      }
    }

    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
              child: CircleAvatar(
                radius: 48,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? Icon(Icons.group,
                        size: 50, color: theme.colorScheme.primary)
                    : null,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Icon(Icons.camera_alt,
                  size: 16, color: theme.colorScheme.onPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (image != null) {
      setState(() {
        _pickedImage = image;
      });
    }
  }
}
