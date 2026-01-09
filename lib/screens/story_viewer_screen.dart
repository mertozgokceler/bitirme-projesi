import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class StoryViewerScreen extends StatefulWidget {
  final String ownerUid;
  final String ownerName;
  final String ownerPhotoUrl;

  const StoryViewerScreen({
    super.key,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerPhotoUrl,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  final PageController _page = PageController();
  final List<Map<String, dynamic>> _items = [];

  bool _loading = true;
  String? _error;

  int _index = 0;

  VideoPlayerController? _vc;

  // ✅ Progress animasyonu bununla akacak
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this);
    _load();
  }

  @override
  void dispose() {
    _progress.dispose();
    _disposeVideo();
    _page.dispose();
    super.dispose();
  }

  void _disposeVideo() {
    final c = _vc;
    _vc = null;
    if (c != null) {
      c.pause();
      c.dispose();
    }
  }

  Map<String, dynamic> get _current => _items[_index];

  // ✅ viewer açılınca "izlendi" yaz
  Future<void> _markSeen() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final seenRef = FirebaseFirestore.instance
        .collection('stories')
        .doc(widget.ownerUid)
        .collection('seen')
        .doc(me.uid);

    Timestamp? curExpiresAt;
    if (_items.isNotEmpty && _index >= 0 && _index < _items.length) {
      final cur = _items[_index];
      final ex = cur['expiresAt'];
      if (ex is Timestamp) curExpiresAt = ex;
    }

    await seenRef.set({
      'viewerUid': me.uid,
      'seenAt': FieldValue.serverTimestamp(),
      'seenAtClient': Timestamp.now(),
      if (curExpiresAt != null) 'lastSeenExpiresAt': curExpiresAt,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'lastSeenAtClient': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _index = 0;
    });

    try {
      final now = Timestamp.now();

      final q = await FirebaseFirestore.instance
          .collection('stories')
          .doc(widget.ownerUid)
          .collection('items')
          .where('expiresAt', isGreaterThan: now)
          .orderBy('expiresAt', descending: true)
          .limit(50)
          .get();

      final parsed = <Map<String, dynamic>>[];

      for (final d in q.docs) {
        final m = d.data();

        final type = (m['type'] ?? '').toString().trim().toLowerCase();
        final url = (m['mediaUrl'] ?? m['url'] ?? '').toString().trim();
        final expiresAt = m['expiresAt'];

        if (type.isEmpty || url.isEmpty) continue;
        if (expiresAt is! Timestamp) continue;
        if (expiresAt.compareTo(now) <= 0) continue;

        parsed.add({
          ...m,
          'type': type,
          'url': url,
          'docId': d.id,
        });
      }

      parsed.sort((a, b) {
        final ta = a['createdAt'];
        final tb = b['createdAt'];
        if (ta is Timestamp && tb is Timestamp) return ta.compareTo(tb);

        final ca = a['createdAtClient'];
        final cb = b['createdAtClient'];
        if (ca is Timestamp && cb is Timestamp) return ca.compareTo(cb);

        return 0;
      });

      if (!mounted) return;

      if (parsed.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Aktif hikaye yok.';
        });
        return;
      }

      _items.addAll(parsed);

      setState(() {
        _loading = false;
        _error = null;
        _index = 0;
      });

      unawaited(_markSeen());

      await _prepareCurrent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _prepareCurrent() async {
    _progress.stop();
    _progress.reset();
    _disposeVideo();

    if (!mounted) return;

    final type = (_current['type'] ?? '').toString().trim().toLowerCase();
    final url = (_current['url'] ?? '').toString().trim();

    // ✅ progress tamamlanınca otomatik next
    _progress.removeStatusListener(_onProgressStatus);
    _progress.addStatusListener(_onProgressStatus);

    if (type == 'video') {
      if (url.isEmpty) {
        _next();
        return;
      }

      try {
        final c = VideoPlayerController.networkUrl(Uri.parse(url));
        _vc = c;

        await c.initialize();
        if (!mounted) return;

        await c.setLooping(false);
        await c.play();

        final d = c.value.duration;
        final dur = (d.inMilliseconds > 200) ? d : const Duration(seconds: 8);

        _progress.duration = dur;
        _progress.forward();

        // Video bitti mi -> next (progress zaten completed olabilir ama garanti)
        c.addListener(() {
          if (!mounted) return;
          final v = _vc;
          if (v == null) return;

          if (v.value.isInitialized &&
              v.value.position >= v.value.duration &&
              v.value.duration.inMilliseconds > 0) {
            _next();
          }
        });
      } catch (_) {
        _next();
        return;
      }
    } else {
      // ✅ foto: 6 sn
      _progress.duration = const Duration(seconds: 6);
      _progress.forward();
    }

    setState(() {});
  }

  void _onProgressStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) {
      _next();
    }
  }

  void _next() {
    if (!mounted) return;

    if (_index >= _items.length - 1) {
      Navigator.pop(context);
      return;
    }

    setState(() => _index++);

    _page.animateToPage(
      _index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );

    _prepareCurrent();
  }

  void _prev() {
    if (!mounted) return;
    if (_index <= 0) return;

    setState(() => _index--);

    _page.animateToPage(
      _index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );

    _prepareCurrent();
  }

  void _pause() {
    _progress.stop();
    _vc?.pause();
  }

  void _resume() {
    if (_items.isEmpty) return;
    _progress.forward();
    final curType = (_current['type'] ?? '').toString().toLowerCase();
    if (curType == 'video') _vc?.play();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
            ? _ErrorView(
          message: _error!,
          onClose: () => Navigator.pop(context),
        )
            : Stack(
          children: [
            // CONTENT
            PageView.builder(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                final type =
                (item['type'] ?? '').toString().trim().toLowerCase();
                final url = (item['url'] ?? '').toString().trim();

                if (type == 'video') {
                  final v = (i == _index) ? _vc : null;
                  if (v == null || !v.value.isInitialized) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Center(
                    child: AspectRatio(
                      aspectRatio: v.value.aspectRatio,
                      child: VideoPlayer(v),
                    ),
                  );
                }

                return Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 3,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const _BrokenItem(),
                      loadingBuilder: (ctx, child, p) {
                        if (p == null) return child;
                        return const Center(
                            child: CircularProgressIndicator());
                      },
                    ),
                  ),
                );
              },
            ),

            // PROGRESS (AKAN)
            Positioned(
              left: 10,
              right: 10,
              top: 6,
              child: _StoryProgressBar(
                count: _items.length,
                activeIndex: _index,
                controller: _progress,
              ),
            ),

            // TOP BAR
            Positioned(
              left: 12,
              right: 12,
              top: 18,
              child: Row(
                children: [
                  _OwnerAvatar(photoUrl: widget.ownerPhotoUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.ownerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white),
                  )
                ],
              ),
            ),

            // TAP AREAS + LONG PRESS PAUSE
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (_) => _pause(),
                onLongPressEnd: (_) => _resume(),
                onTapDown: (d) {
                  final w = MediaQuery.of(context).size.width;
                  if (d.globalPosition.dx < w * 0.35) {
                    _prev();
                  } else {
                    _next();
                  }
                },
                child: const SizedBox.expand(),
              ),
            ),

            // ALT İPUCU
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Text(
                    'İleri/geri için dokun • basılı tut: durdur',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryProgressBar extends StatelessWidget {
  final int count;
  final int activeIndex;
  final AnimationController controller;

  const _StoryProgressBar({
    required this.count,
    required this.activeIndex,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Row(
          children: List.generate(count, (i) {
            final double v;
            if (i < activeIndex) {
              v = 1.0;
            } else if (i == activeIndex) {
              v = controller.value; // ✅ AKIYOR
            } else {
              v = 0.0;
            }

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == count - 1 ? 0 : 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 3,
                    backgroundColor: Colors.white.withOpacity(0.25),
                    valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _OwnerAvatar extends StatelessWidget {
  final String photoUrl;
  const _OwnerAvatar({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final has = photoUrl.trim().isNotEmpty;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
      ),
      child: CircleAvatar(
        backgroundColor: Colors.white.withOpacity(0.08),
        backgroundImage: has ? NetworkImage(photoUrl.trim()) : null,
        child: !has
            ? const Icon(Icons.person, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}

class _BrokenItem extends StatelessWidget {
  const _BrokenItem();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.broken_image_rounded, color: Colors.white, size: 40),
        SizedBox(height: 10),
        Text(
          'Medya yüklenemedi',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _ErrorView({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded,
                color: Colors.white, size: 36),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onClose,
              child:
              const Text('Kapat', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }
}
