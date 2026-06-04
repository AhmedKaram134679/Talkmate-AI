import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_block_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/screens/profile_screen.dart';
import 'package:talkmate_ai/utils/user_display.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final _auth = Get.find<AuthController>();
  final _friendRepo = Get.find<IFriendshipRepository>();
  final _blockRepo = Get.find<IBlockRepository>();
  final _userRepo = Get.find<IUserRepository>();
  final _chatController = Get.put(ChatController(), permanent: true);

  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  List<AppUser> _results = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.friends),
        bottom: TabBar(
          controller: _tabController,
          tabs: [Tab(text: l10n.friends), Tab(text: l10n.search)],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsTab(l10n),
          _buildSearchTab(l10n),
        ],
      ),
    );
  }

  Widget _buildFriendsTab(AppLocalizations l10n) {
    return Obx(() {
      final loggedIn = _auth.isLoggedInRx.value;
      final uid = _auth.userId;
      if (!loggedIn || uid.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return StreamBuilder<List<String>>(
        stream: _friendRepo.watchAllForUser(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data ?? const <String>[];
          if (list.isEmpty) {
            return Center(child: Text(l10n.noFriendsYet));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, index) {
              final otherId = list[index];
              return StreamBuilder<AppUser?>(
                stream: _userRepo.watchById(otherId),
                builder: (ctx, userSnap) {
                  final u = userSnap.data;
                  final status = u?.status;
                  return ListTile(
                    leading: UserDisplay.avatarCircle(user: u, userId: otherId),
                    title: Text(UserDisplay.nameOrFallback(u, otherId)),
                    subtitle: Text(status == null ? '' : _statusText(status)),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) => _onFriendAction(
                        value,
                        otherId,
                        user: u,
                      ),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                            value: 'view_profile',
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, size: 20),
                                SizedBox(width: 8),
                                Text(l10n.viewProfile),
                              ],
                            )),
                        PopupMenuItem(
                            value: 'chat',
                            child: Row(
                              children: [
                                Icon(Icons.chat_outlined, size: 20),
                                SizedBox(width: 8),
                                Text(l10n.startChat),
                              ],
                            )),
                        PopupMenuItem(
                            value: 'remove',
                            child: Row(
                              children: [
                                Icon(Icons.person_remove_outlined,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.error),
                                const SizedBox(width: 8),
                                Text(l10n.removeFromFriends,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                              ],
                            )),
                        PopupMenuItem(
                            value: 'block',
                            child: Row(
                              children: [
                                Icon(Icons.block,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.error),
                                const SizedBox(width: 8),
                                Text(l10n.block,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                              ],
                            )),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      );
    });
  }

  Widget _buildSearchTab(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: l10n.searchFriendsHint,
              suffixIcon: IconButton(
                icon: _searching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                onPressed: _searching ? null : _doSearch,
              ),
            ),
            onSubmitted: (_) => _doSearch(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _results.isEmpty
                ? Center(child: Text(l10n.noResults))
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final u = _results[index];
                      final me = _auth.userId;
                      final isMe = u.id == me;
                      return ListTile(
                        onTap: () => Get.to(() => ProfileScreen(userId: u.id)),
                        leading:
                            UserDisplay.avatarCircle(user: u, userId: u.id),
                        title: Text(UserDisplay.nameOrFallback(u, u.id)),
                        subtitle: Text(u.about ?? ''),
                        trailing: isMe
                            ? const SizedBox.shrink()
                            : IconButton(
                                tooltip: l10n.startChat,
                                icon: const Icon(Icons.chat_outlined),
                                onPressed: () async {
                                  try {
                                    final name =
                                        UserDisplay.nameOrFallback(u, u.id);
                                    await _chatController.createIndividualChat(
                                      otherUserId: u.id,
                                      otherUserName: name,
                                    );
                                    // Switch to friends tab or close if needed,
                                    // but usually we just navigate to chat
                                    Get.back();
                                  } catch (e) {
                                    Get.snackbar(l10n.error, e.toString(),
                                        snackPosition: SnackPosition.BOTTOM,
                                        backgroundColor: Colors.red,
                                        colorText: Colors.white);
                                  }
                                },
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _doSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      if (mounted) setState(() => _results = []);
      return;
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (mounted) {
      setState(() {
        _searching = true;
        _results = [];
      });
    }

    try {
      final uid = _auth.userId;
      final friendsList = await _friendRepo.getAllForUser(uid);
      if (!mounted) return;

      if (friendsList.isEmpty) {
        setState(() => _results = []);
        return;
      }

      final list = await _userRepo.searchByNameOrEmail(q,
          limit: 30, userIds: friendsList);
      if (!mounted) return;
      setState(() => _results = list);
    } catch (e) {
      if (mounted) {
        Get.snackbar(l10n.error, e.toString(),
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: theme.colorScheme.errorContainer,
            colorText: theme.colorScheme.onErrorContainer);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _onFriendAction(String value, String otherId,
      {AppUser? user}) async {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final uid = _auth.userId;

    if (value == 'view_profile') {
      unawaited(Get.to(() => ProfileScreen(userId: otherId)));
    } else if (value == 'chat') {
      try {
        final name = UserDisplay.nameOrFallback(user, otherId);
        await _chatController.createIndividualChat(
          otherUserId: otherId,
          otherUserName: name,
        );
        if (!mounted) return;
        Get.back();
      } catch (e) {
        if (mounted) {
          Get.snackbar(l10n.error, e.toString(),
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: theme.colorScheme.errorContainer,
              colorText: theme.colorScheme.onErrorContainer);
        }
      }
    } else if (value == 'remove') {
      try {
        await _friendRepo.deleteFriendship(uid, otherId);
        if (!mounted) return;
        Get.snackbar(l10n.doneLabel, l10n.friendRemoved,
            snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        if (mounted) {
          Get.snackbar(l10n.error, e.toString(),
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: theme.colorScheme.errorContainer,
              colorText: theme.colorScheme.onErrorContainer);
        }
      }
    } else if (value == 'block') {
      try {
        await _blockRepo.block(blockerId: uid, blockedId: otherId);
        if (!mounted) return;
        Get.snackbar(l10n.doneLabel, l10n.blocked,
            snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        if (mounted) {
          Get.snackbar(l10n.error, e.toString(),
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: theme.colorScheme.errorContainer,
              colorText: theme.colorScheme.onErrorContainer);
        }
      }
    }
  }

  String _statusText(UserStatus s) {
    final l10n = AppLocalizations.of(context);
    switch (s) {
      case UserStatus.online:
        return l10n.online;
      case UserStatus.busy:
        return l10n.statusBusy;
      case UserStatus.away:
        return l10n.statusAway;
      case UserStatus.offline:
        return l10n.statusOffline;
      case UserStatus.inCall:
        return l10n.statusInCall;
      case UserStatus.inRoomVoice:
        return l10n.statusInRoomVoice;
      case UserStatus.inRoomVideo:
        return l10n.statusInRoomVideo;
    }
  }
}
