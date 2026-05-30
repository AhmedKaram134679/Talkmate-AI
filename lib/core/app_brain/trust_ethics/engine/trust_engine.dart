import 'package:get/get.dart';
import '../models/trust_profile.dart';

/// Manages trust scores for all features.
class TrustEngine extends GetxService {
  final Map<String, TrustProfile> _profiles = {};

  TrustProfile getProfile(String featureId) {
    return _profiles.putIfAbsent(
        featureId, () => TrustProfile(featureId: featureId));
  }

  void reportOutcome(String featureId,
      {required bool accepted, bool explicitRejection = false}) {
    final profile = getProfile(featureId);
    profile.totalInteractions++;

    if (accepted) {
      // Trust is earned slowly
      profile.score = (profile.score + 1.0).clamp(0.0, 100.0);
    } else {
      profile.rejections++;
      // Trust is lost quickly
      final double penalty = explicitRejection ? 10.0 : 5.0;
      profile.score = (profile.score - penalty).clamp(0.0, 100.0);
    }
  }
}
