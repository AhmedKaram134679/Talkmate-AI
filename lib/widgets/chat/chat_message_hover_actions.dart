import 'package:flutter/material.dart';
import '../../models/message_model.dart';

class ChatMessageHoverActions extends StatefulWidget {
  final Widget child;
  final MessageModel message;
  final bool isMe;
  final VoidCallback onReaction;
  final VoidCallback onReply;

  const ChatMessageHoverActions({
    super.key,
    required this.child,
    required this.message,
    required this.isMe,
    required this.onReaction,
    required this.onReply,
  });

  @override
  State<ChatMessageHoverActions> createState() =>
      _ChatMessageHoverActionsState();
}

class _ChatMessageHoverActionsState extends State<ChatMessageHoverActions> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_isHovered)
            Positioned.directional(
              textDirection: Directionality.of(context),
              top: -20,
              start: widget.isMe ? 0 : null,
              end: widget.isMe ? null : 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_reaction_outlined, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: widget.onReaction,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.reply, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: widget.onReply,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
