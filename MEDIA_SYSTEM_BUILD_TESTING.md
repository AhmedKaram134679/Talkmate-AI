# WhatsApp-Level Media System - Testing & Compilation Guide

## Pre-Compilation Checklist

Before building, ensure the following are completed:

### 1. Code Generation

The Isar database requires code generation. Run:

```bash
cd F:\ProgrammingProjects\Talkmate-AI
flutter pub run build_runner build
```

This will generate:
- `lib/data/models/pending_upload_entity.g.dart`
- `lib/data/models/cached_media_entity.g.dart`
- `lib/data/models/audio_playback_entity.g.dart`
- `lib/data/models/failed_upload_entity.g.dart`

### 2. Dependency Check

Verify all dependencies are installed:

```bash
flutter pub get
```

Expected new packages:
- photo_view
- flutter_cache_manager
- just_audio
- isar
- isar_flutter_libs
- isar_generator
- build_runner

### 3. pubspec.yaml Verification

Ensure these sections are present in `pubspec.yaml`:

**Dependencies**:
- ✅ photo_view: ^0.14.0
- ✅ flutter_cache_manager: ^3.3.1
- ✅ just_audio: ^0.9.36
- ✅ isar: ^3.1.0+1
- ✅ isar_flutter_libs: ^3.1.0+1

**Dev Dependencies**:
- ✅ isar_generator: ^3.1.0+1
- ✅ build_runner: ^2.4.0

## Building the Application

### Clean Build (Recommended First Time)

```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk    # or iOS, web, windows, etc.
```

### Incremental Build

```bash
flutter pub run build_runner build
flutter run
```

## Compilation Issues & Solutions

### Issue: Isar Code Not Generated

**Symptom**: "The getter 'pendingUploadEntitys' isn't defined"

**Solution**:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Issue: Import Errors

**Symptom**: "Can't find file entity in build"

**Solution**: Make sure annotations are present in entity files:
```dart
import 'package:isar/isar.dart';

part 'pending_upload_entity.g.dart';  // This line is essential

@collection
class PendingUploadEntity { ... }
```

### Issue: Circular Dependencies

**Symptom**: "Circular dependency detected"

**Solution**: The architecture uses hierarchical service initialization. If you get this:
1. Check no service imports sibling services
2. Import only from lower hierarchy levels
3. Use dependency injection (GetX) instead

### Issue: Audio Service Not Starting

**Symptom**: "AudioPlayer not initialized"

**Solution**: Ensure `MediaServicesInitializer().initialize()` is called in main() before using media features.

## Testing Phases

### Phase 1: Basic Initialization Test

```dart
void testInitialization() async {
  final initializer = MediaServicesInitializer();
  await initializer.initialize();
  
  assert(initializer.isInitialized == true);
  assert(initializer.database != null);
  assert(initializer.cacheManager != null);
  assert(initializer.backgroundUpload != null);
  
  print('✅ Initialization test passed');
}
```

### Phase 2: Database Test

```dart
void testDatabase() async {
  final db = IsarDatabaseService();
  await db.initialize();
  
  // Add pending upload
  final upload = PendingUploadEntity(
    messageId: 'test_msg_1',
    chatId: 'test_chat_1',
    userId: 'test_user_1',
    localFilePath: '/tmp/test.jpg',
    fileExtension: 'jpg',
    fileSizeBytes: 1024 * 100,
    uploadPath: 'test/image.jpg',
    mediaType: 'image',
  );
  
  await db.addPendingUpload(upload);
  
  // Retrieve
  final retrieved = await db.getPendingUploadByMessageId('test_msg_1');
  assert(retrieved != null);
  assert(retrieved!.messageId == 'test_msg_1');
  
  print('✅ Database test passed');
}
```

### Phase 3: Cache Manager Test

```dart
void testCacheManager() async {
  final cache = MediaCacheManager();
  await cache.initialize();
  
  final stats = await cache.getCacheStats();
  assert(stats.containsKey('totalSize'));
  assert(stats.containsKey('itemCount'));
  
  print('✅ Cache manager test passed');
  print('Cache stats: $stats');
}
```

