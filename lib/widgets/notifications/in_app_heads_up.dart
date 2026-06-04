import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_notification_repository.dart';

class InAppHeadsUp extends StatelessWidget {
  final String title;
  final String body;
  final String? avatarUrl;
  final String? reasonText;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const InAppHeadsUp({
    super.key,
    required this.title,
    required this.body,
    this.avatarUrl,
    this.reasonText,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Dismissible(
          key: UniqueKey(),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => onDismiss(),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                    child: avatarUrl != null
                        ? ClipOval(child: Image.network(avatarUrl!))
                        : Icon(Icons.person, color: theme.primaryColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        if (reasonText != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 10,
                                  color: theme.primaryColor
                                      .withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                              Text(
                                reasonText!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      theme.primaryColor.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 4,
                    height: 30,
                    decoration: BoxDecoration(
                      color: theme.primaryColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void show({
    required String title,
    required String body,
    String? avatarUrl,
    String? messageId,
    String? reasonText,
    required VoidCallback onTap,
  }) {
    if (Get.overlayContext == null) {
      debugPrint('InAppHeadsUp: Overlay not available, skipping heads-up');
      return;
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: InAppHeadsUp(
          title: title,
          body: body,
          avatarUrl: avatarUrl,
          reasonText: reasonText,
          onTap: () {
            entry.remove();
          },
          onDismiss: () {
            if (messageId != null) {
              try {
                final repo = Get.find<INotificationRepository>();
                final userId = Get.find<AuthController>().userId;
                repo.reportInteractionSignal(
                  userId: userId,
                  signalType: 'dismiss_fast',
                  messageId: messageId,
                );
              } catch (_) {}
            }
            entry.remove();
          },
        ),
      ),
    );

    try {
      Overlay.of(Get.overlayContext!).insert(entry);
      // Auto-dismiss after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (entry.mounted) entry.remove();
      });
    } catch (e) {
      debugPrint('InAppHeadsUp: Failed to insert overlay: $e');
    }
  }
}
