import 'package:flutter/material.dart';
import '../../services/link_preview_service.dart';

class ChatLinkPreview extends StatefulWidget {
  final String url;
  final bool isMe;

  const ChatLinkPreview({
    super.key,
    required this.url,
    required this.isMe,
  });

  @override
  State<ChatLinkPreview> createState() => _ChatLinkPreviewState();
}

class _ChatLinkPreviewState extends State<ChatLinkPreview> {
  late Future<LinkPreviewData?> _future;

  @override
  void initState() {
    super.initState();
    _future = LinkPreviewService.instance.fetch(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = widget.isMe ? Colors.white : theme.colorScheme.onSurface;

    return FutureBuilder<LinkPreviewData?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 1));
        }
        final data = snap.data;
        if (data == null || data.title == null) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: onColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border:
                Border(left: BorderSide(color: theme.primaryColor, width: 2)),
          ),
          child: InkWell(
            onTap: () {
              /* Open URL logic if needed, usually handled by parent */
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(data.imageUrl!,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink()),
                    ),
                  const SizedBox(height: 4),
                  Text(data.title!,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: onColor),
                      maxLines: 1),
                  if (data.description != null)
                    Text(data.description!,
                        style: TextStyle(
                            fontSize: 11,
                            color: onColor.withValues(alpha: 0.7)),
                        maxLines: 2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
