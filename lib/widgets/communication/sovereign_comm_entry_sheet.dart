import 'package:flutter/material.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/widgets/communication/presence_indicator_widget.dart';

enum CommEntryMode { individual, group, global }

class SovereignCommEntrySheet extends StatelessWidget {
  final CommEntryMode mode;
  final String? targetId; // UserId for individual, GroupId for group
  final String? targetName;
  final UserStatus? targetStatus; // C7: Awareness
  final Function(bool isVideo)? onStartIndividualCall;
  final Function(bool isVideo)? onStartRoom;

  const SovereignCommEntrySheet({
    super.key,
    required this.mode,
    this.targetId,
    this.targetName,
    this.targetStatus,
    this.onStartIndividualCall,
    this.onStartRoom,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final engine = SovereignCommunicationEngine.instance;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(l10n, theme),
            const SizedBox(height: 24),
            if (engine.isBusy) _buildBusyWarning(l10n, theme),
            const SizedBox(height: 16),
            _buildOptionsGrid(context, l10n, theme, engine.isBusy),
            const SizedBox(height: 16),
            if (mode == CommEntryMode.group)
              _buildGroupBoundaryNote(l10n, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.startConversation, // Using existing key for 'Start Communication'
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (targetName != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text(
                  targetName!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (targetStatus != null &&
                    mode == CommEntryMode.individual) ...[
                  const SizedBox(width: 8),
                  PresenceIndicatorWidget(
                      status: targetStatus!, size: 10, showLabel: true),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBusyWarning(AppLocalizations l10n, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: theme.colorScheme.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'أنت حالياً في جلسة أخرى، يمكنك إنهاؤها أو الانتظار للمتابعة.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsGrid(BuildContext context, AppLocalizations l10n,
      ThemeData theme, bool isBusy) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.2,
      children: [
        // Individual Calls (Hidden in Group Mode)
        if (mode != CommEntryMode.group) ...[
          _buildOptionCard(
            context,
            icon: Icons.call_rounded,
            label: l10n.voiceCall,
            color: Colors.blue,
            disabled: isBusy,
            onTap: () {
              Navigator.pop(context);
              onStartIndividualCall?.call(false);
            },
          ),
          _buildOptionCard(
            context,
            icon: Icons.videocam_rounded,
            label: l10n.videoCall,
            color: Colors.deepPurple,
            disabled: isBusy,
            onTap: () {
              Navigator.pop(context);
              onStartIndividualCall?.call(true);
            },
          ),
        ],
        // Rooms (Always visible, but emphasized in Group Mode)
        _buildOptionCard(
          context,
          icon: Icons.mic_external_on_rounded,
          label: 'إنشاء غرفة صوتية',
          color: Colors.orange,
          disabled: isBusy,
          onTap: () {
            Navigator.pop(context);
            onStartRoom?.call(false);
          },
        ),
        _buildOptionCard(
          context,
          icon: Icons.live_tv_rounded,
          label: 'إنشاء غرفة مرئية',
          color: Colors.redAccent,
          disabled: isBusy,
          onTap: () {
            Navigator.pop(context);
            onStartRoom?.call(true);
          },
        ),
      ],
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Opacity(
          opacity: disabled ? 0.5 : 1.0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupBoundaryNote(AppLocalizations l10n, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'المجموعة مساحة تواصل كتابي، والغرف هي مساحة البث.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
