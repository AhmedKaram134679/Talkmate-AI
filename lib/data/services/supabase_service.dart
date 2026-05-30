import 'dart:io';
import 'package:http/io_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/core/constants/api_constants.dart';

class SupabaseService {
  Future<void> initialize() async {
    // [PRODUCTION_HARDENING]: Set shorter idleTimeout to proactively close connections
    // before the Supabase Gateway (Kong/Nginx) resets them.
    final httpClient = HttpClient()..idleTimeout = const Duration(seconds: 4);
    final client = IOClient(httpClient);

    await Supabase.initialize(
      url: ApiConstants.supabaseUrl,
      anonKey: ApiConstants.supabaseAnonKey,
      httpClient: client,
      realtimeClientOptions: const RealtimeClientOptions(
        timeout: Duration(seconds: 30),
        eventsPerSecond: 10,
      ),
    );
  }
}