### Phase 4: Upload Queue Test

```dart
void testUploadQueue() async {
  final queue = UploadQueue();
  
  final task = UploadTask(
    taskId: 'upload_1',
    messageId: 'msg_1',
    chatId: 'chat_1',
    userId: 'user_1',
    localFilePath: '/tmp/test.jpg',
    uploadPath: 'test/image.jpg',
    mediaType: 'image',
    fileSizeBytes: 1024 * 100,
  );
  
  queue.enqueue(task);
  assert(queue.size == 1);
  
  final dequeued = queue.dequeue();
  assert(dequeued != null);
  assert(dequeued!.taskId == 'upload_1');
  assert(queue.isEmpty);
  
  queue.dispose();
  print('✅ Upload queue test passed');
}
```

### Phase 5: Message Model Test

```dart
void testMessageModel() {
  final message = MessageModel(
    chatId: 'chat_1',
    senderId: 'user_1',
    content: 'Test message',
    type: MessageType.image,
    status: MessageStatus.local,
    localFilePath: '/tmp/test.jpg',
    uploadProgress: 0.5,
  );
  
  assert(message.isLocal == true);
  assert(message.hasLocalFile == true);
  assert(message.uploadProgress == 0.5);
  
  // Test copyWith
  final updated = message.copyWith(
    status: MessageStatus.uploading,
    uploadProgress: 0.75,
  );
  
  assert(updated.isUploading == true);
  assert(updated.uploadProgress == 0.75);
  
  // Test JSON serialization
  final json = updated.toJson();
  assert(json['uploadProgress'] == 0.75);
  
  final fromJson = MessageModel.fromJson(json);
  assert(fromJson.uploadProgress == 0.75);
  
  print('✅ Message model test passed');
}
```

### Phase 6: Connectivity Test

```dart
void testConnectivityMonitor() async {
  final monitor = ConnectivityMonitor();
  await monitor.initialize();
  
  assert(monitor.isOnline != null);
  print('Current connectivity: ${monitor.getStatusText()}');
  
  // Test that resume/pause works (don't actually disconnect)
  final service = BackgroundUploadService();
  service.pauseAllUploads();
  service.resumeAllUploads();
  
  monitor.dispose();
  print('✅ Connectivity test passed');
}
```

### Phase 7: UI Component Test

```dart
void testMediaGalleryDataSource() {
  final messages = [
    MessageModel.mock(type: MessageType.image, content: 'http://example.com/1.jpg'),
    MessageModel.mock(type: MessageType.text, content: 'Just text'),
    MessageModel.mock(type: MessageType.image, content: 'http://example.com/2.jpg'),
    MessageModel.mock(type: MessageType.video, content: 'http://example.com/1.mp4'),
  ];
  
  final mediaMessages = MediaGalleryDataSource.getMediaMessages(messages);
  assert(mediaMessages.length == 3); // Only images and videos
  
  final index = MediaGalleryDataSource.getMediaIndex(
    messages,
    mediaMessages[1].id,
  );
  assert(index == 1);
  
  print('✅ Media gallery datasource test passed');
}
```

## Platform-Specific Testing

### Android

```bash
flutter build apk
# or
flutter run -d emulator-5554
```

Check:
- ✅ Media upload works
- ✅ Cache persists after app restart
- ✅ Background upload service continues

### iOS

```bash
flutter build ios
# or
flutter run -d iPhone
```

Check:
- ✅ Audio queue works
- ✅ Voice messages play sequentially
- ✅ Hero animations work

### Web

```bash
flutter run -d chrome
```

Check:
- ✅ Media gallery renders
- ✅ Swipe navigation works
- ✅ Image loading indicator shows

### Windows

```bash
flutter run -d windows
```

Check:
- ✅ Mouse wheel zoom works
- ✅ Upload progress updates
- ✅ Cache folder exists

### macOS

```bash
flutter run -d macos
```

Check:
- ✅ Permission requests work
- ✅ File picker integration
- ✅ Audio session management

### Linux

