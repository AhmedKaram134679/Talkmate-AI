import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:uuid/uuid.dart';

/// UI Message Model (presentation layer)
///
/// هذا النموذج يخدم العرض والتفاعل داخل واجهة المستخدم ويحتوي حالات إضافية
/// مثل `sending` و`failed`، بعكس نموذج التخزين في Firestore الذي يقتصر على
/// `sent/delivered/read`. التحويل بين هذا النموذج ونموذج البيانات يتم عبر
/// `ChatController` وطبقة المستودعات.
///
/// Message lifecycle (UI vs Firestore):
/// - UI: sending -> sent -> delivered -> read (or failed)
/// - Firestore (persisted): sent -> delivered -> read
///
/// Mapping guidelines:
/// - UI.sending/UI.failed لا يتم حفظهما في Firestore. عند الحفظ يُستخدم أقرب
///   حالة دائمة (عادةً `sent`) ثم تُحدّث لاحقًا إلى `delivered/read`.
/// - الحقول الإضافية الخاصة بالواجهة (مثل النص المعروض، الرد، المرفقات) تبقى
///   في طبقة الواجهة ولا تؤثر على مخطط Firestore.
enum MessageType {
  text,
  image,
  video,
  audio,
  file,
  location,
  contact,
  chat,
  call
}

enum MessageStatus { 
  local,        // Message created locally, not uploaded
  uploading,    // Upload in progress
  uploaded,     // Upload completed, ready to send
  pending,      // Sending to server
  sent,         // Received by server
  delivered,    // Delivered to recipient
  read,         // Read by recipient
  failed        // Upload or send failed
}

