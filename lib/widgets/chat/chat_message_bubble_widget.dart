import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/chat_controller.dart';
import '../../localization/app_localizations.dart';
import '../../models/chat_model.dart';
import '../../models/message_model.dart';
import '../message_status_icon.dart' as ui_status;
import 'chat_link_preview.dart';
import 'chat_message_content.dart';
import 'chat_message_hover_actions.dart';
import 'chat_reactions_bar.dart';
import 'chat_reply_preview.dart';

class ChatMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isCurrentMatch;
  final bool isSelectionMode;
  final bool isSelected;
  final ChatModel chat;
  final String? roleLabel;
  final Function(String) onToggleSelection;
  final Function() onReply;
  final Function() onLongPress;
  final Function(String) onScrollToMessage;
  final Function(MessageModel) onShowReactionDetails;
  final TextSpan Function(String, Color,
      {TextStyle? style, Color? highlightColor}) buildHighlightedText;
  final String Function(DateTime) formatTime;
  final Future<void> Function(String url, String messageId, String chatId) openUrl;
  final String Function(String) inferFileName;
  final String Function(int) formatBytes;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isCurrentMatch,
    required this.isSelectionMode,
    required this.isSelected,
    required this.chat,
    this.roleLabel,
    required this.onToggleSelection,
    required this.onReply,
    required this.onLongPress,
    required this.onScrollToMessage,
    required this.onShowReactionDetails,
    required this.buildHighlightedText,
    required this.formatTime,
    required this.openUrl,
    required this.inferFileName,
    required this.formatBytes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatController = Get.find<ChatController>();
    final l10n = AppLocalizations.of(context);

    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isMe ? 20 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 20),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isSelectionMode) ...[
            Checkbox(
              value: isSelected,
              onChanged: (val) => onToggleSelection(message.id),
            ),
          ],
          if (!isMe) ...[
            _buildAvatar(context, isMe: false),
            const SizedBox(width: 8)
          ],
          Flexible(
            child: ChatMessageHoverActions(
              message: message,
              isMe: isMe,
              onReaction: () {
                /* handled via long press or hover action callback if needed */
              },
              onReply: onReply,
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isMe
                        ? LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.primary.withValues(alpha: 0.85),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isMe
                        ? null
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                    borderRadius: bubbleRadius,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 4)),
                      if (isCurrentMatch)
                        BoxShadow(
                            color: theme.colorScheme.tertiary
                                .withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 2),
                    ],
                    border: isCurrentMatch
                        ? Border.all(
                            color: theme.colorScheme.tertiary
                                .withValues(alpha: 0.8),
                            width: 2)
                        : (!isMe
                            ? Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.2))
                            : null),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.replyToMessageId != null &&
                          message.metadata?['deleted'] != true)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ChatReplyPreview(
                            message: message,
                            chatId: chat.id,
                            isMe: isMe,
                            onScrollToMessage: onScrollToMessage,
                          ),
                        ),
                      ChatMessageContent(
                        message: message,
                        isMe: isMe,
                        isCurrentMatch: isCurrentMatch,
                        buildHighlightedText: buildHighlightedText,
                        firstUrl: ChatController.extractFirstUrl(
                            message.getDisplayContent(l10n)),
                        buildLinkPreview: (url, me) =>
                            ChatLinkPreview(url: url, isMe: me),
                        openUrl: openUrl,
                        inferFileName: inferFileName,
                        formatBytes: formatBytes,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (message.metadata?['editedAt'] != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(l10n.editedLabel,
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: (isMe
                                              ? theme.colorScheme.onPrimary
                                                  .withValues(alpha: 0.7)
                                              : theme.hintColor))),
                                  const SizedBox(width: 2),
                                  Icon(Icons.edit_note,
                                      size: 12,
                                      color: (isMe
                                          ? theme.colorScheme.onPrimary
                                              .withValues(alpha: 0.7)
                                          : theme.hintColor)),
                                ],
                              ),
                            ),
                          Text(
                            formatTime(message.timestamp),
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color:
                                    (isMe ? Colors.white70 : theme.hintColor)),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Obx(() {
                              final liveState =
                                  chatController.messageStates[message.id];
                              if (liveState != null) {
                                return ui_status.MessageStatusIcon(
                                    state: liveState);
                              }
                              return _buildFallbackStatusIcon(message.status);
                            }),
                          ],
                        ],
                      ),
                      if (message.reactionCounts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ChatReactionsBar(
                            message: message,
                            isMe: isMe,
                            chatId: chat.id,
                            onLongPress: onShowReactionDetails,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildAvatar(context, isMe: true, label: roleLabel),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context,
      {required bool isMe, String? label}) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(label,
                style: TextStyle(
                    fontSize: 8,
                    color: theme.hintColor,
                    fontWeight: FontWeight.bold)),
          ),
        CircleAvatar(
          radius: 14,
          backgroundColor: isMe
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          child: Text(
            isMe
                ? AppLocalizations.of(context).me
                : (message.senderId.length > 2
                    ? message.senderId.substring(0, 2).toUpperCase()
                    : '؟'),
            style: TextStyle(
                fontSize: 10,
                color: isMe
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackStatusIcon(MessageStatus status) {
    IconData icon;
    Color color = Colors.white70;
    switch (status) {
      case MessageStatus.local:
        icon = Icons.schedule;
        color = Colors.orangeAccent;
        break;
      case MessageStatus.uploading:
        icon = Icons.cloud_upload;
        color = Colors.blueAccent;
        break;
      case MessageStatus.uploaded:
        icon = Icons.cloud_done;
        color = Colors.blueAccent;
        break;
      case MessageStatus.pending:
        icon = Icons.access_time_rounded;
        break;
      case MessageStatus.sent:
        icon = Icons.done;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        break;
      case MessageStatus.read:
        icon = Icons.done_all;
        color = Colors.lightBlueAccent;
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Colors.redAccent;
        break;
    }
    return Icon(icon, size: 12, color: color);
  }
}