```bash
flutter run -d linux
```

Check:
- ✅ File operations work
- ✅ Cache directory created
- ✅ No permission errors

## Integration Testing

### Test 1: Full Upload Cycle

1. Select image from device
2. Message appears immediately (LOCAL status)
3. Upload starts (UPLOADING status)
4. Progress bar updates
5. Upload completes (UPLOADED status)
6. Message sent to server (SENT status)
7. Recipient receives (DELIVERED status)
8. Message read (READ status)

### Test 2: Failed Upload Recovery

1. Select image and initiate upload
2. Disconnect internet (or simulate network error)
3. Upload pauses automatically
4. Show "Offline" indicator
5. Reconnect internet
6. Upload resumes automatically
7. Verify message sent successfully

### Test 3: Media Gallery

1. Send multiple images to chat
2. Tap on middle image
3. Gallery opens with correct image
4. Swipe left/right to navigate
5. Verify image count updates
6. Test pinch zoom
7. Test double-tap zoom
8. Test pan while zoomed
9. Close gallery

### Test 4: Voice Queue

1. Send multiple consecutive voice messages
2. Tap first message
3. Queue builds automatically
4. Play button triggers first message
5. First message completes, second starts automatically
6. Navigation buttons work (next/previous)
7. Pause/resume works
8. Speed adjustment works

### Test 5: Cache Hit

1. View image in chat (first load from network)
2. Verify file is cached
3. Close chat
4. Reopen chat
5. Tap same image
6. Verify loads from cache (no network activity)
7. Check cache stats

## Performance Testing

### Scroll Performance (Target: 60 FPS)

```bash
flutter run --profile
# Enable performance overlay: View → Performance Overlay
```

Check:
- ✅ Smooth scrolling through chat messages
- ✅ No jank when loading images
- ✅ 60 FPS maintained

### Memory Usage

```bash
flutter run --debug
# Use DevTools Memory tab
```

Check:
- ✅ Memory doesn't spike during uploads
- ✅ Cache has reasonable size
- ✅ LRU cleanup activates at 2 GB

### Network Usage

Monitor upload/download:
- ✅ Images compress appropriately
- ✅ Bandwidth usage reasonable
- ✅ Retries don't duplicate uploads

## Debugging Tips

### Enable Detailed Logging

All services print debug logs. Example output:

```
✅ [MediaServicesInitializer] Starting initialization...
✅ [IsarDatabaseService] Database initialized successfully
✅ [MediaCacheManager] Cache managers initialized
✅ [BackgroundUploadService] Initialized
...
✅ [MediaServicesInitializer] All services initialized
```

### Monitor Upload Queue

```dart
final initializer = Get.find<MediaServicesInitializer>();
final status = initializer.backgroundUpload.getQueueStatus();
print('Queue: ${status['total']}, Processing: ${status['processing']}');
```

### Check Cache Stats

```dart
final cache = Get.find<MediaServicesInitializer>().cacheManager;
final stats = await cache.getCacheStats();
print('Cache: ${stats['totalSizeMB']} MB, Items: ${stats['itemCount']}');
```

## Troubleshooting Checklist

- [ ] `flutter clean && flutter pub get`
- [ ] `flutter pub run build_runner build`
- [ ] Check all Isar entities have `@collection` annotation
- [ ] Check all Isar entities have `part 'xxx.g.dart'`
- [ ] Verify no circular imports between services
- [ ] Test on actual device (not just emulator)
- [ ] Check connectivity before testing offline recovery
- [ ] Verify file picker permissions on Android/iOS
- [ ] Check console for any red error messages
- [ ] Enable debugPrintSynchronously for verbose logs

## Successful Build Indicators

When build succeeds:
- ✅ No errors (only warnings are acceptable)
- ✅ App launches without crashing
- ✅ All services initialize (check logs)
- ✅ Chat screen loads
- ✅ Media selection works
- ✅ No security warnings

---

**Build Status**: Ready for compilation and testing
**Estimated Build Time**: 3-5 minutes (cold build)
**Required Disk Space**: ~500 MB (including cache)
