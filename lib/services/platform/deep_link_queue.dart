import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/utils/deep_link_logger.dart';

/// Deep Link navigation queue for handling Deep Links before GetX Navigator is ready.
/// 
/// Problem: When the app is launched via Deep Link (cold start), app_links may receive
/// the URI before GetMaterialApp/GetX Navigator is fully initialized, causing:
/// "You are trying to use contextless navigation without a GetMaterialApp or Get.key"
///
/// Solution: Queue Deep Links until the app is ready, then execute them in order.
class DeepLinkQueue {
  static final DeepLinkQueue _instance = DeepLinkQueue._internal();
  
  factory DeepLinkQueue() => _instance;
  
  DeepLinkQueue._internal();

  /// Queue of pending Deep Link navigation actions
  final List<_DeepLinkNavigation> _queue = [];
  
  /// Whether the app is ready for navigation
  bool _isAppReady = false;

  /// Queue a Deep Link navigation action
  /// Returns true if queued, false if immediately navigated
  bool queueNavigation({
    required String routeName,
    Map<String, dynamic>? arguments,
  }) {
    if (_isAppReady) {
      // Navigator is ready, execute immediately
      DeepLinkLogger.log('NAVIGATOR_READY - executing immediately');
      _executeNavigation(routeName, arguments);
      return false;
    } else {
      // Queue for later execution
      DeepLinkLogger.log('NAVIGATOR_NOT_READY - queueing Deep Link');
      _queue.add(
        _DeepLinkNavigation(
          routeName: routeName,
          arguments: arguments,
        ),
      );
      DeepLinkLogger.log('DEFERRED_DEEP_LINK_STORED - queue size: ${_queue.length}');
      return true;
    }
  }

  /// Mark the app as ready and execute any queued navigations
  void markAppReady() {
    DeepLinkLogger.log('APP_READY - marking navigator ready');
    _isAppReady = true;
    _processQueue();
  }

  /// Process the queue of pending Deep Link navigations
  void _processQueue() {
    if (_queue.isEmpty) {
      DeepLinkLogger.log('QUEUE_EMPTY - no deferred Deep Links to execute');
      return;
    }

    DeepLinkLogger.log('PROCESSING_QUEUE - ${_queue.length} deferred Deep Link(s)');
    
    // Process each queued navigation
    while (_queue.isNotEmpty) {
      final navigation = _queue.removeAt(0);
      DeepLinkLogger.log(
        'EXECUTING_QUEUED_DEEP_LINK - route: ${navigation.routeName}, args: ${navigation.arguments}',
      );
      
      try {
        _executeNavigation(navigation.routeName, navigation.arguments);
        DeepLinkLogger.log('DEFERRED_DEEP_LINK_EXECUTED - route: ${navigation.routeName}');
      } catch (e, st) {
        DeepLinkLogger.logException(
          'QUEUED_NAVIGATION_FAILED',
          e,
          stackTrace: st,
        );
        debugPrint('Failed to execute queued Deep Link: $e');
      }
    }
  }

  /// Execute navigation immediately (internal method)
  void _executeNavigation(String routeName, Map<String, dynamic>? arguments) {
    try {
      if (arguments != null && arguments.isNotEmpty) {
        Get.toNamed(routeName, arguments: arguments);
      } else {
        Get.toNamed(routeName);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Clear the queue (useful for testing)
  void clearQueue() {
    DeepLinkLogger.log('QUEUE_CLEARED');
    _queue.clear();
  }

  /// Check if there are pending navigations
  bool hasPendingNavigations() => _queue.isNotEmpty;

  /// Get the number of pending navigations
  int getPendingCount() => _queue.length;
}

class _DeepLinkNavigation {
  final String routeName;
  final Map<String, dynamic>? arguments;

  _DeepLinkNavigation({
    required this.routeName,
    this.arguments,
  });

  @override
  String toString() => 'DeepLinkNav(route: $routeName, args: $arguments)';
}
