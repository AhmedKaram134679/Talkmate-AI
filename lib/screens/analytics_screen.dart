import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/analytics_controller.dart';
import 'package:talkmate_ai/data/models/device_analytics_model.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(AnalyticsController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('تحليلات الأداء'), // Analytics Dashboard
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.fetchStats,
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.deviceStats.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد بيانات متاحة حالياً',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: controller.deviceStats.length,
          itemBuilder: (context, index) {
            final stats = controller.deviceStats[index];
            return _buildDeviceCard(context, stats);
          },
        );
      }),
    );
  }

  Widget _buildDeviceCard(BuildContext context, DeviceAnalyticsModel stats) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stats.deviceId.isEmpty ? 'Unknown Device' : stats.deviceId,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(),
            _buildStatRow('إجمالي الرسائل', stats.totalSent.toString()),
            const SizedBox(height: 8),
            _buildStatBar(
              context,
              'تم التسليم',
              stats.totalDelivered,
              stats.totalSent,
              Colors.blue,
            ),
            const SizedBox(height: 8),
            _buildStatBar(
              context,
              'تمت القراءة',
              stats.totalRead,
              stats.totalSent,
              Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatBar(
      BuildContext context, String label, int value, int total, Color color) {
    final double percentage = total == 0 ? 0.0 : (value / total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(
              '${(percentage * 100).toStringAsFixed(1)}% ($value)',
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percentage,
          backgroundColor: color.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    );
  }
}
