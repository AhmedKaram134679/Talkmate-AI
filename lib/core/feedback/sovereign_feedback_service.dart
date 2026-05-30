import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

/// [Stage B1] Sovereign Feedback Service
///
/// Collects user feedback locally without forced transmission.
/// Stores data in `feedback_logs.json` in the app's documents directory.
class SovereignFeedbackService extends GetxService {
  static SovereignFeedbackService get instance => Get.find();

  File? _logFile;
  final RxList<Map<String, dynamic>> _memoryLog = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    _initLogFile();
  }

  Future<void> _initLogFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/feedback_logs.json');
      if (!await _logFile!.exists()) {
        await _logFile!.create();
        await _logFile!.writeAsString(jsonEncode({'feedback': []}));
      }
      await _loadLogs();
    } catch (e) {
      debugPrint('Sovereign Feedback: Failed to init log file: $e');
    }
  }

  Future<void> _loadLogs() async {
    if (_logFile == null) return;
    try {
      final content = await _logFile!.readAsString();
      if (content.isNotEmpty) {
        final data = jsonDecode(content) as Map<String, dynamic>;
        if (data['feedback'] is List) {
          _memoryLog
              .assignAll(List<Map<String, dynamic>>.from(data['feedback']));
        }
      }
    } catch (e) {
      debugPrint('Sovereign Feedback: Failed to load logs: $e');
    }
  }

  Future<void> submitFeedback({
    required int rating, // 1-5
    String? text,
    Map<String, dynamic>? context,
  }) async {
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'rating': rating,
      'text': text ?? '',
      'context': context ?? {},
    };

    _memoryLog.add(entry);
    await _saveLogs();
    debugPrint('Sovereign Feedback: Entry saved locally.');
  }

  Future<void> _saveLogs() async {
    if (_logFile == null) return;
    try {
      final data = {'feedback': _memoryLog};
      await _logFile!.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Sovereign Feedback: Failed to save logs: $e');
    }
  }

  Future<String?> getFeedbackFilePath() async {
    if (_logFile == null || !await _logFile!.exists()) return null;
    return _logFile!.path;
  }

  /// Clears local feedback logs (Privacy feature)
  Future<void> clearLogs() async {
    _memoryLog.clear();
    await _saveLogs();
  }
}
