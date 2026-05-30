import 'package:flutter/material.dart';

import '../../localization/app_localizations.dart';
import '../../models/message_model.dart';
import '../voice_message_bubble.dart';

class ChatMessageContent extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isCurrentMatch;
  final TextSpan Function(String, Color,
      {TextStyle? style, Color? highlightColor}) buildHighlightedText;
  final String firstUrl;
  final Widget Function(String, bool) buildLinkPreview;
  final Future<void> Function(String) openUrl;
  final String Function(String) inferFileName;
  final String Function(int) formatBytes;

  const ChatMessageContent({
    super.key,
    required this.message,
    required this.isMe,
    required this.isCurrentMatch,
    required this.buildHighlightedText,
    required this.firstUrl,
    required this.buildLinkPreview,
    required this.openUrl,
    required this.inferFileName,
    required this.formatBytes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final me = message.senderId;

    final deletedGlobally = (message.metadata?['deleted'] == true);
    final deletedByName = message.metadata?['deletedByName'] as String?;
    final deletedForMap = (message.metadata?['deletedFor'] is Map)
        ? (message.metadata!['deletedFor'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    final deletedForMe = deletedForMap[me] == true;

    if (deletedGlobally) {
      final who = (deletedByName != null && deletedByName.isNotEmpty)
          ? deletedByName
          : l10n.member;
      return Text(
        isMe ? l10n.youDeletedMessage : l10n.deletedBy(who),
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: (isMe ? Colors.white : theme.colorScheme.onSurface)
              .withValues(alpha: 0.7),
        ),
      );
    }

    if (deletedForMe) {
      return Text(
        l10n.youDeletedMessage,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: (isMe ? Colors.white : theme.colorScheme.onSurface)
              .withValues(alpha: 0.7),
        ),
      );
    }

    // Audio bubble
    if (message.isAudioMessage && message.metadata?['mediaUrl'] != null) {
      return VoiceMessageBubble(
        url: message.metadata!['mediaUrl'] as String,
        isMe: isMe,
      );
    }

    // Image bubble
    if (message.isImageMessage && message.metadata?['mediaUrl'] != null) {
      final url = message.metadata!['mediaUrl'] as String;
      final thumb = message.metadata?['thumbnailUrl'] as String?;
      return _buildImageWidget(
          context, thumb?.isNotEmpty == true ? thumb! : url, isMe, l10n);
    }

    // Video bubble
    if (message.isVideoMessage && message.metadata?['mediaUrl'] != null) {
      final url = message.metadata!['mediaUrl'] as String;
      final thumb = message.metadata?['thumbnailUrl'] as String?;
      return _buildVideoWidget(context, url, thumb, isMe);
    }

    // File bubble
    if (message.isFileMessage && message.metadata?['mediaUrl'] != null) {
      return _buildFileWidget(context, message.metadata!['mediaUrl'] as String,
          message.metadata?['mediaSize'] as int?, isMe, l10n);
    }

    // Fallback: Text
    final onColor = isMe ? Colors.white : theme.colorScheme.onSurface;
    final rich = RichText(
      text: buildHighlightedText(
        message.getDisplayContent(l10n),
        onColor,
        highlightColor: isCurrentMatch
            ? (theme.brightness == Brightness.dark
                ? Colors.lightGreenAccent.withValues(alpha: 0.60)
                : Colors.orange.withValues(alpha: 0.60))
            : (theme.brightness == Brightness.dark
                ? Colors.amber.withValues(alpha: 0.30)
                : Colors.yellow.withValues(alpha: 0.45)),
      ),
    );

    if (firstUrl.isEmpty) return rich;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        rich,
        const SizedBox(height: 6),
        buildLinkPreview(firstUrl, isMe),
      ],
    );
  }

  Widget _buildImageWidget(
      BuildContext context, String url, bool isMe, AppLocalizations l10n) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
          maxHeight: 260,
        ),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => _buildErrorState(
              context, isMe, l10n.imageLoadError, Icons.broken_image),
        ),
      ),
    );
  }

  Widget _buildVideoWidget(
      BuildContext context, String url, String? thumb, bool isMe) {
    return GestureDetector(
      onTap: () => openUrl(url),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.6,
                maxHeight: 260,
              ),
              child: thumb != null && thumb.isNotEmpty
                  ? Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) =>
                          _buildErrorPlaceholder(Icons.videocam_off),
                    )
                  : _buildErrorPlaceholder(Icons.videocam),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(10),
            child: const Icon(Icons.play_arrow, size: 36, color: Colors.white),
          )
        ],
      ),
    );
  }

  Widget _buildFileWidget(BuildContext context, String url, int? size,
      bool isMe, AppLocalizations l10n) {
    final fileName = inferFileName(url);
    final onColor =
        isMe ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: onColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, size: 28, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: onColor, fontWeight: FontWeight.w600)),
                if (size != null)
                  Text(formatBytes(size),
                      style: TextStyle(
                          fontSize: 12, color: onColor.withValues(alpha: 0.7))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: l10n.openOrDownload,
            icon: Icon(Icons.download, color: onColor),
            onPressed: () => openUrl(url),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
      BuildContext context, bool isMe, String text, IconData icon) {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: Colors.grey),
          const SizedBox(height: 6),
          Text(text,
              style: TextStyle(
                color: (isMe
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface)
                    .withValues(alpha: 0.75),
                fontSize: 12,
              )),
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder(IconData icon) {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: Icon(icon, size: 36, color: Colors.grey),
    );
  }
}
