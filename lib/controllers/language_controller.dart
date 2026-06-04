import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageController extends GetxController {
  static const String _languageKey = 'language_code';
  static const String _countryKey = 'country_code';

  final Rx<Locale> _currentLocale = const Locale('ar', 'SA').obs;

  Locale get currentLocale => _currentLocale.value;
  String get currentLanguageCode => _currentLocale.value.languageCode;
  String get currentCountryCode => _currentLocale.value.countryCode ?? '';
  String get currentLanguage => _currentLocale.value.languageCode;

  bool get isArabic => _currentLocale.value.languageCode == 'ar';
  bool get isEnglish => _currentLocale.value.languageCode == 'en';

  // Supported locales
  final List<Locale> supportedLocales = const [
    Locale('ar', 'SA'), // Arabic
    Locale('en', 'US'), // English
  ];

  @override
  void onInit() {
    super.onInit();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString(_languageKey) ?? 'ar';
      final countryCode = prefs.getString(_countryKey) ?? 'SA';

      final locale = Locale(languageCode, countryCode);
      if (supportedLocales.contains(locale)) {
        _currentLocale.value = locale;
        unawaited(Get.updateLocale(locale));
      }
    } catch (e) {
      debugPrint('Error loading language: $e');
      _currentLocale.value = const Locale('ar', 'SA');
    }
  }

  Future<void> _saveLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, _currentLocale.value.languageCode);
      await prefs.setString(
        _countryKey,
        _currentLocale.value.countryCode ?? '',
      );
    } catch (e) {
      debugPrint('Error saving language: $e');
    }
  }

  Future<void> changeLanguage(dynamic language) async {
    Locale locale;

    if (language is String) {
      // Convert string to Locale
      switch (language) {
        case 'ar':
          locale = const Locale('ar', 'SA');
          break;
        case 'en':
          locale = const Locale('en', 'US');
          break;
        default:
          locale = const Locale('ar', 'SA');
      }
    } else if (language is Locale) {
      locale = language;
    } else {
      return;
    }

    if (supportedLocales.contains(locale)) {
      _currentLocale.value = locale;
      unawaited(Get.updateLocale(locale));
      await _saveLanguage();
    }
  }

  Future<void> setArabic() async {
    await changeLanguage(const Locale('ar', 'SA'));
  }

  Future<void> setEnglish() async {
    await changeLanguage(const Locale('en', 'US'));
  }

  Future<void> toggleLanguage() async {
    if (isArabic) {
      await setEnglish();
    } else {
      await setArabic();
    }
  }

  String get currentLanguageName {
    switch (_currentLocale.value.languageCode) {
      case 'ar':
        return 'العربية';
      case 'en':
        return 'English';
      default:
        return 'العربية';
    }
  }

  String get currentLanguageNativeName {
    switch (_currentLocale.value.languageCode) {
      case 'ar':
        return 'العربية';
      case 'en':
        return 'English';
      default:
        return 'العربية';
    }
  }

  IconData get currentLanguageIcon {
    switch (_currentLocale.value.languageCode) {
      case 'ar':
        return Icons.language;
      case 'en':
        return Icons.translate;
      default:
        return Icons.language;
    }
  }

  TextDirection get textDirection {
    return isArabic ? TextDirection.rtl : TextDirection.ltr;
  }
}
