// lib/widgets/post_actions.dart
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PostActions {
  static String _chatIdOf(String a, String b) {
    final x = [a, b]..sort();
    return '${x[0]}_${x[1]}';
  }

  static Future<void> toggleLike(BuildContext context, String postId, bool isLiked) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final likeRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(u.uid);

    if (isLiked) {
      await likeRef.delete();
    } else {
      await likeRef.set({
        'userId': u.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static Future<void> toggleSave(BuildContext context, String postId, bool isSaved) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final fs = FirebaseFirestore.instance;

    final postSaveRef = fs.collection('posts').doc(postId).collection('saves').doc(u.uid);
    final userSaveRef = fs.collection('users').doc(u.uid).collection('savedPosts').doc(postId);

    if (isSaved) {
      await Future.wait([postSaveRef.delete(), userSaveRef.delete()]);
    } else {
      final now = FieldValue.serverTimestamp();
      await Future.wait([
        postSaveRef.set({'userId': u.uid, 'createdAt': now}),
        userSaveRef.set({'postId': postId, 'userId': u.uid, 'createdAt': now}),
      ]);
    }
  }

  static Future<void> openCommentsSheet(BuildContext context, String postId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(postId: postId),
    );
  }

  static Future<void> openSendSheet(
      BuildContext context, {
        required String postId,
        required String postText,
        required String? postImageUrl,
      }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SendPostSheet(
        postId: postId,
        postText: postText,
        postImageUrl: postImageUrl,
      ),
    );
  }

  static Future<void> _sendPostToChat({
    required String toUid,
    required String postId,
    required String postText,
    required String? postImageUrl,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final fs = FirebaseFirestore.instance;

    final chatId = _chatIdOf(me.uid, toUid);
    final chatRef = fs.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();

    final now = FieldValue.serverTimestamp();

    await fs.runTransaction((tx) async {
      final chatSnap = await tx.get(chatRef);

      if (!chatSnap.exists) {
        tx.set(chatRef, {
          'chatId': chatId,
          'participants': [me.uid, toUid],
          'createdAt': now,
          'updatedAt': now,
          'lastMessage': {
            'type': 'post',
            'text': (postText.trim().isEmpty) ? 'Paylaşım' : postText.trim(),
            'postId': postId,
          },
        });
      } else {
        tx.update(chatRef, {
          'updatedAt': now,
          'lastMessage': {
            'type': 'post',
            'text': (postText.trim().isEmpty) ? 'Paylaşım' : postText.trim(),
            'postId': postId,
          },
        });
      }

      tx.set(msgRef, {
        'id': msgRef.id,
        'type': 'post',
        'senderId': me.uid,
        'receiverId': toUid,
        'createdAt': now,

        // post payload (chatte render edeceksin)
        'post': {
          'postId': postId,
          'text': postText,
          'imageUrl': postImageUrl,
        },
      });
    });
  }
}

// ============================================================
// ✅ COMMENTS SHEET (posts/{postId}/comments)
// ============================================================

class _CommentsSheet extends StatefulWidget {
  final String postId;
  const _CommentsSheet({required this.postId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      final fs = FirebaseFirestore.instance;
      await fs
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .add({
        'userId': me.uid,
        'userName': me.displayName ?? 'Kullanıcı',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: Container(
            color: cs.surface.withOpacity(isDark ? 0.92 : 0.98),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'Yorumlar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, color: cs.onSurface.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('posts')
                        .doc(widget.postId)
                        .collection('comments')
                        .orderBy('createdAt', descending: true)
                        .limit(100)
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'İlk yorumu sen yaz.',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final d = docs[i].data();
                          final name = (d['userName'] ?? 'Kullanıcı').toString();
                          final text = (d['text'] ?? '').toString();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cs.outline.withOpacity(0.7)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  text,
                                  style: TextStyle(
                                    color: cs.onSurface.withOpacity(0.85),
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 8,
                    bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: cs.outline.withOpacity(0.7)),
                          ),
                          child: TextField(
                            controller: _ctrl,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Yorum yaz...',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _sending ? null : _send,
                        child: Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6E44FF), Color(0xFF00C4FF)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                blurRadius: 14,
                                offset: const Offset(0, 8),
                                color: Colors.black.withOpacity(isDark ? 0.30 : 0.12),
                              ),
                            ],
                          ),
                          child: _sending
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.send_rounded, color: Colors.white),
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
  }
}

