import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// User-friendly error messages for both English and Arabic
class ErrorMessages {
  /// Map of error codes/patterns to user-friendly messages
  static const Map<String, Map<String, String>> _errorMap = {
    // Email rate limit errors
    'over_email_send_rate_limit': {
      'en': 'Too many password reset requests. Please try again in a few minutes.',
      'ar': 'عدد طلبات كثير جداً لاستعادة كلمة المرور. يرجى المحاولة مرة أخرى بعد دقائق قليلة.',
    },
    'email_rate_limit_exceeded': {
      'en': 'Email limit exceeded. Please try again later.',
      'ar': 'تم تجاوز حد الرسائل. يرجى المحاولة لاحقاً.',
    },
    
    // Authentication errors
    'invalid_credentials': {
      'en': 'Invalid email or password.',
      'ar': 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
    },
    'user_not_found': {
      'en': 'User account not found.',
      'ar': 'حساب المستخدم غير موجود.',
    },
    'user_already_exists': {
      'en': 'This email is already registered.',
      'ar': 'هذا البريد الإلكتروني مسجل بالفعل.',
    },
    
    // Password reset errors
    'invalid_recovery_token': {
      'en': 'This password reset link is invalid or expired. Please request a new one.',
      'ar': 'رابط استعادة كلمة المرور هذا غير صالح أو انتهت صلاحيته. يرجى طلب رابط جديد.',
    },
    'recovery_token_expired': {
      'en': 'Password reset link has expired. Please request a new one.',
      'ar': 'انتهت صلاحية رابط استعادة كلمة المرور. يرجى طلب رابط جديد.',
    },
    'weak_password': {
      'en': 'Password is too weak. Use at least 8 characters with uppercase, lowercase, and numbers.',
      'ar': 'كلمة المرور ضعيفة جداً. استخدم 8 أحرف على الأقل مع أحرف كبيرة وصغيرة وأرقام.',
    },
    
    // Session errors
    'session_not_found': {
      'en': 'Your session has expired. Please log in again.',
      'ar': 'انتهت صلاحية جلستك. يرجى تسجيل الدخول مرة أخرى.',
    },
    'invalid_session': {
      'en': 'Your session is invalid. Please log in again.',
      'ar': 'جلستك غير صالحة. يرجى تسجيل الدخول مرة أخرى.',
    },
    
    // Network errors
    'network_error': {
      'en': 'Network error. Please check your connection.',
      'ar': 'خطأ في الشبكة. يرجى التحقق من اتصالك.',
    },
    'timeout': {
      'en': 'Request timed out. Please try again.',
      'ar': 'انتهت مهلة الطلب. يرجى المحاولة مرة أخرى.',
    },
  };

  /// Get user-friendly error message
  /// 
  /// - Extracts the current app language (en/ar)
  /// - Maps the error code/message to user-friendly text
  /// - Returns a helpful message the user can understand
  static String getUserFriendlyMessage(dynamic error) {
    // Get current language
    final locale = Get.locale?.languageCode ?? 'en';
    final isArabic = locale == 'ar';

    // Handle AuthApiException specifically
    if (error is AuthApiException) {
      return _handleAuthApiException(error, isArabic);
    }

    // Handle generic exceptions
    if (error is Exception) {
      return _handleGenericException(error, isArabic);
    }

    // Fallback
    return isArabic
        ? 'حدث خطأ ما. يرجى المحاولة مرة أخرى.'
        : 'Something went wrong. Please try again.';
  }

  /// Handle AuthApiException (from Supabase Auth)
  static String _handleAuthApiException(AuthApiException error, bool isArabic) {
    final errorCode = error.code;
    final errorMessage = error.message.toLowerCase();

    // Check if we have a mapped error
    if (_errorMap.containsKey(errorCode)) {
      return isArabic 
          ? _errorMap[errorCode]!['ar']! 
          : _errorMap[errorCode]!['en']!;
    }

    // Try to match error message patterns
    for (final entry in _errorMap.entries) {
      if (errorMessage.contains(entry.key.toLowerCase())) {
        return isArabic 
            ? entry.value['ar']! 
            : entry.value['en']!;
      }
    }

    // Handle HTTP status codes
    final statusCode = error.statusCode;
    if (statusCode == '429') {
      // Too Many Requests
      return isArabic
          ? 'عدد طلبات كثير جداً. يرجى الانتظار قبل المحاولة مرة أخرى.'
          : 'Too many requests. Please wait before trying again.';
    }

    // Default error messages
    return isArabic
        ? 'خطأ في المصادقة. يرجى المحاولة مرة أخرى.'
        : 'Authentication error. Please try again.';
  }

