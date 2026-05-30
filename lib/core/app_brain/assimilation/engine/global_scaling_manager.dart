import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/global_expansion_models.dart';

/// Global Scaling & Distribution Manager (G11).
/// Manages clusters, load balancing, and regional sovereignty.
class GlobalScalingManager extends GetxService {
  final _activeNodes = <GlobalNode>[].obs;
  final _currentRegion = GlobalRegion.meSouth.obs;
  final _strategy = DeploymentStrategy.latencyFirst.obs;

  List<GlobalNode> get activeNodes => _activeNodes.toList();
  GlobalRegion get currentRegion => _currentRegion.value;

  /// Registers a new node in the global cluster (G11).
  void registerNode(GlobalNode node) {
    debugPrint(
        '🌍 GlobalScaling: Registering NODE ${node.nodeId} in ${node.region.name}');
    _activeNodes.add(node);
  }

  /// Selects the best node for a session based on strategy and sovereignty.
  GlobalNode? negotiateBestNode(GlobalRegion preferredRegion) {
    debugPrint(
        '⚖️ GlobalScaling: Negotiating node for region ${preferredRegion.name} [Strategy: ${_strategy.value.name}]');

    // 1. Enforce Residency if strict
    if (_strategy.value == DeploymentStrategy.residencyStrict ||
        _strategy.value == DeploymentStrategy.enterprisePrivate) {
      final regionalNodes =
          _activeNodes.where((n) => n.region == preferredRegion).toList();
      if (regionalNodes.isNotEmpty) {
        return _selectLeastLoaded(regionalNodes);
      }
      return null; // Refuse if residency cannot be guaranteed
    }

    // 2. Latency First Fallback
    final availableNodes = _activeNodes
        .where((n) => n.state != NodeScalingState.overloaded)
        .toList();
    return _selectLeastLoaded(availableNodes);
  }

  GlobalNode? _selectLeastLoaded(List<GlobalNode> nodes) {
    if (nodes.isEmpty) return null;
    nodes.sort((a, b) => a.loadFactor.compareTo(b.loadFactor));
    return nodes.first;
  }

  /// Global Kill Switch for a specific region.
  void evacuateRegion(GlobalRegion region) {
    debugPrint(
        '🚨 GlobalScaling: EVACUATING REGION ${region.name} due to security/stability breach.');
    // Logic to migrate or terminate sessions would go here
  }

  /// Updates global deployment strategy.
  void setDeploymentStrategy(DeploymentStrategy strategy) {
    _strategy.value = strategy;
    debugPrint('🛠️ GlobalScaling: Strategy updated to ${strategy.name}');
  }
}
