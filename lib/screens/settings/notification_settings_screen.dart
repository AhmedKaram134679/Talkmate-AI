import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/notification_settings_controller.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NotificationSettingsController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الإشعارات'),
        elevation: 0,
      ),
      body: Obx(() {
        if (controller.isLoading.value &&
            controller.preferences.value == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final prefs = controller.preferences.value;
        if (prefs == null) {
          return const Center(child: Text('تعذر تحميل الإعدادات'));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader(context, 'التحكم في النوع'),
            _buildSwitchTile(
              context: context,
              title: 'الدردشات الفردية',
              subtitle: 'إشعارات الرسائل الخاصة',
              value: prefs.chatsEnabled,
              onChanged: controller.toggleChats,
              icon: Icons.person_outline,
            ),
            _buildSwitchTile(
              context: context,
              title: 'المجموعات',
              subtitle: 'إشعارات رسائل المجموعات',
              value: prefs.groupsEnabled,
              onChanged: controller.toggleGroups,
              icon: Icons.group_outlined,
            ),
            _buildSwitchTile(
              context: context,
              title: 'المكالمات',
              subtitle: 'إشعارات المكالمات الواردة',
              value: prefs.callsEnabled,
              onChanged: controller.toggleCalls,
              icon: Icons.call_outlined,
            ),
            const Divider(height: 32),
            _buildStyleSelector(context, controller),
            const SizedBox(height: 16),
            _buildPreviewCard(context, prefs.style),
            const Divider(height: 32),
            _buildSectionHeader(context, 'تجربة المستخدم الذكية (Stage S)'),
            _buildExperienceSection(context, controller),
            _buildTransparencyInfo(context),
            const SizedBox(height: 16),
            _buildSnoozeButton(context, controller),
            const Divider(height: 32),
            _buildSectionHeader(context, 'ساعات الهدوء (DND)'),
            _buildSwitchTile(
              context: context,
              title: 'تفعيل وضع الهدوء',
              subtitle: 'تحويل الإشعارات لصامتة في أوقات محددة',
              value: prefs.dndEnabled,
              onChanged: controller.toggleDnd,
              icon: Icons.do_not_disturb_on_outlined,
            ),
            if (prefs.dndEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildTimePicker(
                      context,
                      'من',
                      prefs.dndStart,
                      (time) => controller.updateDndStart(time),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTimePicker(
                      context,
                      'إلى',
                      prefs.dndEnd,
                      (time) => controller.updateDndEnd(time),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),
            _buildInformationCard(context),
          ],
        );
      }),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary:
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildStyleSelector(
      BuildContext context, NotificationSettingsController controller) {
    final style = controller.preferences.value?.style ?? 'full';
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildStyleButton(context, 'كاملة', 'full', style == 'full',
              () => controller.updateStyle('full')),
          _buildStyleButton(context, 'صامتة', 'silent', style == 'silent',
              () => controller.updateStyle('silent')),
          _buildStyleButton(context, 'مجمعة', 'digest', style == 'digest',
              () => controller.updateStyle('digest')),
        ],
      ),
    );
  }

  Widget _buildStyleButton(BuildContext context, String label, String value,
      bool isSelected, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context, String style) {
    final theme = Theme.of(context);
    String description = '';
    IconData icon = Icons.notifications;

    switch (style) {
      case 'full':
        description = 'ستصلك الإشعارات بصوت وبانر فوري.';
        icon = Icons.notifications_active;
        break;
      case 'silent':
        description =
            'ستصل الإشعارات بدون صوت، مع تحديث الـ Badge وحالة التطبيق.';
        icon = Icons.notifications_none;
        break;
      case 'digest':
        description = 'سيتم تجميع الإشعارات غير الهامة وإرسالها كملخص دوري.';
        icon = Icons.notifications_paused;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('كيف تظهر الإشعارات؟',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(description,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker(BuildContext context, String label,
      String currentTime, Function(String) onTimeSelected) {
    return InkWell(
      onTap: () async {
        final parts = currentTime.split(':');
        final initialTime =
            TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        final picked =
            await showTimePicker(context: context, initialTime: initialTime);
        if (picked != null) {
          final formatted =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          onTimeSelected(formatted);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16),
                const SizedBox(width: 8),
                Text(currentTime,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInformationCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            Theme.of(context).colorScheme.infoContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'تنبيه: المكالمات والرسائل الهامة (Mentions) ستتجاوز هذه الإعدادات لضمان وصولها دائماً.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExperienceSection(
      BuildContext context, NotificationSettingsController controller) {
    final mode =
        controller.experiencePreferences.value?.experienceMode ?? 'smart';
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildModeButton(
                  context,
                  'الأولوية فقط',
                  'critical',
                  mode == 'critical',
                  () => controller.updateExperienceMode('critical')),
              _buildModeButton(context, 'الوضع الذكي', 'smart', mode == 'smart',
                  () => controller.updateExperienceMode('smart')),
              _buildModeButton(context, 'الكل', 'all', mode == 'all',
                  () => controller.updateExperienceMode('all')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _getModeDescription(mode),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(BuildContext context, String label, String value,
      bool isSelected, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color:
                isSelected ? theme.colorScheme.secondary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected
                  ? theme.colorScheme.onSecondary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  String _getModeDescription(String mode) {
    switch (mode) {
      case 'critical':
        return 'وضع التركيز العميق: يتم حجب جميع التنبيات باستثناء المحادثات المثبتة، المنشن، والمكالمات العاجلة.';
      case 'smart':
        return 'الذكاء الاصطناعي (موصى به): يقوم النظام بتحليل نمط استخدامك لإيصال ما يهمك فقط وتأجيل الباقي للوقت الأنسب.';
      case 'all':
        return 'الوضع التقليدي: إيصال كافة التنبيهات فور صدورها دون أي معالجة ذكية أو تجميع.';
      default:
        return '';
    }
  }

  Widget _buildTransparencyInfo(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'كيف يعمل النظام الذكي؟',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoItem(context, Icons.verified_user_outlined,
              'خصوصية تامة: يتم تحليل البيانات محلياً وعلى مستوى المياداتا فقط.'),
          _buildInfoItem(context, Icons.history_toggle_off,
              'احترام الوقت: النظام يتجنب إزعاجك في ساعات الهدوء المتوقعة.'),
          _buildInfoItem(context, Icons.security_outlined,
              'الأمان أولاً: الرسائل الحرجة لا تخضع لأي تأخير أو حجب.'),
        ],
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnoozeButton(
      BuildContext context, NotificationSettingsController controller) {
    final isSnoozed =
        controller.experiencePreferences.value?.isSnoozed ?? false;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => controller.toggleSnooze(!isSnoozed),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSnoozed
              ? theme.colorScheme.errorContainer.withValues(alpha: 0.1)
              : theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSnoozed
                ? theme.colorScheme.error.withValues(alpha: 0.3)
                : theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSnoozed ? Icons.notifications_off : Icons.timer,
              color: isSnoozed
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSnoozed
                        ? 'الإشعارات مكتومة حالياً'
                        : 'تفعيل وضع الغفوة (Snooze)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    isSnoozed
                        ? 'سيتم استعادة الإشعارات تلقائياً لاحقاً'
                        : 'كتم جميع الإشعارات لمدة ساعة واحدة للتركيز.',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (isSnoozed)
              TextButton(
                onPressed: () => controller.toggleSnooze(false),
                child: const Text('إلغاء الآن'),
              ),
          ],
        ),
      ),
    );
  }
}

extension ColorSchemeExt on ColorScheme {
  Color get infoContainer => Colors.blue;
}
