import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/notification_ai_settings_controller.dart';
import 'package:talkmate_ai/data/models/notification_ai_settings_model.dart';
import 'package:talkmate_ai/data/models/user_learning_model.dart';

class AILearningDashboardScreen extends StatelessWidget {
  const AILearningDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<NotificationAiSettingsController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ذكاء التعلّم الذاتي'),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final settings = controller.aiSettings.value;
        final weights = controller.learningWeights.value;

        if (settings == null) {
          return const Center(child: Text('لا توجد بيانات متاحة'));
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildStatusCard(theme, settings),
            const SizedBox(height: 24),
            _buildMetricGrid(theme, settings, weights),
            const SizedBox(height: 24),
            _buildWeightsChart(theme, weights),
            const SizedBox(height: 32),
            _buildLearningToggle(theme, controller, settings),
            const SizedBox(height: 16),
            const Text(
              'يقوم النظام بتعديل أوزان اتخاذ القرار تلقائياً بناءً على تفاعلك مع الإشعارات لتقليل الإزعاج وتحسين الدقة.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        );
      }),
    );
  }

  Widget _buildStatusCard(ThemeData theme, NotificationAiSettings settings) {
    final trustIndex = settings
        .systemTrustIndex; // Assuming non-nullable double based on model
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
            'مؤشر ثقة النظام',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${(trustIndex * 100).toInt()}%',
            style: theme.textTheme.displayMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: trustIndex,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid(ThemeData theme, NotificationAiSettings settings,
      LearningWeights? weights) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildSmallMetric(theme, 'دورات التعلم',
            '${weights?.learningCycles ?? 0}', Icons.loop),
        _buildSmallMetric(theme, 'نمو الدقة', '+12%', Icons.trending_up,
            color: Colors.green),
      ],
    );
  }

  Widget _buildSmallMetric(
      ThemeData theme, String label, String value, IconData icon,
      {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color ?? theme.colorScheme.secondary),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildWeightsChart(ThemeData theme, LearningWeights? weights) {
    final eWeight = weights?.engagementWeight ?? 0.4;
    final cWeight = weights?.contextWeight ?? 0.3;
    final uWeight = weights?.urgencyWeight ?? 0.3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('توزيع أوزان القرار (Decision Weights)',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 16),
        Container(
          height: 24,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Expanded(
                  flex: (eWeight * 100).toInt(),
                  child: Container(color: Colors.blue)),
              Expanded(
                  flex: (cWeight * 100).toInt(),
                  child: Container(color: Colors.orange)),
              Expanded(
                  flex: (uWeight * 100).toInt(),
                  child: Container(color: Colors.purple)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildLegendItem('التفاعل', Colors.blue),
            _buildLegendItem('السياق', Colors.orange),
            _buildLegendItem('الأهمية', Colors.purple),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildLearningToggle(
      ThemeData theme,
      NotificationAiSettingsController controller,
      NotificationAiSettings settings) {
    return SwitchListTile(
      value: settings.learningEnabled,
      onChanged: (val) => controller.toggleLearningEnabled(val),
      title: const Text('التعلّم التلقائي مفعّل'),
      subtitle: const Text('السماح للنظام بتحديث أوزان القرار تلقائياً'),
      secondary: Icon(Icons.auto_fix_high,
          color: settings.learningEnabled ? Colors.amber : null),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
    );
  }
}
