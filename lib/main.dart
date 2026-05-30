import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/config/theme_config.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/language_controller.dart';
import 'package:talkmate_ai/controllers/theme_controller.dart';
import 'package:talkmate_ai/core/bootstrapper.dart';
import 'package:talkmate_ai/core/communication/call_ringing_screen.dart';
import 'package:talkmate_ai/core/communication/communication_live_screen.dart';
import 'package:talkmate_ai/core/communication/communication_session.dart';
import 'package:talkmate_ai/core/diagnostic/diagnostic_controller.dart';
import 'package:talkmate_ai/core/diagnostic/diagnostic_screen.dart';
import 'package:talkmate_ai/core/diagnostic/unified_diagnostic_controller.dart';
import 'package:talkmate_ai/core/diagnostic/unified_readiness_screen.dart';
import 'package:talkmate_ai/core/main_wrapper.dart';
import 'package:talkmate_ai/core/network_diagnostic/network_diagnostic_controller.dart';
import 'package:talkmate_ai/core/network_diagnostic/network_diagnostic_screen.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/models/chat_model.dart' as ui_models;
import 'package:talkmate_ai/screens/auth/login_screen.dart';
import 'package:talkmate_ai/screens/auth/register_screen.dart';
import 'package:talkmate_ai/screens/calls_screen.dart';
import 'package:talkmate_ai/screens/chat_screen.dart';
import 'package:talkmate_ai/screens/chats_screen.dart';
import 'package:talkmate_ai/screens/friend_requests_screen.dart';
import 'package:talkmate_ai/screens/friends_screen.dart';
import 'package:talkmate_ai/screens/groups_screen.dart';
import 'package:talkmate_ai/screens/main_tab_screen.dart';
import 'package:talkmate_ai/screens/onboarding_screen.dart';
import 'package:talkmate_ai/screens/profile_edit_screen.dart';
import 'package:talkmate_ai/screens/search_screen.dart';
import 'package:talkmate_ai/screens/settings_screen.dart';
import 'package:talkmate_ai/services/observability/performance_tracker.dart';

// Entry Point
void main() async {
  final startTime = DateTime.now();
  // Use the new centralized bootstrapper
  await AppBootstrapper.init();
  final bootstrapDuration = DateTime.now().difference(startTime);

  unawaited(
      PerformanceTracker.instance.logAppStartupComplete(bootstrapDuration));
  AppLogger.info('App Lifecycle: Bootstrap complete',
      context: {'duration_ms': bootstrapDuration.inMilliseconds});

  runApp(const TalkMateApp());
}

class TalkMateApp extends StatelessWidget {
  const TalkMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ThemeController and LanguageController are injected by AppBootstrapper
    final themeController = Get.find<ThemeController>();
    final languageController = Get.find<LanguageController>();

    return Obx(() {
      return GetMaterialApp(
        title: 'TalkMate AI',
        debugShowCheckedModeBanner: false,

        // Localization
        locale: languageController.currentLocale,
        fallbackLocale: const Locale('en', 'US'),
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('ar', 'SA'),
        ],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        // Theme
        theme: ThemeConfig.lightTheme,
        darkTheme: ThemeConfig.darkTheme,
        themeMode: themeController.themeMode,

        // Navigation
        initialRoute: !Get.find<AuthController>().hasSeenOnboarding
            ? '/onboarding'
            : Get.find<AuthController>().isLoggedIn
                ? '/main'
                : '/login',
        getPages: [
          GetPage(name: '/onboarding', page: () => const OnboardingScreen()),
          GetPage(name: '/login', page: () => const LoginScreen()),
          GetPage(name: '/register', page: () => const RegisterScreen()),
          GetPage(name: '/main', page: () => const MainTabScreen()),
          GetPage(name: '/chats', page: () => const ChatsScreen()),
          GetPage(
            name: '/chat',
            page: () {
              if (Get.arguments is ui_models.ChatModel) {
                return ChatScreen(chat: Get.arguments as ui_models.ChatModel);
              }
              // Fallback for cases with missing/wrong arguments (e.g. direct deep link)
              return const MainTabScreen();
            },
          ),
          GetPage(name: '/settings', page: () => const SettingsScreen()),
          GetPage(name: '/profile_edit', page: () => const ProfileEditScreen()),
          GetPage(name: '/search', page: () => const SearchScreen()),
          GetPage(name: '/friends', page: () => const FriendsScreen()),
          GetPage(name: '/calls', page: () => const CallsScreen()),
          GetPage(name: '/groups', page: () => const GroupsScreen()),
          GetPage(
              name: '/friend_requests',
              page: () => const FriendRequestsScreen()),
          GetPage(
            name: '/call_ringing',
            page: () {
              final rawArgs = Get.arguments;
              final args = rawArgs is Map
                  ? Map<String, dynamic>.from(rawArgs)
                  : <String, dynamic>{};
              return CallRingingScreen(
                callId: args['callId'],
                otherId: args['otherId'],
                isIncoming: args['isIncoming'],
                isVideo: args['isVideo'] ?? false,
              );
            },
          ),
          GetPage(
            name: '/incoming_call',
            page: () {
              final args = Get.arguments is Map
                  ? Map<String, dynamic>.from(Get.arguments as Map)
                  : null;
              if (args == null) return const MainTabScreen();
              return CommunicationLiveScreen(
                sessionId: args['callId'],
                type: CommunicationSessionType.call,
              );
            },
          ),
          GetPage(
            name: '/active_call',
            page: () {
              final args = Get.arguments is Map
                  ? Map<String, dynamic>.from(Get.arguments as Map)
                  : null;
              if (args == null) return const MainTabScreen();
              return CommunicationLiveScreen(
                sessionId: args['callId'] ?? args['sessionId'],
                type: CommunicationSessionType.call,
              );
            },
          ),
          GetPage(
            name: '/communication_live',
            page: () {
              final args = Get.arguments is Map
                  ? Map<String, dynamic>.from(Get.arguments as Map)
                  : null;
              if (args == null) return const MainTabScreen();
              return CommunicationLiveScreen(
                sessionId: args['sessionId'] ?? args['callId'],
                type: CommunicationSessionType.call,
              );
            },
          ),
          GetPage(
            name: '/diagnostic_center',
            page: () => const DiagnosticScreen(),
            binding: BindingsBuilder(() {
              Get.put(DiagnosticController());
            }),
          ),
          GetPage(
            name: '/network_diagnostic',
            page: () => const NetworkDiagnosticScreen(),
            binding: BindingsBuilder(() {
              Get.put(NetworkDiagnosticController());
            }),
          ),
          GetPage(
            name: '/unified_readiness',
            page: () => const UnifiedReadinessScreen(),
            binding: BindingsBuilder(() {
              Get.put(UnifiedDiagnosticController());
            }),
          ),
        ],

        // [Stage R6] Global Call Navigation Wrapper
        builder: (context, child) {
          return MainWrapper(child: child ?? const SizedBox());
        },

        unknownRoute:
            GetPage(name: '/notfound', page: () => const MainTabScreen()),

        // Initial Binding (Optional if handled by Bootstrapper)
        // initialBinding: BindingsBuilder(() { ... }),
      );
    });
  }
}
