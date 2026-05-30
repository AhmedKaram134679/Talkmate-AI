import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:talkmate_ai/controllers/devices_controller.dart';
import 'package:talkmate_ai/data/models/device_model.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(DevicesController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('الأجهزة النشطة'),
        actions: [
          IconButton(
            tooltip: 'تسجيل خروج كل الأجهزة الأخرى',
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
            onPressed: () => _confirmRevokeAll(context, controller),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.devices.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد أجهزة نشطة أخرى',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: controller.devices.length,
          itemBuilder: (context, index) {
            final device = controller.devices[index];
            return _buildDeviceCard(context, device, controller);
          },
        );
      }),
    );
  }

  Widget _buildDeviceCard(
      BuildContext context, DeviceModel device, DevicesController controller) {
    final isCurrent = device.isCurrentDevice;
    final lastActive = device.lastActiveAt != null
        ? DateFormat.yMMMd().add_jm().format(device.lastActiveAt!)
        : 'غير معروف';

    IconData iconData;
    if (device.platform?.toLowerCase().contains('android') ?? false) {
      iconData = Icons.android;
    } else if (device.platform?.toLowerCase().contains('ios') ?? false) {
      iconData = Icons.phone_iphone;
    } else if (device.platform?.toLowerCase().contains('windows') ?? false) {
      iconData = Icons.desktop_windows;
    } else {
      iconData = Icons.device_unknown;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCurrent
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          child: Icon(iconData, color: isCurrent ? Colors.green : Colors.grey),
        ),
        title: Row(
          children: [
            Text(device.platform ?? 'جهاز غير معروف'),
            if (isCurrent) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'هذا الجهاز',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              device.isOnline ? 'نشط الآن' : 'آخر ظهور: $lastActive',
              style: TextStyle(
                color: device.isOnline ? Colors.green : Colors.grey,
                fontWeight:
                    device.isOnline ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (device.appState != null && device.isOnline)
              Text(
                'الحالة: ${device.appState}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        trailing: !isCurrent
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _confirmRevoke(context, controller, device),
              )
            : null,
      ),
    );
  }

  void _confirmRevokeAll(BuildContext context, DevicesController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إخلاء كل الجلسات الأخرى'),
        content: const Text(
            'هل أنت متأكد من رغبتك في تسجيل الخروج من جميع الأجهزة الأخرى؟ ستحتاج إلى تسجيل الدخول مرة أخرى على تلك الأجهزة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await controller.revokeAllOtherDevices();
            },
            child: const Text('تأكيد الإخلاء',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmRevoke(
      BuildContext context, DevicesController controller, DeviceModel device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل خروج الجهاز'),
        content: const Text(
            'هل أنت متأكد من رغبتك في إزالة هذا الجهاز؟ لن يستلم الإشعارات بعد الآن.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.revokeDevice(device.deviceId);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
