// lib/services/incoming_call_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'call_service.dart'; // ✅ CallType burada

class IncomingCall {
  final String callId;
  final String callerId;
  final String callerName;
  final CallType type; // ✅ type eklendi

  const IncomingCall({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.type,
  });
}

class IncomingCallService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  IncomingCallService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _activeCallSub;

  bool _running = false;

  /// UI açık mı? (IncomingCallScreen/CallScreen push edildi mi)
  bool _uiOpen = false;

  /// Şu an takip ettiğimiz callId (tek aktif çağrı)
  String? _activeCallId;

  String? get _uid => _auth.currentUser?.uid;

  /// ✅ UI kapanınca bunu çağıracaksın (IncomingCallScreen pop/dispose içinde)
  void markUiClosed() {
    _uiOpen = false;
    // activeCallId'yi KORU: ringing devam ediyorsa tekrar açabilsin.
  }

  void stop() {
    _sub?.cancel();
    _sub = null;

    _activeCallSub?.cancel();
    _activeCallSub = null;

    _running = false;
    _uiOpen = false;
    _activeCallId = null;
  }

  void dispose() => stop();

  void start({
    required Future<void> Function(IncomingCall call) onIncoming,
    required void Function(Object e, StackTrace st) onError,
  }) {
    final uid = _uid;
    if (uid == null) return;

    stop();
    _running = true;

    _sub = _db
        .collection('calls')
        .where('calleeId', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((qs) async {
      if (!_running) return;

      // UI açıkken ikinci pop-up açma
      if (_uiOpen) return;

      if (qs.docs.isEmpty) return;

      final doc = qs.docs.first;
      final data = doc.data();

      final callId = doc.id;
      final status = (data['status'] ?? '').toString();
      if (status != 'ringing') return;

      final callerId = (data['callerId'] ?? '').toString().trim();
      if (callerId.isEmpty) return;

      final callerName = (data['callerName'] ?? callerId).toString();

      // ✅ type oku (Firestore'da 'audio' | 'video')
      final rawType = (data['type'] ?? 'audio').toString().toLowerCase().trim();
      final type = (rawType == 'video') ? CallType.video : CallType.audio;

      // Aynı callId için zaten UI açıldıysa tekrar açma.
      // Ama UI kapandıysa (markUiClosed), aynı ringing çağrıyı tekrar açabilsin.
      if (_activeCallId == callId && _uiOpen == false) {
        // allow re-open
      } else if (_activeCallId != null && _activeCallId != callId) {
        // başka active call varken yenisini açma
        return;
      }

      _activeCallId = callId;
      _uiOpen = true;

      // Active call status değişimini ayrıca izle
      _watchActiveCallStatus(callId);

      try {
        await onIncoming(
          IncomingCall(
            callId: callId,
            callerId: callerId,
            callerName: callerName,
            type: type,
          ),
        );
      } catch (e, st) {
        // onIncoming patlarsa UI kilidini bırak
        _uiOpen = false;
        onError(e, st);
      }
    }, onError: (e, st) {
      onError(e, st);
    });
  }

  void _watchActiveCallStatus(String callId) {
    _activeCallSub?.cancel();
    _activeCallSub = _db.collection('calls').doc(callId).snapshots().listen(
          (snap) {
        final data = snap.data();
        if (data == null) {
          _activeCallId = null;
          _uiOpen = false;
          _activeCallSub?.cancel();
          _activeCallSub = null;
          return;
        }

        final status = (data['status'] ?? '').toString();

        // ✅ ringing bittiği an activeCallId temizle
        // ⚠️ ama _uiOpen'ı burada zorla false yapma.
        // UI kapanınca markUiClosed çağıracaksın.
        if (status != 'ringing') {
          _activeCallId = null;

          _activeCallSub?.cancel();
          _activeCallSub = null;
        }
      },
      onError: (e) {
        _activeCallId = null;
        _uiOpen = false;
      },
    );
  }
}
