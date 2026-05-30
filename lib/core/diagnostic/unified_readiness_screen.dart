import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:get/get.dart';
import 'package:talkmate_ai/core/diagnostic/unified_diagnostic_controller.dart';

class UnifiedReadinessScreen extends GetView<UnifiedDiagnosticController> {
  const UnifiedReadinessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Call Readiness Center'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Obx(() {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                _buildProgressTimeline(theme),
                const SizedBox(height: 24),
                Expanded(child: _buildCurrentSection(theme)),
                _buildDynamicFooter(theme),
              ],
            ),
          );
        }),
      ),
      // [HARDENING]: Debug Overlay
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: () => _showDebugOverlay(context),
        child: const Icon(Icons.bug_report),
      ),
    );
  }

  void _showDebugOverlay(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Diagnostic Debug'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Step: ${controller.currentStep.value}'),
            Text('Mic Level: ${controller.micLevel.value.toStringAsFixed(4)}'),
            Text('Speaker Verified: ${controller.speakerVerified.value}'),
            Text('Frames: ${controller.frameCount.value}'),
            Text('Res: ${controller.cameraRes.value}'),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressTimeline(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: UnifiedStep.values.map((step) {
        final isCompleted = controller.currentStep.value.index > step.index;
        final isActive = controller.currentStep.value == step;

        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 6,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green
                  : (isActive ? theme.primaryColor : theme.dividerColor),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCurrentSection(ThemeData theme) {
    switch (controller.currentStep.value) {
      case UnifiedStep.hardwareAudit:
        return _buildAuditView(theme);
      case UnifiedStep.micTest:
        return _buildMicView(theme);
      case UnifiedStep.speakerTest:
        return _buildSpeakerView(theme);
      case UnifiedStep.cameraTest:
        return _buildCameraView(theme);
      case UnifiedStep.networkTest:
        return _buildNetworkView(theme);
      case UnifiedStep.results:
        return _buildResultsView(theme);
    }
  }

  Widget _buildAuditView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hardware Discovery',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildHwTile('Microphones', controller.audioInputs.length, Icons.mic),
        _buildHwTile('Speakers', controller.audioOutputs.length, Icons.speaker),
        _buildHwTile('Cameras', controller.videoInputs.length, Icons.videocam),
        const Spacer(),
        const Center(
            child: Text('We will now check each device for quality.',
                textAlign: TextAlign.center)),
      ],
    );
  }

  Widget _buildHwTile(String label, int count, IconData icon) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text('$count detected',
          style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildMicView(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.mic, size: 80, color: Colors.blue),
        const SizedBox(height: 24),
        const Text('Testing Microphone Level', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: controller.micLevel.value.clamp(0, 1)),
        if (controller.micClipping.value)
          const Text('⚠️ AUDIO CLIPPING',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSpeakerView(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.volume_up, size: 80, color: Colors.orange),
        const SizedBox(height: 24),
        const Text('Tone Verification', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
                onPressed: () => controller.playTestTone('LEFT'),
                child: const Text('Test Left')),
            ElevatedButton(
                onPressed: () => controller.playTestTone('RIGHT'),
                child: const Text('Test Right')),
          ],
        ),
        const SizedBox(height: 32),
        const Text('Did you hear the audio clearly?'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
                onPressed: () => controller.endSpeakerTest(false),
                child: const Text('No')),
            ElevatedButton(
                onPressed: () => controller.endSpeakerTest(true),
                child: const Text('Yes')),
          ],
        ),
      ],
    );
  }

  Widget _buildCameraView(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Camera Analysis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: webrtc.RTCVideoView(
            controller.videoRenderer,
            mirror: true,
            objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(width: 12),
            Text('Checking Stream: ${controller.cameraRes.value}'),
          ],
        ),
        Text('Frames Captured: ${controller.frameCount.value}',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildNetworkView(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.network_check, size: 80, color: Colors.green),
        const SizedBox(height: 24),
        const Text('Measuring Network Stability',
            style: TextStyle(fontSize: 18)),
        const SizedBox(height: 32),
        _buildNetMetric('Latency', '${controller.latency.value.toInt()}ms'),
        _buildNetMetric('Download',
            '${controller.downloadSpeed.value.toStringAsFixed(1)} Mbps'),
      ],
    );
  }

  Widget _buildNetMetric(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold))
        ],
      ),
    );
  }

  Widget _buildResultsView(ThemeData theme) {
    final score = controller.globalScore.value;
    Color color = Colors.green;
    if (score < 50) {
      color = Colors.red;
    } else if (score < 75) {
      color = Colors.orange;
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 8)),
            child: Text('$score%',
                style: TextStyle(
                    fontSize: 48, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(height: 24),
          const Text('Unified Readiness Assessment',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...controller.combinedRecommendations.map((rec) => Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.blue),
                  title: Text(rec),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildDynamicFooter(ThemeData theme) {
    final step = controller.currentStep.value;

    if (step == UnifiedStep.hardwareAudit) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
            onPressed: () => controller.startCompleteTest(),
            child: const Text('Start Complete Test')),
      );
    }

    if (step == UnifiedStep.results) {
      return Row(
        children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => Get.back(), child: const Text('Close'))),
          const SizedBox(width: 16),
          Expanded(
              child: ElevatedButton(
                  onPressed: () => controller.onInit(),
                  child: const Text('Retest'))),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}
