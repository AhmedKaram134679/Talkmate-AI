import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/chat_controller.dart';
import '../../localization/app_localizations.dart';
import '../../models/message_model.dart';

class ChatReplyPreview extends StatelessWidget {
  final MessageModel message;
  final String chatId;
  final bool isMe;
  final Function(String) onScrollToMessage;

  const ChatReplyPreview({
    super.key,
    required this.message,
    required this.chatId,
    required this.isMe,
    required this.onScrollToMessage,
  });

  @override
  Widget build(BuildContext context) {
    final chatController = Get.find<ChatController>();
    final replyToMsg = chatController
        .getMessages(chatId)
        .firstWhereOrNull((m) => m.id == message.replyToMessageId);

    if (replyToMsg == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return InkWell(
      onTap: () => onScrollToMessage(replyToMsg.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isMe ? Colors.black : theme.colorScheme.surface)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            right: BorderSide(
              color: isMe ? Colors.white70 : theme.primaryColor,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              replyToMsg.senderId == Get.find<AuthController>().userId
                  ? l10n.user
                  : l10n.member,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: isMe ? Colors.white70 : theme.primaryColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _getMessageSummary(replyToMsg, l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: (isMe ? Colors.white : theme.colorScheme.onSurface)
                    .withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMessageSummary(MessageModel msg, AppLocalizations l10n) {
    if (msg.isDeleted) {
      return l10n.messageDeleted;
    }
    switch (msg.type) {
      case MessageType.text:
        return msg.content;
      case MessageType.image:
        return '📷 صورة';
      case MessageType.video:
        return '🎥 فيديو';
      case MessageType.audio:
        return '🎵 رسالة صوتية';
      case MessageType.file:
        return '📎 ملف';
      case MessageType.location:
        return '📍 موقع';
      case MessageType.contact:
        return '👤 جهة اتصال';
      case MessageType.chat:
        return '💬 محادثة';
      case MessageType.call:
        return '📞 مكالمة';
    }
  }
}
