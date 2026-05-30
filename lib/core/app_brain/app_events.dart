import 'package:flutter/foundation.dart';

/// AppEvent: Base class for all cross-feature signals in the system.
@immutable
abstract class AppBrainEvent {
  final DateTime timestamp;
  final String source; // e.g., 'chat', 'calls', 'system'
  final Map<String, dynamic> metadata;

  AppBrainEvent({
    required this.source,
    Map<String, dynamic>? metadata,
  })  : timestamp = DateTime.now(),
        metadata = metadata ?? {};

  @override
  String toString() => '[$source] ${runtimeType.toString()} @ $timestamp';
}

/// Feature Specific Event Types
class CallEvent extends AppBrainEvent {
  final String callId;
  final String status; // ringing, ongoing, ended

  CallEvent({
    required super.source,
    required this.callId,
    required this.status,
    super.metadata,
  });
}

class ChatEvent extends AppBrainEvent {
  final String chatId;
  final String action; // newMessage, typing, read

  ChatEvent({
    required super.source,
    required this.chatId,
    required this.action,
    super.metadata,
  });
}

class SystemEvent extends AppBrainEvent {
  final String type; // networkChange, lowMemory, backgrounding

  SystemEvent({
    required super.source,
    required this.type,
    super.metadata,
  });
}
