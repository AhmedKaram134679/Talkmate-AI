import 'package:flutter/material.dart';

class NotificationTransparencyScreen extends StatelessWidget {
  final Map<String, dynamic> routingMeta;
  final String title;
  final String body;

  const NotificationTransparencyScreen({
    super.key,
    required this.routingMeta,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final arbitration =
        routingMeta['device_arbitration'] as Map<String, dynamic>?;
    final userOverride = routingMeta['user_override'] as Map<String, dynamic>?;
    final quietHoursApplied = routingMeta['quiet_hours_applied'] == true;
    final arbitrationBypassed = routingMeta['arbitration_bypassed'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark Slate
      appBar: AppBar(
        title: const Text('شفافية الإشعارات',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildDecisionSource(userOverride),
            const SizedBox(height: 20),
            _buildDeviceSection(arbitration, arbitrationBypassed),
            const SizedBox(height: 20),
            _buildTimingSection(quietHoursApplied),
            const SizedBox(height: 20),
            _buildTrustSection(),
            const SizedBox(height: 40),
            _buildNotificationPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'لماذا وصلني هذا؟',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'نحن نستخدم الذكاء الاصطناعي وإعداداتك الشخصية لضمان وصول الرسائل المهمة فقط.',
          style: TextStyle(color: Colors.blueGrey[300], fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildDecisionSource(Map<String, dynamic>? userOverride) {
    final isUser = userOverride != null && userOverride['applied'] == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUser
            ? Colors.blue.withValues(alpha: 0.1)
            : Colors.purple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isUser ? Colors.blue : Colors.purple, width: 1),
      ),
      child: Row(
        children: [
          Icon(isUser ? Icons.person : Icons.auto_awesome,
              color: isUser ? Colors.blue : Colors.purple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUser ? 'تدخل يدوي (إعداداتك)' : 'قرار ذكي (تلقائي)',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  isUser
                      ? 'تم تطبيق تفضيلاتك الشخصية لهذا الإشعار.'
                      : 'قام النظام باختيار أفضل مسار بناءً على سياقك.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSection(Map<String, dynamic>? arb, bool bypassed) {
    String message = 'تم إرسال الإشعار لجميع أجهزتك (حالة طارئة).';
    if (!bypassed && arb != null) {
      message = 'تم اختيار هذا الجهاز لأنه الأكثر ملاءمة حالياً.';
    }

    return _buildInfoCard(
      title: 'اختيار الجهاز',
      subtitle: message,
      icon: Icons.devices,
      color: Colors.green,
    );
  }

  Widget _buildTimingSection(bool quietApplied) {
    return _buildInfoCard(
      title: 'التوقيت ووضع الهدوء',
      subtitle: quietApplied
          ? 'تم تأخير أو تجميع الإشعار ضمن موجز الهدوء الخاص بك.'
          : 'تم الإرسال فوراً لضمان سرعة الاستجابة.',
      icon: Icons.access_time_filled,
      color: Colors.orange,
    );
  }

  Widget _buildTrustSection() {
    final trustScore = routingMeta['trust_score'] ?? 100;
    return _buildInfoCard(
      title: 'مستوى الثقة الذكي',
      subtitle:
          'يتم تسليم هذه الرسالة بناءً على مستوى ثقة $trustScore% في المحتوى والراسل.',
      icon: Icons.shield,
      color: Colors.cyan,
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildNotificationPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('معاينة الإشعار',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white10),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }
}
