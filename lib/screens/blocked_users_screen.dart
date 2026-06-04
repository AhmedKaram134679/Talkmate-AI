import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_block_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';

class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = Get.find<AuthController>();
    final uid = auth.userId;
    final inputCtrl = TextEditingController();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.blockedUsers)),
      body: uid.isEmpty
          ? Center(child: Text(l10n.loginErrorMessage))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.manageBlockedUsers,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: inputCtrl,
                          decoration: InputDecoration(
                            hintText: l10n.enterUserIdToBlock,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final target = inputCtrl.text.trim();
                          if (target.isEmpty || target == uid) return;
                          try {
                            await Get.find<IBlockRepository>()
                                .block(blockerId: uid, blockedId: target);
                            inputCtrl.clear();
                            Get.snackbar(l10n.blockedUsers, l10n.block,
                                snackPosition: SnackPosition.BOTTOM);
                          } catch (e) {
                            Get.snackbar(l10n.error, e.toString(),
                                snackPosition: SnackPosition.BOTTOM,
                                backgroundColor: Colors.red,
                                colorText: Colors.white);
                          }
                        },
                        icon: const Icon(Icons.block),
                        label: Text(l10n.block),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<List<String>>(
                      stream: Get.find<IBlockRepository>().watchBlockedIds(uid),
                      builder: (context, snap) {
                        final list = snap.data ?? const <String>[];
                        if (list.isEmpty) {
                          return Center(child: Text(l10n.noBlockedUsers));
                        }
                        return ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final bid = list[i];
                            return ListTile(
                              leading: const Icon(Icons.person_off),
                              title: Text(bid),
                              trailing: TextButton.icon(
                                onPressed: () async {
                                  try {
                                    await Get.find<IBlockRepository>().unblock(
                                        blockerId: uid, blockedId: bid);
                                  } catch (e) {
                                    Get.snackbar(l10n.error, e.toString(),
                                        snackPosition: SnackPosition.BOTTOM);
                                  }
                                },
                                icon: const Icon(Icons.undo),
                                label: Text(l10n.unblock),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
