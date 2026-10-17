import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/language_controller.dart';
import 'package:talkmate_ai/controllers/theme_controller.dart';
import 'package:talkmate_ai/data/models/chat_model.dart' as chat_models;
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/models/chat_model.dart' as ui_models;
import 'package:talkmate_ai/screens/chat_screen.dart';
import 'package:talkmate_ai/screens/create_group_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _auth = Get.find<AuthController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/logo/talkmate_ai_logo_transparent.png',
            fit: BoxFit.contain,
          ),
        ),
        title: Text(AppLocalizations.of(context).groups),
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
              onPressed: () => Get.toNamed('/friend_requests'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Get.toNamed('/search'),
          ),
        ],
      ),
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton(
        heroTag: 'groups_fab',
        onPressed: () => Get.to(() => const CreateGroupScreen()),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.group_add_rounded),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final uid = _auth.userId;
    if (uid.isEmpty) {
      return _buildEmpty(context,
          message: AppLocalizations.of(context).pleaseLoginToView);
    }
    return StreamBuilder<List<chat_models.Chat>>(
      stream: Get.find<IChatRepository>().watchUserChatsNoOrder(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data ?? const [];
        final groups =
            all.where((c) => c.isGroup == true).toList(growable: false);
        if (groups.isEmpty) {
          return _buildEmpty(context);
        }
        return ListView.builder(
          itemCount: groups.length,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemBuilder: (context, index) {
            final g = groups[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5)),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Hero(
                    tag: 'groups_avatar_list_${g.id}',
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        (g.groupName ?? 'G')[0].toUpperCase(),
                        style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  title: Text(
                    g.groupName ?? 'مجموعة',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.people_outline,
                            size: 14, color: theme.hintColor),
                        const SizedBox(width: 4),
                        Text('${g.participantIds.length} عضو',
                            style: TextStyle(color: theme.hintColor)),
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(chat: _toUiChat(g))),
                      );
                    },
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(chat: _toUiChat(g))),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context, {String? message}) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.groups_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.2)),
          const SizedBox(height: 24),
          Text(
            message ?? l10n.noGroupsYet,
            style:
                theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Get.to(() => const CreateGroupScreen()),
            icon: const Icon(Icons.add),
            label: Text(l10n.createYourFirstGroup),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          )
        ],
      ),
    );
  }

  ui_models.ChatModel _toUiChat(chat_models.Chat c) {
    return ui_models.ChatModel(
      id: c.id,
      name: c.groupName ?? AppLocalizations.of(context).group,
      type: ui_models.ChatType.group,
      participantIds: c.participantIds,
    );
  }
}
