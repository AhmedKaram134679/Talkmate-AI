/// Defines ethical boundaries that cannot be crossed.
class EthicalBoundaryMatrix {
  static const _forbiddenActions = {
    'unmute_device', // Never unmute without explicit permission
    'record_audio_stealth', // Never record without indicator
    'upload_sensitive_data_background',
  };

  static const _requiresHighTrust = {
    'interrupt_call', // Only if very trusted
    'auto_purchase',
  };

  /// Checks if an action violates ethical boundaries.
  static bool isEthicallyAllowed(String action, double trustScore) {
    if (_forbiddenActions.contains(action)) {
      return false; // Hard Barrier
    }

    if (_requiresHighTrust.contains(action)) {
      return trustScore > 80; // Soft Barrier
    }

    return true; // Allowed
  }
}
