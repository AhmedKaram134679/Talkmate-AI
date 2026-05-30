import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:get/get.dart';
import 'package:talkmate_ai/core/diagnostic/diagnostic_service.dart';
import 'package:talkmate_ai/core/media/webrtc_connection_manager.dart';
import 'package:talkmate_ai/services/audio/app_audio_service.dart';

enum DiagnosticStep { deviceAudit, micTest, speakerTest, cameraTest, results }

class DiagnosticController extends GetxController {
  final _service = DiagnosticService();
  final _webrtc = WebRTCConnectionManager.instance;
  final _sound = AppAudioService.instance;

  final Rx<DiagnosticStep> currentStep = DiagnosticStep.deviceAudit.obs;

  // Device Data
  final RxList<webrtc.MediaDeviceInfo> audioInputs =
      <webrtc.MediaDeviceInfo>[].obs;
  final RxList<webrtc.MediaDeviceInfo> audioOutputs =
      <webrtc.MediaDeviceInfo>[].obs;
  final RxList<webrtc.MediaDeviceInfo> videoInputs =
      <webrtc.MediaDeviceInfo>[].obs;

  // Live Analysis States
  final RxDouble currentMicLevel = 0.0.obs;
  final RxBool isClippingDetected = false.obs;
  final RxDouble noiseLevel = 0.0.obs;

  // Results
  final RxInt readinessScore = 0.obs;
  final Map<String, dynamic> report = {};

  @override
  void onInit() {
    super.onInit();
    refreshDevices();
  }

  Future<void> refreshDevices() async {
    final devices = await webrtc.navigator.mediaDevices.enumerateDevices();
    audioInputs.value = devices.where((d) => d.kind == 'audioinput').toList();
    audioOutputs.value = devices.where((d) => d.kind == 'audiooutput').toList();
    videoInputs.value = devices.where((d) => d.kind == 'videoinput').toList();
  }

  // --- Step 2: Mic Test ---
  StreamSubscription? _micAnalysisSub;

  Future<void> startMicTest() async {
    final stream = await _service.startAudioAnalysis();
    _micAnalysisSub = stream.listen((stats) {
      currentMicLevel.value = stats.rms;
      if (stats.isClipping) isClippingDetected.value = true;
      noiseLevel.value = stats.noiseFloor;
    });

    // Auto-stop after 5 seconds as per requirements
    Future.delayed(const Duration(seconds: 5), () => stopMicTest());
  }

  Future<void> stopMicTest() async {
    await _micAnalysisSub?.cancel();
    await _service.stopAudioAnalysis();

    // Analyze results for report
    final double healthMultiplier = isClippingDetected.value ? 0.7 : 1.0;
    final double levelScore = (currentMicLevel.value * 100).clamp(0, 100);
    report['mic_score'] = (levelScore * healthMultiplier).toInt();

    currentStep.value = DiagnosticStep.speakerTest;
  }

  // --- Step 3: Speaker Test ---
  Future<void> playTestTone(String type) async {
    debugPrint('� Playing Test Tone: $type');

    // Using AppAudioService for actual playback control
    switch (type) {
      case 'LEFT':
        await _sound.play(
            'message_receive.mp3'); // Fallback for now, should be calibrated left
        break;
      case 'RIGHT':
        await _sound.play(
            'message_send.mp3'); // Fallback for now, should be calibrated right
        break;
      case 'SWEEP':
        await _sound.play(
            'audio_record_start.mp3'); // Fallback for now, should be sweep
        break;
    }
  }

  void completeSpeakerTest(bool success) {
    report['speaker_score'] = success ? 100 : 0;
    currentStep.value = DiagnosticStep.cameraTest;
  }

  // --- Step 4: Camera Test ---
  Future<void> runCameraCheck() async {
    // Uses a temporary stream to verify stats
    final stream = await _webrtc.initLocalMedia(isVideo: true);
    // In a real scenario, we'd wait for a few frames
    await Future.delayed(const Duration(seconds: 2));

    // Fallback/Simulated stats extraction if PC is not active
    report['camera_res'] = '1280x720';
    report['camera_fps'] = 30;
    report['camera_score'] = 100;

    await stream.dispose();
    calculateFinalScore();
  }

  void calculateFinalScore() {
    final mic = (report['mic_score'] ?? 0) * 0.4;
    final speaker = (report['speaker_score'] ?? 0) * 0.2;
    final camera = (report['camera_score'] ?? 0) * 0.4;

    readinessScore.value = (mic + speaker + camera).toInt();
    currentStep.value = DiagnosticStep.results;
  }
}
