// lib/screens/incoming_call_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/incoming_call_service.dart';
import '../services/call_service.dart';
import '../services/call_controller.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final IncomingCall call;
  final CallService callService;
  final VoidCallback onDone;

  const IncomingCallScreen({
    super.key,
    required this.call,
    required this.callService,
    required this.onDone,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _busy = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await widget.callService.rejectCall(widget.call.callId);
    } catch (_) {
      // ignore
    } finally {
      if (!mounted) return;
      widget.onDone();
      Navigator.of(context).maybePop();
    }
  }

  Future<bool> _ensurePermissions(CallType type) async {
    // Audio: mic
    // Video: mic + cam
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _snack('Mikrofon izni gerekli.');
      return false;
    }

    if (type == CallType.video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        _snack('Kamera izni gerekli.');
        return false;
      }
    }
    return true;
  }

  Future<void> _accept({required CallType type}) async {
    if (_busy) return;
    setState(() => _busy = true);

    final ok = await _ensurePermissions(type);
    if (!ok) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final controller = CallController(widget.callService);

    try {
      await controller.acceptIncoming(
        incomingCallId: widget.call.callId,
        callerId: widget.call.callerId,
        callerName: widget.call.callerName,
        onRemoteEnded: () async {
          // ✅ karşı taraf kapattı -> ended yazma, sadece temizle
          try {
            await controller.disposeAll(writeEnded: false);
          } catch (_) {}
          if (mounted) Navigator.of(context).maybePop();
        },
      );

      // ✅ Video çağrıda hoparlör açık başlasın (isteğe bağlı ama UX doğru)
      if (controller.callType == CallType.video && !controller.speakerOn) {
        try {
          await controller.toggleSpeaker();
        } catch (_) {}
      }

      if (!mounted) return;

      widget.onDone();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CallScreen(controller: controller),
        ),
      );
    } catch (e) {
      try {
        await controller.disposeAll(writeEnded: false);
      } catch (_) {}

      if (!mounted) return;

      _snack('Arama kabul edilemedi: $e');

      widget.onDone();
      Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.call.callerName.isEmpty
        ? widget.call.callerId
        : widget.call.callerName;

    // ✅ call doc’u dinle: type/status değişirse ekranda güncellensin
    final callDocStream = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.call.callId)
        .snapshots();

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        widget.onDone();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gelen Arama'),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _busy
                ? null
                : () {
              widget.onDone();
              Navigator.of(context).maybePop();
            },
          ),
        ),
        body: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: callDocStream,
            builder: (context, snap) {
              // Varsayılan: audio
              CallType type = CallType.audio;
              String status = 'ringing';

              if (snap.hasData && snap.data?.data() != null) {
                final data = snap.data!.data()!;
                type = widget.callService.parseCallType(data['type']);
                status = (data['status'] ?? 'ringing').toString();
              }

              // Eğer çağrı artık yoksa / ended olduysa ekranı kapat
              // (IncomingCallService zaten kapatıyor olabilir ama burada da güvenli)
              if (status == 'ended' || status == 'rejected') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  widget.onDone();
                  Navigator.of(context).maybePop();
                });
              }

              final isVideo = type == CallType.video;
              final icon = isVideo
                  ? Icons.videocam_rounded
                  : Icons.phone_in_talk_rounded;
              final label = isVideo ? 'Görüntülü Arama' : 'Sesli Arama';

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 64),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(color: Theme.of(context).hintColor),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Seni arıyor…',
                        style: TextStyle(color: Theme.of(context).hintColor),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _busy ? null : _reject,
                            icon: const Icon(Icons.call_end_rounded),
                            label: const Text('Reddet'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _busy ? null : () => _accept(type: type),
                            icon: Icon(isVideo
                                ? Icons.videocam_rounded
                                : Icons.call_rounded),
                            label: const Text('Kabul Et'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: CircularProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
