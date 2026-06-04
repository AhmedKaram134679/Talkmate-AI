/// Secure Media Session States (G4).
enum MediaSecureState {
  initializing,
  authenticating,
  active,
  suspended,
  terminated,
}

/// Security event types for media auditing.
enum MediaSecurityEvent {
  identityVerified,
  tokenExpired,
  unauthorizedAccess,
  encryptionViolation,
  manualKill,
  rateLimitTriggered,
}
