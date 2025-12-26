// lib/services/call_controller.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_service.dart';

class CallController {
  final CallService service;

  // ---- identity ----
  String? callId;
  String? otherUid;
  String? otherName;
  late final bool isCaller;

  // ✅ call type: audio/video (single source of truth)
  CallType _callType = CallType.audio;
  CallType get callType => _callType;
  bool get isVideo => _callType == CallType.video;

  // ---- RTC ----
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream; // ✅ unified-plan track->stream
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool _muted = false;
  bool _speakerOn = false;

  bool get muted => _muted;
  bool get speakerOn => _speakerOn;

  // ---- subs ----
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candSub;

  // ---- callbacks ----
  VoidCallback? _onRemoteEnded;

  // ✅ UI’nin dinleyebilmesi için
  final ValueNotifier<String> statusText = ValueNotifier<String>('Bağlanıyor…');

  // ✅ ICE buffer (callId oluşmadan candidate drop olmasın)
  final List<RTCIceCandidate> _pendingIce = [];

  // ✅ Remote ended mi? (disposeAll içinde ended yazmayı engellemek için)
  bool _remoteTerminated = false;

  // ✅ Ended status’ı yazıldı mı? (double write engeli)
  bool _endedWritten = false;

  CallController(this.service);

  String? get myUid => FirebaseAuth.instance.currentUser?.uid;

  // =========================
  // Init renderers
  // =========================
  Future<void> initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  // =========================
  // Flush pending ICE
  // =========================
  Future<void> _flushPendingIce({required bool asCaller}) async {
    final id = callId;
    if (id == null) return;
    if (_pendingIce.isEmpty) return;

    final toSend = List<RTCIceCandidate>.from(_pendingIce);
    _pendingIce.clear();

    for (final c in toSend) {
      if (c.candidate == null) continue;
      try {
        if (asCaller) {
          await service.addCallerCandidate(id, c);
        } else {
          await service.addCalleeCandidate(id, c);
        }
      } catch (e) {
        service.log('flushCandidate error: $e');
      }
    }
  }

  // =========================
  // Write ended ONCE (local hangup)
  // =========================
  Future<void> _writeEndedOnce() async {
    final id = callId;
    if (id == null) return;
    if (_endedWritten) return;
    if (_remoteTerminated) return;

    _endedWritten = true;
    try {
      await service.endCall(id);
    } catch (e) {
      service.log('endCall failed: $e');
    }
  }

  // =========================
  // Create peer connection & local media
  // =========================
  Future<void> _ensurePc({required bool asCaller, required CallType type}) async {
    if (_pc != null) return;

    _callType = type;

    await initRenderers();

    _pc = await createPeerConnection(service.rtcConfig);

    // ✅ Local media: audio always true, video only if video call
    final constraints = <String, dynamic>{
      'audio': true,
      'video': (type == CallType.video)
          ? {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'frameRate': {'ideal': 30},
      }
          : false,
    };

    final media = await navigator.mediaDevices.getUserMedia(constraints);

    _localStream = media;
    localRenderer.srcObject = _localStream;

    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    // ✅ unified-plan: streams bazen boş gelir -> remote stream yarat, track ekle
    _remoteStream ??= await createLocalMediaStream('remote');

    _pc!.onTrack = (RTCTrackEvent e) async {
      try {
        final track = e.track;
        if (track == null) return;

        _remoteStream ??= await createLocalMediaStream('remote');
        _remoteStream!.addTrack(track);

        remoteRenderer.srcObject = _remoteStream;
      } catch (err) {
        service.log('onTrack error: $err');
      }
    };

    _pc!.onIceCandidate = (RTCIceCandidate c) async {
      if (c.candidate == null) return;

      final id = callId;
      if (id == null) {
        _pendingIce.add(c);
        return;
      }

      try {
        if (asCaller) {
          await service.addCallerCandidate(id, c);
        } else {
          await service.addCalleeCandidate(id, c);
        }
      } catch (e) {
        service.log('addCandidate error: $e');
      }
    };
  }

  // =========================
  // OUTGOING
  // =========================
  Future<void> startOutgoing({
    required String calleeId,
    required String calleeName,
    required String callerName,
    required CallType type,
    VoidCallback? onRemoteEnded,
  }) async {
    if (callId != null) return;

    isCaller = true;
    otherUid = calleeId;
    otherName = calleeName;
    _onRemoteEnded = onRemoteEnded;
    _callType = type;

    _remoteTerminated = false;
    _endedWritten = false;

    statusText.value = 'Aranıyor…';

    await _ensurePc(asCaller: true, type: type);

    final offer = await _pc!.createOffer(service.offerConstraints(type: type));
    await _pc!.setLocalDescription(offer);

    final id = await service.createOutgoingCall(
      calleeId: calleeId,
      callerName: callerName,
      calleeName: calleeName,
      offer: offer,
      type: type,
    );

    callId = id;

    await _flushPendingIce(asCaller: true);

    _listenCallDocOutgoing(id);
    _listenRemoteCandidates(id, remoteIsCaller: false);

    statusText.value = 'Aranıyor…';
  }

