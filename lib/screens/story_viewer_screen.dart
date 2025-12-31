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

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  final PageController _page = PageController();
  final List<Map<String, dynamic>> _items = [];

  bool _loading = true;
  String? _error;

  int _index = 0;

  VideoPlayerController? _vc;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
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

    // ✅ Ring için stabil kıyas: expiresAt
    // (createdAt null olabiliyor, expiresAt her zaman dolu olmalı)
    Timestamp? curExpiresAt;
    if (_items.isNotEmpty && _index >= 0 && _index < _items.length) {
      final cur = _items[_index];
      final ex = cur['expiresAt'];
      if (ex is Timestamp) curExpiresAt = ex;
    }

    await seenRef.set({
      'viewerUid': me.uid,

      // Eski alanların dursun (analytics vs.)
      'seenAt': FieldValue.serverTimestamp(),
      'seenAtClient': Timestamp.now(),

      // ✅ StoriesStrip bununla "izlendi mi" karar veriyor
      if (curExpiresAt != null) 'lastSeenExpiresAt': curExpiresAt,

      // İstersen bu da kalsın (debug için faydalı)
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

      // ✅ SUBCOLLECTION OKU: stories/{uid}/items
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
          // normalize
          'type': type,
          'url': url,
          'docId': d.id,
        });
      }

      // ✅ createdAt varsa ona göre sırala, yoksa client backup
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

      // ✅ seen yaz (halkayı gri yapmak için)
      unawaited(_markSeen());

      // İlk item hazırlığı
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
    _autoTimer?.cancel();
    _disposeVideo();

    if (!mounted) return;

    final type = (_current['type'] ?? '').toString().trim().toLowerCase();
    final url = (_current['url'] ?? '').toString().trim();

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

        c.addListener(() {
          if (!mounted) return;
          final v = _vc;
          if (v == null) return;

          if (v.value.isInitialized &&
              !v.value.isPlaying &&
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
      _autoTimer = Timer(const Duration(seconds: 6), _next);
    }

    setState(() {});
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
            PageView.builder(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                final type = (item['type'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                final url = (item['url'] ?? '').toString().trim();

                if (type == 'video') {
                  final v = (i == _index) ? _vc : null;
                  if (v == null || !v.value.isInitialized) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
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
                      errorBuilder: (_, __, ___) =>
                      const _BrokenItem(),
                      loadingBuilder: (ctx, child, p) {
                        if (p == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      },
                    ),
                  ),
                );
              },
            ),

            // Üst bar
            Positioned(
              left: 12,
              right: 12,
              top: 10,
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

            // Progress bar
            Positioned(
              left: 10,
              right: 10,
              top: 0,
              child: Row(
                children: List.generate(_items.length, (i) {
                  final active = i == _index;
                  final done = i < _index;
                  return Expanded(
                    child: Container(
                      margin:
                      const EdgeInsets.symmetric(horizontal: 2),
                      height: 3,
                      decoration: BoxDecoration(
                        color: done
                            ? Colors.white
                            : active
                            ? Colors.white.withOpacity(0.85)
                            : Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Sol/sağ tap alanları
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _prev,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _next,
                    ),
                  ),
                ],
              ),
            ),

            // Alt ipucu
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
                    'İleri/geri için dokun',
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
              child: const Text('Kapat',
                  style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }
}
