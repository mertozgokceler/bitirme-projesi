import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:uuid/uuid.dart';

class MyStoriesScreen extends StatefulWidget {
  const MyStoriesScreen({super.key});

  @override
  State<MyStoriesScreen> createState() => _MyStoriesScreenState();
}

class _MyStoriesScreenState extends State<MyStoriesScreen> {
  bool _loading = true;
  bool _saving = false;

  String _photoUrl = '';

  final _picker = ImagePicker();

  String? _uid;
  late CollectionReference<Map<String, dynamic>> _itemsRef;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _uid = me.uid;

    _itemsRef = FirebaseFirestore.instance
        .collection('stories')
        .doc(me.uid)
        .collection('items');

    await _loadUserMeta();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadUserMeta() async {
    final uid = _uid;
    if (uid == null) return;

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final u = userDoc.data() ?? {};

    _photoUrl = (u['photoUrl'] ??
        u['photoURL'] ??
        u['profilePhotoUrl'] ??
        u['photo'] ??
        '')
        .toString()
        .trim();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _myItemsStream() {
    final now = Timestamp.now();
    return _itemsRef
        .where('expiresAt', isGreaterThan: now)
        .orderBy('expiresAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> _addImage() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null) return;
    await _uploadAndCreateItem(File(x.path), type: 'image');
  }

  Future<void> _addVideo() async {
    final x = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 30),
    );
    if (x == null) return;
    await _uploadAndCreateItem(File(x.path), type: 'video');
  }

