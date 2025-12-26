// lib/screens/call_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_controller.dart';

class CallScreen extends StatefulWidget {
  final CallController controller;

  const CallScreen({
    super.key,
    required this.controller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  bool _ending = false;
  bool _closed = false; // ✅ double-pop engeli
  Timer? _ticker;
  int _seconds = 0;

  CallController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    c.statusText.addListener(_onStatusChanged);

    // Video call’da speaker açmak istersen
    if (c.isVideo && !c.speakerOn) {
      // ignore: discarded_futures
      c.toggleSpeaker();
    }
  }

  void _onStatusChanged() {
    final v = c.statusText.value.toLowerCase();
    final connected =
        v.contains('bağlandı') || v.contains('connected') || v.contains('active');

    if (connected && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.statusText.removeListener(_onStatusChanged);

    _ticker?.cancel();
    _ticker = null;

    super.dispose();
  }

  String _fmt(int s) {
    final m = (s / 60).floor();
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _safePop() async {
    if (_closed) return;
    _closed = true;
    if (!mounted) return;
    Navigator.of(context).pop(); // ✅ kesin pop
  }

  Future<void> _endCall() async {
    if (_ending || _closed) return;
    setState(() => _ending = true);

    // ✅ UI kapanması HİÇBİR ZAMAN hangUp’a bağlı olmamalı.
    // hangUp takılırsa 1.2s sonra yine de kapat.
    try {
      await c.hangUp().timeout(const Duration(milliseconds: 1200));
    } catch (_) {
      // ignore
    } finally {
      await _safePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherName = (c.otherName ?? c.otherUid ?? 'Kullanıcı');

    return PopScope(
      // ✅ canPop KAPALI OLMAYACAK. Yoksa pop çalışmaz, ekran kilitlenir.
      canPop: true,
      onPopInvoked: (didPop) async {
        // Kullanıcı back/swipe yaptıysa, call’ı düzgün kapat.
        // didPop true ise zaten pop oldu; tekrar pop yapma.
        if (didPop) return;
        await _endCall();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _ending ? null : _endCall,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(otherName, maxLines: 1, overflow: TextOverflow.ellipsis),
              ValueListenableBuilder<String>(
                valueListenable: c.statusText,
                builder: (_, v, __) {
                  return Text(
                    v,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Theme.of(context).hintColor),
                  );
                },
              ),
            ],
          ),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(_fmt(_seconds),
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: c.isVideo
                    ? _buildVideoStage(context)
                    : _buildAudioStage(context),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: _buildControls(context),
                ),
              ),
              if (_ending)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.25),
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioStage(BuildContext context) {
    final otherName = (c.otherName ?? c.otherUid ?? 'Kullanıcı');
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_circle, size: 120),
          const SizedBox(height: 12),
          Text(
            otherName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<String>(
            valueListenable: c.statusText,
            builder: (_, v, __) => Text(
              v,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoStage(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: RTCVideoView(
              c.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirror: false,
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 110,
                height: 150,
                color: Colors.black54,
                child: RTCVideoView(
                  c.localRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final isMuted = c.muted;
    final spk = c.speakerOn;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlBtn(
          icon: isMuted ? Icons.mic_off : Icons.mic,
          label: isMuted ? 'Muted' : 'Mic',
          onTap: _ending
              ? null
              : () async {
            await c.toggleMute();
            if (mounted) setState(() {});
          },
        ),
        _ControlBtn(
          icon: spk ? Icons.volume_up : Icons.volume_off,
          label: spk ? 'Speaker' : 'Earpiece',
          onTap: _ending
              ? null
              : () async {
            await c.toggleSpeaker();
            if (mounted) setState(() {});
          },
        ),
        _ControlBtn(
          icon: Icons.call_end_rounded,
          label: 'Kapat',
          danger: true,
          onTap: _ending ? null : _endCall,
        ),
      ],
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  const _ControlBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = danger ? Colors.red : Theme.of(context).colorScheme.primary;
    final disabled = onTap == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          onTap: onTap,
          radius: 34,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: disabled ? Colors.grey : bg,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
