import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ThemeConfig {
  // --- Premium Color Palette ---
  // A modern, vibrant primary blue (Royal Blue)
  static const Color primaryColor = Color(0xFF2962FF);
  // Secondary / Accent (Teal for fresh contrast)
  static const Color accentColor = Color(0xFF00BFA5);

  // Semantic Colors
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color successColor = Color(0xFF388E3C);
  static const Color warningColor = Color(0xFFFBC02D);

  // --- Light Theme Colors ---
  static const Color lightBackgroundColor = Color(0xFFFDFDFD);
  static const Color lightSurfaceColor = Color(0xFFFFFFFF);
  static const Color lightTextPrimary =
      Color(0xFF121212); // Slightly darker for better clarity
  static const Color lightTextSecondary = Color(0xFF5F6368);

  // --- Dark Theme Colors ---
  static const Color darkBackgroundColor = Color(0xFF0F1216); // Deep blue-black
  static const Color darkSurfaceColor =
      Color(0xFF1B1F26); // Modern dark surface
  static const Color darkTextPrimary =
      Color(0xFFF8F9FA); // Very clear off-white
  static const Color darkTextSecondary =
      Color(0xFFBDC1C6); // Improved contrast for dark mode

  // --- Common Settings ---
  static const String fontFamily = 'Cairo'; // Primary font for Arabic support

  // --- Light Theme Definition ---
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    fontFamilyFallback: const ['Tajawal', 'Segoe UI', 'Arial', 'Noto Sans'],
    brightness: Brightness.light,

    // Generates a harmonious scheme from our seed
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      primary: primaryColor,
      secondary: accentColor,
      surface: lightSurfaceColor,
      error: errorColor,
    ),

    scaffoldBackgroundColor: lightBackgroundColor,

    // Smooth Page Transitions
    // NOTE: not const because CupertinoPageTransitionsBuilder() is no longer a
    // const constructor in current Flutter, which made the const map invalid.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: const ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: const ZoomPageTransitionsBuilder(),
      },
    ),

    // App Bar: Clean & Solid
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: lightSurfaceColor,
      elevation: 0,
      scrolledUnderElevation: 0, // Keep it flat even when scrolling
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      iconTheme: IconThemeData(color: lightTextPrimary),
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: lightTextPrimary,
      ),
    ),

    // Cards: Elevated & Rounded
    cardTheme: CardThemeData(
      color: lightSurfaceColor,
      elevation:
          0, // Flat by default, use border/shadow manually if needed or increase
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.withAlpha(20), width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    ),

    // Buttons: Modern & Pill-shaped
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: primaryColor, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryColor.withValues(alpha: 0.1),
        foregroundColor: primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),

    // Inputs: Modern Filled Style
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: primaryColor.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      labelStyle: const TextStyle(color: lightTextSecondary),
      hintStyle: TextStyle(color: lightTextSecondary.withValues(alpha: 0.5)),
    ),

    // Text Theme
    textTheme: _buildTextTheme(lightTextPrimary, lightTextSecondary),

    // Icon Theme
    iconTheme: const IconThemeData(color: lightTextPrimary, size: 24),
  );

  // --- Dark Theme Definition ---
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    fontFamilyFallback: const ['Tajawal', 'Segoe UI', 'Arial', 'Noto Sans'],
    brightness: Brightness.dark,

    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      primary: primaryColor,
      secondary: accentColor,
      surface: darkSurfaceColor,
      error: errorColor,
    ),

    scaffoldBackgroundColor: darkBackgroundColor,

    // NOTE: not const because CupertinoPageTransitionsBuilder() is no longer a
    // const constructor in current Flutter, which made the const map invalid.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: const ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: const ZoomPageTransitionsBuilder(),
      },
    ),

    // App Bar: Clean & Solid
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: darkSurfaceColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      iconTheme: IconThemeData(color: darkTextPrimary),
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: darkTextPrimary,
      ),
    ),

    cardTheme: CardThemeData(
      color: darkSurfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withAlpha(10), width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side:
            BorderSide(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      labelStyle: const TextStyle(color: darkTextSecondary),
      hintStyle: TextStyle(color: darkTextSecondary.withValues(alpha: 0.5)),
    ),

    textTheme: _buildTextTheme(darkTextPrimary, darkTextSecondary),

    iconTheme: const IconThemeData(color: darkTextPrimary, size: 24),

    // Dialog & BottomSheet
    dialogTheme: DialogThemeData(
      backgroundColor: darkSurfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: darkSurfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: TextStyle(
          color: primary, fontFamily: fontFamily, fontWeight: FontWeight.bold),
      displayMedium: TextStyle(
          color: primary, fontFamily: fontFamily, fontWeight: FontWeight.bold),
      displaySmall: TextStyle(
          color: primary, fontFamily: fontFamily, fontWeight: FontWeight.bold),
      headlineLarge: TextStyle(
          color: primary, fontFamily: fontFamily, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(
          color: primary, fontFamily: fontFamily, fontWeight: FontWeight.w700),
      headlineSmall: TextStyle(
          color: primary, fontFamily: fontFamily, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(
          color: primary, fontFamily: fontFamily, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(
          color: primary, fontFamily: fontFamily, fontWeight: FontWeight.w700),
      titleSmall: TextStyle(
          color: primary, fontFamily: fontFamily, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(
          color: primary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.normal),
      bodyMedium: TextStyle(
          color: primary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.normal),
      bodySmall: TextStyle(
          color: secondary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.normal),
      labelLarge: TextStyle(
          color: primary,
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w700), // Button text
      labelMedium: TextStyle(
          color: secondary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w500),
      labelSmall: TextStyle(
          color: secondary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w500),
    );
  }

  // Additional Custom Colors (Getters for consistent usage)
  static Color get sentMessageColor => primaryColor;
  static Color get receivedMessageLight => const Color(0xFFF0F0F0);
  static Color get receivedMessageDark => const Color(0xFF2C323F);

  // Surface adaptors
  static Color getSurfaceColor(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color getOnSurfaceColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color getPrimaryColor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
  static Color getOnPrimaryColor(BuildContext context) =>
      Theme.of(context).colorScheme.onPrimary;
}
