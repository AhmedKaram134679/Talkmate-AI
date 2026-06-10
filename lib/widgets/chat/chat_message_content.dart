import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/data/models/media_state_model.dart';
import 'package:talkmate_ai/data/services/media_state_store.dart';
import 'package:talkmate_ai/models/message_model.dart';
import 'package:talkmate_ai/screens/media_gallery_screen.dart';
import 'package:talkmate_ai/utils/forensic_logger.dart';

import '../../localization/app_localizations.dart';
import '../voice_message_bubble.dart';

class ChatMessageContent extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isCurrentMatch;
  final TextSpan Function(String, Color,
      {TextStyle? style, Color? highlightColor}) buildHighlightedText;
  final String firstUrl;
  final Widget Function(String, bool) buildLinkPreview;
  final Future<void> Function(String url, String messageId, String chatId)
      openUrl;
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

    // Resolve Media strictly from store (pass message for auto-seeding fallback)
    final media =
        MediaStateStore.to.resolveForMessage(message.id, message: message);

    // Audio bubble
    final isAudio = message.isAudioMessage && media.isAvailable;
    if (isAudio) {
      return VoiceMessageBubble(
        message: message,
        isMe: isMe,
      );
    }

    // Image bubble
    final isImage = message.isImageMessage &&
        (media.isAvailable ||
            media.status == MediaUploadStatus.uploading ||
            media.status == MediaUploadStatus.failed);
    if (isImage) {
      return _buildImageWidget(context, media, isMe, l10n);
    }

    // Video bubble
    final isVideo = message.isVideoMessage;
    if (isVideo) {
      return _buildVideoWidget(context, media, isMe);
    }

    // File bubble
    final isFile = message.isFileMessage &&
        (media.isAvailable ||
            media.status == MediaUploadStatus.uploading ||
            media.status == MediaUploadStatus.failed);
    if (isFile) {
      return _buildFileWidget(
          context, media, message.metadata?['mediaSize'] as int?, isMe, l10n);
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

  Widget _buildImageWidget(BuildContext context, ResolvedMedia media, bool isMe,
      AppLocalizations l10n) {
    Widget imageWidget;
    if (media.hasLocalFile) {
      imageWidget = Image.file(
        File(media.localPath!),
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => media.remoteUrl != null
            ? Image.network(media.remoteUrl!,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => _buildErrorState(
                    context, isMe, l10n.imageLoadError, Icons.broken_image))
            : _buildErrorState(
                context, isMe, l10n.imageLoadError, Icons.broken_image),
      );
    } else if (media.remoteUrl != null) {
      imageWidget = Image.network(
        media.remoteUrl!,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => _buildErrorState(
            context, isMe, l10n.imageLoadError, Icons.broken_image),
      );
    } else {
      imageWidget = _buildErrorState(
          context, isMe, l10n.imageLoadError, Icons.broken_image);
    }

    return GestureDetector(
      onTap: () {
        if (media.status == MediaUploadStatus.uploading) return;
        final chatController = Get.find<ChatController>();
        final messages = chatController.getMessages(message.chatId);
        final mediaMessages = MediaGalleryDataSource.getMediaMessages(messages);
        final index =
            MediaGalleryDataSource.getMediaIndex(messages, message.id);
        if (index >= 0) {
          Get.to(() => MediaGalleryScreen(
                images: mediaMessages,
                initialIndex: index,
              ));
        }
      },
      child: Hero(
        tag: message.id,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
              maxHeight: 260,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                imageWidget,
                if (media.status == MediaUploadStatus.uploading)
                  Container(
                    color: Colors.black38,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: media.progress > 0 ? media.progress : null,
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                if (media.status == MediaUploadStatus.failed)
                  Container(
                    color: Colors.black45,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 36),
                          SizedBox(height: 4),
                          Text(
                            'فشل الرفع',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoWidget(
      BuildContext context, ResolvedMedia media, bool isMe) {
    final localThumb = media.thumbnailPath;
    final remoteThumb = message.metadata?['thumbnailUrl'] as String?;

    Widget imageWidget;
    if (localThumb != null && localThumb.isNotEmpty && File(localThumb).existsSync()) {
      imageWidget = Image.file(
        File(localThumb),
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => _buildVideoPlaceholder(remoteThumb),
      );
    } else {
      imageWidget = _buildVideoPlaceholder(remoteThumb);
    }

    // Forensic logging for card rendering
    ForensicLogger.log(
      tag: 'VIDEO_UI_REBUILT',
      messageId: message.id,
      localId: message.id,
      chatId: message.chatId,
      filename: media.fileName ?? message.originalFileName,
      localFilePath: media.localPath ?? message.localFilePath,
      thumbnailPath: localThumb,
      remoteUrl: media.remoteUrl,
      status: media.status.name,
      uploadProgress: media.progress,
    );

    return GestureDetector(
      onTap: () {
        if (media.status == MediaUploadStatus.uploading ||
            media.status == MediaUploadStatus.queued) {
          return;
        }
        final url = media.remoteUrl ?? media.localPath ?? '';
        if (url.isNotEmpty) {
          openUrl(url, message.id, message.chatId);
        }
      },
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(child: imageWidget),
                  if (media.status == MediaUploadStatus.uploading ||
                      media.status == MediaUploadStatus.queued)
                    Container(
                      color: Colors.black38,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: media.progress > 0 ? media.progress : null,
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                  if (media.status == MediaUploadStatus.failed)
                    Container(
                      color: Colors.black45,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.redAccent, size: 36),
                            SizedBox(height: 4),
                            const Text(
                              'فشل الرفع',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Sleek filename overlay at the bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                      child: Text(
                        media.fileName ?? message.originalFileName ?? 'فيديو',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (media.status != MediaUploadStatus.uploading &&
              media.status != MediaUploadStatus.queued &&
              media.status != MediaUploadStatus.failed)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(10),
              child:
                  const Icon(Icons.play_arrow, size: 36, color: Colors.white),
            )
        ],
      ),
    );
  }

  Widget _buildVideoPlaceholder(String? remoteThumb) {
    if (remoteThumb != null && remoteThumb.isNotEmpty) {
      return Image.network(
        remoteThumb,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => _buildErrorPlaceholder(Icons.videocam_off),
      );
    }
    return _buildErrorPlaceholder(Icons.videocam);
  }

  Widget _buildFileWidget(BuildContext context, ResolvedMedia media, int? size,
      bool isMe, AppLocalizations l10n) {
    // Priority: Metadata name > Resolved filename > Fallback
    final fileName = message.userReactions['originalFileName'] ??
        message.userReactions['filename'] ??
        media.fileName ??
        'ملف';
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
          if (media.status == MediaUploadStatus.uploading)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: media.progress > 0 ? media.progress : null,
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(onColor),
              ),
            )
          else if (media.status == MediaUploadStatus.failed)
            Icon(Icons.error_outline, color: Colors.redAccent, size: 24)
          else
            IconButton(
              tooltip: l10n.openOrDownload,
              icon: Icon(Icons.download, color: onColor),
              onPressed: () {
                final url = media.remoteUrl ?? media.localPath ?? '';
                if (url.isNotEmpty) {
                  openUrl(url, message.id, message.chatId);
                }
              },
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
