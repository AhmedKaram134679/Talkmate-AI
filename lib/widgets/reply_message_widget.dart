import 'package:flutter/material.dart';
import '../models/message_model.dart';

class ReplyMessageWidget extends StatelessWidget {
  final MessageModel replyToMessage;
  final VoidCallback onCancel;

  const ReplyMessageWidget({
    super.key,
    required this.replyToMessage,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).primaryColor,
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.reply,
                      size: 16,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'الرد على',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _getMessagePreview(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onCancel,
            iconSize: 20,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ],
      ),
    );
  }

  String _getMessagePreview() {
    switch (replyToMessage.type) {
      case MessageType.text:
        return replyToMessage.content;
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
