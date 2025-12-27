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
  List<Map<String, dynamic>> _items = [];

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final u = userDoc.data() ?? {};
    _userName = (u['name'] ?? u['username'] ?? 'Kullanıcı').toString();
    _photoUrl = (u['photoUrl'] ?? '').toString();

    final storyDoc = await FirebaseFirestore.instance.collection('stories').doc(uid).get();
    final s = storyDoc.data() ?? {};
    final items = (s['items'] is List) ? List<Map<String, dynamic>>.from(s['items']) : <Map<String, dynamic>>[];

    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _addImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    await _uploadAndAppend(File(x.path), type: 'image');
  }

  Future<void> _addVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
    if (x == null) return;
    await _uploadAndAppend(File(x.path), type: 'video');
  }

  Future<void> _uploadAndAppend(File file, {required String type}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      final id = const Uuid().v4();
      final ext = (type == 'video') ? 'mp4' : 'jpg';
      final path = 'stories/$uid/$id.$ext';

      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      final now = Timestamp.now();

      setState(() {
        _items.insert(0, {
          'id': id,
          'type': type,
          'url': url,
          'createdAt': now,
        });
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      final now = FieldValue.serverTimestamp();
      // 24 saat
      final expires = Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24)));

      await FirebaseFirestore.instance.collection('stories').doc(uid).set({
        'uid': uid,
        'userName': _userName,
        'userPhotoUrl': _photoUrl,
        'items': _items,
        'updatedAt': now,
        'expiresAt': expires,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Durum güncellendi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydetme hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(int index) async {
    setState(() => _items.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Durumun'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                : const Text('Kaydet'),
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

          Expanded(
            child: _items.isEmpty
                ? Center(
              child: Text(
                'Henüz durum yok. Foto/video ekle.',
                style: TextStyle(color: cs.onSurface.withOpacity(0.75), fontWeight: FontWeight.w700),
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final it = _items[i];
                final type = (it['type'] ?? '').toString();
                final url = (it['url'] ?? '').toString();

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
                          type == 'video' ? Icons.videocam_rounded : Icons.image_rounded,
                          color: cs.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          type == 'video' ? 'Video' : 'Fotoğraf',
                          style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                        ),
                      ),
                      IconButton(
                        onPressed: _saving ? null : () => _delete(i),
                        icon: Icon(Icons.delete_outline, color: cs.error),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
