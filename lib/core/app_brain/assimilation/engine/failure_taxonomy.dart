/// Defines the types of failures that can occur within the communication system.
/// This taxonomy is used to determine the graceful UX response (Silent Recovery vs. Soft Exit).
enum FailureType {
  /// Transient network issue (e.g., packet loss, temp disconnect).
  /// Response: Silent Reconnect + Pulse UI.
  networkTransient,

  /// Fatal network failure (e.g., offline, firewall block).
  /// Response: Dignified Exit + "Check Connection" message.
  networkFatal,

  /// Target user is busy.
  /// Response: Sovereignty Notice + Invitation Option.
  sessionBusy,

  /// Target user declined the call.
  /// Response: Polite Notice + "Try Later".
  sessionDeclined,

  /// Internal system error (ICE failure, unexpected exception).
  /// Response: Generic Warm Apology + "Try Again".
  systemError,
}

class FailureTaxonomy {
  /// Maps a raw exception or error code to a [FailureType].
  static FailureType classify(dynamic error) {
    final s = error.toString().toLowerCase();

    if (s.contains('ice') || s.contains('connect') || s.contains('socket')) {
      return FailureType
          .networkTransient; // Assume transient first for better UX
    }
    if (s.contains('busy')) {
      return FailureType.sessionBusy;
    }
    if (s.contains('decline') || s.contains('reject')) {
      return FailureType.sessionDeclined;
    }
    if (s.contains('offline')) {
      return FailureType.networkFatal;
    }

    return FailureType.systemError;
  }

  /// Returns a human-friendly, comforting message for the failure.
  static String getGracefulMessage(FailureType type) {
    switch (type) {
      case FailureType.networkTransient:
        return 'الاتصال غير مستقر، نحاول إصلاحه بهدوء...';
      case FailureType.networkFatal:
        return 'تعذر الوصول للشبكة، يرجى التحقق من اتصالك.';
      case FailureType.sessionBusy:
        return 'الطرف الآخر في جلسة حالياً، يمكنك إرسال دعوة.';
      case FailureType.sessionDeclined:
        return 'تعذر إتمام الاتصال في الوقت الحالي.';
      case FailureType.systemError:
        return 'حدث خطأ غير متوقع، نحاول تحسين الخدمة.';
    }
  }
}
