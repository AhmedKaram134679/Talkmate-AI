import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_view/photo_view.dart';
import 'package:talkmate_ai/data/services/media_cache_manager.dart';
import 'package:talkmate_ai/data/services/media_file_service.dart';
import 'package:talkmate_ai/data/services/media_state_store.dart';
import 'package:talkmate_ai/models/message_model.dart';

/// Media gallery controller for managing gallery state
class MediaGalleryController extends GetxController {
  final List<MessageModel> allImages;
  final int initialIndex;

  late PageController _pageController;
  final RxInt currentIndex = 0.obs;
  final RxBool isLoading = false.obs;
  final Rx<String> currentImageUrl = Rx<String>('');

  final MediaCacheManager _cacheManager = MediaCacheManager();

  MediaGalleryController({
    required this.allImages,
    required this.initialIndex,
  });

  @override
  void onInit() {
    super.onInit();
    _pageController = PageController(initialPage: initialIndex);
    currentIndex.value = initialIndex;
    _preloadAdjacentImages();
  }

  /// Preload current, next, and previous images for smooth navigation
  Future<void> _preloadAdjacentImages() async {
    final indices = [
      currentIndex.value - 1,
      currentIndex.value,
      currentIndex.value + 1,
    ];

    for (final index in indices) {
      if (index >= 0 && index < allImages.length) {
        final image = allImages[index];
        if (image.isImageMessage) {
          // Resolve media strictly from MediaStateStore
          final resolved =
              MediaStateStore.to.resolveForMessage(image.id, message: image);
          final imageUrl = resolved.remoteUrl;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            debugPrint(
                '🖼️ [MediaGallery] MEDIA_GALLERY_RESOLVE: Preloading index=$index, messageId=${image.id}, source=${resolved.hasLocalFile ? "LOCAL" : "REMOTE"}');
            _cacheManager
                .cacheImage(
                  url: imageUrl,
                  messageId: image.id,
                  chatId: image.chatId,
                )
                .ignore();
          }
        }
      }
    }
  }

  /// Jump to specific image
  void jumpToImage(int index) {
    if (index >= 0 && index < allImages.length) {
      _pageController.jumpToPage(index);
      currentIndex.value = index;
      _preloadAdjacentImages();
    }
  }

  /// Get next image
  void nextImage() {
    if (currentIndex.value < allImages.length - 1) {
      _pageController.nextPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Get previous image
  void previousImage() {
    if (currentIndex.value > 0) {
      _pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Check if has next
  bool get hasNext => currentIndex.value < allImages.length - 1;

  /// Check if has previous
  bool get hasPrevious => currentIndex.value > 0;

  /// Handle page change
  void onPageChanged(int index) {
    currentIndex.value = index;
    _preloadAdjacentImages();
  }

  /// Get page controller
  PageController get pageController => _pageController;

  @override
  void onClose() {
    _pageController.dispose();
    super.onClose();
  }
}

/// Full-screen media gallery screen
class MediaGalleryScreen extends StatelessWidget {
  final List<MessageModel> images;
  final int initialIndex;

  const MediaGalleryScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MediaGalleryController>(
      init: MediaGalleryController(
        allImages: images,
        initialIndex: initialIndex,
      ),
      builder: (controller) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            Navigator.pop(context);
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                // Image viewer with swipe and zoom
                PageView.builder(
                  controller: controller.pageController,
                  onPageChanged: controller.onPageChanged,
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final message = images[index];
                    return _buildImageViewer(
                      context,
                      message,
                      index == controller.currentIndex.value,
                    );
                  },
                ),

                // Top controls
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(context, controller),
                ),

                // Bottom info
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomBar(controller),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build image viewer with zoom support - uses MediaStateStore exclusively
  Widget _buildImageViewer(
    BuildContext context,
    MessageModel message,
    bool isCurrent,
  ) {
    // Resolve media strictly from MediaStateStore
    final resolved =
        MediaStateStore.to.resolveForMessage(message.id, message: message);
    debugPrint(
        '🖼️ [MediaGallery] MEDIA_GALLERY_RESOLVE: messageId=${message.id}, available=${resolved.isAvailable}, hasLocal=${resolved.hasLocalFile}');

    final ImageProvider provider;
    if (message.isVideoMessage) {
      final localThumb = resolved.thumbnailPath;
      final remoteThumb = message.metadata?['thumbnailUrl'] as String?;
      if (localThumb != null && localThumb.isNotEmpty && File(localThumb).existsSync()) {
        provider = FileImage(File(localThumb));
      } else if (remoteThumb != null && remoteThumb.isNotEmpty) {
        provider = NetworkImage(remoteThumb);
      } else {
        // Fallback for video thumbnail missing
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.play_circle_fill, size: 72, color: Colors.white),
                onPressed: () {
                  final url = resolved.remoteUrl ?? resolved.localPath ?? '';
                  if (url.isNotEmpty) {
                    MediaFileService.instance.openFile(
                      url: url,
                      messageId: message.id,
                      chatId: message.chatId,
                    ).ignore();
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('شغل الفيديو', style: TextStyle(color: Colors.white)),
            ],
          ),
        );
      }
    } else {
      if (resolved.hasLocalFile && resolved.localPath != null) {
        provider = FileImage(File(resolved.localPath!));
      } else if (resolved.remoteUrl != null && resolved.remoteUrl!.isNotEmpty) {
        provider = NetworkImage(resolved.remoteUrl!);
      } else {
        // Fallback: show error state directly
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, size: 48, color: Colors.white),
              SizedBox(height: 16),
              Text(
                'خطأ في تحميل الصورة',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      }
    }

    final viewer = PhotoView(
      imageProvider: provider,
      minScale: PhotoViewComputedScale.contained * 0.8,
      maxScale: PhotoViewComputedScale.covered * 2.0,
      initialScale: PhotoViewComputedScale.contained,
      heroAttributes: PhotoViewHeroAttributes(
        tag: message.id,
      ),
      loadingBuilder: (context, event) {
        return Center(
          child: CircularProgressIndicator(
            value: event == null
                ? null
                : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
          ),
        );
      },
      errorBuilder: (context, error, stacktrace) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, size: 48, color: Colors.white),
              SizedBox(height: 16),
              Text(
                'خطأ في تحميل الصورة',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      },
    );

    if (message.isVideoMessage) {
      return GestureDetector(
        onTap: () {
          final url = resolved.remoteUrl ?? resolved.localPath ?? '';
          if (url.isNotEmpty) {
            MediaFileService.instance.openFile(
              url: url,
              messageId: message.id,
              chatId: message.chatId,
            ).ignore();
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            viewer,
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(Icons.play_arrow, size: 64, color: Colors.white),
            ),
          ],
        ),
      );
    }

    return viewer;
  }

  /// Build top bar with close button
  Widget _buildTopBar(BuildContext context, MediaGalleryController controller) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding:
          EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Obx(
            () => Text(
              '${controller.currentIndex.value + 1} / ${images.length}',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  /// Build bottom bar with navigation and info - uses MediaStateStore for filenames
  Widget _buildBottomBar(MediaGalleryController controller) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Navigation buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Obx(
                  () => IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: controller.hasPrevious
                        ? controller.previousImage
                        : null,
                  ),
                ),
                Expanded(child: SizedBox()),
                Obx(
                  () => IconButton(
                    icon: Icon(Icons.arrow_forward_ios, color: Colors.white),
                    onPressed: controller.hasNext ? controller.nextImage : null,
                  ),
                ),
              ],
            ),
            // Image info - resolved from MediaStateStore
            Obx(
              () {
                final image = images[controller.currentIndex.value];
                // Resolve media strictly from MediaStateStore
                final resolved = MediaStateStore.to
                    .resolveForMessage(image.id, message: image);

                // Filename priority: ResolvedMedia fileName > metadata originalFileName > fallback
                final originalName = resolved.fileName ??
                    image.userReactions['originalFileName'] ??
                    'Media File';

                return Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text(
                          originalName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        image.isImageMessage
                            ? 'صورة'
                            : image.isVideoMessage
                                ? 'فيديو'
                                : 'ملف وسائط',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Media gallery data source - builds list of images from messages
class MediaGalleryDataSource {
  /// Filter image and video messages from chat
  static List<MessageModel> getMediaMessages(List<MessageModel> messages) {
    return messages.where((m) => m.isImageMessage || m.isVideoMessage).toList();
  }

  /// Get index of specific message in media list
  static int getMediaIndex(
    List<MessageModel> messages,
    String messageId,
  ) {
    final mediaMessages = getMediaMessages(messages);
    return mediaMessages.indexWhere((m) => m.id == messageId);
  }
}
