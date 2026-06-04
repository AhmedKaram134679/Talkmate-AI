import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../app_brain/assimilation/engine/sovereign_communication_engine.dart';
import '../communication/communication_controller.dart';

/// [Stage R7]: Sovereign Telemetry Service
///
/// A silent observer that records session lifecycle events, perceived performance metrics,
/// and potential failures for Beta readiness analysis.
///
/// Principles:
/// - Zero-Touch: Does not modify CommunicationController logic.
/// - Local-First: Stores logs locally on the device (beta_logs.json).
/// - Privacy-Centric: No PII or content recording.
class SovereignTelemetryService extends GetxService {
  static SovereignTelemetryService get to => Get.find();

  // Dependencies
  CommunicationController? _commController;

  // State
  final RxList<Map<String, dynamic>> _sessionLogs =
      <Map<String, dynamic>>[].obs;
  File? _logFile;
  Stopwatch? _connectionStopwatch;
  DateTime? _sessionStartTime;

  // Metrics
  bool _isSessionActive = false;
  bool _wasAnswered = false;
  String? _currentSessionType;

  @override
  void onInit() {
    super.onInit();
    _initLogFile();
    // We bind lazily to the controller when it's available or put this service after it.
    // Ideally, we listen to Get.put events, but simply finding it if it exists is easier.
    // For robustness, we can try to find it periodically or assume it's initialized before this.
    // However, CommunicationController might be lazy loaded.
    // Best approach: Use Get.lazyPut for this service, and in its onReady look for the controller,
    // or just checking in a periodic 'heartbeat' if we can't hook into DI events easily.

    // Actually, since this is a "Core" service, let's assume it's alive.
    // But we need to wait for CommunicationController to be active.

    // We'll use a worker on the CommunicationController if we can access it.
    // If not, we might need to be injected *into* it, but that violates "Zero-Touch".
    // Alternatively, we can use Get.find inside a loop or reaction.

    // Strategy: We will be initialized in main(). We will try to find CommunicationController.
    // If not found, we wait.

    // For now, let's assume standard GetX pattern where we can find it if it's in memory.
    // Since CommunicationController is likely a Singleton or long-lived, we can try to find it.

    // Note: In Stage R7, we are "External Listener".
    // We will use a periodic check to attach listeners if not already attached.
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_commController == null) {
        try {
          if (Get.isRegistered<CommunicationController>()) {
            _commController = Get.find<CommunicationController>();
            _attachListeners();
            timer.cancel(); // Attached successfully
            debugPrint('📡 Telemetry: Attached to CommunicationController');
          }
        } catch (_) {}
      }
    });
  }

  Future<void> _initLogFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/beta_logs.json');
      if (!await _logFile!.exists()) {
        await _logFile!.create();
        await _logFile!.writeAsString('[]');
      }
    } catch (e) {
      debugPrint('📡 Telemetry: Failed to init log file: $e');
    }
  }

  void _attachListeners() {
    if (_commController == null) return;

    final engine = SovereignCommunicationEngine.instance;

    // 1. Session Start/End Observation
    ever(engine.statusRx, (CommSessionStatus status) {
      if (status != CommSessionStatus.idle && !_isSessionActive) {
        _onSessionStart(engine.activeSessionId);
      } else if (status == CommSessionStatus.idle && _isSessionActive) {
        _onSessionEnd();
      }
    });

    // 2. Connection State Observation (Performance Metrics)
    ever(engine.statusRx, (CommSessionStatus status) {
      _logEvent('connection_state_change', {'status': status.toString()});

      if (status == CommSessionStatus.connecting) {
        _connectionStopwatch = Stopwatch()..start();
      } else if (status == CommSessionStatus.activeAudio ||
          status == CommSessionStatus.activeVideo) {
        _wasAnswered = true;
        if (_connectionStopwatch != null) {
          final duration = _connectionStopwatch!.elapsedMilliseconds;
          _logEvent('performance_metric', {
            'metric': 'timeToConnected',
            'duration_ms': duration,
          });
          debugPrint(
              '📡 Telemetry: Time to Connected ($status): ${duration}ms');
          _connectionStopwatch = null;
        }
      } else if (status == CommSessionStatus.failed) {
        _logEvent('session_failure', {'recoverable': false});
      }
    });

    // 3. User Behavior Observation
    ever(_commController!.isMuted, (bool muted) {
      if (_isSessionActive) {
        _logEvent(
            'behavior_interaction', {'action': 'mute_toggle', 'value': muted});
      }
    });

    ever(_commController!.isCameraOn, (bool cameraOn) {
      if (_isSessionActive) {
        _logEvent('behavior_interaction',
            {'action': 'camera_toggle', 'value': cameraOn});
      }
    });
  }

  void _onSessionStart(String id) {
    _isSessionActive = true;
    _wasAnswered = false;
    _currentSessionType = _commController?.sessionType.value.toString();
    _sessionStartTime = DateTime.now();
    _logEvent('session_start', {
      'session_id': id,
      'type': _currentSessionType,
    });
    debugPrint('📡 Telemetry: Session Started ($id)');
  }

  void _onSessionEnd() {
    if (!_isSessionActive) return;

    // [Stage R13] Constitutional Missed Call Log (Clause 6)
    final engine = SovereignCommunicationEngine.instance;
    if (!_wasAnswered &&
        (engine.status == CommSessionStatus.ringingIncoming ||
            engine.status == CommSessionStatus.ringingOutgoing ||
            engine.status == CommSessionStatus.dialing)) {
      _logEvent('missed_call', {
        'session_id': engine.activeSessionId,
        'type': _currentSessionType,
        'duration_seconds': 0,
        'is_incoming': engine.status == CommSessionStatus.ringingIncoming,
      });
      debugPrint('📡 Telemetry: Missed Call logged');
    }

    _isSessionActive = false;
    final duration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds
        : 0;

    _logEvent('session_end', {'duration_seconds': duration});
    debugPrint('📡 Telemetry: Session Ended (Duration: ${duration}s)');
    _sessionStartTime = null;
  }

  Future<void> _logEvent(String eventName, Map<String, dynamic> data) async {
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'event': eventName,
      ...data,
    };

    _sessionLogs.add(entry);

    if (_logFile != null) {
      try {
        final content = await _logFile!.readAsString();
        List<dynamic> logs = [];
        if (content.isNotEmpty) {
          try {
            logs = json.decode(content);
          } catch (_) {
            logs = [];
          }
        }
        logs.add(entry);
        if (logs.length > 1000) logs = logs.sublist(logs.length - 1000);
        await _logFile!.writeAsString(json.encode(logs));
      } catch (e) {
        debugPrint('📡 Telemetry: Failed to write log: $e');
      }
    }
  }
}
