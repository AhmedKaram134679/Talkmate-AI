// Integration test helpers for Supabase-backed repositories.
// To enable these tests, set environment variable TALKMATE_IT=1 and ensure
// Supabase options are configured.
// Example (PowerShell):
//   $env:TALKMATE_IT=1; flutter test test/integration

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/core/constants/api_constants.dart';
import 'package:talkmate_ai/data/services/firebase_service.dart';

class ItEnv {
  static bool get enabled => Platform.environment['TALKMATE_IT'] == '1';
}

Future<bool> ensureFirebaseInitialized() async {
  // Initialize Flutter bindings for tests
  TestWidgetsFlutterBinding.ensureInitialized();

  try {
    await FirebaseService.initialize();
    final ready = await ensureSupabaseInitialized();
    if (!ready) {
      debugPrint('Skipping integration test - Supabase not available');
      return false;
    }
    return FirebaseService.isInitialized;
  } catch (e) {
    debugPrint('Firebase not available for IT');
    return false;
  }
}

Future<bool> ensureSupabaseInitialized() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  try {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      await Supabase.initialize(
        url: ApiConstants.supabaseUrl,
        anonKey: ApiConstants.supabaseAnonKey,
      );
    }
    return true;
  } catch (e) {
    debugPrint('Supabase initialization failed for IT: $e');
    return false;
  }
}
