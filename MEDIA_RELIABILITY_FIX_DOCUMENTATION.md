# Media Reliability Fix - Comprehensive Documentation

## P0 Issue Summary

**Problem:** Videos uploaded by users disappear after app restart and show as generic placeholder "Video" text instead of the original message.

**Root Cause Analysis:** Critical metadata loss during app lifecycle:
1. Video metadata (localFilePath, originalFileName, uploadProgress) was stored but not persisted to SQLite
2. LocalMessageRepository did not save/load media metadata from database
3. MediaStateStore could not rebuild media state on app restart
4. Upload queue restoration failed without message metadata

## Root Causes Fixed

### Bug #1: Missing Media Fields in SQLite Persistence
**File:** `lib/data/repositories/local/local_message_repository_native.dart`  
**Issue:** Message.saveMessage() was NOT persisting media fields:
- localFilePath
- originalFileName  
- uploadProgress

**Fix:** Updated saveMessage() and _mapToMessage() to persist and restore all media fields via database columns:
```
local_file_path TEXT
original_file_name TEXT
upload_progress REAL
```

### Bug #2: Message Model Missing Dedicated Media Fields
**Files:** 
- `lib/data/models/message_model.dart`
- `lib/models/message_model.dart`

**Issue:** Message models lacked dedicated fields for media data. Media was temporarily stored in reactions field but lost during DB round-trip.

**Fix:** Added dedicated fields to both Message models:
```dart
final String? localFilePath;
final String? originalFileName;
final double uploadProgress;
```

### Bug #3: Database Schema Missing Media Columns
**File:** `lib/data/services/database_service_native.dart`

**Issue:** local_messages table schema didn't include media tracking columns. New fields were added but not to database.

**Fix:** 
- Updated database version from 2 to 3
- Added migration in _onUpgrade() to add media columns to existing installations
- Updated _createDB() to include media columns for new installations

### Bug #4: Chat Controller Metadata Storage
**File:** `lib/controllers/chat_controller.dart`

**Issue:** _enqueueBackgroundUpload() was storing media metadata in reactions field, which is not semantically correct and prone to loss.

**Fix:** Updated to use dedicated Message fields with forensic logging:
```dart
localFilePath: file.path,
originalFileName: file.name,
uploadProgress: 0.0,
```

### Bug #5: MediaStateStore Cannot Seed Missing States
**File:** `lib/data/services/media_state_store.dart`

**Issue:** _buildStateFromMessage() expected media metadata in reactions/metadata but messages loaded from SQLite didn't have it properly mapped.

**Fix:** 
- Updated _buildStateFromMessage() to check message.originalFileName field first
- Added forensic logging tag: VIDEO_TRACE_MEDIA_STATE_SAVE
- Ensures media state is properly reconstructed from message data

## Forensic Logging Tags Added

All logging includes the required forensic tags for complete lifecycle tracing:

### Lifecycle Trace Points:

1. **VIDEO_TRACE_CREATE** - Message created with media (chat_controller.dart:259)
   - Logs: messageId, localId, fileName, filePath, status, mediaType

2. **VIDEO_TRACE_DB_SAVE** - Message persisted to SQLite (local_message_repository_native.dart:32)
   - Logs: messageId, localId, fileName, filePath, status, mediaType

3. **VIDEO_TRACE_DB_LOAD** - Message loaded from SQLite (local_message_repository_native.dart:210)
   - Logs: messageId, localId, fileName, filePath, status, mediaType

4. **VIDEO_TRACE_MEDIA_STATE_SAVE** - Media state created (media_state_store.dart:250)
   - Logs: messageId, fileName, filePath, status, mediaType

5. **VIDEO_TRACE_QUEUE_ADD** - Upload task queued (upload_manager.dart:85)
   - Logs: messageId, taskId, fileName, filePath, status, mediaType

6. **VIDEO_TRACE_QUEUE_RESTORE** - Upload task restored on app restart (upload_manager.dart:343)
   - Logs: messageId, taskId, fileName, filePath, status, mediaType

7. **VIDEO_TRACE_CHAT_REBUILD** - Messages combined during chat load (chat_controller.dart:1662)
   - Logs: messageId, fileName, localPath, mediaUrl, status, mediaType

8. **VIDEO_TRACE_UI_RENDER** - Media resolved for UI rendering (media_state_store.dart:172)
   - Logs: messageId, status, source (LOCAL/REMOTE/NONE)

## Database Migration

Version 3 Migration automatically handles both:
- **New Installations:** Creates table with media columns from start
- **Existing Installations:** Adds 3 new columns to local_messages table:
  ```sql
  ALTER TABLE local_messages ADD COLUMN local_file_path TEXT
  ALTER TABLE local_messages ADD COLUMN original_file_name TEXT  
  ALTER TABLE local_messages ADD COLUMN upload_progress REAL DEFAULT 0.0
  ```

## Complete Media Lifecycle (Fixed)

### Upload Creation Phase:
1. User selects video file → `_enqueueBackgroundUpload()` called
2. Message created with dedicated media fields
3. **VIDEO_TRACE_CREATE** logged with complete metadata
4. Message saved to SQLite with all media fields → **VIDEO_TRACE_DB_SAVE** logged
5. Upload task queued → **VIDEO_TRACE_QUEUE_ADD** logged

### Upload Execution Phase:
1. UploadManager.processQueue() executes upload
2. Progress updated and persisted to MediaStateStore
3. Upload completes, message updated with mediaUrl and status=uploaded
4. Chat rebuilds messages list

