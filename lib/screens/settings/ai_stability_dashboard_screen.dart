import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:talkmate_ai/controllers/notification_ai_settings_controller.dart';
import 'package:talkmate_ai/data/models/ai_stability_model.dart';

class AIStabilityDashboardScreen
    extends GetView<NotificationAiSettingsController> {
  const AIStabilityDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حوكمة واستقرار الذكاء'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.loadStabilityData(),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final ai = controller.aiSettings.value;
        if (ai == null) return const Center(child: Text('فشل تحميل الإعدادات'));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStabilityHeader(context, ai.stabilityScore),
            const SizedBox(height: 24),
            _buildSandboxCard(context, ai.sandboxModeEnabled),
            const SizedBox(height: 24),
            _buildSnapshotsSection(context),
            const SizedBox(height: 24),
            _buildAuditSection(context),
          ],
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSnapshotDialog(context),
        icon: const Icon(Icons.backup),
        label: const Text('نسخة احتياطية'),
      ),
    );
  }

  Widget _buildStabilityHeader(BuildContext context, double score) {
    final theme = Theme.of(context);
    final color =
        score > 0.8 ? Colors.green : (score > 0.5 ? Colors.orange : Colors.red);

    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.security, color: color, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مؤشر استقرار النموذج',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        score > 0.8
                            ? 'النظام في حالة استقرار مثالية'
                            : 'يتم مراقبة الانحراف في التعلم',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(score * 100).toInt()}%',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: score,
              backgroundColor: color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              borderRadius: BorderRadius.circular(10),
              minHeight: 8,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSandboxCard(BuildContext context, bool enabled) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'بيئة الاختبار (Sandbox)',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Switch(
                  value: enabled,
                  onChanged: (val) => controller.toggleSandboxMode(val),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'عند التفعيل، سيتم اختبار أوزان التعلم الجديدة في الخلفية دون التأثير على الإشعارات الحقيقية حتى يتم التأكد من دقتها.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotsSection(BuildContext context) {
    final theme = Theme.of(context);
    final snapshots = controller.weightSnapshots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                'نسخ الأوزان التاريخية',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${snapshots.length} نسخة',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (snapshots.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('لا توجد نسخ محفوظة حالياً'),
            ),
          )
        else
          ...snapshots.map((snap) => _buildSnapshotTile(context, snap)),
      ],
    );
  }

  Widget _buildSnapshotTile(BuildContext context, LearningWeightSnapshot snap) {
    final theme = Theme.of(context);
    final isActive = controller.aiSettings.value?.weightVersionId == snap.id;
    final isGold = snap.versionTag == 'gold_standard';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isGold
              ? Colors.amber.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            isGold ? Icons.star : Icons.history,
            color: isGold ? Colors.amber : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(snap.versionTag?.toUpperCase() ?? 'يومي'),
        subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(snap.createdAt)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              const Chip(
                label: Text('نشط', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              )
            else
              TextButton(
                onPressed: () => _confirmRollback(context, snap),
                child: const Text('استرجاع'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditSection(BuildContext context) {
    final theme = Theme.of(context);
    final audits = controller.governanceAudit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'سجل الحوكمة والأمان',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (audits.isEmpty)
          const Center(child: Text('لا توجد أحداث حوكمة مسجلة'))
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: audits.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final audit = audits[index];
                final isWarning =
                    audit.severity == 'warning' || audit.severity == 'critical';

                return ListTile(
                  leading: Icon(
                    isWarning ? Icons.warning_amber : Icons.info_outline,
                    color: isWarning ? Colors.orange : Colors.blue,
                  ),
                  title: Text(_formatAction(audit.actionType)),
                  subtitle:
                      Text(DateFormat('HH:mm - MM/dd').format(audit.createdAt)),
                  trailing: const Icon(Icons.chevron_left, size: 16),
                  onTap: () => _showAuditDetails(context, audit),
                );
              },
            ),
          ),
      ],
    );
  }

  String _formatAction(String type) {
    switch (type) {
      case 'guardrail_violation':
        return 'تدخل درع الحماية';
      case 'auto_rollback':
        return 'تراجع تلقائي للاستقرار';
      case 'manual_rollback':
        return 'تراجع يدوي من المستخدم';
      case 'snapshot_created':
        return 'حفظ نسخة أوزان جديدة';
      default:
        return type;
    }
  }

  void _showCreateSnapshotDialog(BuildContext context) {
    final controller_ = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حفظ نسخة للأوزان'),
        content: TextField(
          controller: controller_,
          decoration: const InputDecoration(
            hintText: 'وصف النسخة (مثال: مستقر سبتمبر)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              controller.createSnapshot(controller_.text);
              Get.back();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _confirmRollback(BuildContext context, LearningWeightSnapshot snap) {
    Get.dialog(
      AlertDialog(
        title: const Text('تأكيد الاسترجاع'),
        content: Text(
            'هل أنت متأكد من العودة إلى أوزان التعلم الخاصة بتاريخ ${DateFormat('yyyy/MM/dd').format(snap.createdAt)}؟ سيتم قفل التعلم عند هذه النسخة مؤقتاً.'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              controller.rollbackToSnapshot(snap.id);
              Get.back();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('تأكيد الاسترجاع'),
          ),
        ],
      ),
    );
  }

  void _showAuditDetails(BuildContext context, GovernanceAudit audit) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تفاصيل حدث الأمان',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildDetailRow(context, 'النوع', _formatAction(audit.actionType)),
            _buildDetailRow(context, 'التوقيت',
                DateFormat('yyyy/MM/dd HH:mm:ss').format(audit.createdAt)),
            _buildDetailRow(context, 'الشدة', audit.severity.toUpperCase()),
            const Divider(height: 32),
            Text('البيانات التقنية:',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                audit.details.toString(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey)),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
