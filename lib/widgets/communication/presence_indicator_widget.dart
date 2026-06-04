import 'package:flutter/material.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';

class PresenceIndicatorWidget extends StatelessWidget {
  final UserStatus status;
  final double size;
  final bool showLabel;

  const PresenceIndicatorWidget({
    super.key,
    required this.status,
    this.size = 12.0,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    Color color;
    String label;

    switch (status) {
      case UserStatus.online:
        color = Colors.green;
        label = l10n.statusOnline;
        break;
      case UserStatus.busy:
        color = Colors.red;
        label = l10n.statusBusy;
        break;
      case UserStatus.away:
        color = Colors.orange;
        label = l10n.statusAway;
        break;
      case UserStatus.offline:
        color = Colors.grey;
        label = l10n.statusOffline;
        break;
      case UserStatus.inCall:
        color = Colors.blue;
        label = l10n.statusInCall;
        break;
      case UserStatus.inRoomVoice:
        color = Colors.orangeAccent;
        label = l10n.statusInRoomVoice;
        break;
      case UserStatus.inRoomVideo:
        color = Colors.purple;
        label = l10n.statusInRoomVideo;
        break;
    }

    final Widget indicator = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.scaffoldBackgroundColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );

    if (!showLabel) return indicator;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
