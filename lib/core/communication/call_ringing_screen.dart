import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/data/models/call_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/services/audio/app_audio_service.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';
import 'package:talkmate_ai/utils/user_display.dart';

class CallRingingScreen extends StatefulWidget {
  final String callId;
  final String otherId;
  final bool isIncoming;
  final bool isVideo;

  const CallRingingScreen({
    super.key,
    required this.callId,
    required this.otherId,
    required this.isIncoming,
    this.isVideo = false,
  });

  @override
  State<CallRingingScreen> createState() => _CallRingingScreenState();
}

class _CallRingingScreenState extends State<CallRingingScreen> {
  final _engine = SovereignCommunicationEngine.instance;
  final _manager = CallManager.instance;
  final _userRepo = Get.find<IUserRepository>();

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🔔 RingingScreen: Init (isIncoming: ${widget.isIncoming}, callId: ${widget.callId})');

    _playRingtone();

    // Listen to Engine status to auto-close if call is ended/active elsewhere
    ever(_engine.statusRx, (status) {
      debugPrint('🔔 RingingScreen: Engine Status -> ${status.name}');
      if (status == CommSessionStatus.idle ||
          status == CommSessionStatus.ended ||
          status == CommSessionStatus.failed) {
        if (mounted) {
          debugPrint('🔔 RingingScreen: Auto-closing due to status');
          Get.back();
        }
      }
    });
  }

  Future<void> _playRingtone() async {
    debugPrint('🔔 RingingScreen: Requesting audio via AppAudioService');
    if (widget.isIncoming) {
      await AppAudioService.instance.play('call_ringtone.mp3', loop: true);
    } else {
      await AppAudioService.instance.play('call_incomming.mp3', loop: true);
    }
    debugPrint('🔔 RingingScreen: Audio request SENT');
  }

  @override
  void dispose() {
    debugPrint('🔔 RingingScreen: Disposing...');
    // We don't stop sounds here if we want them to continue until accept/decline
    // AppAudioService.instance.stop(...) is called in CallManager.terminateCall or acceptCall
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              await _manager.terminateCall(securityContext: widget.callId);
            },
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                    theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    StreamBuilder<AppUser?>(
                      stream: _userRepo.watchById(widget.otherId),
                      builder: (context, snapshot) {
                        final user = snapshot.data;
                        return Column(
                          children: [
                            Hero(
                              tag: 'avatar_${widget.otherId}',
                              child: UserDisplay.avatarCircle(
                                user: user,
                                userId: widget.otherId,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              user?.displayName ??
                                  UserDisplay.shortId(widget.otherId),
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.isIncoming ? l10n.incomingCall : l10n.outgoingCall,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    _buildActions(context, l10n),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildActions(BuildContext context, AppLocalizations l10n) {
    if (widget.isIncoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.call_end,
            label: l10n.decline,
            color: Colors.red,
            onPressed: () => _manager.terminateCall(
                status: CallStatus.rejected, securityContext: widget.callId),
          ),
          _ActionButton(
            icon: widget.isVideo ? Icons.videocam : Icons.call,
            label: l10n.accept,
            color: Colors.green,
            onPressed: () async {
              await _manager.acceptCall();
            },
          ),
        ],
      );
    } else {
      return Column(
        children: [
          _ActionButton(
            icon: Icons.call_end,
            label: l10n.cancel,
            color: Colors.red,
            onPressed: () =>
                _manager.terminateCall(securityContext: widget.callId),
          ),
        ],
      );
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(24),
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 8,
          ),
          child: Icon(icon, size: 32),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    );
  }
}