  /// Handle generic exceptions
  static String _handleGenericException(Exception error, bool isArabic) {
    final message = error.toString().toLowerCase();

    // Check network errors
    if (message.contains('network') || message.contains('connection')) {
      return isArabic
          ? 'خطأ في الاتصال. يرجى التحقق من اتصالك بالإنترنت.'
          : 'Connection error. Please check your internet connection.';
    }

    // Check timeout errors
    if (message.contains('timeout') || message.contains('timed out')) {
      return isArabic
          ? 'انتهت مهلة الطلب. يرجى المحاولة مرة أخرى.'
          : 'Request timed out. Please try again.';
    }

    // Default
    return isArabic
        ? 'حدث خطأ ما. يرجى المحاولة مرة أخرى.'
        : 'Something went wrong. Please try again.';
  }

  /// Specific messages for password recovery flow
  static String getPasswordRecoveryErrorMessage(dynamic error) {
    final locale = Get.locale?.languageCode ?? 'en';
    final isArabic = locale == 'ar';

    if (error is AuthApiException) {
      final errorMessage = error.message.toLowerCase();

      // Rate limit on password recovery
      if (errorMessage.contains('over_email_send_rate_limit') ||
          errorMessage.contains('rate limit') ||
          errorMessage.contains('429')) {
        return isArabic
            ? 'تم إرسال رسالة استعادة كلمة المرور مؤخراً. يرجى الانتظار بضع دقائق قبل طلب رسالة جديدة.'
            : 'A password reset email was recently sent. Please wait a few minutes before requesting another.';
      }

      // Invalid recovery link
      if (errorMessage.contains('recovery') && errorMessage.contains('invalid')) {
        return isArabic
            ? 'رابط استعادة كلمة المرور غير صحيح أو انتهت صلاحيته.'
            : 'Password reset link is invalid or expired.';
      }
    }

    return getUserFriendlyMessage(error);
  }

  /// Specific messages for login flow
  static String getLoginErrorMessage(dynamic error) {
    final locale = Get.locale?.languageCode ?? 'en';
    final isArabic = locale == 'ar';

    if (error is AuthApiException) {
      final errorMessage = error.message.toLowerCase();

      if (errorMessage.contains('invalid') || errorMessage.contains('credentials')) {
        return isArabic
            ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة.'
            : 'Email or password is incorrect.';
      }

      if (errorMessage.contains('not found') || errorMessage.contains('user')) {
        return isArabic
            ? 'لا يوجد حساب بهذا البريد الإلكتروني.'
            : 'No account found with this email.';
      }
    }

    return getUserFriendlyMessage(error);
  }

  /// Specific messages for sign-up flow
  static String getSignUpErrorMessage(dynamic error) {
    final locale = Get.locale?.languageCode ?? 'en';
    final isArabic = locale == 'ar';

    if (error is AuthApiException) {
      final errorMessage = error.message.toLowerCase();

      if (errorMessage.contains('already') || errorMessage.contains('exists')) {
        return isArabic
            ? 'هذا البريد الإلكتروني مسجل بالفعل.'
            : 'This email is already registered.';
      }

      if (errorMessage.contains('weak') || errorMessage.contains('password')) {
        return isArabic
            ? 'كلمة المرور ضعيفة. استخدم 8 أحرف على الأقل مع أحرف كبيرة وصغيرة وأرقام.'
            : 'Password is too weak. Use at least 8 characters with uppercase, lowercase, and numbers.';
      }
    }

    return getUserFriendlyMessage(error);
  }

  /// Specific messages for password update flow
  static String getPasswordUpdateErrorMessage(dynamic error) {
    final locale = Get.locale?.languageCode ?? 'en';
    final isArabic = locale == 'ar';

    if (error is AuthApiException) {
      final errorMessage = error.message.toLowerCase();

      if (errorMessage.contains('session')) {
        return isArabic
            ? 'انتهت صلاحية الجلسة. يرجى طلب رابط استعادة كلمة المرور مرة أخرى.'
            : 'Session expired. Please request a new password reset link.';
      }

      if (errorMessage.contains('weak') || errorMessage.contains('password')) {
        return isArabic
            ? 'كلمة المرور الجديدة ضعيفة. استخدم 8 أحرف على الأقل مع أحرف كبيرة وصغيرة وأرقام.'
            : 'New password is too weak. Use at least 8 characters with uppercase, lowercase, and numbers.';
      }
    }

    return getUserFriendlyMessage(error);
  }
}
