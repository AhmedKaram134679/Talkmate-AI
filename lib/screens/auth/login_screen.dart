import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/config/theme_config.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/theme_controller.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = Get.find<AuthController>();
  final _theme = Get.find<ThemeController>();
  final _lang = Get.find<LanguageController>();

  bool _obscure = true;
  Timer? _tick;

  // Animation for smooth entry
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _animController, curve: Curves.easeOutQuart));

    _animController.forward();

    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_auth.needsEmailVerification.value) {
        setState(() {}); // لتحديث العد التنازلي
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final ok = await _auth.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;

    if (ok) {
      unawaited(
          Get.offAllNamed('/main')); // Navigate to main shell with bottom nav
      Get.snackbar(
        l10n.login,
        l10n.loginSuccessTitle,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: theme.colorScheme.primaryContainer,
        colorText: theme.colorScheme.onPrimaryContainer,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final l10n = AppLocalizations.of(context);
    final controller =
        TextEditingController(text: _emailController.text.trim());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.forgotPassword,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: l10n.email,
            prefixIcon: const Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final theme = Theme.of(context);
              final email = controller.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                Get.snackbar(
                  l10n.updateErrorTitle,
                  l10n.invalidEmail,
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: theme.colorScheme.errorContainer,
                  colorText: theme.colorScheme.onErrorContainer,
                );
                return;
              }
              await _auth.resetPassword(email);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(l10n.send),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Gradient Background
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              theme.scaffoldBackgroundColor,
              theme.colorScheme.primary.withValues(alpha: 0.15),
            ]
          : [
              theme.colorScheme.primary.withValues(alpha: 0.05),
              theme.colorScheme.secondary.withValues(alpha: 0.05),
            ],
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_lang.currentLanguageIcon),
            onPressed: () => _lang.toggleLanguage(),
            tooltip: l10n.tooltipChangeLanguage,
          ),
          IconButton(
            icon: Icon(_theme.currentThemeIcon),
            onPressed: () => _theme.toggleTheme(),
            tooltip: l10n.tooltipChangeTheme,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Logo / Icon
                    Container(
                      height: 100,
                      width: 100,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .primaryColor
                            .withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chat_bubble_rounded,
                        size: 50,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.welcomeBack,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.loginToContinue,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                    const SizedBox(height: 40),

                    // Login Card
                    Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .cardTheme
                            .color
                            ?.withValues(alpha: 0.8), // Glass-ish
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.3 : 0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: l10n.email,
                                prefixIcon: const Icon(Icons.email_outlined),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return l10n.pleaseEnterEmail;
                                }
                                if (!v.contains('@')) {
                                  return l10n.invalidEmail;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: l10n.password,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              obscureText: _obscure,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return l10n.pleaseEnterPassword;
                                }
                                if (v.length < 6) {
                                  return l10n.minChars(6);
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: _auth.isLoading
                                    ? null
                                    : _showResetPasswordDialog,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(l10n.forgotPassword,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                            const SizedBox(height: 24),

                            Obx(() => ElevatedButton(
                                  onPressed: _auth.isLoading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize:
                                        const Size(double.infinity, 50),
                                  ),
                                  child: _auth.isLoading
                                      ? SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              color:
                                                  theme.colorScheme.onPrimary,
                                              strokeWidth: 2),
                                        )
                                      : Text(l10n.login),
                                )),

                            const SizedBox(height: 24),

                            // Divider
                            Row(
                              children: [
                                Expanded(
                                    child: Divider(
                                        color: Theme.of(context).dividerColor)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Text(
                                    l10n.or,
                                    style: TextStyle(
                                      color: Theme.of(context).disabledColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Expanded(
                                    child: Divider(
                                        color: Theme.of(context).dividerColor)),
                              ],
                            ),

                            const SizedBox(height: 24),
                            Center(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                children: [
                                  Text(
                                    l10n.dontHaveAccount,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Get.to(() => const RegisterScreen()),
                                    child: Text(
                                      l10n.register,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),
                            // Verification status
                            Obx(() {
                              if (!_auth.needsEmailVerification.value) {
                                return const SizedBox.shrink();
                              }
                              final can = _auth.canResendEmailVerification;
                              final sec = _auth.resendSecondsRemaining;
                              return Container(
                                margin: const EdgeInsets.only(top: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: ThemeConfig.warningColor
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: ThemeConfig.warningColor
                                          .withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  children: [
                                    if (!can)
                                      Text(
                                        l10n.verificationSent(sec),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: ThemeConfig.warningColor,
                                            fontSize: 13),
                                      )
                                    else
                                      TextButton.icon(
                                        icon:
                                            const Icon(Icons.refresh, size: 16),
                                        onPressed:
                                            _auth.resendEmailVerification,
                                        label: Text(l10n.resendVerification),
                                        style: TextButton.styleFrom(
                                            foregroundColor:
                                                ThemeConfig.warningColor),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