  Future<void> _uploadAndCreateItem(File file, {required String type}) async {
    final uid = _uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      final id = const Uuid().v4();

      final ext = (type == 'video') ? 'mp4' : 'jpg';
      final storagePath = 'stories/$uid/$id.$ext';

      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putFile(file);
      final mediaUrl = await ref.getDownloadURL();

      final expiresAt =
      Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24)));

      await _itemsRef.doc(id).set({
        'id': id,
        'type': type,
        'mediaUrl': mediaUrl,
        'thumbUrl': type == 'image' ? mediaUrl : null,
        'storagePath': storagePath,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtClient': Timestamp.now(),
        'expiresAt': expiresAt,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Durum eklendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yükleme hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteItem(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final uid = _uid;
    if (uid == null) return;

    final ok = await _confirmDelete();
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      final data = doc.data() ?? {};
      final storagePath = (data['storagePath'] ?? '').toString().trim();

      await doc.reference.delete();

      if (storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref().child(storagePath).delete();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Durum silindi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silme hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirmDelete() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surface.withOpacity(isDark ? 0.96 : 0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Silinsin mi?'),
        content: const Text('Bu durumu silmek üzeresin. Geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Vazgeç',
              style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  LinearGradient _bgGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0B1220), Color(0xFF0A1B2E), Color(0xFF081829)],
      );
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF6FAFF), Color(0xFFEFF6FF), Color(0xFFF9FBFF)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Scaffold(
      backgroundColor: cs.background,
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
          Positioned(
            top: -110,
            left: -80,
            child: _GlowBlob(size: 260, color: cs.primary.withOpacity(0.20)),
          ),
          Positioned(
            bottom: -140,
            right: -90,
            child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18)),
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  title: 'Durumun',
                  saving: _saving,
                  onClose: () => Navigator.pop(context),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        _HeroHeader(photoUrl: _photoUrl, saving: _saving),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _AddButtonsRow(
                            saving: _saving,
                            onAddImage: _addImage,
                            onAddVideo: _addVideo,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: _InfoCard(
                            text:
                            'Durumlar 24 saat sonra otomatik kaybolur. Foto veya video ekleyebilirsin.',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                          child: Text(
                            'Aktif Durumların',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                          child: _GlassContainer(
                            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: _myItemsStream(),
                              builder: (context, snap) {
                                if (snap.connectionState == ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(18),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }

                                final docs = snap.data?.docs ?? const [];

                                if (docs.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(18),
                                    child: _EmptyState(
                                      title: 'Henüz durum yok',
                                      subtitle: 'Yukarıdan fotoğraf veya video ekle.',
                                    ),
                                  );
                                }

                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                  itemCount: docs.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final d = docs[i];
                                    final it = d.data();

                                    final type = (it['type'] ?? '').toString().trim();
                                    final mediaUrl =
                                    (it['mediaUrl'] ?? it['url'] ?? '').toString().trim();
                                    final thumbUrl = (it['thumbUrl'] ?? '').toString().trim();

                                    final ttlText = _ttlText(it['expiresAt']);
                                    final createdText =
                                    _createdText(it['createdAt'] ?? it['createdAtClient']);

                                    return _StoryItemCard(
                                      type: type,
                                      mediaUrl: mediaUrl,
                                      thumbUrl: thumbUrl,
                                      ttlText: ttlText,
                                      createdText: createdText,
                                      saving: _saving,
                                      onDelete: () => _deleteItem(d),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _ttlText(dynamic expiresAt) {
    if (expiresAt is! Timestamp) return '';
    final diff = expiresAt.toDate().difference(DateTime.now());

    if (diff.isNegative) return 'Süresi doldu';

    final h = diff.inHours;
    final m = diff.inMinutes % 60;

    if (h <= 0 && m <= 0) return 'Süresi dolmak üzere';
    if (h <= 0) return 'Kalan: ${m}dk';
    if (m == 0) return 'Kalan: ${h}sa';
    return 'Kalan: ${h}sa ${m}dk';
  }

  String _createdText(dynamic ts) {
    if (ts is! Timestamp) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Şimdi';
    if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}

// ===================== UI =====================

class _TopBar extends StatelessWidget {
  final String title;
  final bool saving;
  final VoidCallback onClose;

  const _TopBar({
    required this.title,
    required this.saving,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: saving ? null : onClose,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(isDark ? 0.70 : 0.90),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outline.withOpacity(0.70)),
              ),
              child: Icon(Icons.arrow_back_rounded, color: cs.onSurface.withOpacity(0.88)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _GradientButton(
            text: 'Bitti',
            loading: saving,
            onTap: saving ? null : onClose,
          ),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final String photoUrl;
  final bool saving;

  const _HeroHeader({
    required this.photoUrl,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isDark = t.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Container(
              height: 118,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6E44FF), Color(0xFF00C4FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                    color: Colors.black.withOpacity(isDark ? 0.30 : 0.14),
                  ),
                ],
              ),
            ),
            Positioned(
              top: -60,
              left: -40,
              child: _GlowBlob(size: 170, color: Colors.white.withOpacity(0.18)),
            ),
            Positioned(
              bottom: -70,
              right: -48,
              child: _GlowBlob(size: 190, color: Colors.white.withOpacity(0.10)),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.55), width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white.withOpacity(0.20),
                        backgroundImage: photoUrl.trim().isNotEmpty ? NetworkImage(photoUrl.trim()) : null,
                        child: photoUrl.trim().isEmpty
                            ? const Icon(Icons.person, color: Colors.white, size: 28)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Durum Yönetimi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _MiniPill(icon: Icons.timer_outlined, text: '24 saat'),
                                const SizedBox(width: 8),
                                _MiniPill(
                                  icon: saving ? Icons.cloud_upload_rounded : Icons.cloud_done_rounded,
                                  text: saving ? 'İşleniyor' : 'Hazır',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ⭐ yok
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withOpacity(0.92)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: Colors.white.withOpacity(0.92),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButtonsRow extends StatelessWidget {
  final bool saving;
  final VoidCallback onAddImage;
  final VoidCallback onAddVideo;

  const _AddButtonsRow({
    required this.saving,
    required this.onAddImage,
    required this.onAddVideo,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            title: 'Foto ekle',
            subtitle: 'JPG / PNG',
            icon: Icons.image_outlined,
            saving: saving,
            onTap: saving ? null : onAddImage,
            fill: cs.surface.withOpacity(isDark ? 0.78 : 0.92),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            title: 'Video ekle',
            subtitle: 'max 30 sn',
            icon: Icons.videocam_outlined,
            saving: saving,
            onTap: saving ? null : onAddVideo,
            fill: cs.surface.withOpacity(isDark ? 0.78 : 0.92),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool saving;
  final VoidCallback? onTap;
  final Color fill;

  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.saving,
    required this.onTap,
    required this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AspectRatio(
            aspectRatio: 0.95,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: cs.outline.withOpacity(0.70)),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 20,
                    offset: const Offset(0, 12),
                    color: Colors.black.withOpacity(isDark ? 0.22 : 0.07),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6E44FF), Color(0xFF00C4FF)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                          color: Colors.black.withOpacity(isDark ? 0.30 : 0.12),
                        ),
                      ],
                    ),
                    child: saving
                        ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    )
                        : Icon(icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                        fontSize: 14.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withOpacity(0.62),
                        fontSize: 12.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  const _InfoCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _GlassContainer(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.2,
                height: 1.25,
                color: cs.onSurface.withOpacity(0.86),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withOpacity(isDark ? 0.55 : 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _GlassContainer({
    required this.child,
    this.padding = const EdgeInsets.all(0),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(isDark ? 0.78 : 0.92),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outline.withOpacity(0.70)),
            boxShadow: [
              BoxShadow(
                blurRadius: 22,
                offset: const Offset(0, 12),
                color: Colors.black.withOpacity(isDark ? 0.18 : 0.07),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StoryItemCard extends StatelessWidget {
  final String type;
  final String mediaUrl;
  final String thumbUrl;
  final String ttlText;
  final String createdText;
  final bool saving;
  final VoidCallback onDelete;

  const _StoryItemCard({
    required this.type,
    required this.mediaUrl,
    required this.thumbUrl,
    required this.ttlText,
    required this.createdText,
    required this.saving,
    required this.onDelete,
  });

  bool get _isVideo => type.toLowerCase().trim() == 'video';
  bool get _hasThumb =>
      (thumbUrl.trim().isNotEmpty || mediaUrl.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final url = (thumbUrl.trim().isNotEmpty) ? thumbUrl.trim() : mediaUrl.trim();

    // pill renkleri (mor / mavi)
    final pillBase = _isVideo ? const Color(0xFF00C4FF) : const Color(0xFF6E44FF);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outline.withOpacity(0.70)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Thumb(
              url: url,
              isVideo: _isVideo,
              hasThumb: _hasThumb,
            ),

            // ✅ ORTA BLOK esnek
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ OVERFLOW BİTİRME: Row yerine Wrap
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // ✅ Tür pill’i (mor şey)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: pillBase.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: pillBase.withOpacity(0.40),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isVideo
                                    ? Icons.videocam_rounded
                                    : Icons.image_rounded,
                                size: 14,
                                color: Colors.white.withOpacity(0.95), // ✅ net görünür
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isVideo ? 'Video' : 'Fotoğraf', // ✅ tür yazısı burada
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.2,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white.withOpacity(0.95), // ✅ net görünür
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ✅ sağdaki zaman (dar ekranda alt satıra iner -> overflow yok)
                        if (createdText.isNotEmpty)
                          Text(
                            createdText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface.withOpacity(0.55),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 16,
                          color: cs.primary.withOpacity(0.85),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            mediaUrl.isEmpty ? 'URL yok (bozuk item)' : 'Yüklendi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.2,
                              fontWeight: FontWeight.w800,
                              color: mediaUrl.isEmpty
                                  ? cs.error.withOpacity(0.90)
                                  : cs.onSurface.withOpacity(0.78),
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (ttlText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _TtlBar(text: ttlText),
                    ],
                  ],
                ),
              ),
            ),

            // ✅ SİL BUTONU (sabit)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: saving ? null : onDelete,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.error.withOpacity(isDark ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.error.withOpacity(0.30)),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: cs.error.withOpacity(0.92),
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

class _Thumb extends StatelessWidget {
  final String url;
  final bool isVideo;
  final bool hasThumb;

  const _Thumb({
    required this.url,
    required this.isVideo,
    required this.hasThumb,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 92,
      height: 92,
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.surfaceVariant.withOpacity(isDark ? 0.30 : 0.55),
        border: Border.all(color: cs.outline.withOpacity(0.55)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: hasThumb
                  ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(context),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                    ),
                  );
                },
              )
                  : _fallback(context),
            ),
            if (isVideo) Positioned.fill(child: Container(color: Colors.black.withOpacity(0.18))),
            if (isVideo)
              Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                        color: Colors.black.withOpacity(0.20),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF0B1220)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.primary.withOpacity(0.10),
      child: Center(
        child: Icon(
          isVideo ? Icons.videocam_rounded : Icons.image_rounded,
          color: cs.primary.withOpacity(0.90),
          size: 30,
        ),
      ),
    );
  }
}

class _TtlBar extends StatelessWidget {
  final String text;
  const _TtlBar({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isExpired = text.toLowerCase().contains('doldu');
    final Color c = isExpired ? cs.error : cs.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(isExpired ? Icons.warning_amber_rounded : Icons.timer_outlined, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w800,
                color: cs.onSurface.withOpacity(0.86),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: SizedBox(
            width: 160,
            height: 160,
            child: Lottie.asset(
              'assets/lottie/no_data.json',
              fit: BoxFit.contain,
              repeat: true,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14.5,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.2,
            height: 1.25,
            color: cs.onSurface.withOpacity(0.70),
          ),
        ),
      ],
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String text;
  final bool loading;
  final VoidCallback? onTap;

  const _GradientButton({
    required this.text,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF6E44FF), Color(0xFF00C4FF)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              blurRadius: 16,
              offset: const Offset(0, 10),
              color: Colors.black.withOpacity(isDark ? 0.30 : 0.14),
            ),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0.0)]),
        ),
      ),
    );
  }
}
