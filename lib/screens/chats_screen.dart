// ignore_for_file: unused_element

import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/config/theme_config.dart';
import 'package:talkmate_ai/controllers/theme_controller.dart';
import 'package:talkmate_ai/core/app_brain/adaptive/adaptive_controller.dart';
import 'package:talkmate_ai/data/models/user_model.dart' as data_user;
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';
import 'package:talkmate_ai/services/observability/analytics_service.dart';
import 'package:talkmate_ai/widgets/friend_picker_dialog.dart';
import 'package:talkmate_ai/widgets/skeleton_chat_list.dart';

import '../controllers/auth_controller.dart';
import '../controllers/chat_controller.dart';
import '../controllers/language_controller.dart';
import '../localization/app_localizations.dart';
import '../models/chat_model.dart';
import '../models/user_model.dart' as ui_user;
import '../widgets/communication/presence_indicator_widget.dart';
import 'chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final AuthController authController = Get.find<AuthController>();
  final ChatController chatController = Get.find<ChatController>();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.logScreenView('ChatsScreen'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content = Column(
      children: [
        _buildResumeNudge(),
        _buildSearchBar(),
        Expanded(
          child: Obx(
            () => chatController.activeChats.isEmpty
                ? _buildEmptyState()
                : _buildChatsList(),
          ),
        ),
      ],
    );

    if (AppConfig.enableKeyboardShortcuts &&
        (GetPlatform.isWindows || GetPlatform.isMacOS || GetPlatform.isLinux)) {
      content = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _startChatWithFriendPicker,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
            // Focus search could be added if search controller has a FocusNode
          },
        },
        child: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/logo/talkmate_ai_logo_transparent.png',
            fit: BoxFit.contain,
          ),
        ),
        title: Text(AppLocalizations.of(context).chats),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.language_rounded),
            onPressed: () => Get.find<LanguageController>().toggleLanguage(),
          ),
          IconButton(
            icon: const Icon(Icons.wb_sunny_outlined),
            onPressed: () => Get.find<ThemeController>().toggleTheme(),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
              onPressed: () => unawaited(Get.toNamed('/friend_requests')),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => unawaited(Get.toNamed('/search')),
          ),
        ],
      ),
      body: content,
      floatingActionButton: FloatingActionButton(
        heroTag: 'chats_fab',
        onPressed: _startChatWithFriendPicker,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0, // Flat design
        child: const Icon(Icons.add_comment_rounded),
      ),
    );
  }

  Future<void> _startWebRtcFromChats(
      {required ChatModel chat, required bool isVideo}) async {
    final l10n = AppLocalizations.of(context);
    if (!chat.isIndividual) {
      Get.snackbar(l10n.webRTC, l10n.webrtcIndividualOnly,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final me = authController.userId;
    String? otherId;
    try {
      otherId =
          chat.participantIds.firstWhere((id) => id != me, orElse: () => '');
    } catch (_) {
      otherId = '';
    }
    if (otherId.isEmpty) {
      Get.snackbar(l10n.webRTC, l10n.webrtcFailedToIdentifyOther,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      await CallManager.instance.startOutgoingCall(
        calleeId: otherId,
        isVideo: isVideo,
      );
    } catch (e) {
      Get.snackbar(l10n.webRTC, e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: TextField(
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context).searchChatsHint,
          suffixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: theme.inputDecorationTheme.fillColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: Colors.grey.withAlpha(30)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: Colors.grey.withAlpha(30)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide:
                const BorderSide(color: ThemeConfig.primaryColor, width: 1),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        onChanged: (value) => chatController.setSearchQuery(value),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(seconds: 1),
                curve: Curves.elasticOut,
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  child: child,
                ),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).primaryColor.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 80,
                    color:
                        Theme.of(context).primaryColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.welcomeToAdvancedMessaging,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.startFirstChatHint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startChatWithFriendPicker,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.add_comment_rounded),
                  label: Text(
                    l10n.startNewChatAction,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumeNudge() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Obx(() {
      final lastChatId = chatController.lastActiveChatId;
      if (lastChatId.isEmpty || chatController.activeChats.isEmpty) {
        return const SizedBox.shrink();
      }

      final chat = chatController.activeChats
          .firstWhereOrNull((c) => c.id == lastChatId);
      if (chat == null) return const SizedBox.shrink();

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListTile(
          dense: true,
          leading:
              Icon(Icons.history_rounded, color: theme.colorScheme.primary),
          title: Center(
            child: Text(
              l10n.resumeChatWith(
                  chat.getDisplayName(AppLocalizations.of(context))),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () => _openChat(chat),
        ),
      );
    });
  }

  Widget _buildChatsList() {
    return Obx(() {
      if (chatController.isLoading && chatController.chats.isEmpty) {
        return const SkeletonChatList();
      }

      final chats =
          chatController.filteredChats.where((c) => !c.isArchived).toList();

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: RefreshIndicator(
          key: ValueKey(
              chats.length), // Ensure switcher triggers on significant changes
          onRefresh: chatController.refreshChats,
          color: ThemeConfig.primaryColor,
          child: chats.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    // Staggered Animation Wrapper
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(
                          milliseconds: 400 + (index * 50).clamp(0, 500)),
                      curve: Curves.easeOutQuart,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 30 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: Obx(() {
                              final adaptive = AdaptiveController.instance;
                              final bool reduceAnimations =
                                  adaptive.adjustments['reduce_animations'] ==
                                      true;
                              final useRepaintBoundary = !reduceAnimations;

                              Widget item = _buildChatItem(chat);
                              if (useRepaintBoundary) {
                                item = RepaintBoundary(child: item);
                              }

                              return OpenContainer(
                                openElevation: 0,
                                closedElevation: 0,
                                transitionDuration: reduceAnimations
                                    ? Duration.zero
                                    : const Duration(milliseconds: 500),
                                closedColor: Colors.transparent,
                                openColor:
                                    Theme.of(context).scaffoldBackgroundColor,
                                onClosed: (data) =>
                                    chatController.markChatAsRead(chat.id),
                                openBuilder: (context, action) =>
                                    ChatScreen(chat: chat),
                                closedBuilder: (context, action) => item,
                              );
                            }),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      );
    });
  }

  Future<void> _startChatWithFriendPicker() async {
    // افتح مربع اختيار الأصدقاء مع دعم التحديد المتعدد
    final picked = await FriendPickerDialog.pick(
      context,
      multiSelect: true,
      title: AppLocalizations.of(context).chooseFriendToChat,
    );
    if (picked == null || picked.isEmpty) return;

    if (picked.length == 1) {
      // محادثة فردية
      final otherUserId = picked.first;
      try {
        final otherUser =
            await Get.find<IUserRepository>().getById(otherUserId);
        final otherName = (otherUser?.displayName?.isNotEmpty ?? false)
            ? otherUser!.displayName!
            : (otherUser?.email ?? otherUserId);

        final chat = await chatController.createIndividualChat(
          otherUserId: otherUserId,
          otherUserName: otherName,
        );
        unawaited(Get.to(
          () => ChatScreen(chat: chat),
          transition: Transition.rightToLeft,
          duration: const Duration(milliseconds: 300),
        ));
      } catch (e) {
        Get.snackbar('المحادثات', 'تعذر بدء المحادثة: $e',
            snackPosition: SnackPosition.BOTTOM);
      }
      return;
    }

    // إنشاء مجموعة عند اختيار أكثر من صديق
    try {
      final me = authController.userId;
      // اقترح اسمًا افتراضيًا للمجموعة من أول اسمين
      final suggested = await _suggestGroupNameFromUsers(picked);
      final groupName = await _promptGroupName(suggestedName: suggested);
      if (groupName == null || groupName.trim().isEmpty) return;

      final chat = await chatController.createGroupChat(
        name: groupName.trim(),
        participantIds: [me, ...picked],
      );
      unawaited(Get.to(
        () => ChatScreen(chat: chat),
        transition: Transition.rightToLeft,
        duration: const Duration(milliseconds: 300),
      ));
    } catch (e) {
      Get.snackbar('المحادثات', 'تعذر إنشاء المجموعة: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<String> _suggestGroupNameFromUsers(List<String> userIds) async {
    final names = <String>[];
    for (final id in userIds.take(3)) {
      final u = await Get.find<IUserRepository>().getById(id);
      if (u == null) continue;
      final name =
          (u.displayName?.isNotEmpty ?? false) ? u.displayName! : u.email;
      names.add(name);
    }
    if (names.isEmpty) return 'مجموعة جديدة';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} + ${names[1]}';
    return '${names[0]}, ${names[1]} + آخرين';
  }

  Future<String?> _promptGroupName({required String suggestedName}) async {
    final ctrl = TextEditingController(text: suggestedName);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اسم المجموعة'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'أدخل اسم المجموعة'),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(context, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('تأكيد')),
        ],
      ),
    );
  }

  Widget _buildChatItem(ChatModel chat) {
    // Custom Time Badge
    final trailingTime = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          chat.getLastActivityText(AppLocalizations.of(context)),
          style: TextStyle(
            fontSize: 11,
            color: chat.hasUnreadMessages
                ? ThemeConfig.primaryColor
                : Theme.of(context).disabledColor,
            fontWeight:
                chat.hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        if (chat.hasUnreadMessages) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: ThemeConfig.primaryColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: ThemeConfig.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ]),
            child: Text(
              '${chat.unreadCount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );

    final trailing = chat.isIndividual
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              trailingTime,
              // Only simple pop up for options
            ],
          )
        : trailingTime;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ]),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openChat(chat),
          onLongPress: () => _showChatOptions(chat),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildChatAvatar(chat),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (chat.isMuted)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: Icon(Icons.volume_off,
                                  size: 14,
                                  color: Theme.of(context).disabledColor),
                            ),
                          if (chat.isPinned)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: Icon(Icons.push_pin,
                                  size: 14, color: ThemeConfig.accentColor),
                            ),
                          Flexible(
                            child: Text(
                              chat.getDisplayName(AppLocalizations.of(context)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: chat.hasUnreadMessages
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (chat.isIndividual)
                            StreamBuilder<data_user.AppUser?>(
                              stream: Get.find<IUserRepository>().watchById(
                                chat.participantIds.firstWhere(
                                    (id) => id != authController.userId,
                                    orElse: () => ''),
                              ),
                              builder: (context, snap) {
                                if (!snap.hasData) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(left: 8, right: 8),
                                  child: PresenceIndicatorWidget(
                                      status: snap.data!.status, size: 8),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chat.getLastMessageText(AppLocalizations.of(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: chat.hasUnreadMessages
                              ? Theme.of(context).textTheme.bodyMedium?.color
                              : Theme.of(context).disabledColor,
                          fontWeight: chat.hasUnreadMessages
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatAvatar(ChatModel chat) {
    if (chat.avatar != null && chat.avatar!.isNotEmpty) {
      return Hero(
        tag: 'chat_avatar_list_${chat.id.isEmpty ? chat.hashCode : chat.id}',
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
                image: AssetImage(chat.avatar!), fit: BoxFit.cover),
            border: Border.all(color: Theme.of(context).dividerColor, width: 1),
          ),
        ),
      );
    }
    return _buildDefaultAvatar(chat);
  }

  Widget _buildDefaultAvatar(ChatModel chat) {
    // Generate gradient based on name hash
    final colorHash = chat.name.hashCode;
    final color1 = Colors.primaries[colorHash % Colors.primaries.length];
    final color2 = Colors.primaries[(colorHash + 1) % Colors.primaries.length];

    return Hero(
      tag: 'chat_avatar_list_${chat.id.isEmpty ? chat.hashCode : chat.id}',
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color1.withValues(alpha: 0.8),
                color2.withValues(alpha: 0.8)
              ]),
        ),
        child: Icon(
          chat.isGroup ? Icons.groups_rounded : Icons.person_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  void _openChat(ChatModel chat) {
    // Create a mock other user for individual chats
    ui_user.UserModel? otherUser;
    if (chat.isIndividual) {
      otherUser = ui_user.UserModel.mock(
        name: chat.getDisplayName(AppLocalizations.of(Get.context!)),
        status: ui_user.UserStatus.online,
      );
    }

    // Mark as read when opening the chat
    chatController.markChatAsRead(chat.id);

    Get.to(
      () => ChatScreen(chat: chat, otherUser: otherUser),
      transition: Transition.rightToLeft,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _showChatOptions(ChatModel chat) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.archive, color: Colors.blue)),
              title: Text(chat.isArchived
                  ? AppLocalizations.of(context).unarchive
                  : AppLocalizations.of(context).archive),
              onTap: () {
                Navigator.pop(context);
                _toggleArchive(chat);
              },
            ),
            ListTile(
              leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(chat.isMuted ? Icons.volume_up : Icons.volume_off,
                      color: Colors.orange)),
              title: Text(chat.isMuted
                  ? AppLocalizations.of(context).unmute
                  : AppLocalizations.of(context).mute),
              onTap: () {
                Navigator.pop(context);
                _toggleMute(chat);
              },
            ),
            ListTile(
              leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(
                      chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                      color: Colors.teal)),
              title: Text(chat.isPinned
                  ? AppLocalizations.of(context).unpin
                  : AppLocalizations.of(context).pin),
              onTap: () {
                Navigator.pop(context);
                _togglePin(chat);
              },
            ),
            const Divider(),
            ListTile(
              leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.delete, color: Colors.red)),
              title: Text(AppLocalizations.of(context).delete,
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _deleteChat(chat);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _createIndividualChat() {
    // ... (Existing logic can remain, or be invoked via FAB)
    final nameController = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).createIndividualChat),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
              hintText: AppLocalizations.of(context).personNameHint),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) =>
              Navigator.pop(context, nameController.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text(AppLocalizations.of(context).create),
          ),
        ],
      ),
    ).then((name) async {
      if (name == null || name.isEmpty) return;

      final otherUserId = 'mock_${DateTime.now().millisecondsSinceEpoch}';
      final chat = await chatController.createIndividualChat(
        otherUserId: otherUserId,
        otherUserName: name,
      );

      final otherUser =
          ui_user.UserModel.mock(name: name, status: ui_user.UserStatus.online);
      unawaited(Get.to(
        () => ChatScreen(chat: chat, otherUser: otherUser),
        transition: Transition.rightToLeft,
        duration: const Duration(milliseconds: 300),
      ));
    });
  }

  void _createGroupChat() {
    // ...
    final nameController = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).createGroup),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
              hintText: AppLocalizations.of(context).groupNameHint),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) =>
              Navigator.pop(context, nameController.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text(AppLocalizations.of(context).create),
          ),
        ],
      ),
    ).then((name) async {
      if (name == null || name.isEmpty) return;

      final chat = await chatController.createGroupChat(
        name: name,
        participantIds: [authController.userId],
      );

      unawaited(Get.to(
        () => ChatScreen(chat: chat),
        transition: Transition.rightToLeft,
        duration: const Duration(milliseconds: 300),
      ));
    });
  }

  void _toggleArchive(ChatModel chat) {
    unawaited(chatController.archiveChat(chat.id, !chat.isArchived));
  }

  Future<void> _toggleMute(ChatModel chat) async {
    if (chat.isMuted) {
      unawaited(chatController.muteChatUntil(chat.id, null)); // Unmute
      return;
    }

    final l10n = AppLocalizations.of(context);
    final duration = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l10n.muteNotifications,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              title: Text('15 ${l10n.minutes(15)}'),
              onTap: () => Navigator.pop(
                  context, DateTime.now().add(const Duration(minutes: 15))),
            ),
            ListTile(
              title: Text('1 ${l10n.hours(1)}'),
              onTap: () => Navigator.pop(
                  context, DateTime.now().add(const Duration(hours: 1))),
            ),
            ListTile(
              title: Text('8 ${l10n.hours(8)}'),
              onTap: () => Navigator.pop(
                  context, DateTime.now().add(const Duration(hours: 8))),
            ),
            ListTile(
              title: Text('24 ${l10n.hours(24)}'),
              onTap: () => Navigator.pop(
                  context, DateTime.now().add(const Duration(hours: 24))),
            ),
            ListTile(
              title: Text(l10n.indefinitely),
              onTap: () => Navigator.pop(
                  context, DateTime.now().add(const Duration(days: 365 * 100))),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (duration != null) {
      unawaited(chatController.muteChatUntil(chat.id, duration));
    }
  }

  void _togglePin(ChatModel chat) {
    unawaited(chatController.pinChat(chat.id, !chat.isPinned));
  }

  void _deleteChat(ChatModel chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).deleteChatTitle),
        content: Text(AppLocalizations.of(context).confirmDeleteChatWithName(
            chat.getDisplayName(AppLocalizations.of(context)))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(chatController.deleteChat(chat.id));
            },
            child: Text(AppLocalizations.of(context).delete,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
