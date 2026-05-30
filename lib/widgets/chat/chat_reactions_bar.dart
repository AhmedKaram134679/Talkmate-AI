import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/chat_controller.dart';
import '../../models/message_model.dart';

class ChatReactionsBar extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final String chatId;
  final Function(MessageModel) onLongPress;

  const ChatReactionsBar({
    super.key,
    required this.message,
    required this.isMe,
    required this.chatId,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final counts = message.reactionCounts;
    final myReactions = message.userReactions;
    final chatController = Get.find<ChatController>();
    final authController =
        Get.find<AuthController>(); // Assuming injected globally
    final myUid = authController.userId;
    final myEmoji = myReactions[myUid];
    final syncing = message.syncingReactions;

    if (counts.isEmpty) return const SizedBox.shrink();

    final onColor =
        isMe ? Colors.white : Theme.of(context).colorScheme.onSurface;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: counts.entries.map((e) {
        final label = e.key;
        final cnt = e.value;
        final isSyncing = syncing.contains(label);
        final isSelectedByMe = myEmoji == label;

        return GestureDetector(
          onTap: () => chatController.toggleReaction(
            chatId: chatId,
            messageId: message.id,
            emoji: label,
          ),
          onLongPress: () => onLongPress(message),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 500),
            opacity: isSyncing ? 0.6 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelectedByMe
                    ? (isMe
                        ? Colors.white.withValues(alpha: 0.2)
                        : Theme.of(context)
                            .primaryColor
                            .withValues(alpha: 0.15))
                    : onColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelectedByMe
                      ? (isMe
                          ? Colors.white.withValues(alpha: 0.4)
                          : Theme.of(context)
                              .primaryColor
                              .withValues(alpha: 0.4))
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (cnt > 1) ...[
                    const SizedBox(width: 4),
                    Text('$cnt',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelectedByMe
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelectedByMe
                                ? (isMe
                                    ? Colors.white
                                    : Theme.of(context).primaryColor)
                                : onColor.withValues(alpha: 0.8))),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
