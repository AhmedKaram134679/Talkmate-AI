import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:record/record.dart';

class DiagnosticAudioStats {
  final double rms;
  final double peak;
  final bool isClipping;
  final double noiseFloor;

  DiagnosticAudioStats({
    required this.rms,
    required this.peak,
    required this.isClipping,
    required this.noiseFloor,
  });

  @override
  String toString() =>
      'RMS: ${rms.toStringAsFixed(4)}, Peak: ${peak.toStringAsFixed(4)}, Clip: $isClipping';
}

class DiagnosticService {
  static final DiagnosticService _instance = DiagnosticService._internal();
  factory DiagnosticService() => _instance;
  DiagnosticService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  // Analysis state
  final List<double> _rmsWindow = [];
  double _noiseFloor = -1.0;
  double _baselineRMS = 0.0;
  bool _isCalibrating = false;
  StreamController<DiagnosticAudioStats>? _analysisController;

  /// Starts real-time PCM analysis
  Future<Stream<DiagnosticAudioStats>> startAudioAnalysis() async {
    if (_micSub != null && _analysisController != null) {
      debugPrint(
          '🎙️ DiagnosticService: Re-using existing audio analysis session');
      return _analysisController!.stream;
    }

    if (await _recorder.hasPermission()) {
      // Clear PCM buffer/stats before starting
      reset();
      debugPrint(
          '🎙️ DiagnosticService: Starting Audio Analysis (Fresh Session)');

      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: 44100,
      ));

      _analysisController = StreamController<DiagnosticAudioStats>.broadcast();

      _micSub = stream.listen(
        (data) {
          final stats = _analyzePCM(data);
          if (!_isCalibrating) {
            _analysisController?.add(stats);
          }
        },
        onDone: () {
          _analysisController?.close();
          _analysisController = null;
        },
        onError: (_) {
          _analysisController?.close();
          _analysisController = null;
        },
      );

      return _analysisController!.stream;
    }
    throw 'Microphone permission denied';
  }

  /// Calibrates the noise floor over a 2-second window
  Future<void> calibrateBaseline() async {
    _isCalibrating = true;
    _baselineRMS = 0.0;
    _rmsWindow.clear();

    // Collect data for 2 seconds
    await Future.delayed(const Duration(seconds: 2));

    if (_rmsWindow.isNotEmpty) {
      _baselineRMS = _rmsWindow.reduce((a, b) => a + b) / _rmsWindow.length;
      debugPrint('🎙️ DiagnosticService: Baseline Calibrated: $_baselineRMS');
    }
    _isCalibrating = false;
  }

  /// Resets all internal counters and windows to prevent state leakage
  void reset() {
    debugPrint('🎙️ DiagnosticService: Resetting internal state...');
    _rmsWindow.clear();
    _noiseFloor = -1.0;
    _baselineRMS = 0.0;
    _isCalibrating = false;
  }

  Future<void> stopAudioAnalysis() async {
    await _micSub?.cancel();
    await _recorder.stop();
    reset();
    debugPrint('🎙️ DiagnosticService: Stopped Audio Analysis & Reset State');
  }

  DiagnosticAudioStats _analyzePCM(Uint8List data) {
    final Int16List samples = data.buffer.asInt16List();
    if (samples.isEmpty) {
      return DiagnosticAudioStats(
          rms: 0, peak: 0, isClipping: false, noiseFloor: 0);
    }

    double sumSq = 0;
    int maxVal = 0;

    for (var sample in samples) {
      final absSample = sample.abs();
      sumSq += absSample * absSample;
      if (absSample > maxVal) maxVal = absSample;
    }

    final double rms = math.sqrt(sumSq / samples.length) / 32768.0;
    final double peak = maxVal / 32768.0;
    final bool isClipping =
        maxVal >= 32760; // Slightly under 32767 for tolerance

    // Track RMS window for noise floor estimation (min RMS during "silence")
    _rmsWindow.add(rms);
    if (_rmsWindow.length > 100) _rmsWindow.removeAt(0);

    _noiseFloor = _rmsWindow.reduce(math.min);

    // Adaptive Clipping/Detection threshold based on baseline
    // If we are significantly above baseline, it's real signal
    final bool isRealSignal = rms > (_baselineRMS * 2.5) + 0.005;

    if (isClipping && isRealSignal) {
      debugPrint(
          '🎙️ DiagnosticService: Clipping Detected! RMS: $rms, Baseline: $_baselineRMS');
    }

    return DiagnosticAudioStats(
      rms: rms,
      peak: peak,
      isClipping: isClipping && isRealSignal,
      noiseFloor: _noiseFloor,
    );
  }

  /// Fetches camera stats via WebRTC PC
  Future<Map<String, dynamic>> getCameraStats(
      webrtc.RTCPeerConnection? pc) async {
    if (pc == null) return {};

    final stats = await pc.getStats();
    for (var report in stats) {
      if (report.type == 'media-source' && report.values['kind'] == 'video') {
        return {
          'width': report.values['width'] ?? 0,
          'height': report.values['height'] ?? 0,
          'fps': report.values['framesPerSecond'] ?? 0,
        };
      }
    }
    return {};
  }
}
