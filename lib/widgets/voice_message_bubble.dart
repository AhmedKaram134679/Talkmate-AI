import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/models/message_model.dart';
import 'package:talkmate_ai/services/audio/audio_queue_manager.dart';

class VoiceMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final Color? color;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.color,
  });

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final String minutes = twoDigits(duration.inMinutes.remainder(60));
    final String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = isMe ? Colors.white : theme.colorScheme.onSurface;
    final playbackController = Get.find<VoicePlaybackController>();

    return Obx(() {
      final isCurrent = playbackController.currentMessage?.id == message.id;
      final isPlaying = isCurrent && playbackController.isPlaying.value;
      
      final currentPosMs = isCurrent ? playbackController.positionMs.value : 0;
      final totalDurMs = isCurrent ? playbackController.durationMs.value : 0;
      
      final position = Duration(milliseconds: currentPosMs);
      final duration = Duration(milliseconds: totalDurMs);
      
      final progress = totalDurMs > 0 ? (currentPosMs / totalDurMs) : 0.0;

      return Container(
        constraints: const BoxConstraints(maxWidth: 250),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play/Pause Button with progress circle
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        onColor.withValues(alpha: 0.8)),
                    backgroundColor: onColor.withValues(alpha: 0.1),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: onColor,
                    size: 28,
                  ),
                  onPressed: () async {
                    if (isCurrent) {
                      if (isPlaying) {
                        await playbackController.pausePlayback();
                      } else {
                        await playbackController.resumePlayback();
                      }
                    } else {
                      // Stop current playback
                      await playbackController.stopPlayback();
                      // Find all messages in chat
                      final chatController = Get.find<ChatController>();
                      final chatMessages = chatController.getMessages(message.chatId);
                      // Build queue starting from this message and play
                      await playbackController.buildQueueFrom(
                        messages: chatMessages,
                        selectedMessage: message,
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(width: 8),
            // Waveform-like slider
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: onColor,
                      inactiveTrackColor: onColor.withValues(alpha: 0.2),
                      thumbColor: onColor,
                      overlayColor: onColor.withValues(alpha: 0.1),
                    ),
                    child: Slider(
                      value: currentPosMs.toDouble(),
                      max: totalDurMs.toDouble() > 0
                          ? totalDurMs.toDouble()
                          : 1.0,
                      onChanged: (value) async {
                        if (isCurrent) {
                          await playbackController.seekTo(Duration(milliseconds: value.toInt()));
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: TextStyle(
                              color: onColor.withValues(alpha: 0.7),
                              fontSize: 10),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: TextStyle(
                              color: onColor.withValues(alpha: 0.7),
                              fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isCurrent)
              // Speed control button
              GestureDetector(
                onTap: () {
                  final currentSpeed = playbackController.playbackSpeed.value;
                  double nextSpeed = 1.0;
                  if (currentSpeed == 1.0) {
                    nextSpeed = 1.5;
                  } else if (currentSpeed == 1.5) {nextSpeed = 2.0;}
                  playbackController.setSpeed(nextSpeed);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: onColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${playbackController.playbackSpeed.value.toStringAsFixed(1).replaceFirst('.0', '')}x',
                    style: TextStyle(
                      color: onColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
