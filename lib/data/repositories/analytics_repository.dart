import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/device_analytics_model.dart';

class AnalyticsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<DeviceAnalyticsModel>> getDevicePerformance(String userId) async {
    try {
      final response = await _client.rpc(
        'get_device_report',
        params: {'p_user_id': userId},
      );

      if (response == null) return [];

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => DeviceAnalyticsModel.fromJson(json)).toList();
    } catch (e) {
      // In case of error (RPC missing or network), return empty list implies no data
      return [];
    }
  }
}
