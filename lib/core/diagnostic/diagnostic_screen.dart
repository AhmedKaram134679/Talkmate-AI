import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:get/get.dart';
import 'package:talkmate_ai/core/diagnostic/diagnostic_controller.dart';

class DiagnosticScreen extends GetView<DiagnosticController> {
  const DiagnosticScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('AI Diagnostic Center'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Obx(() {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                _buildProgressHeader(theme),
                const SizedBox(height: 32),
                Expanded(child: _buildCurrentStepView(theme)),
                _buildNavigationButtons(theme),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildProgressHeader(ThemeData theme) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: DiagnosticStep.values.map((step) {
            final isActive = controller.currentStep.value.index >= step.index;
            return Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isActive ? theme.primaryColor : theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Text(
          controller.currentStep.value.name
              .toUpperCase()
              .replaceAll('TEST', ' TEST'),
          style: theme.textTheme.labelLarge?.copyWith(
            letterSpacing: 1.2,
            color: theme.primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStepView(ThemeData theme) {
    switch (controller.currentStep.value) {
      case DiagnosticStep.deviceAudit:
        return _buildDeviceAudit(theme);
      case DiagnosticStep.micTest:
        return _buildMicTest(theme);
      case DiagnosticStep.speakerTest:
        return _buildSpeakerTest(theme);
      case DiagnosticStep.cameraTest:
        return _buildCameraTest(theme);
      case DiagnosticStep.results:
        return _buildResultsView(theme);
    }
  }

  Widget _buildDeviceAudit(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hardware Discovery', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Detecting and listing available devices on your system.',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
        const SizedBox(height: 24),
        _buildDeviceSection('Microphones', controller.audioInputs, Icons.mic),
        const SizedBox(height: 16),
        _buildDeviceSection('Speakers', controller.audioOutputs, Icons.speaker),
        const SizedBox(height: 16),
        _buildDeviceSection('Cameras', controller.videoInputs, Icons.videocam),
      ],
    );
  }

  Widget _buildDeviceSection(
      String title, List<webrtc.MediaDeviceInfo> devices, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        if (devices.isEmpty)
          const Text('No devices detected.')
        else
          ...devices.map((d) => Card(
                child: ListTile(
                  title: Text(d.label),
                  subtitle: Text(d.deviceId == 'default'
                      ? 'Default Device'
                      : 'Internal/USB'),
                  dense: true,
                ),
              )),
      ],
    );
  }

  Widget _buildMicTest(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.mic, size: 64, color: Colors.blue),
        const SizedBox(height: 24),
        const Text('Real-time Signal Analysis',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        // Level Meter
        Container(
          height: 20,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: controller.currentMicLevel.value.clamp(0, 1),
            child: Container(
              decoration: BoxDecoration(
                gradient:
                    LinearGradient(colors: [theme.primaryColor, Colors.green]),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
            'RMS: ${(controller.currentMicLevel.value * 100).toStringAsFixed(1)}%',
            style: theme.textTheme.bodySmall),

        if (controller.isClippingDetected.value)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('⚠️ CLIPPING DETECTED: PLEASE LOWER GAIN',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),

        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => controller.startMicTest(),
          child: const Text('Start 5s Voice Sample'),
        ),
      ],
    );
  }

  Widget _buildSpeakerTest(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.volume_up, size: 64, color: Colors.orange),
        const SizedBox(height: 24),
        const Text('Calibrated Tone Test',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 32),
        Wrap(
          spacing: 16,
          children: [
            ElevatedButton(
                onPressed: () => controller.playTestTone('LEFT'),
                child: const Text('Left')),
            ElevatedButton(
                onPressed: () => controller.playTestTone('RIGHT'),
                child: const Text('Right')),
            ElevatedButton(
                onPressed: () => controller.playTestTone('SWEEP'),
                child: const Text('Sweep')),
          ],
        ),
        const SizedBox(height: 48),
        const Text('Did you hear the tones clearly?'),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
                onPressed: () => controller.completeSpeakerTest(false),
                child: const Text('No')),
            const SizedBox(width: 16),
            ElevatedButton(
                onPressed: () => controller.completeSpeakerTest(true),
                child: const Text('Yes')),
          ],
        ),
      ],
    );
  }

  Widget _buildCameraTest(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.camera_alt, size: 64, color: Colors.purple),
        const SizedBox(height: 24),
        const Text('Vision Analysis',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => controller.runCameraCheck(),
          child: const Text('Start Video Analysis'),
        ),
      ],
    );
  }

  Widget _buildResultsView(ThemeData theme) {
    final score = controller.readinessScore.value;
    String status = 'Excellent';
    Color color = Colors.green;

    if (score < 50) {
      status = 'Not Recommended';
      color = Colors.red;
    } else if (score < 70) {
      status = 'Needs Improvement';
      color = Colors.orange;
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24),
                _buildScoreCircle(score, status, color, theme),
                const SizedBox(height: 40),
                _buildResultDetail(
                    'Microphone',
                    '${controller.report['mic_score']}%',
                    controller.isClippingDetected.value ? 'Clipping' : 'Good'),
                _buildResultDetail('Speaker',
                    '${controller.report['speaker_score']}%', 'Verified'),
                _buildResultDetail('Camera',
                    '${controller.report['camera_score']}%', '720p @ 30fps'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreCircle(
      int score, String status, Color color, ThemeData theme) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.2), width: 12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$score%',
                style: theme.textTheme.displayMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            Text(status,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultDetail(String title, String val, String desc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing:
            Text(val, style: const TextStyle(fontSize: 18, color: Colors.blue)),
        subtitle: Text(desc),
      ),
    );
  }

  Widget _buildNavigationButtons(ThemeData theme) {
    if (controller.currentStep.value == DiagnosticStep.results) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Get.back(),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          child: const Text('Finish Diagnostic'),
        ),
      );
    }

    if (controller.currentStep.value == DiagnosticStep.deviceAudit) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () =>
              controller.currentStep.value = DiagnosticStep.micTest,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          child: const Text('Start Signal Tests'),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
