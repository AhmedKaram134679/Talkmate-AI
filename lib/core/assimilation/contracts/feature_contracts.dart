import 'definitions.dart';

/// IFeatureContract: The agreement between the App Brain and a Feature.
///
/// Features must implement or be wrapped by this contract to sit at the table.
/// This approach ensures the Brain checks permissions/conditions BEFORE
/// the legacy feature code is ever executed.
abstract class IFeatureContract {
  /// Unique identifier for the feature type.
  FeatureType get type;

  /// A human-readable name for debugging.
  String get name;

  /// What this feature needs to run (e.g., Internet, Camera).
  Set<FeatureRequirement> get requirements;

  /// How critical is this feature? (Affects prioritization).
  int get priorityLevel; // 1 (Critical) to 10 (Optional)

  /// Called when access is granted with 'degrade'.
  /// The feature should switch to a lightweight mode.
  void applyDegradation(FeatureStateSignals signals);

  /// Called when access is granted fully.
  /// The feature should restore full functionality.
  void restoreNormalOperation();
}
