import 'package:get/get.dart';

/// [Stage B1] Beta Feature Flags Service
///
/// Manages "Soft Controls" for the Beta phase.
/// Allows enabling/disabling features without code changes (via defaults or future remote config).
/// Currently uses safe defaults for the Sovereign Beta.
class BetaFeatureFlagsService extends GetxService {
  static BetaFeatureFlagsService get instance => Get.find();

  // --- Flags ---

  /// Enables the advanced Room UI with detailed stats and controls.
  /// Default: true for Beta.
  final RxBool enableAdvancedRoomsUI = true.obs;

  /// Enables verbose telemetry logging (for debugging).
  /// Default: false (Sovereign Privacy).
  final RxBool enableVerboseTelemetry = false.obs;

  /// Enables the "Conclusion Sheet" after calls to ask for feedback.
  /// Default: true (Voluntary Feedback).
  final RxBool enableFeedbackSheet = true.obs;

  /// Enables the "Developer Logs" section in Settings.
  /// Default: true (Transparency).
  final RxBool enableDeveloperLogs = true.obs;
}
