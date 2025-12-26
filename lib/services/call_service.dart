// lib/services/call_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum CallType { audio, video }

String callTypeToString(CallType t) => t == CallType.video ? 'video' : 'audio';

class CallService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CallService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;

  // ---- ICE servers ----
  Map<String, dynamic> get rtcConfig => {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ✅ constraints call type'a göre
  Map<String, dynamic> offerConstraints({required CallType type}) => {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': type == CallType.video,
    },
    'optional': [],
  };

  // =========================
  // Firestore refs
  // =========================
  DocumentReference<Map<String, dynamic>> callRef(String callId) =>
      _db.collection('calls').doc(callId);

  CollectionReference<Map<String, dynamic>> callerCandRef(String callId) =>
      callRef(callId).collection('callerCandidates');

  CollectionReference<Map<String, dynamic>> calleeCandRef(String callId) =>
      callRef(callId).collection('calleeCandidates');

  // =========================
  // Create outgoing call doc + offer
  // =========================
  Future<String> createOutgoingCall({
    required String calleeId,
    required String callerName,
    required String calleeName,
    required RTCSessionDescription offer,
    required CallType type,
  }) async {
    final me = uid;
    if (me == null) throw StateError('Not signed in');

    final doc = _db.collection('calls').doc();

    await doc.set({
      'callerId': me,
      'calleeId': calleeId,
      'callerName': callerName,
      'calleeName': calleeName,
      'type': callTypeToString(type), // 'audio' | 'video'
      'status': 'ringing',
      'offer': {
        'type': offer.type, // 'offer'
        'sdp': offer.sdp,
      },
      'answer': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'endedAt': null,
    });

    return doc.id;
  }

  // =========================
  // Accept incoming: set answer + status accepted
  // =========================
  Future<void> acceptIncomingCall({
    required String callId,
    required RTCSessionDescription answer,
  }) async {
    final me = uid;
    if (me == null) throw StateError('Not signed in');

    await callRef(callId).set({
      'status': 'accepted',
      'answer': {
        'type': answer.type, // 'answer'
        'sdp': answer.sdp,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // =========================
  // Reject (rejected standard)
  // =========================
  Future<void> rejectCall(String callId) async {
    await callRef(callId).set({
      'status': 'rejected',
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // =========================
  // End
  // =========================
  Future<void> endCall(String callId) async {
    await callRef(callId).set({
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // =========================
  // Candidate write
  // =========================
  Future<void> addCallerCandidate(String callId, RTCIceCandidate c) async {
    await callerCandRef(callId).add({
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
      'ts': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addCalleeCandidate(String callId, RTCIceCandidate c) async {
    await calleeCandRef(callId).add({
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
      'ts': FieldValue.serverTimestamp(),
    });
  }

  // =========================
  // Streams
  // =========================
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCallDoc(String callId) {
    return callRef(callId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCallerCandidates(
      String callId) {
    return callerCandRef(callId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCalleeCandidates(
      String callId) {
    return calleeCandRef(callId).snapshots();
  }

  // =========================
  // Read once
  // =========================
  Future<Map<String, dynamic>?> getCallData(String callId) async {
    final snap = await callRef(callId).get();
    return snap.data();
  }

  // =========================
  // Helpers
  // =========================
  RTCSessionDescription parseSdpMap(Map<String, dynamic> m) {
    final sdp = (m['sdp'] ?? '').toString();
    final type = (m['type'] ?? '').toString();
    if (sdp.isEmpty || type.isEmpty) throw StateError('Invalid SDP map');
    return RTCSessionDescription(sdp, type);
  }

  RTCIceCandidate parseCandidateMap(Map<String, dynamic> m) {
    final cand = (m['candidate'] ?? '').toString();
    final sdpMid = (m['sdpMid'] ?? '').toString();
    final sdpMLineIndex = m['sdpMLineIndex'];
    if (cand.isEmpty) throw StateError('Invalid candidate');
    return RTCIceCandidate(
      cand,
      sdpMid.isEmpty ? null : sdpMid,
      (sdpMLineIndex is int) ? sdpMLineIndex : int.tryParse('$sdpMLineIndex'),
    );
  }

  CallType parseCallType(dynamic v) {
    final s = (v ?? '').toString().toLowerCase().trim();
    return (s == 'video') ? CallType.video : CallType.audio;
  }

  void log(String msg) {
    if (kDebugMode) debugPrint('CALL: $msg');
  }
}
