// Integration test helpers for Supabase-backed repositories.
// To enable these tests, set environment variable TALKMATE_IT=1 and configure
// staging credentials (e.g. TALKMATE_STAGING_URL, TALKMATE_STAGING_ANON_KEY).
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

  static String get supabaseUrl =>
      Platform.environment['TALKMATE_STAGING_URL'] ?? ApiConstants.supabaseUrl;

  static String get supabaseAnonKey =>
      Platform.environment['TALKMATE_STAGING_ANON_KEY'] ?? ApiConstants.supabaseAnonKey;

  static String get testUserEmail =>
      Platform.environment['TALKMATE_IT_USER_EMAIL'] ?? 'it_tester@talkmate.staging';

  static String get testUserPassword =>
      Platform.environment['TALKMATE_IT_USER_PASSWORD'] ?? 'TestPassword123!';
}

Future<bool> ensureFirebaseInitialized() async {
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
        url: ItEnv.supabaseUrl,
        anonKey: ItEnv.supabaseAnonKey,
      );
    }
    return true;
  } catch (e) {
    debugPrint('Supabase initialization failed for IT: $e');
    return false;
  }
}

/// Helper to authenticate a real staging session to validate RLS policies
Future<User?> ensureAuthenticatedStagingUser() async {
  try {
    final client = Supabase.instance.client;
    if (client.auth.currentUser != null) {
      return client.auth.currentUser;
    }

    try {
      final res = await client.auth.signInWithPassword(
        email: ItEnv.testUserEmail,
        password: ItEnv.testUserPassword,
      );
      return res.user;
    } catch (_) {
      // If user does not exist on staging, attempt sign up
      final res = await client.auth.signUp(
        email: ItEnv.testUserEmail,
        password: ItEnv.testUserPassword,
      );
      return res.user;
    }
  } catch (e) {
    debugPrint('Staging authentication skipped or unavailable: $e');
    return null;
  }
}
