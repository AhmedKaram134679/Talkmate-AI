import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/screens/onboarding_screen.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Smoke test: verify the OnboardingScreen builds and renders.
    Get.testMode = true;

    // OnboardingScreen reads AppLocalizations.of(context), so the localization
    // delegates must be provided for it to build.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OnboardingScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // The screen and its core page view should be present (locale-independent).
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
  });
}
