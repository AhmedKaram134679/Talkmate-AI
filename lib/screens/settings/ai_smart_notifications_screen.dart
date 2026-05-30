import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/notification_ai_settings_controller.dart';
import 'package:talkmate_ai/screens/settings/ai_context_settings_screen.dart';
import 'package:talkmate_ai/screens/settings/ai_learning_dashboard_screen.dart';
import 'package:talkmate_ai/screens/settings/ai_policy_dashboard_screen.dart';
import 'package:talkmate_ai/screens/settings/ai_stability_dashboard_screen.dart';

class AISmartNotificationsScreen extends StatelessWidget {
  const AISmartNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NotificationAiSettingsController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات الذكية AI'),
        elevation: 0,
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.aiSettings.value == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final settings = controller.aiSettings.value;
        if (settings == null) {
          return const Center(
              child: Text('تعذر تحميل إعدادات الذكاء الاصطناعي'));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeroCard(context, controller),
            const SizedBox(height: 24),
            if (settings.isEnabled) ...[
              _buildSectionHeader(context, 'تخصيص الخوارزمية'),
              _buildAdaptiveToggle(context, controller),
              const SizedBox(height: 16),
              _buildSensitivitySlider(context, controller),
              const SizedBox(height: 24),
              _buildSectionHeader(context, 'الذكاء السياقي (Context)'),
              _buildContextLink(context, controller),
              const SizedBox(height: 24),
              _buildSectionHeader(context, 'التعلّم الذاتي (Learning Loop)'),
              _buildLearningLink(context, controller),
              const SizedBox(height: 24),
              _buildStatsCard(context, controller),
              const SizedBox(height: 24),
              _buildSectionHeader(context, 'حوكمة وأمان AI (Governance)'),
              _buildGovernanceControls(context, controller),
            ],
            const SizedBox(height: 32),
            _buildAIExplanation(context),
          ],
        );
      }),
    );
  }

  Widget _buildContextLink(
      BuildContext context, NotificationAiSettingsController controller) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: const Icon(Icons.psychology_outlined),
        title: const Text('إعدادات السياق والبيئة'),
        subtitle: const Text('تحكم في كيفية تأثر الذكاء بالوقت ومكان تواجدك.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Get.to(() => const AIContextSettingsScreen()),
      ),
    );
  }

  Widget _buildHeroCard(
      BuildContext context, NotificationAiSettingsController controller) {
    final isEnabled = controller.aiSettings.value?.isEnabled ?? false;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isEnabled
              ? [theme.colorScheme.primary, theme.colorScheme.primaryContainer]
              : [
                  theme.colorScheme.surfaceContainerHighest,
                  theme.colorScheme.surfaceContainerHighest
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: isEnabled
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الطيار الآلي للإشعارات',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: isEnabled
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isEnabled ? 'يعمل الآن بذكاء' : 'متوقف حالياً',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isEnabled
                            ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: controller.toggleAiEnabled,
                activeThumbColor: theme.colorScheme.onPrimary,
                activeTrackColor:
                    theme.colorScheme.onPrimary.withValues(alpha: 0.3),
              ),
            ],
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
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildAdaptiveToggle(
      BuildContext context, NotificationAiSettingsController controller) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.psychology_outlined),
      title: const Text('الوضع التكيفي (Adaptive)',
          style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle:
          const Text('تغيير أسلوب الوصول تلقائياً بناءً على سرعة تفاعلك.'),
      trailing: Switch(
        value: controller.aiSettings.value?.adaptiveMode ?? true,
        onChanged: controller.toggleAdaptiveMode,
      ),
    );
  }

  Widget _buildSensitivitySlider(
      BuildContext context, NotificationAiSettingsController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('حساسية الفلترة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              _getSensitivityLabel(
                  controller.aiSettings.value?.sensitivity ?? 0.5),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: controller.aiSettings.value?.sensitivity ?? 0.5,
          min: 0.1,
          max: 1.0,
          onChanged: controller.updateSensitivity,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('خفيف', style: TextStyle(fontSize: 10)),
              Text('متوازن', style: TextStyle(fontSize: 10)),
              Text('صارم', style: TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard(
      BuildContext context, NotificationAiSettingsController controller) {
    final stats = controller.efficiencyStats;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 20),
              const SizedBox(width: 8),
              const Text('كفاءة التوفير الرقمي',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                '${(((controller.efficiencyStats['efficiency_rate'] as num?) ?? 0.0) * 100).toInt()}%',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _buildStatRow(
              'إشعارات تمت معالجتها', '${stats['total_processed'] ?? 0}'),
          _buildStatRow(
              'تم تحويلها لصامتة/مجمعة', '${stats['ai_silenced'] ?? 0}'),
          const SizedBox(height: 8),
          const Text(
            'تم تقليل الضوضاء الرقمية بشكل ملحوظ بواسطة الجناح الذكي.',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildGovernanceControls(
      BuildContext context, NotificationAiSettingsController controller) {
    final settings = controller.aiSettings.value!;
    final theme = Theme.of(context);

    final isPaused = settings.pausedUntil != null &&
        settings.pausedUntil!.isAfter(DateTime.now());

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: settings.isSafeMode,
            onChanged: controller.toggleSafeMode,
            secondary: Icon(Icons.gpp_maybe_outlined,
                color: settings.isSafeMode ? theme.colorScheme.error : null),
            title: const Text('وضع الأمان (Safe Mode)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                'تجاهل ذكاء AI والعودة للوضع التقليدي في حال عدم الدقة.'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.pause_circle_outline),
            title: const Text('تجميد الذكاء مؤقتاً (Pause AI)'),
            subtitle: Text(isPaused
                ? 'مجمد حتى: ${settings.pausedUntil!.hour}:${settings.pausedUntil!.minute}'
                : 'أوقف الذكاء لفترة محددة للراحة.'),
            trailing: OutlinedButton(
              onPressed: () => _showPauseDialog(context, controller),
              child: Text(isPaused ? 'تعديل' : 'تجميد'),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: const Text('المحادثات المستثناة'),
            subtitle:
                Obx(() => Text('${controller.aiExclusions.length} محادثات')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Navigation to Exclusion List (To be implemented or shown as dialog)
              Get.snackbar('قريباً', 'قائمة الاستثناءات التفصيلية قيد التطوير');
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('استقرار وحوكمة النموذج'),
            subtitle:
                const Text('إدارة النسخ الاحتياطية ومراقبة انحراف التعلم.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.to(() => const AIStabilityDashboardScreen()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('سياسات الذكاء (Policies)'),
            subtitle:
                const Text('تحكم في صلاحيات الذكاء عبر النطاقات المختلفة.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.to(() => const AiPolicyDashboardScreen()),
          ),
        ],
      ),
    );
  }

  void _showPauseDialog(
      BuildContext context, NotificationAiSettingsController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تجميد الذكاء الاصطناعي'),
        content:
            const Text('اختر المدة التي تريد فيها تعطيل الذكاء الاصطناعي:'),
        actions: [
          TextButton(
            onPressed: () {
              controller.pauseAi(const Duration(hours: 1));
              Navigator.pop(context);
            },
            child: const Text('ساعة واحدة'),
          ),
          TextButton(
            onPressed: () {
              controller.pauseAi(const Duration(hours: 8));
              Navigator.pop(context);
            },
            child: const Text('8 ساعات'),
          ),
          TextButton(
            onPressed: () {
              controller.pauseAi(const Duration(days: 1));
              Navigator.pop(context);
            },
            child: const Text('يوم كامل'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Widget _buildAIExplanation(BuildContext context) {
    return Card(
      elevation: 0,
      color:
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 20),
                SizedBox(width: 8),
                Text('كيف يعمل الذكاء الاصطناعي؟',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'يقوم النظام بتحليل سرعة فتحك للرسائل لكل محادثة على حدة. إذا لاحظ تجاهلاً متكرراً، سيقوم بتحويل الإشعارات تلقائياً إلى وضع الصمت أو التجميع (Digest) لتوفير وقتك، مع ضمان وصول رسائل الـ Mentions والمكالمات دائماً.',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLearningLink(
      BuildContext context, NotificationAiSettingsController controller) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: const Icon(Icons.auto_fix_high),
        title: const Text('لوحة قيادة التعلّم'),
        subtitle: const Text('شاهد كيف يطور النظام أسلوبه بناءً على تفاعلك.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Get.to(() => const AILearningDashboardScreen()),
      ),
    );
  }

  String _getSensitivityLabel(double value) {
    if (value < 0.4) return 'متساهل';
    if (value < 0.7) return 'متوازن';
    return 'صارم جداً';
  }
}
