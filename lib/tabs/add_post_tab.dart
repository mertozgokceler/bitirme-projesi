// lib/tabs/add_post_tab.dart

import 'dart:io';

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  // ✅ Storage upload helper
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

  // ✅ Edit sheet: text + image preview + pick image file
  void _openEditPostSheet(
      BuildContext context, {
        required String postId,
        required Map<String, dynamic> postData,
      }) {
    final theme = Theme.of(context);
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
    String currentImageUrl = oldImageUrl; // UI’da anlık güncelleme için

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

              // TIRT: boş post kaydetme.
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
              initialChildSize: 0.78,
              minChildSize: 0.50,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
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
                            color:
                            theme.colorScheme.onSurface.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: EdgeInsets.fromLTRB(
                              16,
                              10,
                              16,
                              16 + MediaQuery.of(context).viewInsets.bottom,
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

                              // ✅ Görsel önizleme (varsa)
                              if ((pickedImage != null) ||
                                  currentImageUrl.isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: pickedImage != null
                                        ? Image.file(
                                      pickedImage!,
                                      fit: BoxFit.cover,
                                    )
                                        : Image.network(
                                      currentImageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(
                                            color: theme
                                                .colorScheme.surfaceVariant,
                                            child: Center(
                                              child: Icon(
                                                Icons.broken_image_outlined,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: saving ? null : pickAndUpload,
                                        icon: const Icon(Icons.photo_library),
                                        label: const Text('Görseli Değiştir'),
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
                                // Görsel yoksa: ekle butonu
                                OutlinedButton.icon(
                                  onPressed: saving ? null : pickAndUpload,
                                  icon: const Icon(Icons.add_photo_alternate),
                                  label: const Text('Görsel Ekle'),
                                ),
                                const SizedBox(height: 14),
                              ],

                              TextField(
                                controller: textCtrl,
                                maxLines: 6,
                                minLines: 3,
                                textInputAction: TextInputAction.newline,
                                decoration: InputDecoration(
                                  labelText: 'Metin',
                                  hintText: 'Gönderi metnini güncelle...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
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
                                  onPressed:
                                  saving ? null : () => Navigator.pop(context),
                                  child: const Text('İptal'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  // ✅ EMPTY FEED (LOTTIE)
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
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Gönderiyi düzenlemek için üstüne dokun.\nSilmek için sağdan sola kaydır.',
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
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return Center(
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
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _postStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Gönderiler yüklenirken bir hata oluştu.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
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

            return Dismissible(
              key: ValueKey(docId),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onErrorContainer,
                  size: 26,
                ),
              ),
              confirmDismiss: (_) => _confirmDelete(context),
              onDismissed: (_) async {
                try {
                  await _deletePost(docId);
                  _snack('Gönderi silindi.');
                } catch (e) {
                  _snack('Silme başarısız: $e');
                }
              },
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openEditPostSheet(
                  context,
                  postId: docId,
                  postData: data,
                ),
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
                ),
              ),
            );
          },
        );
      },
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

  const _PostCard({
    required this.userName,
    required this.userTitle,
    required this.userAvatarUrl,
    required this.text,
    required this.imageUrl,
    required this.timeAgo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cardColor = theme.colorScheme.surface;
    final borderColor = theme.colorScheme.outlineVariant.withOpacity(0.45);
    final subtle = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundImage: userAvatarUrl != null
                      ? NetworkImage(userAvatarUrl!)
                      : null,
                  child: userAvatarUrl == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (userTitle.isNotEmpty)
                        Text(
                          userTitle,
                          style: TextStyle(color: subtle, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (timeAgo.isNotEmpty)
                  Text(
                    timeAgo,
                    style: TextStyle(color: subtle, fontSize: 12),
                  ),
              ],
            ),
          ),

          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),

          if (imageUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                              (progress.expectedTotalBytes ?? 1)
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _actionButton(context, Icons.thumb_up_alt_outlined, 'Beğen', () {
                  // TODO
                }),
                _actionButton(context, Icons.comment_outlined, 'Yorum Yap', () {
                  // TODO
                }),
                _actionButton(context, Icons.share_outlined, 'Paylaş', () {
                  // TODO
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
      BuildContext context,
      IconData icon,
      String label,
      VoidCallback onPressed,
      ) {
    final theme = Theme.of(context);
    final subtle = theme.colorScheme.onSurfaceVariant;

    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: subtle),
      label: Text(label, style: TextStyle(color: subtle)),
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