### App Restart Recovery Phase:
1. UploadManager.initialize() called
2. _restorePendingUploads() loads upload tasks from database
3. For each task:
   - Loads message metadata from SQLite → **VIDEO_TRACE_DB_LOAD** logged
   - Restores upload task → **VIDEO_TRACE_QUEUE_RESTORE** logged
   - Updates MediaStateStore → **VIDEO_TRACE_MEDIA_STATE_SAVE** logged
4. _attachMessagesStream() combines messages
5. **VIDEO_TRACE_CHAT_REBUILD** logged for each media message
6. MediaStateStore.rebuildIndex() seeds missing media states
7. UI renders message with media → **VIDEO_TRACE_UI_RENDER** logged

## Files Modified

1. `lib/data/models/message_model.dart` - Added media fields to data model
2. `lib/models/message_model.dart` - Added media fields to UI model  
3. `lib/data/repositories/local/local_message_repository_native.dart` - Persist/load media fields
4. `lib/data/services/database_service_native.dart` - Database schema v3 with migration
5. `lib/data/services/media_state_store.dart` - Extract media fields from messages + forensic logging
6. `lib/data/services/upload_manager.dart` - Forensic logging for queue operations
7. `lib/controllers/chat_controller.dart` - Store media in dedicated fields + forensic logging
8. `lib/data/models/upload_task_model.dart` - Added lastPersistedProgress field

## Acceptance Test Procedures

### TEST A: 5MB Video Upload & Restart
```
1. Open app and navigate to chat
2. Select 5MB video and upload
3. Verify video appears in chat with preview
4. Kill app (force stop)
5. Restart app
6. Navigate back to same chat

EXPECTED RESULT:
- Video still visible with preview
- Upload shows in progress or completed
- No generic "Video" placeholder
- Forensic logs show VIDEO_TRACE_DB_LOAD and VIDEO_TRACE_MEDIA_STATE_SAVE
```

### TEST B: 50MB Video Upload & Restart
```
1. Open app and navigate to chat
2. Select 50MB video and upload
3. Let upload progress to 30-50%
4. Kill app (force stop)
5. Restart app
6. Check chat

EXPECTED RESULT:
- Video message visible
- Upload resumes automatically
- Progress continues from last checkpoint
- Forensic logs show VIDEO_TRACE_QUEUE_RESTORE with progress preserved
```

### TEST C: Offline Scenario
```
1. Open app and navigate to chat
2. Select video and start upload
3. Turn off internet (airplane mode)
4. Wait 10 seconds, then kill app
5. Turn on internet
6. Restart app

EXPECTED RESULT:
- Message visible when reopened
- Upload resumes automatically when network available
- Forensic logs show VIDEO_TRACE_QUEUE_RESTORE
```

### TEST D: Completed Upload & Restart
```
1. Upload video and wait for completion
2. Verify video shows with mediaUrl (not local path)
3. Restart app

EXPECTED RESULT:
- Video remains fully accessible
- Shows synced status
- No placeholder text
- Forensic logs show VIDEO_TRACE_MEDIA_STATE_SAVE with synced status
```

## Debugging with Forensic Logs

Filter logs for media lifecycle:
```
adb logcat | grep VIDEO_TRACE
```

Expected output shows complete lifecycle:
```
VIDEO_TRACE_CREATE: messageId=abc123, localId=abc123, fileName=video.mp4, filePath=/path/to/video.mp4, status=uploading, mediaType=video
VIDEO_TRACE_DB_SAVE: messageId=abc123, localId=abc123, fileName=video.mp4, filePath=/path/to/video.mp4, status=uploading, mediaType=video
VIDEO_TRACE_QUEUE_ADD: messageId=abc123, taskId=abc123_1234567, fileName=video.mp4, filePath=/path/to/video.mp4, status=queued, mediaType=video
[... upload progress ...]
[app restart]
VIDEO_TRACE_DB_LOAD: messageId=abc123, localId=abc123, fileName=video.mp4, filePath=/path/to/video.mp4, status=uploading, mediaType=video
VIDEO_TRACE_QUEUE_RESTORE: messageId=abc123, taskId=abc123_1234567, fileName=video.mp4, filePath=/path/to/video.mp4, status=queued, mediaType=video
VIDEO_TRACE_MEDIA_STATE_SAVE: messageId=abc123, fileName=video.mp4, filePath=/path/to/video.mp4, status=queued, mediaType=video
VIDEO_TRACE_CHAT_REBUILD: messageId=abc123, fileName=Video, localPath=/path/to/video.mp4, mediaUrl=null, status=uploading, mediaType=video
```

## Known Limitations & Future Improvements

1. **Cleanup:** Old pending uploads should be cleaned after 30 days of failed status
2. **Throttling:** SQLite writes throttled to 5% progress intervals to prevent write storms (already implemented in upload_manager.dart:211)
3. **Disk Space:** No automatic cleanup of cached local files after successful upload
4. **Pause/Resume:** UI controls for pausing/resuming uploads not yet implemented

## Verification Checklist

- [x] Message model has dedicated media fields
- [x] Database schema includes media columns  
- [x] LocalMessageRepository persists/loads media fields
- [x] MediaStateStore properly seeds media state from messages
- [x] UploadManager restores tasks on app startup
- [x] Forensic logging covers complete lifecycle
- [x] Chat controller stores media in dedicated fields
- [x] Code compiles without errors
- [x] Database migration handles upgrades smoothly
