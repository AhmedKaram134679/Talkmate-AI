import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/notification_ai_settings_controller.dart';
import 'package:talkmate_ai/data/models/user_context_model.dart';

class AIContextSettingsScreen extends StatelessWidget {
  const AIContextSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<NotificationAiSettingsController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('الذكاء السياقي (Context)'),
        elevation: 0,
      ),
      body: Obx(() {
        final settings = controller.contextSettings.value;
        final profile = controller.contextProfile.value;

        if (settings == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildContextHero(context),
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'التوقيت الذكي'),
            _buildPredictiveToggle(controller, settings),
            const SizedBox(height: 16),
            _buildDrivingModeToggle(controller, settings),
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'حساسية الفترات الزمنية'),
            _buildNightSensitivity(context, controller, settings),
            const SizedBox(height: 16),
            _buildWorkSensitivity(context, controller, settings),
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'نمط نشاطك (Peak Hours)'),
            _buildPeakHoursMap(context, profile),
            const SizedBox(height: 32),
            _buildInfoCard(context),
          ],
        );
      }),
    );
  }

  Widget _buildContextHero(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.psychology, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'فهم المحيط والسلوك',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'يتعلم النظام متى تكون أكثر نشاطاً ليقوم بتسليم الإشعارات في الوقت الأمثل لك.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildPredictiveToggle(NotificationAiSettingsController controller,
      UserContextSettings settings) {
    return SwitchListTile(
      value: settings.predictiveTimingEnabled,
      onChanged: (val) {
        controller.updateContextSettings(
            settings.copyWith(predictiveTimingEnabled: val));
      },
      title: const Text('التوقيت التنبؤي (Predictive Timing)'),
      subtitle: const Text('تأخير الإشعارات غير العاجلة للحظة نشاطك القادمة.'),
      secondary: const Icon(Icons.timer_outlined),
    );
  }

  Widget _buildDrivingModeToggle(NotificationAiSettingsController controller,
      UserContextSettings settings) {
    return SwitchListTile(
      value: settings.respectDrivingMode,
      onChanged: (val) {
        controller
            .updateContextSettings(settings.copyWith(respectDrivingMode: val));
      },
      title: const Text('وضع القيادة الذكي'),
      subtitle: const Text('تقليل الإشعارات تلقائياً أثناء القيادة لسلامتك.'),
      secondary: const Icon(Icons.directions_car_outlined),
    );
  }

  Widget _buildNightSensitivity(
      BuildContext context,
      NotificationAiSettingsController controller,
      UserContextSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('هدوء الليل (Night Sensitivity)'),
            Text('${(settings.nightModeSensitivity * 100).toInt()}%',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: settings.nightModeSensitivity,
          onChanged: (val) {
            controller.updateContextSettings(
                settings.copyWith(nightModeSensitivity: val));
          },
        ),
      ],
    );
  }

  Widget _buildWorkSensitivity(
      BuildContext context,
      NotificationAiSettingsController controller,
      UserContextSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('تركيز العمل (Work Focus)'),
            Text('${(settings.workHoursSensitivity * 100).toInt()}%',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: settings.workHoursSensitivity,
          onChanged: (val) {
            controller.updateContextSettings(
                settings.copyWith(workHoursSensitivity: val));
          },
        ),
      ],
    );
  }

  Widget _buildPeakHoursMap(BuildContext context, UserContextProfile? profile) {
    final theme = Theme.of(context);
    final hours = profile?.peakInteractionHours ?? [];

    return Container(
      height: 80,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(24, (index) {
          final isPeak = hours.contains(index);
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: isPeak
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
              height: isPeak ? 40 : 10,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.2),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.security, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'يتم معالجة بيانات السياق محلياً وبالحد الأدنى لضمان خصوصيتك الكاملة.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