/// يمثل رسالة معروضة في الواجهة UI مع بيانات تساعد على التقديم والتفاعل.
class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String? receiverId;
  final String content;
  final MessageType type;
  final MessageStatus status;
  final DateTime timestamp;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final bool isDeleted;
  final bool isEdited;
  final String? replyToMessageId;
  final Map<String, dynamic>? metadata;
  final List<String>? attachments;
  final Map<String, String> userReactions;
  final Map<String, int> reactionCounts;
  final Set<String> syncingReactions;
  
  // Media upload tracking fields (Phase 2)
  final String? localFilePath;
  final String? cachedFilePath;
  final String? localThumbnailPath;
  final String? originalFileName;
  final double uploadProgress;
  final int retryCount;
  final DateTime? lastRetryTime;
  final bool isCached;

  MessageModel({
    String? id,
    required this.chatId,
    required this.senderId,
    this.receiverId,
    required this.content,
    this.type = MessageType.text,
    this.status = MessageStatus.pending,
    DateTime? timestamp,
    this.editedAt,
    this.deletedAt,
    this.isDeleted = false,
    this.isEdited = false,
    this.replyToMessageId,
    this.metadata,
    this.attachments,
    this.userReactions = const {},
    this.reactionCounts = const {},
    this.syncingReactions = const {},
    // Media upload tracking
    this.localFilePath,
    this.cachedFilePath,
    this.localThumbnailPath,
    this.originalFileName,
    this.uploadProgress = 0.0,
    this.retryCount = 0,
    this.lastRetryTime,
    this.isCached = false,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  // Factory constructor for creating from JSON
  factory MessageModel.fromJson(Map<String, dynamic> json) {
    // Parse userReactions (user_id -> emoji)
    Map<String, String> parsedUserReactions = {};
    if (json['userReactions'] != null) {
      parsedUserReactions = Map<String, String>.from(json['userReactions']);
    } else if (json['reactions'] != null) {
      try {
        parsedUserReactions = Map<String, String>.from(json['reactions']);
      } catch (_) {}
    }

    // Parse reactionCounts (emoji -> count)
    Map<String, int> parsedReactionCounts = {};
    if (json['reactionCounts'] != null) {
      parsedReactionCounts = Map<String, int>.from(json['reactionCounts']);
    }

    return MessageModel(
      id: json['id'] as String,
      chatId: json['chatId'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String?,
      content: json['content'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.toString() == 'MessageType.${json['type']}',
        orElse: () => MessageType.text,
      ),
      status: MessageStatus.values.firstWhere(
        (e) => e.toString() == 'MessageStatus.${json['status']}',
        orElse: () => MessageStatus.pending,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      editedAt: json['editedAt'] != null
          ? DateTime.parse(json['editedAt'] as String)
          : null,
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
      isDeleted: json['isDeleted'] as bool? ?? false,
      isEdited: json['isEdited'] as bool? ?? false,
      replyToMessageId: json['replyToMessageId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      attachments: (json['attachments'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      userReactions: parsedUserReactions,
      reactionCounts: parsedReactionCounts,
      syncingReactions: (json['syncingReactions'] as List?)
              ?.map((e) => e as String)
              .toSet() ??
          {},
      // Media upload tracking - backward compatible
      localFilePath: json['localFilePath'] as String?,
      cachedFilePath: json['cachedFilePath'] as String?,
      localThumbnailPath: json['localThumbnailPath'] as String?,
      originalFileName: json['originalFileName'] as String?,
      uploadProgress: (json['uploadProgress'] as num?)?.toDouble() ?? 0.0,
      retryCount: json['retryCount'] as int? ?? 0,
      lastRetryTime: json['lastRetryTime'] != null
          ? DateTime.parse(json['lastRetryTime'] as String)
          : null,
      isCached: json['isCached'] as bool? ?? false,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
      'type': type.toString().split('.').last,
      'status': status.toString().split('.').last,
      'timestamp': timestamp.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'isDeleted': isDeleted,
      'isEdited': isEdited,
      'replyToMessageId': replyToMessageId,
      'metadata': metadata,
      'attachments': attachments,
      'userReactions': userReactions,
      'reactionCounts': reactionCounts,
      // Media upload tracking
      'localFilePath': localFilePath,
      'cachedFilePath': cachedFilePath,
      'localThumbnailPath': localThumbnailPath,
      'originalFileName': originalFileName,
      'uploadProgress': uploadProgress,
      'retryCount': retryCount,
      'lastRetryTime': lastRetryTime?.toIso8601String(),
      'isCached': isCached,
    };
  }

  // Copy with method for updating message data
  MessageModel copyWith({
    String? content,
    MessageType? type,
    MessageStatus? status,
    DateTime? editedAt,
    DateTime? deletedAt,
    bool? isDeleted,
    bool? isEdited,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    List<String>? attachments,
    Map<String, String>? userReactions,
    Map<String, int>? reactionCounts,
    Set<String>? syncingReactions,
    String? localFilePath,
    String? cachedFilePath,
    String? localThumbnailPath,
    String? originalFileName,
    double? uploadProgress,
    int? retryCount,
    DateTime? lastRetryTime,
    bool? isCached,
  }) {
    return MessageModel(
      id: id,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      isEdited: isEdited ?? this.isEdited,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      metadata: metadata ?? this.metadata,
      attachments: attachments ?? this.attachments,
      userReactions: userReactions ?? this.userReactions,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      syncingReactions: syncingReactions ?? this.syncingReactions,
      // Media upload tracking
      localFilePath: localFilePath ?? this.localFilePath,
      cachedFilePath: cachedFilePath ?? this.cachedFilePath,
      localThumbnailPath: localThumbnailPath ?? this.localThumbnailPath,
      originalFileName: originalFileName ?? this.originalFileName,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      retryCount: retryCount ?? this.retryCount,
      lastRetryTime: lastRetryTime ?? this.lastRetryTime,
      isCached: isCached ?? this.isCached,
    );
  }

  // Helper methods
  bool get isTextMessage => type == MessageType.text;
  bool get isImageMessage => type == MessageType.image;
  bool get isVideoMessage => type == MessageType.video;
  bool get isAudioMessage => type == MessageType.audio;
  bool get isFileMessage => type == MessageType.file;
  bool get isLocationMessage => type == MessageType.location;
  bool get isContactMessage => type == MessageType.contact;

  bool get isLocal => status == MessageStatus.local;
  bool get isUploading => status == MessageStatus.uploading;
  bool get isUploaded => status == MessageStatus.uploaded;
  bool get isPending => status == MessageStatus.pending;
  bool get isSent => status == MessageStatus.sent;
  bool get isDelivered => status == MessageStatus.delivered;
  bool get isRead => status == MessageStatus.read;
  bool get isFailed => status == MessageStatus.failed;

  bool get hasAttachments => attachments != null && attachments!.isNotEmpty;
  bool get isReply => replyToMessageId != null;
  bool get hasLocalFile => localFilePath != null && localFilePath!.isNotEmpty;
  bool get hasCachedFile => cachedFilePath != null && cachedFilePath!.isNotEmpty;

  String getTypeText(AppLocalizations l10n) {
    switch (type) {
      case MessageType.text:
        return l10n.msgTypeText;
      case MessageType.image:
        return l10n.msgTypeImage;
      case MessageType.video:
        return l10n.msgTypeVideo;
      case MessageType.audio:
        return l10n.msgTypeAudio;
      case MessageType.file:
        return l10n.msgTypeFile;
      case MessageType.location:
        return l10n.msgTypeLocation;
      case MessageType.contact:
        return l10n.msgTypeContact;
      case MessageType.chat:
        return l10n.msgTypeChat;
      case MessageType.call:
        return l10n.msgTypeCall;
    }
  }

  String getStatusText(AppLocalizations l10n) {
    switch (status) {
      case MessageStatus.local:
        return l10n.msgStatusPending;
      case MessageStatus.uploading:
        return 'جاري الرفع...';
      case MessageStatus.uploaded:
        return 'تم الرفع';
      case MessageStatus.pending:
        return l10n.msgStatusPending;
      case MessageStatus.sent:
        return l10n.msgStatusSent;
      case MessageStatus.delivered:
        return l10n.msgStatusDelivered;
      case MessageStatus.read:
        return l10n.msgStatusRead;
      case MessageStatus.failed:
        return l10n.msgStatusFailed;
    }
  }

  String getDisplayContent(AppLocalizations l10n) {
    if (isDeleted) return l10n.messageDeleted;
    if (type == MessageType.text) return content;
    return getTypeText(l10n);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'MessageModel(id: $id, chatId: $chatId, senderId: $senderId, type: $type, status: $status)';
  }

  // Static method for creating a text message
  static MessageModel text({
    required String chatId,
    required String senderId,
    String? receiverId,
    required String content,
    String? replyToMessageId,
  }) {
    return MessageModel(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      type: MessageType.text,
      replyToMessageId: replyToMessageId,
    );
  }

  // Static method for creating a mock message for testing
  static MessageModel mock({
    String? chatId,
    String? senderId,
    String? content,
    MessageType? type,
    MessageStatus? status,
  }) {
    return MessageModel(
      chatId: chatId ?? 'mock_chat_${DateTime.now().millisecondsSinceEpoch}',
      senderId:
          senderId ?? 'mock_user_${DateTime.now().millisecondsSinceEpoch}',
      content: content ?? 'رسالة تجريبية للاختبار',
      type: type ?? MessageType.text,
      status: status ?? MessageStatus.delivered,
    );
  }
}
