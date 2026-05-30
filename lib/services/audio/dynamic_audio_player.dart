import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

enum PlayerState { idle, playing, paused, completed, error }

/// A modern wrapper for media_kit designed for dynamic URL playback
/// (like voice messages) with state tracking.
class DynamicAudioPlayer {
  mk.Player? _player;
  bool _isDisposed = false;

  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  Stream<PlayerState> get stateStream => _stateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  DynamicAudioPlayer() {
    _init();
  }

  void _init() {
    _player = mk.Player();

    _player!.stream.playing.listen((playing) {
      if (!_isDisposed) {
        _stateController
            .add(playing ? PlayerState.playing : PlayerState.paused);
      }
    });

    _player!.stream.position.listen((pos) {
      if (!_isDisposed) _positionController.add(pos);
    });

    _player!.stream.duration.listen((dur) {
      if (!_isDisposed) _durationController.add(dur);
    });

    _player!.stream.completed.listen((completed) {
      if (completed && !_isDisposed) {
        _stateController.add(PlayerState.completed);
      }
    });
  }

  Future<void> setUrl(String url) async {
    if (_isDisposed) return;
    try {
      await _player!.open(mk.Media(url), play: false);
    } catch (e) {
      debugPrint('DynamicAudioPlayer: Error setting URL: $e');
      _stateController.add(PlayerState.error);
    }
  }

  Future<void> play() async {
    if (_isDisposed) return;
    await _player!.play();
  }

  Future<void> pause() async {
    if (_isDisposed) return;
    await _player!.pause();
  }

  Future<void> resume() async {
    if (_isDisposed) return;
    await _player!.play();
  }

  Future<void> seek(Duration position) async {
    if (_isDisposed) return;
    await _player!.seek(position);
  }

  void dispose() {
    _isDisposed = true;
    _player?.dispose();
    _stateController.close();
    _positionController.close();
    _durationController.close();
  }
}
