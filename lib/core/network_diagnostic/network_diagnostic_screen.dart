import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/network_diagnostic/network_diagnostic_controller.dart';

class NetworkDiagnosticScreen extends GetView<NetworkDiagnosticController> {
  const NetworkDiagnosticScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Network Diagnostic'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Obx(() {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(theme),
                const SizedBox(height: 32),
                Expanded(child: _buildMainContent(theme)),
                _buildActionButton(theme),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection Type',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.hintColor),
                ),
                Text(
                  controller.connectionType.value,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (controller.status.value == NetworkTestStatus.testing)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMainContent(ThemeData theme) {
    if (controller.status.value == NetworkTestStatus.idle) {
      return _buildIdleView(theme);
    }

    if (controller.status.value == NetworkTestStatus.testing) {
      return _buildTestingView(theme);
    }

    return _buildResultsView(theme);
  }

  Widget _buildIdleView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.network_check_rounded,
              size: 80, color: theme.primaryColor.withValues(alpha: 0.5)),
          const SizedBox(height: 24),
          const Text(
            'Ready to Analyze',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'A 15-second test will measure your real-time latency, jitter, and bandwidth.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  Widget _buildTestingView(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${(controller.progress.value * 100).toInt()}%',
          style: theme.textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: controller.progress.value,
          borderRadius: BorderRadius.circular(10),
          minHeight: 10,
        ),
        const SizedBox(height: 32),
        const Text('Measuring latency and signal stability...'),
      ],
    );
  }

  Widget _buildResultsView(ThemeData theme) {
    final score = controller.readinessScore.value;
    Color scoreColor = Colors.green;
    String statusText = 'Excellent for HD';

    if (score < 50) {
      scoreColor = Colors.red;
      statusText = 'Unstable Connection';
    } else if (score < 70) {
      scoreColor = Colors.orange;
      statusText = 'Voice Only Recommended';
    } else if (score < 90) {
      scoreColor = Colors.blue;
      statusText = 'Good for Video';
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildScoreGauge(score, statusText, scoreColor, theme),
          const SizedBox(height: 32),
          _buildMetricRow(Icons.timer_rounded, 'Latency',
              '${controller.latency.value.toInt()} ms'),
          _buildMetricRow(Icons.waves_rounded, 'Jitter',
              '${controller.jitter.value.toInt()} ms'),
          _buildMetricRow(Icons.download_rounded, 'Download',
              '${controller.downloadSpeed.value.toStringAsFixed(1)} Mbps'),
          _buildMetricRow(Icons.upload_rounded, 'Upload',
              '${controller.uploadSpeed.value.toStringAsFixed(1)} Mbps'),
          const SizedBox(height: 24),
          if (controller.recommendations.isNotEmpty) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Recommendations',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 12),
            ...controller.recommendations
                .map((rec) => _buildRecommendationItem(rec, theme)),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreGauge(
      int score, String status, Color color, ThemeData theme) {
    return Column(
      children: [
        Text(
          '$score%',
          style: theme.textTheme.displayMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          status,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildMetricRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blueAccent),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildRecommendationItem(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme) {
    final status = controller.status.value;
    final isTesting = status == NetworkTestStatus.testing;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isTesting ? null : () => controller.startFullDiagnostic(),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          status == NetworkTestStatus.idle ? 'Start Network Test' : 'Run Again',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
