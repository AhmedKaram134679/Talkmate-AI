import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/chat_model.dart' as data_chat;
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/data/services/storage_service.dart';

class GroupManagementScreen extends StatefulWidget {
  final String chatId;
  const GroupManagementScreen({super.key, required this.chatId});

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  final _nameCtrl = TextEditingController();
  final _photoCtrl = TextEditingController();

  final _userRepo = Get.find<IUserRepository>();
  final _chatRepo = Get.find<IChatRepository>();
  final _friendshipRepo = Get.find<IFriendshipRepository>();
  final _storage = StorageService.instance;

  bool _updating = false;
  XFile? _pickedImage;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _photoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المجموعة'),
        centerTitle: true,
      ),
      body: StreamBuilder<data_chat.Chat?>(
        stream: _chatRepo.watchById(widget.chatId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final chat = snap.data;
          if (chat == null || chat.isGroup != true) {
            return const Center(child: Text('لم يتم العثور على المجموعة'));
          }

          if (_nameCtrl.text.isEmpty) {
            _nameCtrl.text = chat.groupName ?? '';
          }
          if (_photoCtrl.text.isEmpty) {
            _photoCtrl.text = chat.groupPhotoUrl ?? '';
          }

          final bool isAdmin =
              chat.creatorId == Get.find<AuthController>().userId;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                    theme, 'معلومات المجموعة', Icons.info_outline),
                const SizedBox(height: 24),
                _buildAvatarPicker(theme, chat, isAdmin),
                const SizedBox(height: 24),
                _buildInfoForm(theme, chat, isAdmin),
                const SizedBox(height: 24),
                _buildSectionHeader(
                    theme,
                    'أعضاء المجموعة (${chat.participantIds.length})',
                    Icons.people_outline),
                const SizedBox(height: 12),
                _buildMembersList(theme, chat.participantIds, chat),
                const SizedBox(height: 24),
                _buildAddMemberButton(theme, chat),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInfoForm(ThemeData theme, data_chat.Chat chat, bool isAdmin) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              enabled: isAdmin,
              decoration: const InputDecoration(
                  labelText: 'اسم المجموعة', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            if (isAdmin)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _updating ? null : _updateInfo,
                  icon: _updating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('تحديث المعلومات'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPicker(
      ThemeData theme, data_chat.Chat chat, bool isAdmin) {
    ImageProvider? imageProvider;
    if (_pickedImage != null) {
      if (kIsWeb) {
        imageProvider = NetworkImage(_pickedImage!.path);
      } else {
        imageProvider = FileImage(File(_pickedImage!.path));
      }
    } else if (chat.groupPhotoUrl != null && chat.groupPhotoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(chat.groupPhotoUrl!);
    }

    return Center(
      child: GestureDetector(
        onTap: isAdmin ? _pickImage : null,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.primary, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 55,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? Icon(Icons.group,
                        size: 60, color: theme.colorScheme.primary)
                    : null,
              ),
            ),
            if (isAdmin)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: theme.colorScheme.surface, width: 2),
                ),
                child: Icon(Icons.camera_alt,
                    size: 20, color: theme.colorScheme.onPrimary),
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

  Future<void> _updateInfo() async {
    setState(() => _updating = true);
    try {
      String? photoUrl = _photoCtrl.text.trim();

      if (_pickedImage != null) {
        final path =
            'groups/${widget.chatId}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final (url, _) = await _storage.uploadFile(
          file: _pickedImage!,
          path: path,
        );
        photoUrl = url;
      }

      await _chatRepo.updateGroupMeta(
        chatId: widget.chatId,
        name: _nameCtrl.text.trim(),
        photoUrl: photoUrl,
      );

      _photoCtrl.text = photoUrl;
      _pickedImage = null;

      Get.snackbar('نجاح', 'تم تحديث معلومات المجموعة');
    } catch (e) {
      Get.snackbar('خطأ', e.toString());
    } finally {
      setState(() => _updating = false);
    }
  }

  Widget _buildMembersList(
      ThemeData theme, List<String> userIds, data_chat.Chat chat) {
    if (userIds.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('لا يوجد أعضاء في هذه المجموعة'),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: userIds.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _buildMemberItem(theme, userIds[index], chat),
    );
  }

  Widget _buildMemberItem(ThemeData theme, String uid, data_chat.Chat chat) {
    final bool isCreator = chat.creatorId == uid;
    final bool isMe = Get.find<AuthController>().userId == uid;
    final bool iAmAdmin = chat.creatorId == Get.find<AuthController>().userId;

    return FutureBuilder<AppUser?>(
      future: _userRepo.getById(uid),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('Error loading user $uid: ${snap.error}');
          return ListTile(
            title: Text('خطأ في تحميل العضو: $uid'),
            subtitle: Text(snap.error.toString()),
          );
        }
        if (!snap.hasData && snap.connectionState != ConnectionState.done) {
          return const ListTile(
            leading: CircleAvatar(child: CircularProgressIndicator()),
            title: Text('جاري التحميل...'),
          );
        }
        final user = snap.data;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundImage:
                (user?.photoUrl != null && user!.photoUrl!.isNotEmpty)
                    ? NetworkImage(user.photoUrl!)
                    : null,
            child: user?.photoUrl == null ? const Icon(Icons.person) : null,
          ),
          title: Row(
            children: [
              Text(user?.displayName ?? '...'),
              const SizedBox(width: 8),
              if (isCreator)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'المؤسس',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Text(user?.email ?? uid,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: (iAmAdmin && !isCreator && !isMe)
              ? IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.red),
                  onPressed: () => _confirmRemoveMember(uid, user?.displayName),
                )
              : null,
        );
      },
    );
  }

  Widget _buildAddMemberButton(ThemeData theme, data_chat.Chat chat) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showAddMemberDialog(chat),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('إضافة أعضاء جدد'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Future<void> _confirmRemoveMember(String uid, String? name) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('إزالة عضو'),
        content:
            Text('هل أنت متأكد من إزالة ${name ?? "هذا العضو"} من المجموعة؟'),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('إزالة', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _chatRepo.removeUserFromChat(chatId: widget.chatId, userId: uid);
        Get.snackbar('نجاح', 'تمت إزالة العضو');
      } catch (e) {
        Get.snackbar('خطأ', e.toString());
      }
    }
  }

  Future<void> _showAddMemberDialog(data_chat.Chat chat) async {
    final currentUid = Get.find<AuthController>().userId;
    final friendIds = await _friendshipRepo.getAllForUser(currentUid);
    final List<AppUser> friendUsers = [];
    for (final id in friendIds) {
      final u = await _userRepo.getById(id);
      if (u != null) friendUsers.add(u);
    }

    final nonMembers =
        friendUsers.where((f) => !chat.participantIds.contains(f.id)).toList();

    if (nonMembers.isEmpty) {
      Get.snackbar('تنبيه', 'لا يوجد أصدقاء جدد لإضافتهم');
      return;
    }

    final selectedIds = <String>{};

    await Get.bottomSheet(
      StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إضافة أعضاء',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: nonMembers.length,
                  itemBuilder: (context, index) {
                    final friend = nonMembers[index];
                    final isSelected = selectedIds.contains(friend.id);
                    return CheckboxListTile(
                      title: Text(friend.displayName ?? 'مستخدم'),
                      secondary: CircleAvatar(
                        backgroundImage: (friend.photoUrl != null &&
                                friend.photoUrl!.isNotEmpty)
                            ? NetworkImage(friend.photoUrl!)
                            : null,
                      ),
                      value: isSelected,
                      onChanged: (v) {
                        setModalState(() {
                          if (v == true) {
                            selectedIds.add(friend.id);
                          } else {
                            selectedIds.remove(friend.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () async {
                          try {
                            await _chatRepo.addUsersToChat(
                                chatId: widget.chatId,
                                userIds: selectedIds.toList());
                            Get.back();
                            Get.snackbar('نجاح', 'تمت إضافة الأعضاء');
                          } catch (e) {
                            Get.snackbar('خطأ', e.toString());
                          }
                        },
                  child: const Text('إضافة المختارين'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
