enum PersonalityType {
  conservative, // Favors stability, rejects risk, slow adaptation
  balanced, // Standard behavior
  proactive, // Favors experimentation, accepts risk, fast adaptation
}

/// Defines the "Character" of the AI.
class DigitalPersonality {
  final PersonalityType type;
  final double riskTolerance; // 0.0 - 1.0
  final double adaptationSpeed; // 0.0 - 1.0
  final double interventionThreshold; // 0.0 - 1.0 (How likely to intervene)

  const DigitalPersonality({
    required this.type,
    required this.riskTolerance,
    required this.adaptationSpeed,
    required this.interventionThreshold,
  });

  // Presets
  static const conservative = DigitalPersonality(
    type: PersonalityType.conservative,
    riskTolerance: 0.2, // Low risk
    adaptationSpeed: 0.1, // Slow change
    interventionThreshold: 0.8, // Only intervene if very necessary
  );

  static const balanced = DigitalPersonality(
    type: PersonalityType.balanced,
    riskTolerance: 0.5,
    adaptationSpeed: 0.5,
    interventionThreshold: 0.5,
  );

  static const proactive = DigitalPersonality(
    type: PersonalityType.proactive,
    riskTolerance: 0.8, // High risk
    adaptationSpeed: 0.9, // Fast change
    interventionThreshold: 0.3, // Intervene often to help
  );
}
