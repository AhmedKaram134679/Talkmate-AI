enum IntentType {
  urgent, // "I need this NOW" (e.g., repeatedly tapping, rapid typing)
  exploratory, // "Just browsing" (slow interactions, random navigation)
  passive, // "Let it run" (background music, downloads)
  noise, // "Accidental" (pocket dial, rapid meaningless clicks)
  contextDriven // "Related to what I'm doing" (e.g., opening a link sent in chat)
}

/// Represents the inferred intent of the user.
class IntentHypothesis {
  final IntentType type;
  final double confidence; // 0.0 - 1.0
  final String reasoning;

  const IntentHypothesis({
    required this.type,
    required this.confidence,
    this.reasoning = '',
  });

  static const unknown =
      IntentHypothesis(type: IntentType.exploratory, confidence: 0.0);

  @override
  String toString() =>
      'Intent($type, ${(confidence * 100).toStringAsFixed(1)}%)';
}
