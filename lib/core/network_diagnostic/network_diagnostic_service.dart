import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NetworkMetrics {
  final double latency; // ms
  final double jitter; // ms
  final double packetLoss; // %
  final double downloadSpeed; // Mbps
  final double uploadSpeed; // Mbps
  final String connectionType;

  NetworkMetrics({
    required this.latency,
    required this.jitter,
    required this.packetLoss,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.connectionType,
  });

  @override
  String toString() =>
      'Lat: ${latency}ms, Jitter: ${jitter}ms, DL: ${downloadSpeed}Mbps, UL: ${uploadSpeed}Mbps';
}

class NetworkDiagnosticService {
  static final NetworkDiagnosticService _instance =
      NetworkDiagnosticService._internal();
  factory NetworkDiagnosticService() => _instance;
  NetworkDiagnosticService._internal();

  final Connectivity _connectivity = Connectivity();

  /// Gets the current connection type and adapter info
  Future<String> getConnectionType() async {
    final result = await _connectivity.checkConnectivity();
    if (result.contains(ConnectivityResult.ethernet)) return 'Ethernet (Wired)';
    if (result.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
    if (result.contains(ConnectivityResult.mobile)) return 'Cellular (LTE/5G)';
    return 'Unknown';
  }

  /// Measures real-time latency and jitter to a specific target
  Future<Map<String, double>> measureLatency(String host,
      {int pings = 10}) async {
    final List<double> rtts = [];
    int successCount = 0;

    for (int i = 0; i < pings; i++) {
      final stopwatch = Stopwatch()..start();
      try {
        // We use Socket.connect as a lightweight "ping" alternative on platforms where ICMP might be restricted
        final socket = await Socket.connect(host, 443,
            timeout: const Duration(seconds: 2));
        stopwatch.stop();
        rtts.add(stopwatch.elapsedMilliseconds.toDouble());
        successCount++;
        await socket.close();
      } catch (e) {
        stopwatch.stop();
        debugPrint('🌐 NetworkDiagnostic: Ping error to $host: $e');
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (rtts.isEmpty) return {'latency': 999, 'jitter': 0, 'packetLoss': 100};

    final double avgLatency = rtts.reduce((a, b) => a + b) / rtts.length;

    // Calculate Jitter (Average variation between consecutive RTTs)
    double jitterSum = 0;
    for (int i = 0; i < rtts.length - 1; i++) {
      jitterSum += (rtts[i] - rtts[i + 1]).abs();
    }
    final double jitter = rtts.length > 1 ? jitterSum / (rtts.length - 1) : 0;
    final double packetLoss = ((pings - successCount) / pings) * 100;

    return {
      'latency': avgLatency,
      'jitter': jitter,
      'packetLoss': packetLoss,
    };
  }

  /// Measures download speed using a progressive chunk method from a reliable public mirror
  /// Note: Real production should use its own backend for accuracy.
  Future<double> measureDownloadSpeed(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      stopwatch.stop();
      final bytes = response.bodyBytes.length;
      if (bytes == 0) throw 'Empty response';

      final double bits = bytes * 8;
      final double mbps =
          (bits / 1000000) / (stopwatch.elapsedMilliseconds / 1000);
      return mbps;
    } catch (e) {
      stopwatch.stop();
      debugPrint('🌐 NetworkDiagnostic: Download test failed: $e');
      return 0.0;
    }
  }

  /// Measures upload speed by sending a payload to an endpoint
  Future<double> measureUploadSpeed(String url) async {
    final payload = Uint8List(500 * 1024); // 500KB dummy payload
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http
          .post(
            Uri.parse(url),
            body: payload,
          )
          .timeout(const Duration(seconds: 15));
      stopwatch.stop();

      // Some endpoints might return 400+ for dummy data but still processed bits
      if (response.statusCode >= 200 && response.statusCode < 500) {
        final double bits = payload.length * 8;
        final double mbps =
            (bits / 1000000) / (stopwatch.elapsedMilliseconds / 1000);
        return mbps;
      }
      return 0.0;
    } catch (e) {
      stopwatch.stop();
      debugPrint('🌐 NetworkDiagnostic: Upload test failed: $e');
      return 0.0;
    }
  }
}
