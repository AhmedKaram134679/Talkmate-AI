import 'package:get/get.dart';
import '../app_brain/app_brain.dart';
import '../app_brain/presence_model.dart';
import 'observability_contracts.dart';

/// BrainStateInspector: Read-only data provider for the current App Brain state.
class BrainStateInspector implements IBrainInspectable {
  static final BrainStateInspector instance = BrainStateInspector._();
  BrainStateInspector._();

  final _brain = Get.find<IAppBrain>();

  @override
  AppSystemState get currentState => _brain.state.value;

  @override
  DeviceEngagement get currentPresence {
    // In this architecture, presence is managed separately,
    // but we can infer engagement from state or other services.
    return DeviceEngagement.idle;
  }

  @override
  String get dominantFeature {
    // Logic to determine which feature is currently "controlling" the system status
    final state = _brain.state.value;
    if (state == AppSystemState.calling) return 'Calls';
    if (state == AppSystemState.chatting) return 'Chat';
    return 'System/Idle';
  }
}