  void _listenCallDocOutgoing(String id) {
    _callSub?.cancel();
    _callSub = service.watchCallDoc(id).listen((snap) async {
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? '').toString();

      // ✅ remote ended -> controller dispose etmez, UI kapatır
      if (status == 'rejected' || status == 'ended') {
        _remoteTerminated = true;
        statusText.value = 'Çağrı sonlandı';
        _onRemoteEnded?.call();
        return;
      }

      if (status == 'accepted') {
        statusText.value = 'Bağlandı';
      }

      final ans = data['answer'];
      if (ans is Map<String, dynamic>) {
        final rd = await _pc!.getRemoteDescription();
        if (rd == null) {
          try {
            final answer = service.parseSdpMap(ans);
            await _pc!.setRemoteDescription(answer);
          } catch (e) {
            service.log('setRemoteDescription(answer) failed: $e');
          }
        }
      }
    }, onError: (e) => service.log('callDoc sub error: $e'));
  }

  // =========================
  // INCOMING
  // =========================
  Future<void> acceptIncoming({
    required String incomingCallId,
    required String callerId,
    required String callerName,
    VoidCallback? onRemoteEnded,
  }) async {
    if (callId != null) return;

    isCaller = false;
    callId = incomingCallId;
    otherUid = callerId;
    otherName = callerName;
    _onRemoteEnded = onRemoteEnded;

    _remoteTerminated = false;
    _endedWritten = false;

    statusText.value = 'Bağlanıyor…';

    final data = await service.getCallData(incomingCallId);
    if (data == null) throw StateError('Call not found');

    final status = (data['status'] ?? '').toString();
    if (status != 'ringing') {
      throw StateError('Call is not ringing (status=$status)');
    }

    final type = service.parseCallType(data['type']);
    _callType = type;

    final offerMap = data['offer'];
    if (offerMap is! Map<String, dynamic>) {
      throw StateError('Offer missing');
    }

    await _ensurePc(asCaller: false, type: type);

    final offer = service.parseSdpMap(offerMap);
    await _pc!.setRemoteDescription(offer);

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    await service.acceptIncomingCall(callId: incomingCallId, answer: answer);

    await _flushPendingIce(asCaller: false);

    _listenCallDocIncoming(incomingCallId);
    _listenRemoteCandidates(incomingCallId, remoteIsCaller: true);

    statusText.value = 'Bağlandı';
  }

  void _listenCallDocIncoming(String id) {
    _callSub?.cancel();
    _callSub = service.watchCallDoc(id).listen((snap) async {
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? '').toString();

      if (status == 'accepted') {
        statusText.value = 'Bağlandı';
      }

      // ✅ remote ended -> controller dispose etmez, UI kapatır
      if (status == 'ended' || status == 'rejected') {
        _remoteTerminated = true;
        statusText.value = 'Çağrı sonlandı';
        _onRemoteEnded?.call();
        return;
      }
    }, onError: (e) => service.log('callDoc sub error: $e'));
  }

  // =========================
  // Remote candidates stream
  // =========================
  void _listenRemoteCandidates(String id, {required bool remoteIsCaller}) {
    _candSub?.cancel();

    final stream = remoteIsCaller
        ? service.watchCallerCandidates(id)
        : service.watchCalleeCandidates(id);

    _candSub = stream.listen((qs) async {
      for (final ch in qs.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;

        final data = ch.doc.data();
        if (data == null) continue;

        try {
          final c = service.parseCandidateMap(data);
          await _pc?.addCandidate(c);
        } catch (e) {
          service.log('addRemoteCandidate failed: $e');
        }
      }
    }, onError: (e) => service.log('cand sub error: $e'));
  }

  // =========================
  // Controls
  // =========================
  Future<void> toggleMute() async {
    _muted = !_muted;

    final audioTracks = _localStream?.getAudioTracks() ?? [];
    for (final t in audioTracks) {
      t.enabled = !_muted;
    }
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);
  }

  // =========================
  // End call (writes ended + cleanup)
  // =========================
  Future<void> hangUp() async {
    await _writeEndedOnce();
    await disposeAll(writeEnded: false);
  }

  // =========================
  // Full cleanup
  // =========================
  Future<void> disposeAll({bool writeEnded = false}) async {
    if (writeEnded) {
      await _writeEndedOnce();
    }

    await _callSub?.cancel();
    await _candSub?.cancel();
    _callSub = null;
    _candSub = null;

    await _cleanupRtc();

    callId = null;
    otherUid = null;
    otherName = null;

    // ❌ statusText resetleme yok. UI kapanınca zaten biter.
  }

  Future<void> _cleanupRtc() async {
    try {
      remoteRenderer.srcObject = null;
      localRenderer.srcObject = null;
    } catch (_) {}

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    try {
      for (final t in _localStream?.getTracks() ?? []) {
        await t.stop();
      }
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      for (final t in _remoteStream?.getTracks() ?? []) {
        await t.stop();
      }
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;

    try {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
    } catch (_) {}
  }
}
