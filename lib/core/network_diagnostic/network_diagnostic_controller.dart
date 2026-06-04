import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/network_diagnostic/network_diagnostic_service.dart';

enum NetworkTestStatus { idle, testing, completed, failed }

class NetworkDiagnosticController extends GetxController {
  final _service = NetworkDiagnosticService();

  // Test State
  final Rx<NetworkTestStatus> status = NetworkTestStatus.idle.obs;
  final RxDouble progress = 0.0.obs;

  // Measured Metrics
  final RxString connectionType = 'Detecting...'.obs;
  final RxDouble latency = 0.0.obs;
  final RxDouble jitter = 0.0.obs;
  final RxDouble packetLoss = 0.0.obs;
  final RxDouble downloadSpeed = 0.0.obs;
  final RxDouble uploadSpeed = 0.0.obs;

  // Final Score & Result
  final RxInt readinessScore = 0.obs;
  final RxList<String> recommendations = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    _initConnectionInfo();
  }

  Future<void> _initConnectionInfo() async {
    connectionType.value = await _service.getConnectionType();
  }

  Future<void> startFullDiagnostic() async {
    status.value = NetworkTestStatus.testing;
    progress.value = 0.0;
    recommendations.clear();

    try {
      // 1. Latency & Jitter (30% progress)
      progress.value = 0.1;
      final latResults =
          await _service.measureLatency('8.8.8.8'); // Google DNS as baseline
      latency.value = latResults['latency']!;
      jitter.value = latResults['jitter']!;
      packetLoss.value = latResults['packetLoss']!;
      progress.value = 0.4;

      // 2. Download Speed (30% progress)
      // Using a small file from a CDN for testing
      const dlUrl = 'https://speed.cloudflare.com/__down?bytes=1048576'; // 1MB
      downloadSpeed.value = await _service.measureDownloadSpeed(dlUrl);
      progress.value = 0.7;

      // 3. Upload Speed (30% progress)
      const ulUrl = 'https://speed.cloudflare.com/__up';
      uploadSpeed.value = await _service.measureUploadSpeed(ulUrl);
      progress.value = 1.0;

      _calculateScoreAndRecommendations();
      status.value = NetworkTestStatus.completed;
    } catch (e) {
      debugPrint('🌐 NetworkDiagnosticController: Error: $e');
      status.value = NetworkTestStatus.failed;
    }
  }

  void _calculateScoreAndRecommendations() {
    // Thresholds
    // Latency: < 40ms Excellent (100), > 150 Poor (0)
    final double latScore =
        (100 - ((latency.value - 20) * (100 / 130))).clamp(0, 100);
    // Jitter: < 10ms (100), > 40ms (0)
    final double jitterScore =
        (100 - (jitter.value * (100 / 40))).clamp(0, 100);
    // Packet Loss: 0% (100), > 5% (0)
    final double lossScore = (100 - (packetLoss.value * 20)).clamp(0, 100);
    // Download: > 5Mbps (100), < 0.5 (0)
    final double dlScore = ((downloadSpeed.value / 5.0) * 100).clamp(0, 100);
    // Upload: > 3Mbps (100), < 0.3 (0)
    final double ulScore = ((uploadSpeed.value / 3.0) * 100).clamp(0, 100);

    // Weighted Score
    // Latency: 30%, Jitter: 20%, Loss: 20%, UL: 15%, DL: 15%
    readinessScore.value = ((latScore * 0.3) +
            (jitterScore * 0.2) +
            (lossScore * 0.2) +
            (ulScore * 0.15) +
            (dlScore * 0.15))
        .toInt();

    // Recommendations
    if (latency.value > 100) {
      recommendations.add('High latency detected. Calls may feel delayed.');
    }
    if (packetLoss.value > 1) {
      recommendations.add('Packet loss detected. Audio might cut out.');
    }
    if (jitter.value > 20) {
      recommendations.add('Jitter is high. Audio quality might fluctuate.');
    }
    if (uploadSpeed.value < 1.0) {
      recommendations.add('Low upload speed. HD video might be unstable.');
    }

    if (connectionType.value.contains('Wi-Fi') && readinessScore.value < 80) {
      recommendations.add(
          'Move closer to the router or use a 5GHz Wi-Fi band for better stability.');
    }

    if (readinessScore.value >= 90) {
      recommendations.add(
          'Network conditions are excellent for high-quality video calls.');
    }
  }
}
