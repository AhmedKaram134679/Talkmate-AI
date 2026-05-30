import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/routing_log_model.dart';

class RoutingLogRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<RoutingLogModel>> getLogs({int limit = 50}) async {
    try {
      final response = await _client
          .from('routing_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => RoutingLogModel.fromJson(json)).toList();
    } catch (e) {
      // Fail safely for debug tools
      return [];
    }
  }
}
