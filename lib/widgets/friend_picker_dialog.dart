import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/utils/user_display.dart';

class FriendPickerDialog extends StatefulWidget {
  final bool multiSelect;
  final String? title;

  const FriendPickerDialog({
    super.key,
    this.multiSelect = false,
    this.title,
  });

  static Future<List<String>?> pick(
    BuildContext context, {
    bool multiSelect = false,
    String? title,
  }) async {
    return showDialog<List<String>>(
      context: context,
      builder: (context) => FriendPickerDialog(
        multiSelect: multiSelect,
        title: title,
      ),
    );
  }

  @override
  State<FriendPickerDialog> createState() => _FriendPickerDialogState();
}

class _FriendPickerDialogState extends State<FriendPickerDialog> {
  final Set<String> selectedIds = {};
  final String myId = Get.find<AuthController>().userId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final displayTitle = widget.title ?? l10n.chooseFriend;
    return AlertDialog(
      title: Text(displayTitle),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: StreamBuilder<List<String>>(
          stream: Get.find<IFriendshipRepository>().watchAllForUser(myId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snapshot.data ?? const <String>[];
            if (list.isEmpty) {
              return Center(child: Text(l10n.noFriendsToSelect));
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final otherId = list[index];
                return StreamBuilder<AppUser?>(
                  stream: Get.find<IUserRepository>().watchById(otherId),
                  builder: (context, userSnap) {
                    final u = userSnap.data;
                    final isSelected = selectedIds.contains(otherId);
                    return ListTile(
                      leading:
                          UserDisplay.avatarCircle(user: u, userId: otherId),
                      title: Text(UserDisplay.nameOrFallback(u, otherId)),
                      subtitle: Text(u?.email ?? ''),
                      trailing: widget.multiSelect
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    selectedIds.add(otherId);
                                  } else {
                                    selectedIds.remove(otherId);
                                  }
                                });
                              },
                            )
                          : null,
                      onTap: () {
                        if (widget.multiSelect) {
                          setState(() {
                            if (isSelected) {
                              selectedIds.remove(otherId);
                            } else {
                              selectedIds.add(otherId);
                            }
                          });
                        } else {
                          Navigator.pop(context, [otherId]);
                        }
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        if (widget.multiSelect)
          ElevatedButton(
            onPressed: () => Navigator.pop(context, selectedIds.toList()),
            child: Text(l10n.confirm),
          ),
      ],
    );
  }
}
