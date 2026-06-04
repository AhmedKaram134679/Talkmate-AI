import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/call_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_call_repository.dart';

class SupabaseCallRepository implements ICallRepository {
  SupabaseCallRepository();

  final _client = Supabase.instance.client;

  // [Stage R22.5]: Resilience Helper
  Future<T> _retry<T>(Future<T> Function() action,
      {int maxAttempts = 3}) async {
    int attempts = 0;
    while (true) {
      try {
        attempts++;
        return await action();
      } catch (e) {
        if (attempts >= maxAttempts) rethrow;
        final bool isConnError = e.toString().contains('Connection closed') ||
            e.toString().contains('Connection terminated') ||
            e.toString().contains('Connection reset');
        if (!isConnError) rethrow;

        debugPrint(
            '⚠️ SupabaseRepo: Retrying request (Attempt $attempts/$maxAttempts) due to: $e');
        await Future.delayed(Duration(milliseconds: 500 * attempts));
      }
    }
  }

  @override
  Future<CallSession> createCall({
    required String senderId,
    required String receiverId,
    bool isVideo = false,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) async {
    return _retry(() async {
      if (senderId.isEmpty || receiverId.isEmpty) {
        throw 'Cannot create call: senderId or receiverId is empty';
      }
      final now = createdAt ?? DateTime.now();
      final response = await _client
          .from('calls')
          .insert({
            'caller_id': senderId,
            'receiver_id': receiverId,
            'type': isVideo ? 'video' : 'audio',
            'status': CallStatus.ringing.name,
            'created_at': now.toIso8601String(),
          })
          .select('id, caller_id, receiver_id, type, status, created_at')
          .single();

      return CallSession.fromJson(response, response['id'].toString());
    });
  }

  @override
  Stream<CallSession?> watchById(String callId) {
    return _client
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callId)
        .map((list) => list.isNotEmpty
            ? CallSession.fromJson(list.first, list.first['id'].toString())
            : null);
  }

  @override
  Future<CallSession?> getById(String callId) async {
    final response =
        await _client.from('calls').select().eq('id', callId).maybeSingle();
    if (response == null) return null;
    return CallSession.fromJson(response, response['id'].toString());
  }

  @override
  Future<void> updateStatus(String callId, CallStatus status) async {
    await _retry(() async {
      final Map<String, dynamic> data = {
        'status': status.name,
      };

      if (status == CallStatus.ongoing) {
        data['started_at'] = DateTime.now().toIso8601String();
      } else if (status == CallStatus.ended ||
          status == CallStatus.rejected ||
          status == CallStatus.missed) {
        data['ended_at'] = DateTime.now().toIso8601String();
      }

      await _client.from('calls').update(data).eq('id', callId);
    });
  }

  @override
  Future<void> updateMetadata(
      String callId, Map<String, dynamic> metadata) async {
    await _retry(() async {
      await _client.from('calls').update(metadata).eq('id', callId);
    });
  }

  @override
  Stream<List<CallSession>> watchUserCalls(String userId, {int limit = 50}) {
    // Native Supabase stream is more robust for error propagation
    return _client
        .from('calls')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(limit * 2) // Over-fetch to allow for local filtering
        .map((list) {
          final filtered = list
              .where((item) =>
                  (item['sender_id'] ?? item['caller_id']) == userId ||
                  (item['receiver_id'] ?? item['callee_id']) == userId)
              .map((json) => CallSession.fromJson(json, json['id'].toString()))
              .take(limit)
              .toList();
          return filtered;
        });
  }

  // [Stage C8] Signaling is now handled via Realtime Broadcast in CommunicationController.
  // These DB-based methods are legacy and should no longer be used for active signaling.

  @override
  Future<void> setOffer(String callId, String sdp,
      {Map<String, dynamic>? extra}) async {
    await _retry(() async {
      final Map<String, dynamic> offerData = {'type': 'offer', 'sdp': sdp};
      if (extra != null) {
        offerData.addAll(extra);
      }

      await _client.from('calls').update({
        'offer': offerData,
      }).eq('id', callId);
    });
  }

  @override
  Future<void> setAnswer(String callId, String sdp,
      {Map<String, dynamic>? extra}) async {
    await _retry(() async {
      final Map<String, dynamic> answerData = {'type': 'answer', 'sdp': sdp};
      if (extra != null) {
        answerData.addAll(extra);
      }
      await _client.from('calls').update({
        'answer': answerData,
      }).eq('id', callId);
    });
  }

  @override
  Future<void> addCandidate(
      String callId, Map<String, dynamic> candidateData) async {
    // Candidates are high volume. We use a shorter retry and non-blocking failure
    try {
      await _retry(() async {
        await _client.rpc('fn_add_call_candidate', params: {
          'p_call_id': callId,
          'p_candidate': candidateData,
        });
      }, maxAttempts: 2);
    } catch (e) {
      debugPrint('⚠️ SupabaseRepo: Candidate sync failed after retries: $e');
    }
  }

  @override
  Future<void> clearGhostCalls(String userId) async {
    await _retry(() async {
      final now = DateTime.now().toIso8601String();
      // End calls where user is caller
      await _client
          .from('calls')
          .update({'status': CallStatus.ended.name, 'ended_at': now})
          .eq('caller_id', userId)
          .inFilter(
              'status', [CallStatus.ringing.name, CallStatus.ongoing.name]);

      // End calls where user is receiver
      await _client
          .from('calls')
          .update({'status': CallStatus.missed.name, 'ended_at': now})
          .eq('receiver_id', userId)
          .inFilter(
              'status', [CallStatus.ringing.name, CallStatus.ongoing.name]);
    });
  }
}
