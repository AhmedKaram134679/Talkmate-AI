import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/models/comm_invitation_model.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';

class SovereignInvitationDialog extends StatelessWidget {
  final CommInvitation invitation;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const SovereignInvitationDialog({
    super.key,
    required this.invitation,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final commEngine = SovereignCommunicationEngine.instance;

    final isCall = invitation.type == InvitationType.individualCall;
    final icon = isCall
        ? (invitation.isVideo ? Icons.videocam_rounded : Icons.call_rounded)
        : Icons.meeting_room_rounded;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(isCall ? 'دعوة اتصال' : 'دعوة انضمام'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invitation.senderName,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(isCall ? 'يرغب في بدء مكالمة معك' : 'يدعوك للانضمام إلى غرفة'),
          const SizedBox(height: 16),
          if (commEngine.isBusy)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: theme.colorScheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'أنت في جلسة أخرى حالياً. قبول الدعوة سيغلق جلستك الحالية.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onDecline();
          },
          child: Text(l10n.decline,
              style: TextStyle(color: theme.colorScheme.error)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onAccept();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(l10n.accept),
        ),
      ],
    );
  }

  static Future<void> show({
    required CommInvitation invitation,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
  }) async {
    return Get.dialog(
      SovereignInvitationDialog(
        invitation: invitation,
        onAccept: onAccept,
        onDecline: onDecline,
      ),
      barrierDismissible: false,
    );
  }
}
