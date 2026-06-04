import 'dart:async';

import 'package:flutter/material.dart';

import 'package:talkmate_ai/services/audio/dynamic_audio_player.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String url;
  final bool isMe;
  final Color? color;

  const VoiceMessageBubble({
    super.key,
    required this.url,
    required this.isMe,
    this.color,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  DynamicAudioPlayer? _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _stateSubscription;
  bool _isPlayerInitializing = false;

  @override
  void initState() {
    super.initState();
    // Creation deferred until Play tap to avoid Windows crashes when many bubbles load at once
  }

  Future<void> _ensurePlayerInitialized() async {
    if (_player != null || _isPlayerInitializing) return;
    _isPlayerInitializing = true;

    try {
      final player = DynamicAudioPlayer();

      // Listen to streams
      _durationSubscription = player.durationStream.listen((d) {
        if (mounted) setState(() => _duration = d);
      });

      _positionSubscription = player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });

      _stateSubscription = player.stateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
            if (state == PlayerState.completed) {
              _position = Duration.zero;
              // Reset UI to start
            }
          });
        }
      });

      await player.setUrl(widget.url);

      if (mounted) {
        setState(() {
          _player = player;
          _isPlayerInitializing = false;
        });
      }
    } catch (e) {
      debugPrint('DynamicAudioPlayer initialization failed: $e');
      if (mounted) setState(() => _isPlayerInitializing = false);
    }
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _playPause() async {
    if (_player == null) {
      await _ensurePlayerInitialized();
    }
    if (_player == null) return; // Still failed

    try {
      if (_isPlaying) {
        await _player!.pause();
      } else {
        await _player!.resume();
      }
    } catch (e) {
      debugPrint('Error playing/pausing: $e');
    }
  }

  Future<void> _seek(double value) async {
    if (_player == null) return;
    try {
      final position = Duration(milliseconds: value.toInt());
      await _player!.seek(position);
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final String minutes = twoDigits(duration.inMinutes.remainder(60));
    final String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = widget.isMe ? Colors.white : theme.colorScheme.onSurface;

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
                  value: _duration.inMilliseconds > 0
                      ? _position.inMilliseconds / _duration.inMilliseconds
                      : 0,
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      onColor.withValues(alpha: 0.8)),
                  backgroundColor: onColor.withValues(alpha: 0.1),
                ),
              ),
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: onColor,
                  size: 28,
                ),
                onPressed: _playPause,
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Waveform-like bars (simulated for now, or just a sleek slider)
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
                    value: _position.inMilliseconds.toDouble(),
                    max: _duration.inMilliseconds.toDouble() > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1.0,
                    onChanged: (value) async {
                      await _seek(value);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: TextStyle(
                            color: onColor.withValues(alpha: 0.7),
                            fontSize: 10),
                      ),
                      Text(
                        _formatDuration(_duration),
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
        ],
      ),
    );
  }
}
