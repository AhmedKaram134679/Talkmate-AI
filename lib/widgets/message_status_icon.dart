import 'package:flutter/material.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';

class MessageStatusIcon extends StatelessWidget {
  final MessageState state;
  final double size;

  const MessageStatusIcon({
    super.key,
    required this.state,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case MessageState.pending:
        return Icon(
          Icons.access_time_rounded,
          size: size,
          color: Colors.grey.withValues(alpha: 0.6),
        );
      case MessageState.sent:
        return Icon(
          Icons.check,
          size: size,
          color: Colors.grey.withValues(alpha: 0.6),
        );
      case MessageState.delivered:
        return Icon(
          Icons.done_all,
          size: size,
          color: Colors.grey.withValues(alpha: 0.6),
        );
      case MessageState.read:
        return Icon(
          Icons.done_all,
          size: size,
          color: Colors.blue,
        );
      case MessageState.failed:
        return Icon(
          Icons.error_outline_rounded,
          size: size,
          color: Colors.red,
        );
    }
  }
}

// Map the data model MessageStatus to UI MessageState if needed, 
// or update the Screen to use data model directly. 
// Given the existing ChatController.MessageState enum, I'll extend it.
