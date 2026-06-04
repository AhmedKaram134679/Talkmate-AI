import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/feedback/sovereign_feedback_service.dart';

class BetaConclusionSheet extends StatefulWidget {
  final Map<String, dynamic> sessionContext;

  const BetaConclusionSheet({super.key, required this.sessionContext});

  static Future<void> show(BuildContext context,
      {required Map<String, dynamic> sessionContext}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BetaConclusionSheet(sessionContext: sessionContext),
    );
  }

  @override
  State<BetaConclusionSheet> createState() => _BetaConclusionSheetState();
}

class _BetaConclusionSheetState extends State<BetaConclusionSheet> {
  int _rating = 0;
  final TextEditingController _commentController = TextEditingController();

  void _submit() {
    if (_rating > 0) {
      SovereignFeedbackService.instance.submitFeedback(
        rating: _rating,
        text: _commentController.text,
        context: widget.sessionContext,
      );
    }
    Get.back();
    Get.snackbar(
      'شكراً لك', // Thank you
      'تم حفظ ملاحظاتك بنجاح.', // Feedback saved successfully
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green.withValues(alpha: 0.8),
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 5,
          )
        ],
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'كيف كانت التجربة؟', // How was the experience?
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'ساعدنا في تحسين TalkMate AI بنسخته التجريبية', // Help us improve...
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starIndex = index + 1;
              return IconButton(
                iconSize: 40,
                icon: Icon(
                  starIndex <= _rating ? Icons.star : Icons.star_border,
                  color: starIndex <= _rating ? Colors.amber : Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _rating = starIndex;
                  });
                },
              );
            }),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _commentController,
            decoration: InputDecoration(
              hintText:
                  'هل واجهت أي مشاكل؟ (اختياري)', // Any issues? (Optional)
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Get.back(),
                  child: const Text('تخطي'), // Skip
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _rating > 0 ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('إرسال'), // Send
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
