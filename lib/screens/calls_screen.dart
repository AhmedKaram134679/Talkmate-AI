import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:talkmate_ai/config/theme_config.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/language_controller.dart';
import 'package:talkmate_ai/controllers/rooms_controller.dart';
import 'package:talkmate_ai/data/models/call_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart' as user_models;
import 'package:talkmate_ai/data/repositories/contracts/i_call_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/models/room_model.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';
import 'package:talkmate_ai/utils/user_display.dart';
import 'package:talkmate_ai/widgets/communication/sovereign_comm_entry_sheet.dart';
import 'package:talkmate_ai/widgets/friend_picker_dialog.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  final AuthController auth = Get.find<AuthController>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  AppLocalizations get l10n => AppLocalizations.of(context);
  String _searchQuery = '';

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = auth.userId;
    if (uid.isEmpty) {
      return _buildEmpty(context, subtitle: l10n.pleaseLoginToViewCalls);
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
        title: Text(l10n.calls),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.language_rounded),
            onPressed: () => Get.find<LanguageController>().toggleLanguage(),
          ),
          IconButton(
            icon: const Icon(Icons.wb_sunny_outlined),
            onPressed: () => Get.changeThemeMode(
                Get.isDarkMode ? ThemeMode.light : ThemeMode.dark),
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
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<List<CallSession>>(
              stream:
                  Get.find<ICallRepository>().watchUserCalls(uid, limit: 100),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var calls = snap.data ?? const <CallSession>[];

                // Simple filtering
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  calls = calls.where((c) {
                    final statusText =
                        _getStatusText(context, c.status).toLowerCase();
                    final typeText = (c.type == CallType.video
                            ? l10n.videoCall
                            : l10n.voiceCall)
                        .toLowerCase();
                    return statusText.contains(q) || typeText.contains(q);
                  }).toList();
                }

                if (calls.isEmpty) {
                  return _buildEmpty(context,
                      subtitle: _searchQuery.isNotEmpty
                          ? l10n.noCallsMatchSearch
                          : null);
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: calls.length,
                  itemBuilder: (context, index) {
                    final c = calls[index];
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(
                          milliseconds: 400 + (index * 50).clamp(0, 500)),
                      curve: Curves.easeOutQuart,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: Opacity(opacity: value, child: child),
                        );
                      },
                      child: _buildCallItem(context, c, uid),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calls_fab',
        onPressed: () {
          // Open friend picker to start a new call
          _reInitiateCallPrompt();
        },
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        child: const Icon(Icons.add_call),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.3
                    : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: l10n.searchInHistoryHint,
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).cardTheme.color,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: TextStyle(color: Theme.of(context).hintColor),
          prefixIconColor: Theme.of(context).hintColor,
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildCallItem(BuildContext context, CallSession c, String uid) {
    final isMissed = c.status == CallStatus.missed;
    final isVideo = c.type == CallType.video;
    final youAreCaller = c.senderId == uid;
    final otherId = youAreCaller ? c.receiverId : c.senderId;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.5),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: StreamBuilder<user_models.AppUser?>(
          stream: Get.find<IUserRepository>().watchById(otherId),
          builder: (context, snapUser) {
            final user = snapUser.data;
            return Hero(
              tag: 'calls_avatar_list_${c.id}',
              child: UserDisplay.avatarCircle(user: user, userId: otherId),
            );
          },
        ),
        title: StreamBuilder<user_models.AppUser?>(
          stream: Get.find<IUserRepository>().watchById(otherId),
          builder: (context, snapUser) {
            final name = UserDisplay.nameOrFallback(snapUser.data, otherId);
            return Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        subtitle: Row(
          children: [
            Icon(
              youAreCaller ? Icons.call_made : Icons.call_received,
              size: 14,
              color: isMissed ? Colors.red : Colors.grey,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${_getStatusText(context, c.status)} • ${_formatDate(c.createdAt)}',
                style: TextStyle(
                  color: isMissed ? Colors.red : theme.disabledColor,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVideo ? Icons.videocam_outlined : Icons.call_outlined,
              color: theme.primaryColor.withValues(alpha: 0.5),
              size: 20,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ThemeConfig.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isVideo ? Icons.videocam : Icons.call,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              onPressed: () => _reInitiateCall(c, otherId, isVideo),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(BuildContext context, CallStatus status) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case CallStatus.missed:
        return l10n.missed;
      case CallStatus.rejected:
        return l10n.rejected;
      case CallStatus.ended:
        return l10n.ended;
      case CallStatus.ongoing:
        return l10n.live;
      default:
        return l10n.unknown;
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inMinutes < 1) {
      return l10n.justNow;
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes} د'; // Keep shorthand for now or localize "m"
    }
    if (difference.inDays < 1) {
      return DateFormat('HH:mm').format(dt);
    }
    if (difference.inDays < 7) {
      return DateFormat('EEEE').format(dt);
    }
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  Future<void> _reInitiateCallPrompt() async {
    final picked = await FriendPickerDialog.pick(
      context,
      multiSelect: false,
      title: AppLocalizations.of(context).chooseFriendToCall,
    );
    if (picked == null || picked.isEmpty) return;

    final otherId = picked.first;
    if (!mounted) return;
    // C7: Show Unified Entry Sheet for the picked friend
    unawaited(showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SovereignCommEntrySheet(
        mode: CommEntryMode.individual,
        targetId: otherId,
        onStartIndividualCall: (isVideo) => _reInitiateCall(
          CallSession(
            id: 'new_${DateTime.now().millisecondsSinceEpoch}',
            senderId: auth.userId,
            receiverId: otherId,
            type: isVideo ? CallType.video : CallType.audio,
            createdAt: DateTime.now(),
          ),
          otherId,
          isVideo,
        ),
        onStartRoom: (isVideo) {
          final roomsCtrl = Get.find<RoomsController>();
          roomsCtrl.createRoom(
            'Global Room with $otherId',
            isVideo ? RoomType.video : RoomType.voice,
          );
          Get.snackbar('تم إنشاء الغرفة', 'تم تجهيز مساحة البث الجماعي بنجاح.',
              snackPosition: SnackPosition.TOP);
        },
      ),
    ));
  }

  Future<void> _reInitiateCall(
      CallSession c, String otherId, bool isVideo) async {
    final l10n = AppLocalizations.of(context);
    try {
      await CallManager.instance.startOutgoingCall(
        calleeId: otherId,
        isVideo: isVideo,
      );
    } catch (e) {
      Get.snackbar(l10n.webRTC, '${l10n.recallFailed}: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _buildEmpty(BuildContext context, {String? subtitle}) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.phone_missed_outlined,
                size: 80,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7)
                    : Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context).calls,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle ?? l10n.noCallsYet,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
