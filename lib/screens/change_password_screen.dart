import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    try {
      final auth = Get.find<AuthController>();
      if (auth.userEmail.isNotEmpty) {
        _emailCtrl.text = auth.userEmail;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.changePassword)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.changePassword,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l10n.email,
                hintText: 'you@example.com',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _sendReset,
                icon: const Icon(Icons.send),
                label: Text(l10n.send),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'سيتم إرسال رابط إعادة تعيين كلمة المرور إلى بريدك الإلكتروني عبر Supabase.',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendReset() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      Get.snackbar(l10n.error, 'الرجاء إدخال بريد إلكتروني صالح',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    setState(() => _sending = true);
    try {
      await Get.find<AuthController>().resetPassword(email);
      // AuthController already shows a snackbar success or error
    } catch (e) {
      Get.snackbar(l10n.error, e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
