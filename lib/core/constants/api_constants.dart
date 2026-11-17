import 'package:talkmate_ai/config/app_config.dart';

class ApiConstants {
  static const String supabaseUrl = AppConfig.supabaseUrl;
  static const String supabasePublishableKey = AppConfig.supabasePublishableKey;

  /// Backward-compatibility alias for [supabasePublishableKey].
  @Deprecated('Use supabasePublishableKey instead.')
  static const String supabaseAnonKey = AppConfig.supabasePublishableKey;
}
