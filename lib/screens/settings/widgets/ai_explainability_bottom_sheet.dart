import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/notification_ai_settings_controller.dart';

class AIExplainabilityBottomSheet extends StatelessWidget {
  final Map<String, dynamic> decisionLog;

  const AIExplainabilityBottomSheet({
    super.key,
    required this.decisionLog,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contextData =
        (decisionLog['explanation_context'] as Map<String, dynamic>?) ?? {};
    final explanationText = (contextData['text'] as String?) ??
        'قرار تلقائي بناءً على السياسات الافتراضية.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                'لماذا وصلني هذا الإشعار؟',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildTimelineItem(
            context,
            icon: Icons.analytics_outlined,
            title: 'تحليل السلوك (AI Input)',
            description: explanationText,
            isFirst: true,
          ),
          _buildTimelineItem(
            context,
            icon: Icons.wb_sunny_outlined,
            title: 'قراءة السياق (Environment)',
            description: _getContextDescription(
                contextData['time_segment'] as String?, contextData['delay']),
          ),
          _buildTimelineItem(
            context,
            icon: Icons.psychology,
            title: 'قرار النظام (Decision)',
            description: _getDecisionText(decisionLog['final_decision']),
            color: _getDecisionColor(theme, decisionLog['final_decision']),
          ),
          _buildTimelineItem(
            context,
            icon: Icons.history_edu,
            title: 'التعلّم المستمر (Outcome)',
            description: 'تم تحديث نمط تواجدك المفضل لضمان دقة أكبر مستقبلاً.',
            isLast: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  _FeedbackButton(
                    icon: Icons.thumb_up_alt_outlined,
                    label: 'مناسب',
                    color: Colors.green,
                    onTap: () => Get.find<NotificationAiSettingsController>()
                        .submitFeedback(
                            decisionLog['id'].toString(), 'positive'),
                  ),
                  const SizedBox(width: 12),
                  _FeedbackButton(
                    icon: Icons.thumb_down_alt_outlined,
                    label: 'غير مناسب',
                    color: Colors.red,
                    onTap: () => Get.find<NotificationAiSettingsController>()
                        .submitFeedback(
                            decisionLog['id'].toString(), 'negative'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('فهمت ذلك'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    Color? color,
    bool isFirst = false,
    bool isLast = false,
    Widget? child,
  }) {
    final theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 2,
                height: 16,
                color: isFirst
                    ? Colors.transparent
                    : theme.colorScheme.outlineVariant,
              ),
              Icon(icon, size: 24, color: color ?? theme.colorScheme.primary),
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast
                      ? Colors.transparent
                      : theme.colorScheme.outlineVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(description,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
                  if (child != null) child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getContextDescription(String? segment, dynamic delay) {
    String text = 'تم تحليل نشاطك: ';
    switch (segment) {
      case 'night':
        text += 'فترة ليلية';
        break;
      case 'work':
        text += 'ساعات عمل';
        break;
      case 'weekend':
        text += 'عطلة نهاية الأسبوع';
        break;
      default:
        text += 'فترة نشاط معتادة';
    }

    if (delay != null && (delay as num) > 0) {
      text += ' (تم التأجيل لـ $delay دقيقة للوقت الأمثل).';
    } else {
      text += ' (التسليم فوري).';
    }
    return text;
  }

  String _getDecisionText(String? decision) {
    if (decision == 'AI_CONTEXT_DELAYED') return 'تأجيل ذكي (Smart Delay)';
    switch (decision) {
      case 'sent':
        return 'إرسال كامل (Full Push)';
      case 'silent':
        return 'إرسال صامت (Silent)';
      case 'throttled':
        return 'إضافة للموجز (Digest)';
      default:
        return 'تجاهل (Skipped)';
    }
  }

  Color _getDecisionColor(ThemeData theme, String? decision) {
    switch (decision) {
      case 'sent':
        return Colors.green;
      case 'silent':
        return Colors.blue;
      case 'throttled':
        return Colors.orange;
      default:
        return theme.colorScheme.primary;
    }
  }
}

class _FeedbackButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FeedbackButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