// ============================================================
// ✅ SEND SHEET (connections/{uid}/list) + confirm + chat message
// - Görsel: attığın ekran gibi (ara bar + grid avatarlar)
// ============================================================

class _SendPostSheet extends StatefulWidget {
  final String postId;
  final String postText;
  final String? postImageUrl;

  const _SendPostSheet({
    required this.postId,
    required this.postText,
    required this.postImageUrl,
  });

  @override
  State<_SendPostSheet> createState() => _SendPostSheetState();
}

class _SendPostSheetState extends State<_SendPostSheet> {
  final _search = TextEditingController();
  String _q = '';
  bool _sending = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _connectionsStream(String uid) {
    return FirebaseFirestore.instance
        .collection('connections')
        .doc(uid)
        .collection('list')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<Map<String, dynamic>?> _getUser(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<void> _confirmAndSend(String toUid, String toName) async {
    if (_sending) return;

    final cs = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gönderilsin mi?'),
        content: Text('$toName kişisine bu gönderi yollansın mı?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Vazgeç', style: TextStyle(color: cs.onSurface.withOpacity(0.75))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _sending = true);
    try {
      await PostActions._sendPostToChat(
        toUid: toUid,
        postId: widget.postId,
        postText: widget.postText,
        postImageUrl: widget.postImageUrl,
      );

      if (!mounted) return;
      Navigator.pop(context); // sheet kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$toName kişisine gönderildi.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (me == null) {
      return const SizedBox.shrink();
    }

    final bg = cs.surface.withOpacity(isDark ? 0.94 : 0.98);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: Container(
            color: bg,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),

                // ✅ Search bar (attığın ekran gibi)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: cs.surfaceVariant.withOpacity(isDark ? 0.45 : 0.55),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: cs.outline.withOpacity(0.55)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded, color: cs.onSurface.withOpacity(0.65)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _search,
                                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Ara',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: cs.surfaceVariant.withOpacity(isDark ? 0.45 : 0.55),
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.outline.withOpacity(0.55)),
                        ),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close_rounded, color: cs.onSurface.withOpacity(0.75)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _connectionsStream(me.uid),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'Bağlantın yok.',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }

                      // docs: { otherUid, createdAt } gibi varsayıyorum.
                      final items = docs.map((d) {
                        final m = d.data();
                        final otherUid = (m['otherUid'] ?? m['uid'] ?? d.id).toString();
                        return otherUid.trim();
                      }).where((x) => x.isNotEmpty).toList();

                      return GridView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final uid = items[i];

                          return FutureBuilder<Map<String, dynamic>?>(
                            future: _getUser(uid),
                            builder: (context, us) {
                              final u = us.data ?? {};
                              final name = (u['name'] ?? u['username'] ?? 'Kullanıcı').toString();
                              final photoUrl = (u['photoUrl'] ?? '').toString().trim();

                              if (_q.isNotEmpty) {
                                final ok = name.toLowerCase().contains(_q);
                                if (!ok) return const SizedBox.shrink();
                              }

                              return InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: _sending ? null : () => _confirmAndSend(uid, name),
                                child: Column(
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          width: 74,
                                          height: 74,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: cs.surfaceVariant.withOpacity(isDark ? 0.35 : 0.55),
                                            border: Border.all(color: cs.outline.withOpacity(0.55)),
                                            image: (photoUrl.isNotEmpty)
                                                ? DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover)
                                                : null,
                                          ),
                                          child: (photoUrl.isEmpty)
                                              ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.75), size: 30)
                                              : null,
                                        ),
                                        if (_sending)
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.black.withOpacity(0.18),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
