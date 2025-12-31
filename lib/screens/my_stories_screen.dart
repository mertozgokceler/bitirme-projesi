import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class MyStoriesScreen extends StatefulWidget {
  const MyStoriesScreen({super.key});

  @override
  State<MyStoriesScreen> createState() => _MyStoriesScreenState();
}

class _MyStoriesScreenState extends State<MyStoriesScreen> {
  bool _loading = true;
  bool _saving = false;

  String _userName = '';
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

    _userName = (u['name'] ?? u['username'] ?? 'Kullanıcı').toString().trim();

    _photoUrl = (u['photoUrl'] ??
        u['photoURL'] ??
        u['profilePhotoUrl'] ??
        u['photo'] ??
        '')
        .toString()
        .trim();
  }

  // ✅ sadece aktif (24 saat geçmemiş) storyleri göster
  Stream<QuerySnapshot<Map<String, dynamic>>> _myItemsStream() {
    final now = Timestamp.now();
    return _itemsRef
        .where('expiresAt', isGreaterThan: now)
    // expiresAt her zaman dolu -> güvenli orderBy
        .orderBy('expiresAt', descending: true)
    // createdAt bazen null olabilir (serverTimestamp) -> orderBy kaldırıldı
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

      // 1) Upload
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putFile(file);
      final mediaUrl = await ref.getDownloadURL();

      // ✅ expiresAt: client + 24h (MVP)
      // (server time ile %100 yapmak istiyorsan Cloud Function ile set et)
      final expiresAt =
      Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24)));

      // ✅ createdAt: serverTimestamp + client backup
      await _itemsRef.doc(id).set({
        'id': id,
        'type': type, // 'image' | 'video'
        'mediaUrl': mediaUrl,
        'thumbUrl': type == 'image' ? mediaUrl : null,
        'storagePath': storagePath,

        // createdAt bazen null döner -> backup koyuyoruz
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Durumun'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: _saving
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.onPrimary,
              ),
            )
                : const Text('Bitti'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _addImage,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Foto ekle'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _addVideo,
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Video ekle'),
                  ),
                ),
              ],
            ),
          ),
          if ((_userName.isNotEmpty || _photoUrl.isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.surface,
                    backgroundImage:
                    _photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null,
                    child: _photoUrl.isEmpty
                        ? Icon(Icons.person,
                        color: cs.onSurface.withOpacity(0.70))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _userName.isEmpty ? 'Kullanıcı' : _userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _myItemsStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data?.docs ?? const [];

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'Henüz durum yok. Foto/video ekle.',
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.75),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final it = d.data();

                    final type = (it['type'] ?? '').toString().trim();
                    final mediaUrl =
                    (it['mediaUrl'] ?? it['url'] ?? '').toString();

                    final expiresAt = it['expiresAt'];
                    String ttlText = '';
                    if (expiresAt is Timestamp) {
                      final diff = expiresAt.toDate().difference(DateTime.now());
                      final h = diff.inHours;
                      final m = diff.inMinutes % 60;
                      if (diff.isNegative) {
                        ttlText = 'Süresi doldu';
                      } else {
                        ttlText = 'Kalan: ${h}sa ${m}dk';
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outline),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: cs.primary.withOpacity(0.10),
                            ),
                            child: Icon(
                              type == 'video'
                                  ? Icons.videocam_rounded
                                  : Icons.image_rounded,
                              color: cs.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  type == 'video' ? 'Video' : 'Fotoğraf',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  mediaUrl.isEmpty
                                      ? 'URL yok (bozuk item)'
                                      : 'Yüklendi',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withOpacity(0.65),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (ttlText.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    ttlText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withOpacity(0.60),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _saving ? null : () => _deleteItem(d),
                            icon: Icon(Icons.delete_outline, color: cs.error),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
