import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/adaptive/adaptive_controller.dart';
import 'package:talkmate_ai/core/app_brain/adaptive/adaptive_models.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';

import 'security_models.dart';

/// The Fortress of TalkMate AI. Manages system hardening.
class SecurityGatekeeper extends GetxService {
  static SecurityGatekeeper get instance => Get.find();

  final _isCompromised = false.obs;
  bool get isCompromised => _isCompromised.value;

  /// Performs initial security checks on startup.
  Future<void> performStartupAudit() async {
    AppLogger.info('Security: Starting Production Audit...');

    // 1. Check for Debug mode in Production build
    if (kDebugMode && !kProfileMode) {
      AppLogger.warning(
          'Security: App running in DEBUG mode. Some protections are relaxed.');
    }

    // 2. Check for Tampering (Basic environment check)
    final bool isTampered = await _detectEnvironmentTampering();
    if (isTampered) {
      _reportSecurityIncident(SecuritySignal(
        type: SecurityThreatType.unauthorizedEnv,
        risk: SecurityRiskLevel.high,
        source: 'environment_audit',
        details: {'env': defaultTargetPlatform.name},
      ));
    }

    AppLogger.info(
        'Security: Audit Complete. Status: ${isCompromised ? "COMPROMISED" : "SECURE"}');
  }

  /// Protects sensitive operations based on security status.
  bool canPerformSensitiveAction(String actionId) {
    if (isCompromised) {
      AppLogger.critical(
          'Security: Action $actionId BLOCKED due to compromised status');
      return false;
    }
    return true;
  }

  Future<bool> _detectEnvironmentTampering() async {
    // Placeholder for advanced checks like Root/Jailbreak, Hooking detections
    // In a real production app, this would use native platform channels.
    return false;
  }

  void _reportSecurityIncident(SecuritySignal signal) {
    AppLogger.critical('SECURITY INCIDENT: ${signal.type.name}',
        context: signal.details);

    // If risk is critical, compromise the system
    if (signal.risk == SecurityRiskLevel.critical ||
        signal.risk == SecurityRiskLevel.high) {
      _isCompromised.value = true;

      // Notify Adaptive Brain to enter emergency mode
      AdaptiveController.instance.processSignal(AdaptiveSignal(
        type: AdaptiveSignalType.securityThreat,
        value: 1.0,
        metadata: {'security_threat': signal.type.name},
      ));
    }
  }
}
