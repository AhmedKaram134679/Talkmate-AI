import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/accountability_models.dart';

/// Compliance Profile Manager (F6).
/// Enforces institutional standards and retention policies.
class ComplianceProfileManager extends GetxService {
  final Rx<ComplianceProfile> currentProfile = ComplianceProfile.consumer.obs;

  /// Updates the global compliance profile (Privileged/Admin action).
  void switchProfile(ComplianceProfile profile) {
    debugPrint(
        '🔄 COMPLIANCE: Switching profile to ${profile.name.toUpperCase()}');
    currentProfile.value = profile;
  }

  /// Returns the retention window in hours based on the current profile.
  int getArchiveRetentionHours() {
    switch (currentProfile.value) {
      case ComplianceProfile.consumer:
        return 0; // Immediate purge
      case ComplianceProfile.enterprise:
        return 24; // 24-hour review window
      case ComplianceProfile.regulated:
        return 72; // 3-day compliance storage
    }
  }

  /// Checks if Evidence Pack generation is mandatory for the current profile.
  bool isEvidencePackRequired() {
    return currentProfile.value != ComplianceProfile.consumer;
  }
}
