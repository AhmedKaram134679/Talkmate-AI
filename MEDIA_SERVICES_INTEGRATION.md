# Media Services Integration Guide

This guide explains how to integrate the WhatsApp-level media system into TalkMate AI.

## Phase 1: Initialization in main.dart

Add this to your `main()` function before running the app:

```dart
import 'package:talkmate_ai/data/services/media_services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase and other core services...
  
  // Initialize media services AFTER Supabase is ready
  final mediaInitializer = MediaServicesInitializer();
  await mediaInitializer.initialize();
  
  // Register services with GetX if needed
  Get.put(mediaInitializer);
  Get.put(mediaInitializer.cacheManager);
  Get.put(mediaInitializer.backgroundUpload);
  Get.put(mediaInitializer.recoveryManager);
  
  runApp(const TalkMateApp());
}
```

## Phase 2: Update ChatScreen Integration

In `chat_screen.dart`, add media support:

```dart
// Import media services
import 'package:talkmate_ai/data/services/media_services.dart';

class ChatScreen extends StatefulWidget {
  // ... existing code ...
  
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late MediaServicesInitializer _mediaServices;
  late VoicePlaybackController _voicePlaybackController;
  
  @override
  void initState() {
    super.initState();
    _mediaServices = Get.find<MediaServicesInitializer>();
    _voicePlaybackController = Get.put(VoicePlaybackController());
  }
  
  // ... existing code ...
}
```

## Phase 3: Implement Instant Preview for Media Upload

When user selects media, use InstantPreviewService:

```dart
Future<void> _handleMediaPick() async {
  final previewService = Get.find<MediaServicesInitializer>().previewService;
  
  // Show file picker
  final XFile? pickedFile = await FilePicker.platform.pickFiles(...);
  if (pickedFile == null) return;
  
  // Create instant preview message (appears immediately)
  final message = await previewService.createInstantPreviewMessage(
    chatId: currentChatId,
    senderId: currentUserId,
    localFilePath: pickedFile.path,
    uploadPath: 'messages/$currentChatId/${uuid.v4()}',
    messageType: MessageType.image, // or video
    replyToMessageId: selectedReplyTo?.id,
  );
  
  // Add to chat immediately (status: local)
  chatController.addMessageToChat(message);
  
  // UI will automatically update as upload progresses:
  // local → uploading → uploaded → sending → sent → delivered → read
}
```

## Phase 4: Implement Media Gallery

When user taps on image in chat:

```dart
void _openMediaGallery(MessageModel tappedImage) {
  final allMessages = chatController.getChatMessages(chatId);
  final mediaMessages = MediaGalleryDataSource.getMediaMessages(allMessages);
  final initialIndex = MediaGalleryDataSource.getMediaIndex(
    allMessages,
    tappedImage.id,
  );
  
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) {
        return MediaGalleryScreen(
          images: mediaMessages,
          initialIndex: initialIndex,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}
```

## Phase 5: Voice Message Queue

When user taps voice message:

```dart
void _playVoiceMessage(MessageModel voiceMessage) {
  final allMessages = chatController.getChatMessages(chatId);
  final voiceController = Get.find<VoicePlaybackController>();
  
  voiceController.buildQueueFrom(
    messages: allMessages,
    selectedMessage: voiceMessage,
  );
}
```

Then display playback controls:

```dart
Obx(
  () {
    final controller = Get.find<VoicePlaybackController>();
    if (controller.currentMessage == null) return SizedBox.shrink();
    
    return AudioPlaybackWidget(
      controller: controller,
      onPlayNext: controller.playNext,
      onPlayPrevious: controller.playPrevious,
      onPause: controller.pausePlayback,
      onResume: controller.resumePlayback,
      onSpeedChange: controller.setSpeed,
    );
  },
)
```

## Phase 6: Handle Upload Progress & Status

Display upload progress in message widgets:

