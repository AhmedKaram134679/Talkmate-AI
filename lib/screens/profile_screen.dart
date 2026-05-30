import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/controllers/language_controller.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId; // If null, show current user profile

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = Get.find<AuthController>();
  final _userRepo = Get.find<IUserRepository>();

  bool _loading = true;
  AppUser? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final uid = widget.userId ?? _auth.userId;
      if (uid.isEmpty) return;

      final user = await _userRepo.getById(uid);
      if (mounted) {
        setState(() {
          _user = user;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final l10n = AppLocalizations.of(context);
        Get.snackbar(l10n.error, 'Failed to load user data');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isMe = widget.userId == null || widget.userId == _auth.userId;

    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(
        leading: canPop
            ? const BackButton()
            : Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.asset(
                  'assets/logo/talkmate_ai_logo_transparent.png',
                  fit: BoxFit.contain,
                ),
              ),
        title: Text(l10n.profile),
        centerTitle: true,
        elevation: 0,
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
          if (isMe) ...[
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              onPressed: () => Get.toNamed('/friend_requests'),
            ),
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Get.toNamed('/search'),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            // 1. Profile Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.cardTheme.color ?? theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                        alpha:
                            theme.brightness == Brightness.dark ? 0.2 : 0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child:
                        (_user?.photoUrl != null && _user!.photoUrl!.isNotEmpty)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(50),
                                child: Image.network(_user!.photoUrl!,
                                    fit: BoxFit.cover),
                              )
                            : Icon(
                                Icons.person_rounded,
                                size: 60,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _user?.displayName ?? l10n.unknown,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                  if (_user?.status != null) ...[
                    const SizedBox(height: 8),
                    _buildStatusBadge(_user!.status),
                  ],
                  if (isMe) ...[
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => _auth.logout(),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 12),
                        elevation: 0,
                      ),
                      child: Text(
                        l10n.logout,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 2. Guest Actions (Communication)
            if (!isMe) ...[
              _buildGuestActions(l10n),
              const SizedBox(height: 32),
            ],

            // 3. User Info (Bio, Join Date)
            _buildProfileInfoSection(l10n),

            const SizedBox(height: 32),

            // 4. "Me" Actions
            if (isMe) ...[
              _buildLargeActionButton(
                label: l10n.editProfile,
                icon: Icons.edit_rounded,
                onTap: () =>
                    Get.toNamed('/profile_edit')?.then((_) => _loadUser()),
              ),
              const SizedBox(height: 16),
              _buildLargeActionButton(
                label: l10n.friends,
                icon: Icons.people_alt_rounded,
                onTap: () => Get.toNamed('/friends'),
              ),
              const SizedBox(height: 16),
              _buildLargeActionButton(
                label: l10n.settings,
                icon: Icons.settings_rounded,
                onTap: () => Get.toNamed('/settings'),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(UserStatus status) {
    Color color;
    String label;
    switch (status) {
      case UserStatus.online:
        color = Colors.green;
        label = AppLocalizations.of(context).statusOnline;
        break;
      case UserStatus.busy:
        color = Colors.red;
        label = AppLocalizations.of(context).statusBusy;
        break;
      case UserStatus.away:
        color = Colors.orange;
        label = AppLocalizations.of(context).statusAway;
        break;
      case UserStatus.offline:
        color = Colors.grey;
        label = AppLocalizations.of(context).statusOffline;
        break;
      case UserStatus.inCall:
        color = Colors.blue;
        label = AppLocalizations.of(context).statusInCall;
        break;
      case UserStatus.inRoomVoice:
        color = Colors.orange;
        label = AppLocalizations.of(context).statusInRoomVoice;
        break;
      case UserStatus.inRoomVideo:
        color = Colors.purple;
        label = AppLocalizations.of(context).statusInRoomVideo;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildGuestActions(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCircleAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: l10n.chatTypeChat,
          color: theme.colorScheme.primary,
          onTap: _startChat,
        ),
        _buildCircleAction(
          icon: Icons.call_outlined,
          label: l10n.voiceCall,
          color: theme.colorScheme.secondary,
          onTap: () => _startCall(false),
        ),
        _buildCircleAction(
          icon: Icons.videocam_outlined,
          label: l10n.videoCall,
          color: theme.colorScheme.tertiary,
          onTap: () => _startCall(true),
        ),
      ],
    );
  }

  Widget _buildCircleAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfoSection(AppLocalizations l10n) {
    if (_user == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    final joinDate = DateFormat.yMMMd(l10n.localeName).format(_user!.createdAt);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.info_outline, l10n.bio,
              _user!.about?.isNotEmpty == true ? _user!.about! : l10n.noBio),
          const Divider(height: 32),
          _buildInfoRow(Icons.email_outlined, l10n.email, _user!.email),
          const Divider(height: 32),
          _buildInfoRow(
              Icons.calendar_today_rounded, l10n.joinDate, '$joinDate 📅'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 20, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.hintColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLargeActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon,
            color: Theme.of(context).colorScheme.onPrimary, size: 22),
        label: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
        ),
      ),
    );
  }

  Future<void> _startChat() async {
    if (_user == null) return;
    try {
      final chatCtrl = Get.put(ChatController());
      await chatCtrl.createIndividualChat(
        otherUserId: _user!.id,
        otherUserName: _user!.displayName ?? 'Unknown',
      );
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(AppLocalizations.of(context).error, 'Failed to start chat');
    }
  }

  Future<void> _startCall(bool isVideo) async {
    if (_user == null) return;
    try {
      await CallManager.instance.startOutgoingCall(
        calleeId: _user!.id,
        isVideo: isVideo,
      );
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(AppLocalizations.of(context).error, 'Failed to start call');
    }
  }
}
