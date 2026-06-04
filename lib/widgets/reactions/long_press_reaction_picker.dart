import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LongPressReactionPicker extends StatefulWidget {
  final Offset position;
  final List<String> emojis;
  final Function(String) onEmojiSelected;
  final VoidCallback onDismiss;

  const LongPressReactionPicker({
    super.key,
    required this.position,
    required this.emojis,
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  @override
  State<LongPressReactionPicker> createState() =>
      _LongPressReactionPickerState();
}

class _LongPressReactionPickerState extends State<LongPressReactionPicker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _controller.forward();
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Adjust position to stay within screen
    double left = widget.position.dx - 100;
    if (left < 10) left = 10;
    if (left + 220 > size.width) left = size.width - 230;

    double top = widget.position.dy - 70;
    if (top < 50) top = widget.position.dy + 40;

    return Stack(
      children: [
        GestureDetector(
          onTap: widget.onDismiss,
          child: Container(
            color: Colors.transparent,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(30),
              color: Theme.of(context).colorScheme.surface,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.emojis.map((emoji) {
                    return _ReactionItem(
                      emoji: emoji,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onEmojiSelected(emoji);
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionItem extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _ReactionItem({required this.emoji, required this.onTap});

  @override
  State<_ReactionItem> createState() => _ReactionItemState();
}

class _ReactionItemState extends State<_ReactionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isHovered = true),
      onTapUp: (_) => setState(() => _isHovered = false),
      onTapCancel: () => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.4 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 26),
          ),
        ),
      ),
    );
  }
}
