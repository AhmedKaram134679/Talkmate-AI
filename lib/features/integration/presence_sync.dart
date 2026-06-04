import 'package:get/get.dart';
import '../../core/app_brain/app_brain.dart';
import '../../core/app_brain/presence_model.dart';

/// PresenceSync: Synchronizes AppBrain's global state with high-level Presence rules.
class PresenceSync extends GetxService {
  final _brain = Get.find<IAppBrain>();
  // final _presenceService = PresenceService.instance;

  void init() {
    // Sync Brain State -> Presence Service
    _brain.state.listen((state) {
      _handleStateChange(state);
    });
  }

  void _handleStateChange(AppSystemState state) {
    // Future: Update Supabase presence with the determined Engagement level
    switch (state) {
      case AppSystemState.calling:
        // Mark user as BUSY in backend
        break;
      case AppSystemState.idle:
        // Mark user as ACTIVE/IDLE
        break;
      case AppSystemState.background:
        // Mark user as AWAY
        break;
      default:
        break;
    }
  }

  /// Maps BrainPresence to the existing PresenceService logic
  void syncToBackend(BrainPresence presence) {
    // Logic to bridge models
  }
}
