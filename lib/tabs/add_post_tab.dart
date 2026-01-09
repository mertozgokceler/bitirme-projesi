// lib/tabs/add_post_tab.dart

import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';

class AddPostTab extends StatefulWidget {
  const AddPostTab({super.key});

  @override
  State<AddPostTab> createState() => _AddPostTabState();
}

class _AddPostTabState extends State<AddPostTab> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

  // ✅ Post expand state (postId bazlı)
  final Set<String> _expandedPostIds = <String>{};

  Stream<QuerySnapshot<Map<String, dynamic>>> _postStream() {
    final user = _auth.currentUser;

    if (user == null) {
      return _firestore
          .collection('posts')
          .where('userId', isEqualTo: '__no_user__')
          .snapshots();
    }

    return _firestore
        .collection('posts')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gönderi silinsin mi?'),
        content: const Text('Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deletePost(String postId) async {
    await _firestore.collection('posts').doc(postId).delete();
  }

  String _timeAgoFromCreatedAt(dynamic createdAt) {
    if (createdAt is! Timestamp) return '';
    final dt = createdAt.toDate();
    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return 'Şimdi';
    if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
    if (diff.inDays < 1) return '${diff.inHours} sa önce';

    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    return '$d.$m.$y';
  }

  Future<String> _uploadPostImage({
    required String uid,
    required String postId,
    required File file,
  }) async {
    final ext = file.path.split('.').last.toLowerCase();
    final safeExt = (ext.isEmpty || ext.length > 5) ? 'jpg' : ext;

    final ref = _storage
        .ref()
        .child('posts')
        .child(uid)
        .child(postId)
        .child('image_${DateTime.now().millisecondsSinceEpoch}.$safeExt');

    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/$safeExt'),
    );

    return await task.ref.getDownloadURL();
  }

  LinearGradient _bgGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0B1220),
          Color(0xFF0A1B2E),
          Color(0xFF081829),
        ],
      );
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFF6FAFF),
        Color(0xFFEFF6FF),
        Color(0xFFF9FBFF),
      ],
    );
  }

  void _openEditPostSheet(
      BuildContext context, {
        required String postId,
        required Map<String, dynamic> postData,
      }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      _snack('Giriş yok.');
      return;
    }

    final oldText = (postData['text'] as String? ?? '').trim();
    final oldImageUrl = (postData['imageUrl'] as String? ?? '').trim();

    final textCtrl = TextEditingController(text: oldText);

    File? pickedImage;
    bool saving = false;
    String currentImageUrl = oldImageUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickAndUpload() async {
              try {
                final x = await _picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                );
                if (x == null) return;

                setSheetState(() {
                  pickedImage = File(x.path);
                  saving = true;
                });

                final url = await _uploadPostImage(
                  uid: uid,
                  postId: postId,
                  file: pickedImage!,
                );

                await _firestore.collection('posts').doc(postId).update({
                  'imageUrl': url,
                  'updatedAt': FieldValue.serverTimestamp(),
                });

                setSheetState(() {
                  currentImageUrl = url;
                  saving = false;
                });

                _snack('Görsel güncellendi.');
              } catch (e) {
                setSheetState(() => saving = false);
                _snack('Görsel yükleme başarısız: $e');
              }
            }

            Future<void> removeImage() async {
              try {
                setSheetState(() => saving = true);

                await _firestore.collection('posts').doc(postId).update({
                  'imageUrl': FieldValue.delete(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });

                setSheetState(() {
                  currentImageUrl = '';
                  pickedImage = null;
                  saving = false;
                });

                _snack('Görsel kaldırıldı.');
              } catch (e) {
                setSheetState(() => saving = false);
                _snack('Görsel kaldırılamadı: $e');
              }
            }

            Future<void> saveTextOnly() async {
              final newText = textCtrl.text.trim();

              if (newText.isEmpty && currentImageUrl.isEmpty) {
                _snack('Metin boşsa görsel olmalı.');
                return;
              }

              try {
                setSheetState(() => saving = true);

                await _firestore.collection('posts').doc(postId).update({
                  'text': newText,
                  'updatedAt': FieldValue.serverTimestamp(),
                });

                if (mounted) Navigator.pop(context);
                _snack('Gönderi güncellendi.');
              } catch (e) {
                setSheetState(() => saving = false);
                _snack('Güncelleme başarısız: $e');
              }
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.80,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                final sheetFill =
                theme.colorScheme.surface.withOpacity(isDark ? 0.86 : 0.95);

                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: sheetFill,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant
                              .withOpacity(isDark ? 0.22 : 0.28),
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 30,
                            spreadRadius: 6,
                            color:
                            Colors.black.withOpacity(isDark ? 0.25 : 0.12),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: ListView(
                                controller: scrollController,
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  16 +
                                      MediaQuery.of(context)
                                          .viewInsets
                                          .bottom,
                                ),
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Gönderiyi Düzenle',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (saving)
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if ((pickedImage != null) ||
                                      currentImageUrl.isNotEmpty) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            pickedImage != null
                                                ? Image.file(pickedImage!,
                                                fit: BoxFit.cover)
                                                : Image.network(
                                              currentImageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                    color: theme.colorScheme
                                                        .surfaceVariant,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ),
                                            ),
                                            Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                  colors: [
                                                    Colors.black
                                                        .withOpacity(0.35),
                                                    Colors.transparent,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed:
                                            saving ? null : pickAndUpload,
                                            icon:
                                            const Icon(Icons.photo_library),
                                            label: const Text('Değiştir'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        OutlinedButton.icon(
                                          onPressed: saving ? null : removeImage,
                                          icon: const Icon(Icons.delete_outline),
                                          label: const Text('Kaldır'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                  ] else ...[
                                    OutlinedButton.icon(
                                      onPressed: saving ? null : pickAndUpload,
                                      icon: const Icon(Icons.add_photo_alternate),
                                      label: const Text('Görsel Ekle'),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  _GlassInput(
                                    child: TextField(
                                      controller: textCtrl,
                                      maxLines: 7,
                                      minLines: 3,
                                      textInputAction: TextInputAction.newline,
                                      decoration: InputDecoration(
                                        labelText: 'Metin',
                                        hintText:
                                        'Gönderi metnini güncelle...',
                                        border: OutlineInputBorder(
                                          borderRadius:
                                          BorderRadius.circular(14),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    height: 50,
                                    child: FilledButton(
                                      onPressed: saving ? null : saveTextOnly,
                                      child: const Text('Kaydet'),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 46,
                                    child: OutlinedButton(
                                      onPressed: saving
                                          ? null
                                          : () => Navigator.pop(context),
                                      child: const Text('İptal'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyFeed(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Transform.translate(
          offset: const Offset(0, -70),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 240,
                height: 240,
                child: Lottie.asset(
                  'assets/lottie/empty_feed.json',
                  repeat: true,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Henüz bir gönderi paylaşmadın',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tamamını görmek için gönderiye dokun.\nSil: sola kaydır • Düzenle: sağa kaydır',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: isDark
                      ? theme.colorScheme.onSurface.withOpacity(0.60)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
          Positioned(
            top: -120,
            left: -80,
            child: _GlowBlob(size: 260, color: cs.primary.withOpacity(0.20)),
          ),
          Positioned(
            bottom: -140,
            right: -90,
            child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Gönderilerini görmek için giriş yapmalısın.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? theme.colorScheme.onSurface.withOpacity(0.70)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
        Positioned(
          top: -120,
          left: -80,
          child: _GlowBlob(size: 260, color: cs.primary.withOpacity(0.20)),
        ),
        Positioned(
          bottom: -140,
          right: -90,
          child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18)),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _postStream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Gönderiler yüklenirken bir hata oluştu.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyFeed(context);
            }

            final docs = snapshot.data!.docs;

            return ListView.builder(
              // ✅ üstten daha fazla boşluk
              padding: const EdgeInsets.fromLTRB(16, 44, 16, 96),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();
                final docId = doc.id;

                final userName =
                (data['userName'] as String?)?.trim().isNotEmpty == true
                    ? (data['userName'] as String).trim()
                    : 'Bilinmeyen Kullanıcı';

                final userTitle = (data['userTitle'] as String? ?? '').trim();
                final userAvatarUrl = (data['userAvatarUrl'] as String?)?.trim();
                final text = (data['text'] as String? ?? '').trim();
                final imageUrl = (data['imageUrl'] as String?)?.trim();
                final timeAgo = _timeAgoFromCreatedAt(data['createdAt']);

                final isExpanded = _expandedPostIds.contains(docId);

                return Dismissible(
                  key: ValueKey(docId),
                  direction: DismissDirection.horizontal,

                  // ✅ SAĞA KAYDIR -> DÜZENLE
                  background: _EditSwipeBackground(),

                  // ✅ SOLA KAYDIR -> SİL
                  secondaryBackground: _DeleteSwipeBackground(),

                  confirmDismiss: (direction) async {
                    // Sağ -> düzenle (dismiss etme, sheet aç)
                    if (direction == DismissDirection.startToEnd) {
                      _openEditPostSheet(
                        context,
                        postId: docId,
                        postData: data,
                      );
                      return false;
                    }

                    // Sol -> sil
                    if (direction == DismissDirection.endToStart) {
                      final ok = await _confirmDelete(context);
                      return ok;
                    }

                    return false;
                  },

                  onDismissed: (direction) async {
                    if (direction != DismissDirection.endToStart) return;

                    try {
                      await _deletePost(docId);
                      _expandedPostIds.remove(docId);
                      _snack('Gönderi silindi.');
                    } catch (e) {
                      _snack('Silme başarısız: $e');
                    }
                  },

                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    // ✅ TAP -> expand/collapse
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedPostIds.remove(docId);
                        } else {
                          _expandedPostIds.add(docId);
                        }
                      });
                    },
                    child: _PostCard(
                      userName: userName,
                      userTitle: userTitle,
                      userAvatarUrl:
                      (userAvatarUrl != null && userAvatarUrl.isNotEmpty)
                          ? userAvatarUrl
                          : null,
                      text: text,
                      imageUrl: (imageUrl != null && imageUrl.isNotEmpty)
                          ? imageUrl
                          : null,
                      timeAgo: timeAgo,
                      isExpanded: isExpanded,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  final String userName;
  final String userTitle;
  final String? userAvatarUrl;
  final String text;
  final String? imageUrl;
  final String timeAgo;
  final bool isExpanded;

  const _PostCard({
    required this.userName,
    required this.userTitle,
    required this.userAvatarUrl,
    required this.text,
    required this.imageUrl,
    required this.timeAgo,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    final fill =
    isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.72);
    final border =
    isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08);

    final hasText = text.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 0.9),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            spreadRadius: 3,
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Row(
                children: [
                  _Avatar(
                    url: userAvatarUrl,
                    fallbackText: userName,
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (userTitle.isNotEmpty)
                          Text(
                            userTitle,
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.65),
                              fontSize: 12,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (timeAgo.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant
                            .withOpacity(isDark ? 0.18 : 0.65),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        timeAgo,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // text (collapsed/expanded)
            if (hasText)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      maxLines: isExpanded ? null : 3,
                      overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                    if (!isExpanded)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Devamını görmek için dokun',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: cs.primary.withOpacity(0.85),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.expand_more,
                              size: 18,
                              color: cs.primary.withOpacity(0.85),
                            ),
                          ],
                        ),
                      ),
                    if (isExpanded)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Kapatmak için dokun',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: cs.primary.withOpacity(0.75),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.expand_less,
                              size: 18,
                              color: cs.primary.withOpacity(0.75),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

            // image
            if (imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(0),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded /
                                  (progress.expectedTotalBytes ?? 1)
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

            // glow line
            Container(
              height: 2,
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.55),
                    cs.tertiary.withOpacity(0.30),
                    Colors.transparent,
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

class _Avatar extends StatelessWidget {
  final String? url;
  final String fallbackText;
  final double size;

  const _Avatar({
    required this.url,
    required this.fallbackText,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final border =
    isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.08);

    final initial = fallbackText.trim().isNotEmpty
        ? fallbackText.trim().characters.first.toUpperCase()
        : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(context, initial),
      )
          : _fallback(context, initial),
    );
  }

  Widget _fallback(BuildContext context, String initial) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.primary.withOpacity(0.35),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _DeleteSwipeBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.colorScheme.error.withOpacity(isDark ? 0.12 : 0.10),
            theme.colorScheme.error.withOpacity(isDark ? 0.25 : 0.18),
            theme.colorScheme.error.withOpacity(isDark ? 0.45 : 0.30),
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.error.withOpacity(0.25),
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.delete_outline, color: theme.colorScheme.onError, size: 26),
          const SizedBox(width: 8),
          Text(
            'Sil',
            style: TextStyle(
              color: theme.colorScheme.onError,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditSwipeBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final c1 = theme.colorScheme.primary.withOpacity(isDark ? 0.14 : 0.10);
    final c2 = theme.colorScheme.primary.withOpacity(isDark ? 0.30 : 0.22);
    final c3 = theme.colorScheme.tertiary.withOpacity(isDark ? 0.26 : 0.18);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [c1, c2, c3],
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.25),
        ),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Icon(Icons.edit_outlined, color: theme.colorScheme.onSurface, size: 26),
          const SizedBox(width: 8),
          Text(
            'Düzenle',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassInput extends StatelessWidget {
  final Widget child;
  const _GlassInput({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fill =
    theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.16 : 0.55);
    final border =
    theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.25 : 0.35);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(10),
      child: child,
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
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}
