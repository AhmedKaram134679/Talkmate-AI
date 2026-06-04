import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/communication/communication_controller.dart';

class AudioAdvisoryModal extends GetView<CommunicationController> {
  const AudioAdvisoryModal({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false, // Force interaction
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 40,
              spreadRadius: 10,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.settings_voice_rounded,
                    color: Colors.amber,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    Get.locale?.languageCode == 'ar'
                        ? 'توصية جهاز الصوت (Windows)'
                        : 'Audio Device Recommendation',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Main Message
            Text(
              Get.locale?.languageCode == 'ar'
                  ? 'لضمان ثبات المكالمة ونقاء الصوت على أجهزة Windows، نوصي بشدة باستخدام ميكروفون USB مخصص.'
                  : 'For the best call stability and audio clarity on Windows devices, we strongly recommend using a dedicated USB microphone.',
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 16),

            // Sub-context
            Text(
              Get.locale?.languageCode == 'ar'
                  ? 'بعض المداخل المدمجة أو التناظرية (AUX) قد تسبب ضجيجاً أو صدىً أو عدم استقرار في التعرف على الجهاز.'
                  : 'Some built-in or analog (3.5mm AUX) audio inputs may cause instability, background noise, or echo depending on hardware configuration.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),

            const SizedBox(height: 32),

            // Actions
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => controller.proceedWithAdvisory(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      Get.locale?.languageCode == 'ar'
                          ? 'المتابعة على أي حال'
                          : 'Continue Anyway',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      // Navigate to settings or specific help page if needed
                      Get.back(); // Just close for now as a bypass
                    },
                    child: Text(
                      Get.locale?.languageCode == 'ar'
                          ? 'فتح إعدادات الصوت'
                          : 'Open Audio Settings',
                      style: TextStyle(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  static void show() {
    Get.bottomSheet(
      const AudioAdvisoryModal(),
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
    );
  }
}