```dart
Obx(
  () {
    final uploadProgress = Get.find<MediaServicesInitializer>()
        .backgroundUpload
        .getUploadProgressObservable(message.id);
    final uploadStatus = Get.find<MediaServicesInitializer>()
        .backgroundUpload
        .getUploadStatusObservable(message.id);
    
    return Stack(
      children: [
        // Message content
        _buildMessageContent(message),
        
        // Upload progress overlay
        if (message.isUploading || message.isLocal)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: uploadProgress.value,
                    ),
                    SizedBox(height: 8),
                    Text('${(uploadProgress.value * 100).toStringAsFixed(0)}%'),
                  ],
                ),
              ),
            ),
          ),
        
        // Failed state
        if (message.isFailed)
          Positioned(
            bottom: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => _showFailureOptions(message),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('فشل الرفع', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
      ],
    );
  },
)
```

## Phase 7: Handle Failed Upload Recovery

Show failure UI:

```dart
void _showFailureOptions(MessageModel failedMessage) {
  final recoveryManager = Get.find<MediaServicesInitializer>().recoveryManager;
  
  showModalBottomSheet(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.refresh),
              title: Text('إعادة المحاولة'),
              onTap: () {
                recoveryManager.retryUpload(failedMessage.id);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.cancel),
              title: Text('إلغاء'),
              onTap: () {
                recoveryManager.cancelUpload(failedMessage.id);
                chatController.removeMessage(failedMessage.id);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete),
              title: Text('حذف'),
              onTap: () {
                recoveryManager.deleteMessage(failedMessage.id);
                chatController.removeMessage(failedMessage.id);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    },
  );
}
```

## Phase 8: Connectivity Monitoring

Show connectivity status in UI:

```dart
Obx(
  () {
    final monitor = Get.find<MediaServicesInitializer>().connectivityMonitor;
    
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      color: monitor.isOnline.value ? Colors.transparent : Colors.red.withOpacity(0.8),
      padding: EdgeInsets.symmetric(vertical: 4),
      child: monitor.isOnline.value
          ? SizedBox.shrink()
          : Center(
              child: Text(
                'غير متصل بالإنترنت - سيتم استكمال الرفع تلقائياً عند الاتصال',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
    );
  },
)
```

## Phase 9: Cleanup in onDispose

When ChatScreen is closed:

```dart
@override
void dispose() {
  _voicePlaybackController.onClose();
  // DO NOT dispose media services here - they persist across screens
  super.dispose();
}
```

## Phase 10: Cleanup in App Lifecycle

In main.dart when app closes:

```dart
void _handleAppLifecycle(AppLifecycleState state) {
  if (state == AppLifecycleState.detached) {
    Get.find<MediaServicesInitializer>().dispose();
  }
}
```

## Key Architecture Points

1. **Instant Upload**: Messages appear immediately with `MessageStatus.local`
2. **Background Processing**: Uploads continue even when user leaves ChatScreen
3. **Automatic Recovery**: Failed uploads retry with exponential backoff (2s, 5s, 10s)
4. **Offline Support**: Uploads pause when offline, resume automatically when online
5. **Media Caching**: Images/audio cached locally, reused on next view
6. **Voice Queuing**: Consecutive voice messages play automatically
7. **Gallery Navigation**: Swipe between images with zoom support
8. **Progress Tracking**: Real-time upload progress displayed in UI

## Error Handling

Always handle potential failures:

```dart
try {
  final message = await previewService.createInstantPreviewMessage(...);
  chatController.addMessageToChat(message);
} catch (e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('خطأ في الرفع: $e')),
  );
}
```

## Performance Tips

1. Use `MediaGalleryScreen` for image viewing (optimized with hero animations)
2. Lazy load images in lists using `LazyImageLoader`
3. Set upload priority for important messages
4. Monitor connectivity for better UX
5. Implement message retry UI for failed uploads
6. Clean cache periodically via `MediaCacheManager.clearAllCache()`

## Troubleshooting

If uploads are not processing:
- Check `BackgroundUploadService.getQueueStatus()`
- Verify connectivity via `ConnectivityMonitor.isOnline`
- Check database: `IsarDatabaseService.getPendingUploads()`
- Enable debug logs

If gallery is not showing:
- Verify message type is `MessageType.image` or `MessageType.video`
- Check `MediaGalleryDataSource.getMediaMessages()` returns data
- Ensure images are accessible via URL

If audio queue not working:
- Verify consecutive messages are all `MessageType.audio`
- Check `AudioQueueManager.buildQueueFromMessages()` is called
- Verify audio URLs are valid
