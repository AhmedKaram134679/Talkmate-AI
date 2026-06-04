import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/feedback/beta_conclusion_sheet.dart';
import 'package:talkmate_ai/core/feedback/sovereign_feedback_service.dart';
import 'package:talkmate_ai/core/governance/beta_feature_flags_service.dart';
import 'package:talkmate_ai/data/models/user_model.dart' as data_models;
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/screens/adaptive_insights_screen.dart';
import 'package:talkmate_ai/screens/analytics_screen.dart';
import 'package:talkmate_ai/screens/blocked_users_screen.dart';
import 'package:talkmate_ai/screens/change_password_screen.dart';
import 'package:talkmate_ai/screens/devices_screen.dart';
import 'package:talkmate_ai/screens/profile_screen.dart';
import 'package:talkmate_ai/screens/routing_debug_screen.dart';
import 'package:talkmate_ai/screens/settings/notification_settings_screen.dart';

import '../config/app_config.dart';
import '../controllers/auth_controller.dart';
import '../controllers/language_controller.dart';
import '../controllers/notification_controller.dart';
import '../controllers/theme_controller.dart';
import '../core/communication/communication_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = Get.find<AuthController>();
    final themeController = Get.find<ThemeController>();
    final languageController = Get.find<LanguageController>();
    final notificationController = Get.find<NotificationController>();

    return Scaffold(
      appBar: AppBar(
          title: Text(AppLocalizations.of(context).settings),
          centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProfileSection(context, authController),
          const SizedBox(height: 24),
          _buildAppearanceSection(context, themeController, languageController),
          const SizedBox(height: 24),
          _buildNotificationSection(context, notificationController),
          const SizedBox(height: 24),
          _buildPrivacySection(context),
          const SizedBox(height: 24),
          _buildAboutSection(context),
          const SizedBox(height: 24),
          _buildAccountSection(context, authController),
          const SizedBox(height: 24),
          _buildReadinessSection(context),
          const SizedBox(height: 24),
          _buildBetaSection(context),
          const SizedBox(height: 24),
          _buildAdvancedSection(context),
        ],
      ),
    );
  }

  Widget _buildProfileSection(
      BuildContext context, AuthController authController) {
    return Card(
      child: InkWell(
        onTap: () => Get.to(() => const ProfileScreen()),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).profile,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    backgroundImage: authController.userPhoto.isNotEmpty
                        ? NetworkImage(authController.userPhoto)
                        : null,
                    child: authController.userPhoto.isEmpty
                        ? Text(
                            authController.user?.initials ?? 'U',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authController.user?.displayName ??
                              AppLocalizations.of(context).user,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          authController.user?.email ?? 'user@example.com',
                          style: TextStyle(
                              fontSize: 14, color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios,
                      size: 16, color: Theme.of(context).hintColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    ThemeController themeController,
    LanguageController languageController,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(Get.context!).appearanceLanguage,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Obx(
              () => SwitchListTile(
                title: Text(AppLocalizations.of(Get.context!).darkMode),
                subtitle: Text(AppLocalizations.of(Get.context!).darkModeHint),
                value: themeController.isDarkMode,
                onChanged: (value) => themeController.toggleTheme(),
                secondary: Icon(
                  themeController.isDarkMode
                      ? Icons.dark_mode
                      : Icons.light_mode,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(AppLocalizations.of(Get.context!).language),
              subtitle: Obx(
                () => Text(
                  languageController.currentLanguage == 'ar'
                      ? AppLocalizations.of(Get.context!).arabic
                      : AppLocalizations.of(Get.context!).english,
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showLanguageDialog(languageController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSection(
    BuildContext context,
    NotificationController notificationController,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).notifications,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Obx(
              () => SwitchListTile(
                title:
                    Text(AppLocalizations.of(Get.context!).enableNotifications),
                subtitle: Text(
                    AppLocalizations.of(Get.context!).newMessagesNotifications),
                value: notificationController.notificationsEnabled,
                onChanged: (value) =>
                    notificationController.setNotificationsEnabled(value),
                secondary: const Icon(Icons.notifications),
              ),
            ),
            const Divider(),
            Obx(
              () => SwitchListTile(
                title:
                    Text(AppLocalizations.of(Get.context!).notificationSound),
                subtitle: Text(
                    AppLocalizations.of(Get.context!).playSoundOnNotifications),
                value: notificationController.soundEnabled,
                onChanged: notificationController.notificationsEnabled
                    ? (value) => notificationController.setSoundEnabled(value)
                    : null,
                secondary: const Icon(Icons.volume_up),
              ),
            ),
            const Divider(),
            Obx(
              () => SwitchListTile(
                title: Text(
                    AppLocalizations.of(Get.context!).notificationVibration),
                subtitle: Text(
                    AppLocalizations.of(Get.context!).vibrateOnNotifications),
                value: notificationController.vibrationEnabled,
                onChanged: notificationController.notificationsEnabled
                    ? (value) =>
                        notificationController.setVibrationEnabled(value)
                    : null,
                secondary: const Icon(Icons.vibration),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.science),
              title: Text(AppLocalizations.of(Get.context!).testNotifications),
              subtitle:
                  Text(AppLocalizations.of(Get.context!).sendTestNotification),
              trailing: const Icon(Icons.send),
              onTap: () => notificationController.testNotification(),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.settings_suggest_outlined,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('تخصيص الإشعارات الذكية'),
              subtitle:
                  const Text('إدارة التنبيهات، ساعات الهدوء، وأسلوب الوصول'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => Get.to(() => const NotificationSettingsScreen()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hardware & Network Readiness',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Test your microphone, camera, and internet quality before starting a call.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.speed_rounded, color: Colors.blue),
              title: const Text('Unified Readiness Check'),
              subtitle: const Text('Get your 0-100% call readiness score'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => Get.toNamed('/unified_readiness'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacySection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).privacySecurity,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.lock),
              title: Text(AppLocalizations.of(Get.context!).password),
              subtitle: Text(AppLocalizations.of(Get.context!).changePassword),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _changePassword(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('الأجهزة النشطة'),
              subtitle: const Text('إدارة الأجهزة والجلسات'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => Get.to(() => const DevicesScreen()),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.refresh_rounded,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('إصلاح حالة الاتصال'),
              subtitle: const Text('إخلاء الجلسات العالقة وإعادة تعيين الحالة'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showResetStatusDialog(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(AppLocalizations.of(Get.context!).blockedUsers),
              subtitle:
                  Text(AppLocalizations.of(Get.context!).manageBlockedUsers),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _manageBlockedUsers(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.visibility),
              title: Text(AppLocalizations.of(Get.context!).privacySettings),
              subtitle: Text(AppLocalizations.of(Get.context!).whoCanSeeInfo),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _privacySettings(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).aboutApp,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.info),
              title: Text(AppLocalizations.of(Get.context!).appInfo),
              subtitle: Text(AppLocalizations.of(Get.context!)
                  .appVersionLabel(AppConfig.appVersion)),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showAppInfo(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.help),
              title: Text(AppLocalizations.of(Get.context!).helpSupport),
              subtitle: Text(AppLocalizations.of(Get.context!).faqSupport),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showHelp(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(AppLocalizations.of(Get.context!).termsOfUse),
              subtitle: Text(AppLocalizations.of(Get.context!).readTerms),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showTerms(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.privacy_tip),
              title: Text(AppLocalizations.of(Get.context!).privacyPolicy),
              subtitle:
                  Text(AppLocalizations.of(Get.context!).howWeProtectData),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showPrivacyPolicy(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection(
      BuildContext context, AuthController authController) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).account,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.logout,
                  color: Theme.of(context).colorScheme.secondary),
              title: Text(AppLocalizations.of(Get.context!).logout),
              subtitle: Text(AppLocalizations.of(Get.context!).logoutHint),
              onTap: () => _showLogoutDialog(context, authController),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_forever,
                  color: Theme.of(context).colorScheme.error),
              title: Text(
                AppLocalizations.of(Get.context!).deleteAccount,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: Text(
                  AppLocalizations.of(Get.context!).deleteAccountPermanently),
              onTap: () => _showDeleteAccountDialog(context, authController),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog(LanguageController languageController) {
    Get.dialog(
      AlertDialog(
        title: Text(AppLocalizations.of(Get.context!).chooseLanguage),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: Text(AppLocalizations.of(Get.context!).arabic),
              value: 'ar',
              // ignore: deprecated_member_use
              groupValue: languageController.currentLanguage,
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) {
                  languageController.changeLanguage(value);
                  Get.back();
                }
              },
            ),
            RadioListTile<String>(
              title: Text(AppLocalizations.of(Get.context!).english),
              value: 'en',
              // ignore: deprecated_member_use
              groupValue: languageController.currentLanguage,
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) {
                  languageController.changeLanguage(value);
                  Get.back();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: Text(AppLocalizations.of(Get.context!).cancel)),
        ],
      ),
    );
  }

  void _changePassword() {
    Get.to(() => const ChangePasswordScreen());
  }

  void _manageBlockedUsers() {
    Get.to(() => const BlockedUsersScreen());
  }

  void _privacySettings(BuildContext context) {
    final auth = Get.find<AuthController>();
    if (auth.userId.isEmpty) {
      Get.snackbar(
        AppLocalizations.of(context).privacySettings,
        AppLocalizations.of(context).loginErrorMessage,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    final l10n = AppLocalizations.of(context);
    Get.dialog(
      AlertDialog(
        title: Text(l10n.privacySettings),
        content: SizedBox(
          width: 380,
          child: StreamBuilder<data_models.AppUser?>(
            stream: Get.find<IUserRepository>().watchById(auth.userId),
            builder: (context, AsyncSnapshot<data_models.AppUser?> snapshot) {
              final u = snapshot.data;
              bool showLastSeen = u?.privacyShowLastSeen ?? true;
              bool showPhoto = u?.privacyShowProfilePhoto ?? true;
              bool showStatus = u?.privacyShowStatus ?? true;

              return StatefulBuilder(
                builder: (context, setState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: Text(l10n.lastSeen),
                      subtitle: Text(l10n.whoCanSeeInfo),
                      value: showLastSeen,
                      onChanged: (v) async {
                        setState(() => showLastSeen = v);
                        try {
                          await Get.find<IUserRepository>().updatePrivacy(
                            auth.userId,
                            showLastSeen: v,
                          );
                        } catch (e) {
                          Get.snackbar(
                            l10n.error,
                            e.toString(),
                            snackPosition: SnackPosition.BOTTOM,
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: Text(l10n.profilePhoto),
                      subtitle: Text(l10n.whoCanSeeInfo),
                      value: showPhoto,
                      onChanged: (v) async {
                        setState(() => showPhoto = v);
                        try {
                          await Get.find<IUserRepository>().updatePrivacy(
                            auth.userId,
                            showProfilePhoto: v,
                          );
                        } catch (e) {
                          Get.snackbar(
                            l10n.error,
                            e.toString(),
                            snackPosition: SnackPosition.BOTTOM,
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: Text(l10n.status),
                      subtitle: Text(l10n.whoCanSeeInfo),
                      value: showStatus,
                      onChanged: (v) async {
                        setState(() => showStatus = v);
                        try {
                          await Get.find<IUserRepository>().updatePrivacy(
                            auth.userId,
                            showStatus: v,
                          );
                        } catch (e) {
                          Get.snackbar(
                            l10n.error,
                            e.toString(),
                            snackPosition: SnackPosition.BOTTOM,
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  void _showAppInfo() {
    Get.dialog(
      AlertDialog(
        title: Text(AppLocalizations.of(Get.context!).appInfo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppConfig.appName),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(Get.context!)
                .appVersionLabel(AppConfig.appVersion)),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(Get.context!)
                .developerLabel('AhmedKaramFathy')),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(Get.context!).appTagline),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: Text(AppLocalizations.of(Get.context!).ok)),
        ],
      ),
    );
  }

  void _showHelp() {
    final l10n = AppLocalizations.of(Get.context!);
    Get.dialog(
      AlertDialog(
        title: Text(l10n.helpSupport),
        content: const Text(
          '• الأسئلة الشائعة\n\n- كيف أبدأ محادثة؟ افتح تبويب المحادثات واضغط + ثم اختر جهة الاتصال.\n- كيف أفعل الإشعارات؟ من الإعدادات > الإشعارات.\n\n• الدعم الفني\nراسلنا عبر البريد: support@talkmate.ai',
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text(l10n.ok))
        ],
      ),
    );
  }

  void _showTerms() {
    final l10n = AppLocalizations.of(Get.context!);
    Get.dialog(
      AlertDialog(
        title: Text(l10n.termsOfUse),
        content: const SingleChildScrollView(
          child: Text(
            'باستخدامك للتطبيق، فإنك توافق على سياسة الاستخدام العادل وعدم إساءة استخدام الخدمات. '
            'قد نقوم بتحديث الشروط من حين لآخر وسيتم إخطارك داخل التطبيق.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text(l10n.ok))
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    final l10n = AppLocalizations.of(Get.context!);
    Get.dialog(
      AlertDialog(
        title: Text(l10n.privacyPolicy),
        content: const SingleChildScrollView(
          child: Text(
            'نحترم خصوصيتك. يتم تخزين بيانات الحساب والمحادثات بشكل آمن على خوادم Firebase وفق القواعد المحددة. '
            'يمكنك التحكم في من يرى آخر ظهور والصورة والحالة من إعدادات الخصوصية.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text(l10n.ok))
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthController authController) {
    Get.dialog(
      AlertDialog(
        title: Text(AppLocalizations.of(Get.context!).logout),
        content: Text(AppLocalizations.of(Get.context!).confirmLogout),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: Text(AppLocalizations.of(Get.context!).cancel)),
          TextButton(
            onPressed: () {
              Get.back();
              authController.logout();
            },
            child: Text(AppLocalizations.of(Get.context!).logout),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(
      BuildContext context, AuthController authController) {
    Get.dialog(
      AlertDialog(
        title: Text(AppLocalizations.of(Get.context!).deleteAccount),
        content: Text(AppLocalizations.of(Get.context!).confirmDeleteAccount),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: Text(AppLocalizations.of(Get.context!).cancel)),
          TextButton(
            onPressed: () {
              Get.back();
              Get.snackbar(
                AppLocalizations.of(Get.context!).deleteAccount,
                AppLocalizations.of(Get.context!).comingSoon,
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: Colors.red,
                colorText: Colors.white,
              );
            },
            child: Text(AppLocalizations.of(Get.context!).delete,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _showResetStatusDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('إصلاح حالة الاتصال'),
        content: const Text(
            'هل تواجه مشكلة في ظهور حسابك "مشغول" باستمرار؟ سيؤدي هذا الإجراء إلى إخلاء أي مكالمات عالقة وإعادة تعيين حالتك إلى "نشط".'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(AppLocalizations.of(Get.context!).cancel),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              final communicationController = CommunicationController.instance;
              await communicationController.resetMyStatus();
            },
            child: const Text('تأكيد الإصلاح',
                style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'أدوات متقدمة',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.analytics,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('لوحة التحليلات'),
              subtitle: const Text('إحصائيات الأداء والتسليم'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => Get.to(() => const AnalyticsScreen()),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.bug_report,
                  color: Theme.of(context).colorScheme.secondary),
              title: const Text('Routing Debugger'),
              subtitle: const Text('سجلات التوجيه (للمطورين)'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => Get.to(() => const RoutingDebugScreen()),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.health_and_safety_outlined,
                  color: Theme.of(context).colorScheme.tertiary),
              title: const Text('Adaptive Insights'),
              subtitle: const Text('صحة النظام (تجريبي)'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => Get.to(() => const AdaptiveInsightsScreen()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBetaSection(BuildContext context) {
    if (!Get.isRegistered<BetaFeatureFlagsService>()) return const SizedBox();
    final betaService = BetaFeatureFlagsService.instance;

    return Obx(() {
      return Card(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.science,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'تجريبي (Beta)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('إرسال ملاحظات'),
                subtitle: const Text('ساعدنا في تحسين التطبيق'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  BetaConclusionSheet.show(context,
                      sessionContext: {'source': 'settings'});
                },
              ),
              if (betaService.enableDeveloperLogs.value) ...[
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('تصدير سجلات بيتا'),
                  subtitle: const Text('مشاركة ملف السجلات يدوياً'),
                  trailing: const Icon(Icons.share, size: 20),
                  onTap: () async {
                    final path = await SovereignFeedbackService.instance
                        .getFeedbackFilePath();
                    if (path != null) {
                      await Get.defaultDialog(
                        title: 'تصدير السجلات',
                        content: Column(
                          children: [
                            const Text('تم حفظ السجلات في المسار التالي:'),
                            const SizedBox(height: 8),
                            SelectableText(path,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            const Text(
                                'يمكنك مشاركة هذا الملف مع فريق التطوير.'),
                          ],
                        ),
                        textConfirm: 'حسناً',
                        confirmTextColor: Colors.white,
                        onConfirm: () => Get.back(),
                      );
                    } else {
                      Get.snackbar('تنبيه', 'لا توجد سجلات حالياً.');
                    }
                  },
                ),
              ]
            ],
          ),
        ),
      );
    });
  }
}
