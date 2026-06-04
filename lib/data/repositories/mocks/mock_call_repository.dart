import 'dart:async';

import 'package:talkmate_ai/data/models/call_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_call_repository.dart';

class MockCallRepository implements ICallRepository {
  MockCallRepository._();
  static final MockCallRepository instance = MockCallRepository._();

  final Map<String, CallSession> _calls = {}; // callId -> session
  final Map<String, StreamController<CallSession?>> _callCtrls =
      {}; // callId -> ctrl
  final Map<String, StreamController<List<CallSession>>> _userCtrls =
      {}; // userId -> ctrl

  StreamController<CallSession?> _callCtrl(String id) => _callCtrls.putIfAbsent(
      id, () => StreamController<CallSession?>.broadcast());
  StreamController<List<CallSession>> _userCtrl(String id) =>
      _userCtrls.putIfAbsent(
        id,
        () => StreamController<List<CallSession>>.broadcast(),
      );

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _emitCall(String id) => _callCtrl(id).add(_calls[id]);

  void _emitUser(String userId) {
    final list = _calls.values
        .where((c) => c.senderId == userId || c.receiverId == userId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _userCtrl(userId).add(list);
  }

  @override
  Future<CallSession> createCall({
    required String senderId,
    required String receiverId,
    bool isVideo = false,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) async {
    final id = _genId();
    final session = CallSession(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      type: isVideo ? CallType.video : CallType.audio,
      status: CallStatus.ringing,
      createdAt: createdAt ?? DateTime.now(),
      metadata: metadata ?? {},
    );
    _calls[id] = session;
    _emitCall(id);
    _emitUser(senderId);
    _emitUser(receiverId);
    return session;
  }

  @override
  Stream<CallSession?> watchById(String callId) {
    Future.microtask(() => _emitCall(callId));
    return _callCtrl(callId).stream;
  }

  @override
  Future<CallSession?> getById(String callId) async {
    return _calls[callId];
  }

  @override
  Future<void> updateStatus(String callId, CallStatus status) async {
    final c = _calls[callId];
    if (c == null) return;
    final updated = CallSession(
      id: c.id,
      senderId: c.senderId,
      receiverId: c.receiverId,
      type: c.type,
      status: status,
      roomId: c.roomId,
      createdAt: c.createdAt,
      startedAt:
          c.startedAt ?? (status == CallStatus.ongoing ? DateTime.now() : null),
      endedAt: status == CallStatus.ended ||
              status == CallStatus.missed ||
              status == CallStatus.rejected
          ? (c.endedAt ?? DateTime.now())
          : c.endedAt,
      metadata: c.metadata,
    );
    _calls[callId] = updated;
    _emitCall(callId);
    _emitUser(updated.senderId);
    _emitUser(updated.receiverId);
  }

  @override
  Future<void> updateMetadata(
      String callId, Map<String, dynamic> metadata) async {
    final c = _calls[callId];
    if (c == null) return;
    final updated = c.copyWith(metadata: {
      ...(c.metadata ?? {}),
      ...metadata,
    });
    _calls[callId] = updated;
    _emitCall(callId);
  }

  @override
  Stream<List<CallSession>> watchUserCalls(String userId, {int limit = 50}) {
    Future.microtask(() => _emitUser(userId));
    return _userCtrl(userId).stream;
  }

  @override
  Future<void> setOffer(String callId, String sdp,
      {Map<String, dynamic>? extra}) async {
    final c = _calls[callId];
    if (c == null) return;
    final meta = Map<String, dynamic>.from(c.metadata ?? {});
    meta['offer'] = {'type': 'offer', 'sdp': sdp};
    if (extra != null) {
      meta['offer'].addAll(extra);
    }

    _calls[callId] = CallSession(
      id: c.id,
      senderId: c.senderId,
      receiverId: c.receiverId,
      type: c.type,
      status: CallStatus.ringing,
      createdAt: c.createdAt,
      metadata: meta,
    );
    _emitCall(callId);
  }

  @override
  Future<void> setAnswer(String callId, String sdp,
      {Map<String, dynamic>? extra}) async {
    final c = _calls[callId];
    if (c == null) return;
    final meta = Map<String, dynamic>.from(c.metadata ?? {});
    meta['answer'] = {'type': 'answer', 'sdp': sdp};
    _calls[callId] = CallSession(
      id: c.id,
      senderId: c.senderId,
      receiverId: c.receiverId,
      type: c.type,
      status: CallStatus.ongoing,
      createdAt: c.createdAt,
      startedAt: DateTime.now(),
      metadata: meta,
    );
    _emitCall(callId);
  }

  @override
  Future<void> addCandidate(
      String callId, Map<String, dynamic> candidateData) async {
    final c = _calls[callId];
    if (c == null) return;
    final meta = Map<String, dynamic>.from(c.metadata ?? {});
    final List candidates = List.from(meta['candidates'] ?? []);
    candidates.add(candidateData);
    meta['candidates'] = candidates;
    _calls[callId] = CallSession(
      id: c.id,
      senderId: c.senderId,
      receiverId: c.receiverId,
      type: c.type,
      status: c.status,
      createdAt: c.createdAt,
      metadata: meta,
    );
    _emitCall(callId);
  }

  @override
  Future<void> clearGhostCalls(String userId) async {
    final active = _calls.keys.where((id) {
      final c = _calls[id]!;
      final isParticipant = c.senderId == userId || c.receiverId == userId;
      final isActive =
          c.status == CallStatus.ringing || c.status == CallStatus.ongoing;
      return isParticipant && isActive;
    }).toList();

    for (final id in active) {
      final c = _calls[id]!;
      final status =
          c.senderId == userId ? CallStatus.ended : CallStatus.missed;
      await updateStatus(id, status);
    }
  }
}
