// lib/tabs/home_tab.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:flutter/rendering.dart';


import '../screens/news_detail_screen.dart';
import '../screens/news_list_screen.dart';
import '../utils/premium_utils.dart';
import '../widgets/job_details_sheet.dart';
import '../widgets/stories_strip.dart';

// ✅ fallback navigation için
import '../tabs/search_tab.dart';
import '../screens/chat_list_screen.dart';
import '../services/call_service.dart';


const String kLogoPath = 'assets/images/techconnectlogo.png';
const String kMessageIconPath = 'assets/icons/send_light.png';

// ============================================================
// ✅ GLASS HELPERS (JobsTab ile aynı hissiyat)
// ============================================================

class _Glass {
  static Color fill(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.72);
  }

  static Color border(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08);
  }

  static List<BoxShadow> shadow(ThemeData t, {double blur = 22, double spread = 3}) {
    final isDark = t.brightness == Brightness.dark;
    return [
      BoxShadow(
        blurRadius: blur,
        spreadRadius: spread,
        color: Colors.black.withOpacity(isDark ? 0.22 : 0.10),
        offset: const Offset(0, 10),
      ),
    ];
  }

  static BoxDecoration deco(
      ThemeData t, {
        double radius = 22,
        double borderWidth = 0.9,
        double blur = 22,
        double spread = 3,
      }) {
    return BoxDecoration(
      color: fill(t),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border(t), width: borderWidth),
      boxShadow: shadow(t, blur: blur, spread: spread),
    );
  }

  static BoxDecoration pill(ThemeData t, {double radius = 999}) {
    final isDark = t.brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08),
      ),
    );
  }
}

// ============================================================
// ✅ POST ACTIONS + SHEETS (LIKE / COMMENT / SEND TO CHAT)
// ============================================================

class PostActions {
  static String _chatIdOf(String a, String b) {
    final x = [a, b]..sort();
    return '${x[0]}_${x[1]}';
  }

  static Future<void> toggleLike(BuildContext context, String postId, bool isLiked) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beğenmek için giriş yapmalısın.')),
      );
      return;
    }

    final likeRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(u.uid);

    try {
      if (isLiked) {
        await likeRef.delete();
      } else {
        await likeRef.set({
          'userId': u.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beğeni işlemi sırasında hata: $e')),
      );
    }
  }

  static Future<void> toggleSave(BuildContext context, String postId, bool isSaved) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydetmek için giriş yapmalısın.')),
      );
      return;
    }

    final fs = FirebaseFirestore.instance;
    final postSaveRef = fs.collection('posts').doc(postId).collection('saves').doc(u.uid);
    final userSaveRef = fs.collection('users').doc(u.uid).collection('savedPosts').doc(postId);

    try {
      if (isSaved) {
        await Future.wait([postSaveRef.delete(), userSaveRef.delete()]);
      } else {
        final now = FieldValue.serverTimestamp();
        await Future.wait([
          postSaveRef.set({'userId': u.uid, 'createdAt': now}),
          userSaveRef.set({'postId': postId, 'userId': u.uid, 'createdAt': now}),
        ]);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme işlemi sırasında hata: $e')),
      );
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

      final lastText = (postText.trim().isEmpty) ? 'Paylaşım' : postText.trim();

      if (!chatSnap.exists) {
        tx.set(chatRef, {
          'chatId': chatId,
          'participants': [me.uid, toUid],
          'createdAt': now,
          'updatedAt': now,
          'lastMessage': {
            'type': 'post',
            'text': lastText,
            'postId': postId,
          },
        });
      } else {
        tx.update(chatRef, {
          'updatedAt': now,
          'lastMessage': {
            'type': 'post',
            'text': lastText,
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
        'post': {
          'postId': postId,
          'text': postText,
          'imageUrl': postImageUrl,
        },
      });
    });
  }
}

class _CommentsSheet extends StatefulWidget {
  final String postId;
  const _CommentsSheet({required this.postId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  String _meName = 'Kullanıcı';
  String _meUsername = '';
  String _mePhotoUrl = '';

  Timer? _debounce;
  bool _showMention = false;
  String _mentionQuery = '';
  List<Map<String, dynamic>> _mentionResults = [];
  bool _mentionLoading = false;
  int _mentionStartIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadMe();
    _ctrl.addListener(_handleMentionTyping);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(me.uid).get();
      final m = doc.data() ?? {};

      if (!mounted) return;
      setState(() {
        _meName = (m['name'] ?? m['username'] ?? me.email ?? 'Kullanıcı').toString().trim();
        _meUsername = (m['username'] ?? '').toString().trim();
        _mePhotoUrl = (m['photoUrl'] ?? '').toString().trim();
      });
    } catch (_) {}
  }

  void _handleMentionTyping() {
    final text = _ctrl.text;
    final sel = _ctrl.selection;

    if (!sel.isValid) {
      _hideMention();
      return;
    }

    final cursor = sel.baseOffset;
    if (cursor <= 0 || cursor > text.length) {
      _hideMention();
      return;
    }

    final before = text.substring(0, cursor);

    final at = before.lastIndexOf('@');
    if (at == -1) {
      _hideMention();
      return;
    }

    if (at > 0) {
      final prev = before[at - 1];
      final okPrev = prev == ' ' || prev == '\n' || prev == '\t' || prev == '\r';
      if (!okPrev) {
        _hideMention();
        return;
      }
    }

    final afterAtRaw = before.substring(at + 1);
    if (afterAtRaw.contains(RegExp(r'\s'))) {
      _hideMention();
      return;
    }

    final q = afterAtRaw.trim().toLowerCase();
    _mentionStartIndex = at;

    if (q.isEmpty) {
      _debounce?.cancel();
      _hideMention();
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      if (!mounted) return;

      setState(() {
        _mentionQuery = q;
        _showMention = true;
        _mentionLoading = true;
      });

      final results = await _searchMentions(q);

      if (!mounted) return;
      setState(() {
        _mentionResults = results;
        _mentionLoading = false;
        _showMention = true;
      });
    });
  }

  void _hideMention() {
    if (!_showMention && _mentionResults.isEmpty && !_mentionLoading) return;
    setState(() {
      _showMention = false;
      _mentionQuery = '';
      _mentionResults = [];
      _mentionLoading = false;
      _mentionStartIndex = -1;
    });
  }

  Future<List<Map<String, dynamic>>> _searchMentions(String q) async {
    final fs = FirebaseFirestore.instance;

    try {
      if (q.isEmpty) return [];

      final end = '$q\uf8ff';
      final snap = await fs
          .collection('users')
          .orderBy('usernameLower')
          .startAt([q])
          .endAt([end])
          .limit(8)
          .get();

      final out = snap.docs.map((d) {
        final m = d.data();
        return {
          'uid': d.id,
          'username': (m['username'] ?? '').toString(),
          'name': (m['name'] ?? '').toString(),
          'photoUrl': (m['photoUrl'] ?? '').toString(),
        };
      }).where((x) => (x['username'] as String).trim().isNotEmpty).toList();

      return out;
    } catch (_) {
      return [];
    }
  }

  void _insertMention(Map<String, dynamic> u) {
    final username = (u['username'] ?? '').toString().trim();
    if (username.isEmpty) return;

    final text = _ctrl.text;
    final sel = _ctrl.selection;
    final cursor = sel.isValid ? sel.baseOffset : text.length;

    final start = (_mentionStartIndex >= 0) ? _mentionStartIndex : text.lastIndexOf('@');
    if (start < 0 || start > text.length) return;

    final left = text.substring(0, start);
    final right = text.substring(cursor.clamp(0, text.length));

    final inserted = '@$username ';
    final newText = '$left$inserted$right';
    final newCursor = (left.length + inserted.length).clamp(0, newText.length);

    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );

    _hideMention();
  }

  Future<void> _send() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      final fs = FirebaseFirestore.instance;

      final mentionUsernames = <String>{};
      final re = RegExp(r'(^|[\s])@([A-Za-z0-9_\.]{2,32})');
      for (final m in re.allMatches(' $text')) {
        final uname = (m.group(2) ?? '').trim();
        if (uname.isNotEmpty) mentionUsernames.add(uname);
      }

      await fs.collection('posts').doc(widget.postId).collection('comments').add({
        'userId': me.uid,
        'userName': _meName,
        'username': _meUsername,
        'userPhotoUrl': _mePhotoUrl,
        'text': text,
        'mentions': mentionUsernames.toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      _ctrl.clear();
      _hideMention();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.48,
      maxChildSize: 0.96,
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
                        .limit(200)
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final d = docs[i].data();

                          final name = (d['userName'] ?? 'Kullanıcı').toString().trim();
                          final username = (d['username'] ?? '').toString().trim();
                          final photo = (d['userPhotoUrl'] ?? '').toString().trim();
                          final text = (d['text'] ?? '').toString();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: _Glass.deco(t, radius: 16, blur: 18, spread: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: cs.surfaceVariant.withOpacity(isDark ? 0.35 : 0.60),
                                      backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                                      child: photo.isEmpty
                                          ? Icon(Icons.person, size: 16, color: cs.onSurface.withOpacity(0.75))
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          if (username.isNotEmpty)
                                            Text(
                                              '@$username',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: cs.onSurface.withOpacity(0.55),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _CommentText(text: text),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_showMention)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: _Glass.deco(t, radius: 16, blur: 18, spread: 2),
                          child: _mentionLoading
                              ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Etiket aranıyor...',
                                  style: TextStyle(
                                    color: cs.onSurface.withOpacity(0.78),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          )
                              : (_mentionResults.isEmpty
                              ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _mentionQuery.isEmpty
                                  ? 'Etiketlemek için @ yazıp devam et.'
                                  : 'Sonuç yok.',
                              style: TextStyle(
                                color: cs.onSurface.withOpacity(0.70),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                              : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                            itemCount: _mentionResults.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final u = _mentionResults[i];
                              final name = (u['name'] ?? '').toString().trim();
                              final username = (u['username'] ?? '').toString().trim();
                              final photoUrl = (u['photoUrl'] ?? '').toString().trim();

                              return InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _insertMention(u),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: _Glass.deco(t, radius: 14, blur: 14, spread: 1),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: cs.surface,
                                        backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                                        child: (photoUrl.isEmpty)
                                            ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.75), size: 18)
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '@$username',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                            if (name.isNotEmpty)
                                              Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: cs.onSurface.withOpacity(0.70),
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.call_made_rounded, size: 18, color: cs.primary.withOpacity(0.85)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: _Glass.pill(t),
                              child: TextField(
                                controller: _ctrl,
                                minLines: 1,
                                maxLines: 3,
                                onTap: () {
                                  Future.microtask(() {
                                    if (!mounted) return;
                                    _handleMentionTyping();
                                  });
                                },
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
      Navigator.pop(context);
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
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    if (me == null) return const SizedBox.shrink();

    final bg = cs.surface.withOpacity(isDark ? 0.94 : 0.98);

    return DraggableScrollableSheet(
      initialChildSize: 0.74,
      minChildSize: 0.48,
      maxChildSize: 0.96,
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: _Glass.deco(t, radius: 18, blur: 16, spread: 2),
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
                        decoration: _Glass.deco(t, radius: 999, blur: 16, spread: 2),
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

                      final items = docs
                          .map((d) {
                        final m = d.data();
                        final otherUid = (m['otherUid'] ?? m['uid'] ?? d.id).toString().trim();
                        return otherUid;
                      })
                          .where((x) => x.isNotEmpty)
                          .toList();

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
                                            color: _Glass.fill(t),
                                            border: Border.all(color: _Glass.border(t), width: 0.9),
                                            boxShadow: _Glass.shadow(t, blur: 18, spread: 2),
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

class HomeTab extends StatefulWidget {
  final VoidCallback onGoToSearchTab;
  final VoidCallback onGoToMessages;

  // ✅ EKLE
  final CallService callService;

  const HomeTab({
    super.key,
    required this.onGoToSearchTab,
    required this.onGoToMessages,
    required this.callService, // ✅ EKLE
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String _firstName = '';
  String? _userPhotoUrl;
  bool _isLoadingUserData = true;
  String _motivationQuote = '';

  Map<String, dynamic> _currentUserMap = {};

  List<dynamic> _newsArticles = [];
  bool _isLoadingNews = true;
  bool _isSuggestionsExpanded = true;

  final String _newsApiKey = dotenv.env['GNEWS_API_KEY'] ?? '';

  final Set<String> _expandedPostIds = <String>{};

  final ScrollController _scrollCtrl = ScrollController();
  final Map<String, GlobalKey> _postKeys = {};


  bool _isPostExpanded(String postId) => _expandedPostIds.contains(postId);

  Future<Map<String, Map<String, dynamic>>>? _jobsFuture;
  String _jobsKey = '';
  String _lastCleanupKey = '';

  Future<Map<String, Map<String, dynamic>>>? _companiesFuture;
  String _companiesKey = '';

  @override
  void initState() {
    super.initState();
    _loadMotivationQuote();
    _fetchUserData();
    _fetchTechNews();
  }

  void _togglePostExpanded(String postId) {
    setState(() {
      if (_expandedPostIds.contains(postId)) {
        _expandedPostIds.remove(postId);
      } else {
        _expandedPostIds.add(postId);
      }
    });
  }

  void _openJobDetailSheetFromHome(
      BuildContext context,
      String jobId,
      Map<String, dynamic> job,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JobDetailsSheet(jobId: jobId, job: job),
    );
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

  Future<void> _togglePostExpandedAnchored(String postId) async {
    final key = _postKeys[postId];
    if (key == null) {
      _togglePostExpanded(postId);
      return;
    }

    final ctx = key.currentContext;
    if (ctx == null || !_scrollCtrl.hasClients) {
      _togglePostExpanded(postId);
      return;
    }

    final ro = ctx.findRenderObject();
    if (ro == null) {
      _togglePostExpanded(postId);
      return;
    }

    // ✅ Scroll offset bazlı ölçüm (doğru yöntem)
    double before = _scrollCtrl.offset;
    final vp1 = RenderAbstractViewport.of(ro);
    if (vp1 != null) {
      before = vp1.getOffsetToReveal(ro, 0.0).offset;
    }

    _togglePostExpanded(postId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx2 = key.currentContext;
      if (ctx2 == null || !_scrollCtrl.hasClients) return;

      final ro2 = ctx2.findRenderObject();
      if (ro2 == null) return;

      final vp2 = RenderAbstractViewport.of(ro2);
      if (vp2 == null) return;

      final after = vp2.getOffsetToReveal(ro2, 0.0).offset;

      final delta = after - before;

      final target = (_scrollCtrl.offset + delta).clamp(
        _scrollCtrl.position.minScrollExtent,
        _scrollCtrl.position.maxScrollExtent,
      );

      _scrollCtrl.jumpTo(target);
    });
  }


  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingUserData = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!mounted) return;

      if (doc.exists) {
        final userData = doc.data() ?? {};
        setState(() {
          _currentUserMap = Map<String, dynamic>.from(userData);

          _firstName = (userData['name'] as String?)?.split(' ').first ?? 'Kullanıcı';
          _userPhotoUrl = userData['photoUrl'] as String?;
          _isLoadingUserData = false;
        });
      } else {
        setState(() => _isLoadingUserData = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUserData = false);
    }
  }

  void _goToSearchTab() {
    final cb = widget.onGoToSearchTab;
    if (cb != null) {
      cb();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchTab()));
  }

  void _goToMessages() {
    final VoidCallback? cb = widget.onGoToMessages;
    if (cb != null) {
      cb();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatListScreen(callService: widget.callService),
      ),
    );
  }


  Widget _buildHeroHeader(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final mq = MediaQuery.of(context);
    final h = mq.size.height;

    final headerH = h < 740 ? 190.0 : 212.0;

    final fullName = (_currentUserMap['name'] ?? '').toString().trim();
    final bool isPremium = isPremiumActiveFromUserDoc(_currentUserMap);

    String firstName = 'Kullanıcı';
    String lastName = '';

    if (fullName.isNotEmpty) {
      final parts = fullName.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      firstName = parts.isNotEmpty ? parts.first : 'Kullanıcı';
      lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    } else if (_firstName.isNotEmpty) {
      firstName = _firstName;
    }

    return SizedBox(
      height: headerH,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6E44FF), Color(0xFF00C4FF)],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(34),
                  bottomRight: Radius.circular(34),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.30 : 0.16),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -90,
            left: -60,
            child: _GlowBlob(size: 240, color: Colors.white.withOpacity(0.14)),
          ),
          Positioned(
            bottom: -110,
            right: -80,
            child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18)),
          ),
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: Image.asset(
                            isPremium ? 'assets/images/techconnect_logo_gold.png' : kLogoPath,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: GestureDetector(
                            onTap: _goToSearchTab,
                            child: Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.92), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Kullanıcı veya şirket ara',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.86),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: GestureDetector(
                            onTap: _goToMessages,
                            child: Image.asset(
                              kMessageIconPath,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(isPremium ? 3 : 0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: isPremium ? Border.all(color: const Color(0xFFEFBF04), width: 3) : null,
                            ),
                            child: CircleAvatar(
                              radius: h < 740 ? 30 : 34,
                              backgroundColor: Colors.white.withOpacity(0.18),
                              backgroundImage: _userPhotoUrl != null ? NetworkImage(_userPhotoUrl!) : null,
                              child: _userPhotoUrl == null ? const Icon(Icons.person, color: Colors.white, size: 30) : null,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Hoş geldin,',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.88),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.2,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: Lottie.asset(
                                        'assets/lottie/hello.json',
                                        repeat: true,
                                        animate: true,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lastName.isNotEmpty ? '$firstName $lastName' : firstName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 26,
                                    height: 1.0,
                                  ),
                                ),
                              ],
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
        ],
      ),
    );
  }

  Widget _buildStoriesSection() {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _Glass.deco(t, radius: 22, blur: 18, spread: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Hikayeler',
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),

              // ✅ Mini info chip (premium hissiyat)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      backgroundColor: cs.surface.withOpacity(0.96),
                      content: Text(
                        'Profil resmine uzun basarak hikaye ekleme ve düzenleme alanına gidebilirsin.',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.90),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: _Glass.pill(t),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Bilgi',
                        style: TextStyle(
                          fontSize: 12.2,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface.withOpacity(0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const StoriesStrip(),
        ],
      ),
    );
  }

  Future<void> _loadMotivationQuote() async {
    try {
      final raw = await rootBundle.loadString('assets/data/motivations.txt');
      final lines = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (lines.isEmpty) return;

      final random = Random();
      final pick = lines[random.nextInt(lines.length)];
      if (mounted) setState(() => _motivationQuote = pick);
    } catch (e) {
      debugPrint('Motivation load error: $e');
    }
  }

  Future<void> _fetchTechNews() async {
    debugPrint('GNEWS_API_KEY: $_newsApiKey');
    if (_newsApiKey.isEmpty) {
      debugPrint('HATA: GNEWS_API_KEY .env dosyasında bulunamadı.');
      if (mounted) setState(() => _isLoadingNews = false);
      return;
    }

    if (mounted) setState(() => _isLoadingNews = true);

    try {
      final url = Uri.parse(
        'https://gnews.io/api/v4/top-headlines'
            '?category=technology'
            '&lang=tr'
            '&country=tr'
            '&max=20'
            '&token=$_newsApiKey',
      );

      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _newsArticles = data['articles'] ?? [];
          _isLoadingNews = false;
        });
      } else {
        debugPrint('GNews Haber API Hatası: ${response.statusCode}');
        setState(() {
          _newsArticles = [];
          _isLoadingNews = false;
        });
      }
    } catch (e) {
      debugPrint('GNews Haber Çekme Hatası: $e');
      if (mounted) {
        setState(() {
          _newsArticles = [];
          _isLoadingNews = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    await _fetchUserData();
    await _fetchTechNews();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _postStream() {
    return FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _topMatchStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('userMatches')
        .doc(user.uid)
        .collection('matches')
        .where('score', isGreaterThanOrEqualTo: 40)
        .orderBy('score', descending: true)
        .limit(10)
        .snapshots();
  }

  String _formatTime(dynamic ts) {
    if (ts is! Timestamp) return '';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return 'Şimdi';
    if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  Future<Map<String, Map<String, dynamic>>> _fetchJobsByIds(List<String> jobIds) async {
    final cleaned = jobIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (cleaned.isEmpty) return {};

    final out = <String, Map<String, dynamic>>{};
    const chunkSize = 30;

    for (var i = 0; i < cleaned.length; i += chunkSize) {
      final chunk = cleaned.sublist(i, (i + chunkSize).clamp(0, cleaned.length));
      final qs = await FirebaseFirestore.instance
          .collection('jobs')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final d in qs.docs) {
        out[d.id] = {
          ...d.data(),
          'id': d.id,
          'jobId': d.id,
        };
      }
    }
    return out;
  }

  void _ensureJobsFuture(List<String> jobIds) {
    final ids = jobIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList()..sort();
    final newKey = ids.join('|');

    if (_jobsFuture == null || newKey != _jobsKey) {
      _jobsKey = newKey;
      _jobsFuture = _fetchJobsByIds(ids);
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchCompaniesByIds(List<String> uids) async {
    final cleaned = uids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (cleaned.isEmpty) return {};

    final out = <String, Map<String, dynamic>>{};
    const chunkSize = 30;

    for (var i = 0; i < cleaned.length; i += chunkSize) {
      final chunk = cleaned.sublist(i, (i + chunkSize).clamp(0, cleaned.length));
      final qs = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final d in qs.docs) {
        out[d.id] = d.data();
      }
    }
    return out;
  }

  void _ensureCompaniesFuture(List<String> companyIds) {
    final ids = companyIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList()..sort();
    final newKey = ids.join('|');

    if (_companiesFuture == null || newKey != _companiesKey) {
      _companiesKey = newKey;
      _companiesFuture = _fetchCompaniesByIds(ids);
    }
  }

  Future<void> _deleteStaleMatches(String uid, List<String> matchDocIds) async {
    if (matchDocIds.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final baseRef = FirebaseFirestore.instance.collection('userMatches').doc(uid).collection('matches');

    for (final id in matchDocIds) {
      batch.delete(baseRef.doc(id));
    }
    await batch.commit();
  }

  void _scheduleCleanupIfNeeded(String uid, List<String> staleDocIds) {
    if (staleDocIds.isEmpty) return;

    final ids = List<String>.from(staleDocIds)..sort();
    final cleanupKey = ids.join('|');

    if (cleanupKey == _lastCleanupKey) return;
    _lastCleanupKey = cleanupKey;

    Future.microtask(() async {
      try {
        await _deleteStaleMatches(uid, ids);
      } catch (e) {
        debugPrint('Cleanup error: $e');
      }
    });
  }

  String _extractJobId(Map<String, dynamic> m) {
    final direct = (m['jobId'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    if (m['jobSnapshot'] is Map) {
      final job = Map<String, dynamic>.from(m['jobSnapshot']);
      final fromSnap1 = (job['jobId'] ?? '').toString().trim();
      if (fromSnap1.isNotEmpty) return fromSnap1;

      final fromSnap2 = (job['id'] ?? '').toString().trim();
      if (fromSnap2.isNotEmpty) return fromSnap2;
    }

    return '';
  }

  bool _workModelEligible(Map<String, dynamic> user, Map<String, dynamic> job) {
    final wm = (job['workModel'] ?? '').toString().trim().toLowerCase();
    if (wm.isEmpty) return true;

    final prefs = (user['workModelPrefs'] is Map) ? Map<String, dynamic>.from(user['workModelPrefs']) : <String, dynamic>{};

    final r = prefs['remote'] == true;
    final h = prefs['hybrid'] == true;
    final o = prefs['on-site'] == true;

    if (wm == 'remote') return r;
    if (wm == 'hybrid') return h;
    if (wm == 'on-site') return o;
    return false;
  }

  int? _levelRank(String s) {
    final x = s.trim().toLowerCase();
    if (x == 'intern') return 0;
    if (x == 'junior') return 1;
    if (x == 'mid') return 2;
    if (x == 'senior') return 3;
    return null;
  }

  bool _levelEligible(Map<String, dynamic> user, Map<String, dynamic> job) {
    final u = _levelRank((user['level'] ?? user['seniority'] ?? '').toString());
    final j = _levelRank((job['level'] ?? '').toString());

    if (j == null) return true;
    if (u == null) return true;
    return u >= j;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUserData) {
      return Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
        SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroHeader(context),
                  Transform.translate(
                    offset: const Offset(0, 20),
                    child: Column(
                      children: [
                        _buildSuggestionSection(),
                        const SizedBox(height: 10),
                        _buildMotivationBubble(context),
                        const SizedBox(height: 10),
                        _buildNewsSection(),
                        const SizedBox(height: 20),
                        _buildStoriesSection(),
                        const SizedBox(height: 10),
                        _buildFeedFromPosts(),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ================== SANA ÖZEL EŞLEŞMELER ==================
  Widget _buildSuggestionSection() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _Glass.deco(theme, radius: 26, blur: 22, spread: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sana Özel Eşleşmeler',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _isSuggestionsExpanded = !_isSuggestionsExpanded),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isSuggestionsExpanded ? 'Gizle' : 'Göster',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isSuggestionsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: cs.onSurface,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _isSuggestionsExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            secondChild: const SizedBox.shrink(),
            firstChild: SizedBox(
              height: 196,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _topMatchStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _errorBox('Eşleşme akışı hatası: ${snapshot.error}');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) return _emptySuggestions();

                  int toIntScore(dynamic v) {
                    if (v == null) return 0;
                    if (v is int) return v;
                    if (v is num) return v.toInt();
                    if (v is String) return int.tryParse(v.trim()) ?? 0;
                    return 0;
                  }

                  final rawItems = docs
                      .map((d) {
                    final m = d.data();
                    final score = toIntScore(m['score']);
                    return <String, dynamic>{
                      ...m,
                      '_scoreInt': score,
                      '_docId': d.id,
                    };
                  })
                      .where((m) => (m['_scoreInt'] as int) >= 40)
                      .toList();

                  if (rawItems.isEmpty) return _emptySuggestions();

                  final jobIds = rawItems
                      .map((m) {
                    final jid = _extractJobId(m);
                    if (jid.isNotEmpty) return jid;
                    return (m['_docId'] ?? '').toString().trim();
                  })
                      .where((id) => id.isNotEmpty)
                      .toList();

                  if (jobIds.isEmpty) {
                    return _errorBox(
                      'Eşleşme verisinde jobId bulunamadı.\n'
                          'Çözüm: match dokümanlarında jobId alanını doldur ya da docId=jobId standardına geç.',
                    );
                  }

                  _ensureJobsFuture(jobIds);

                  return FutureBuilder<Map<String, Map<String, dynamic>>>(
                    future: _jobsFuture,
                    builder: (context, jobsSnap) {
                      if (jobsSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (jobsSnap.hasError) {
                        return _errorBox('Job çekme/kontrol hatası: ${jobsSnap.error}');
                      }

                      final jobsMap = jobsSnap.data ?? {};
                      final existingIds = jobsMap.keys.toSet();

                      final baseFiltered = rawItems.where((m) {
                        final jobId = (() {
                          final jid = _extractJobId(m);
                          if (jid.isNotEmpty) return jid;
                          return (m['_docId'] ?? '').toString().trim();
                        })();
                        return jobId.isNotEmpty && existingIds.contains(jobId);
                      }).toList();

                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null) {
                        final staleDocIds = rawItems
                            .where((m) {
                          final jobId = (() {
                            final jid = _extractJobId(m);
                            if (jid.isNotEmpty) return jid;
                            return (m['_docId'] ?? '').toString().trim();
                          })();
                          return jobId.isNotEmpty && !existingIds.contains(jobId);
                        })
                            .map((m) => (m['_docId'] ?? '').toString().trim())
                            .where((x) => x.isNotEmpty)
                            .toList();

                        _scheduleCleanupIfNeeded(user.uid, staleDocIds);
                      }

                      if (baseFiltered.isEmpty) return _emptySuggestions();

                      final filtered = baseFiltered.where((m) {
                        final jobId = (() {
                          final jid = _extractJobId(m);
                          if (jid.isNotEmpty) return jid;
                          return (m['_docId'] ?? '').toString().trim();
                        })();

                        final job = jobsMap[jobId];
                        if (job == null) return false;

                        if (!_workModelEligible(_currentUserMap, job)) return false;
                        if (!_levelEligible(_currentUserMap, job)) return false;

                        return true;
                      }).toList();

                      if (filtered.isEmpty) return _emptySuggestions();

                      final companyIds = <String>{};
                      for (final m in filtered) {
                        final jobId = (() {
                          final jid = _extractJobId(m);
                          if (jid.isNotEmpty) return jid;
                          return (m['_docId'] ?? '').toString().trim();
                        })();

                        final jobFromDb = jobsMap[jobId] ?? <String, dynamic>{};
                        final cid = (jobFromDb['companyId'] ?? jobFromDb['companyUid'] ?? jobFromDb['ownerId'] ?? jobFromDb['createdBy'] ?? '').toString().trim();
                        if (cid.isNotEmpty) companyIds.add(cid);
                      }

                      _ensureCompaniesFuture(companyIds.toList());

                      return FutureBuilder<Map<String, Map<String, dynamic>>>(
                        future: _companiesFuture,
                        builder: (context, compSnap) {
                          if (compSnap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (compSnap.hasError) {
                            return _errorBox('Company fetch hatası: ${compSnap.error}');
                          }

                          final companiesMap = compSnap.data ?? {};

                          return ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final m = filtered[index];
                              final score = (m['_scoreInt'] as int);

                              final jobId = (() {
                                final jid = _extractJobId(m);
                                if (jid.isNotEmpty) return jid;
                                return (m['_docId'] ?? '').toString().trim();
                              })();

                              final job = jobsMap[jobId] ?? <String, dynamic>{};

                              final companyId = (job['companyId'] ?? job['companyUid'] ?? job['ownerId'] ?? job['createdBy'] ?? '').toString().trim();
                              final companyDoc = companiesMap[companyId] ?? <String, dynamic>{};

                              final company = (job['companyName'] ?? job['company'] ?? companyDoc['name'] ?? 'Şirket').toString();
                              final position = (job['title'] ?? job['position'] ?? 'Pozisyon').toString();
                              final location = (job['location'] ?? job['city'] ?? '—').toString();

                              final logoUrl = (job['companyLogoUrl'] ?? job['logoUrl'] ?? job['logo'] ?? job['companyLogo'] ?? companyDoc['photoUrl'] ?? '').toString();
                              final safeLogo = logoUrl.trim().isEmpty ? null : logoUrl.trim();

                              final workModel = (job['workModel'] ?? 'Hybrid').toString();
                              final level = (job['level'] ?? 'Junior').toString();
                              final skills = (job['skills'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

                              final confidenceBadge = (m['confidenceBadge'] ?? '').toString().trim();
                              final confidenceScore = (m['confidenceScore'] is num)
                                  ? (m['confidenceScore'] as num).toDouble()
                                  : double.tryParse((m['confidenceScore'] ?? '').toString().trim()) ?? 0.0;

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(22),
                                  onTap: () => _openJobDetailSheetFromHome(context, jobId, job),
                                  child: _SuggestionCard(
                                    company: company,
                                    position: position,
                                    location: location,
                                    matchRate: score,
                                    companyLogoUrl: safeLogo,
                                    workModel: workModel,
                                    level: level,
                                    skills: skills,
                                    confidenceBadge: confidenceBadge.isEmpty ? null : confidenceBadge,
                                    confidenceScore: confidenceScore,
                                    isNew: (job['isNew'] == true) || (m['isNew'] == true),
                                    isTrending: (job['isTrending'] == true) || (m['isTrending'] == true),
                                    isBoosted: (job['isBoosted'] == true) || (m['isBoosted'] == true),
                                    onTap: () => _openJobDetailSheetFromHome(context, jobId, job),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: _Glass.deco(theme, radius: 14, blur: 16, spread: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Eşleşme ve güven skorları, yüklenen CV ve profil bilgilerine göre otomatik hesaplanır. '
                        'Bu skorlar yalnızca yönlendirme amaçlıdır; nihai değerlendirme işveren tarafından yapılır.',
                    style: TextStyle(
                      fontSize: 12.2,
                      height: 1.25,
                      color: cs.onSurface.withOpacity(0.85),
                      fontWeight: FontWeight.w600,
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

  Widget _badgeIcon(BuildContext context, {double size = 50}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withOpacity(isDark ? 0.22 : 0.14),
        border: Border.all(color: cs.primary.withOpacity(0.35)),
        boxShadow: _Glass.shadow(theme, blur: 16, spread: 2),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.10),
        child: Lottie.asset(
          'assets/lottie/motivation.json',
          fit: BoxFit.contain,
          repeat: true,
          animate: true,
          errorBuilder: (_, __, ___) => Icon(
            Icons.auto_awesome_rounded,
            color: cs.primary,
            size: size * 0.60,
          ),
        ),
      ),
    );
  }

  Widget _buildMotivationBubble(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final quote = _motivationQuote.isNotEmpty ? _motivationQuote : 'Bugün bir şey yap. Küçük de olsa.';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      constraints: const BoxConstraints(minHeight: 64),
      decoration: _Glass.deco(theme, radius: 22, blur: 18, spread: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _badgeIcon(context, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              quote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: cs.onSurface.withOpacity(0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _Glass.deco(t, radius: 14, blur: 16, spread: 2),
      child: Text(msg, style: TextStyle(color: cs.onSurface)),
    );
  }

  Widget _emptySuggestions() {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return SizedBox(
      height: 196,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: _Glass.deco(t, radius: 18, blur: 16, spread: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 78,
              child: Lottie.asset(
                'assets/lottie/empty2.json',
                repeat: true,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Henüz sana özel eşleşme yok',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.6,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Profilini güçlendirdikçe ve yeni ilanlar geldikçe burada sana özel eşleşmeleri göreceksin.',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.2,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================== GÜNDEM ==================
  Widget _buildNewsSection() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gündem',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewsListScreen(
                        articles: _newsArticles,
                        isLoading: _isLoadingNews,
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  backgroundColor: _Glass.fill(theme),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: _Glass.border(theme), width: 0.9),
                  ),
                ),
                child: Text(
                  'Tümünü Gör',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 230,
          child: _isLoadingNews
              ? const Center(child: CircularProgressIndicator())
              : (_newsArticles.isNotEmpty ? _buildNewsList() : _buildStaticFallbackNews()),
        ),
      ],
    );
  }

  Widget _buildNewsList() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _newsArticles.length > 5 ? 5 : _newsArticles.length,
      itemBuilder: (context, index) {
        final Map<String, dynamic> article = _newsArticles[index] as Map<String, dynamic>;

        final String title = article['title']?.toString() ?? 'Başlıksız';
        final String? imageUrl = (article['image'] ?? article['urlToImage']) as String?;

        String source = 'Haber';
        if (article['source'] != null && article['source'] is Map && article['source']['name'] != null) {
          source = article['source']['name'].toString();
        } else if (article['source'] != null && article['source'] is String) {
          source = article['source'].toString();
        }

        return Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewsDetailScreen(article: article),
                ),
              );
            },
            child: _NewsCard(
              title: title,
              source: source,
              imageUrl: imageUrl,
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaticFallbackNews() {
    final fallbackNews = [
      {'title': 'Flutter 4.0 Duyuruldu: Yenilikler Neler?', 'source': 'Flutter Dev Blog'},
      {'title': 'Yapay Zeka Etik Kuralları Gündemde', 'source': 'TechCrunch'},
      {'title': 'Yeni Nesil Veritabanı Teknolojileri', 'source': 'InfoWorld'},
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: fallbackNews.length,
      itemBuilder: (context, index) {
        final item = fallbackNews[index];
        return Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: _NewsCard(
            title: item['title']!,
            source: item['source']!,
            imageUrl: null,
          ),
        );
      },
    );
  }

  // ================== GERÇEK POST AKIŞI ==================
  Widget _buildFeedFromPosts() {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 32, bottom: 8),
          child: Text(
            'Akış',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _postStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Henüz kimse bir şey paylaşmadı.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }

            final docs = snapshot.data!.docs;

            return ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];

                final key = _postKeys.putIfAbsent(doc.id, () => GlobalKey());

                final postMap = {
                  'userName': doc['userName'] ?? 'Kullanıcı',
                  'userTitle': doc['userTitle'] ?? '',
                  'userAvatarUrl': doc['userAvatarUrl'],
                  'postText': doc['text'] ?? '',
                  'postImageUrl': doc['imageUrl'],
                  'timeAgo': _formatTime(doc['createdAt']),
                };

                return Container(
                  key: key,
                  child: _PostCard(
                    postId: doc.id,
                    postData: postMap,
                    isExpanded: _isPostExpanded(doc.id),
                    onToggleExpanded: () => _togglePostExpandedAnchored(doc.id),
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

// ================== HELPERS ==================
Color matchColor(int score) {
  final s = score.clamp(0, 100) / 100.0;
  return Color.lerp(const Color(0xFFE53935), const Color(0xFF43A047), s)!;
}

// ================== SUGGESTION CARD ==================
class _SuggestionCard extends StatelessWidget {
  final String company, position, location;
  final int matchRate;
  final String? companyLogoUrl;

  final String workModel;
  final String level;
  final List<String> skills;

  final bool isBoosted;
  final bool isTrending;
  final bool isNew;

  final String? confidenceBadge;
  final double confidenceScore;

  final VoidCallback? onTap;

  const _SuggestionCard({
    required this.company,
    required this.position,
    required this.location,
    required this.matchRate,
    this.companyLogoUrl,
    this.workModel = 'Hybrid',
    this.level = 'Junior',
    this.skills = const [],
    this.isBoosted = false,
    this.isTrending = false,
    this.isNew = false,
    this.confidenceBadge,
    this.confidenceScore = 0.0,
    this.onTap,
  });

  bool get _hasConfidence => (confidenceBadge ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final subtitleColor = cs.onSurface.withOpacity(0.70);

    final chipLabels = <String>[
      workModel.trim(),
      level.trim(),
      ...skills.map((e) => e.trim()),
    ].where((e) => e.isNotEmpty).toList();

    final badge = (confidenceBadge ?? '').trim();

    return SizedBox(
      width: 240,
      height: 196,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: _Glass.deco(t, radius: 22, blur: 22, spread: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: _CompanyLogo(
                            logoUrl: companyLogoUrl,
                            companyName: company,
                            fit: BoxFit.cover,
                            padding: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          company,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.2,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface.withOpacity(0.92),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: matchColor(matchRate).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: matchColor(matchRate).withOpacity(0.42)),
                        ),
                        child: Text(
                          '%$matchRate',
                          style: TextStyle(
                            fontSize: 12.2,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface.withOpacity(0.92),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    position,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.6,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ChipsRow(labels: chipLabels, isDark: t.brightness == Brightness.dark),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Flexible(
                        flex: 1,
                        fit: FlexFit.loose,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _buildPill(matchRate),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_hasConfidence)
                        Flexible(
                          flex: 1,
                          fit: FlexFit.loose,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _ConfidenceTag(badge: badge, score: confidenceScore),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 16, color: subtitleColor.withOpacity(0.9)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.2,
                            fontWeight: FontWeight.w700,
                            color: subtitleColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(int matchRate) {
    Color color;
    IconData icon;
    String label;

    if (matchRate >= 75) {
      color = const Color(0xFF34C579);
      icon = Icons.trending_up_rounded;
      label = 'Trend';
    } else if (matchRate >= 60) {
      color = const Color(0xFFFFD166);
      icon = Icons.bolt_rounded;
      label = 'Hızlı eşleşme';
    } else {
      color = const Color(0xFFE53935);
      icon = Icons.warning_amber_rounded;
      label = 'Düşük eşleşme';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceTag extends StatelessWidget {
  final String badge;
  final double score;

  const _ConfidenceTag({required this.badge, required this.score});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = badge.toLowerCase();

    late final String text;
    late final IconData icon;
    late final Color color;

    if (b == 'high') {
      text = 'Güven Yüksek';
      icon = Icons.verified_rounded;
      color = const Color(0xFF34C579);
    } else if (b == 'medium') {
      text = 'Güven Orta';
      icon = Icons.shield_rounded;
      color = const Color(0xFFFFD166);
    } else {
      text = 'Güven Düşük';
      icon = Icons.info_outline_rounded;
      color = const Color(0xFFE53935);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.2,
              fontWeight: FontWeight.w900,
              color: cs.onSurface.withOpacity(0.92),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  final List<String> labels;
  final bool isDark;

  const _ChipsRow({required this.labels, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => _MiniChip(label: labels[i], isDark: isDark),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final bool isDark;

  const _MiniChip({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _Glass.pill(Theme.of(context)),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white.withOpacity(0.92) : Colors.black.withOpacity(0.85),
        ),
      ),
    );
  }
}

// ================== NEWS CARD ==================
class _NewsCard extends StatelessWidget {
  final String title;
  final String source;
  final String? imageUrl;

  const _NewsCard({
    required this.title,
    required this.source,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    final img = (imageUrl ?? '').trim();
    final hasImage = img.isNotEmpty;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(14),
      decoration: _Glass.deco(t, radius: 18, blur: 18, spread: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/icons/news1.png', width: 26, height: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasImage)
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Glass.border(t), width: 0.9),
                  image: DecorationImage(
                    image: NetworkImage(img),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
            maxLines: hasImage ? 2 : 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ================= POST CARD =================
class _PostCard extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> postData;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  const _PostCard({
    required this.postId,
    required this.postData,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  static String _assetForTheme(String baseName, bool isDark) {
    if (baseName == 'like_filled') return 'assets/icons/like_filled.png';
    return isDark ? 'assets/icons/${baseName}_light.png' : 'assets/icons/$baseName.png';
  }

  static Widget _postActionIcon({
    required BuildContext context,
    required String assetBaseName,
    required VoidCallback onTap,
    int? count,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconPath = _assetForTheme(assetBaseName, isDark);
    final showCount = (count != null && count > 0);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(iconPath, width: 20, height: 20),
            if (showCount) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.78),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final avatarUrl = (postData['userAvatarUrl'] ?? '').toString().trim();
    final userName = (postData['userName'] ?? 'Kullanıcı').toString().trim();
    final userTitle = (postData['userTitle'] ?? '').toString().trim();

    final postTextRaw = (postData['postText'] ?? '').toString();
    final text = postTextRaw.trim();
    final hasText = text.isNotEmpty;
    final shouldClamp = hasText && text.length > 140;

    final postImageUrl = (postData['postImageUrl'] ?? '').toString().trim();
    final hasImage = postImageUrl.isNotEmpty;

    final timeAgo = (postData['timeAgo'] ?? '').toString().trim();

    final subtle = cs.onSurface.withOpacity(0.62);

    final me = FirebaseAuth.instance.currentUser;

    final likeCount = (postData['likeCount'] is num) ? (postData['likeCount'] as num).toInt() : 0;
    final commentCount = (postData['commentCount'] is num) ? (postData['commentCount'] as num).toInt() : 0;

    final likeDocStream = (me == null)
        ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
        : FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(me.uid)
        .snapshots();

    final saveDocStream = (me == null)
        ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
        : FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('saves')
        .doc(me.uid)
        .snapshots();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: _Glass.deco(t, radius: 18, blur: 22, spread: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: cs.surface,
                        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl.isEmpty
                            ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.8))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                            ),
                            if (userTitle.isNotEmpty)
                              Text(
                                userTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: subtle,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          color: subtle,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                // TEXT + MORE
                if (hasText)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          maxLines: (shouldClamp && !isExpanded) ? 3 : null,
                          overflow: (shouldClamp && !isExpanded) ? TextOverflow.ellipsis : TextOverflow.visible,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        if (shouldClamp)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: onToggleExpanded,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Text(
                                  isExpanded ? 'Daha az' : 'Daha fazla',
                                  style: TextStyle(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                // IMAGE
                if (hasImage)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _Glass.border(t), width: 0.9),
                        ),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            postImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: cs.surfaceVariant.withOpacity(0.35),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.broken_image_rounded,
                                color: cs.onSurface.withOpacity(0.55),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // COMMENTS PREVIEW
                _CommentsPreview(
                  postId: postId,
                  onOpenComments: () => PostActions.openCommentsSheet(context, postId),
                ),

                // ACTIONS
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: likeDocStream,
                    builder: (context, likeSnap) {
                      final isLiked = me != null && (likeSnap.data?.exists ?? false);

                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: saveDocStream,
                        builder: (context, saveSnap) {
                          final isSaved = me != null && (saveSnap.data?.exists ?? false);

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _postActionIcon(
                                context: context,
                                assetBaseName: isLiked ? 'like_filled' : 'like',
                                count: likeCount,
                                onTap: () => PostActions.toggleLike(context, postId, isLiked),
                              ),
                              _postActionIcon(
                                context: context,
                                assetBaseName: 'comment',
                                count: commentCount,
                                onTap: () => PostActions.openCommentsSheet(context, postId),
                              ),
                              _postActionIcon(
                                context: context,
                                assetBaseName: 'send1',
                                onTap: () => PostActions.openSendSheet(
                                  context,
                                  postId: postId,
                                  postText: postTextRaw,
                                  postImageUrl: hasImage ? postImageUrl : null,
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () => PostActions.toggleSave(context, postId, isSaved),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Icon(
                                    isSaved ? Icons.bookmark : Icons.bookmark_outline,
                                    size: 22,
                                    color: isSaved ? const Color(0xFFFFA726) : cs.onSurface.withOpacity(0.65),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _CommentsPreview extends StatelessWidget {
  final String postId;
  final VoidCallback onOpenComments;

  const _CommentsPreview({
    required this.postId,
    required this.onOpenComments,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .orderBy('createdAt', descending: true)
          .limit(2)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final docs = snapshot.data!.docs;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onOpenComments,
                child: Text(
                  'Tüm yorumları gör',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ...docs.map((doc) {
                final data = doc.data();
                final name = (data['userName'] ?? 'Kullanıcı').toString().trim();
                final username = (data['username'] ?? '').toString().trim();
                final text = (data['text'] ?? '').toString();

                final label = username.isNotEmpty ? '$name (@$username)' : name;

                return Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$label: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                      Expanded(child: _CommentText(text: text)),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}

class _CommentText extends StatelessWidget {
  final String text;

  const _CommentText({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final baseStyle = DefaultTextStyle.of(context).style.copyWith(
      fontSize: 13,
      color: cs.onSurface,
      height: 1.25,
      fontWeight: FontWeight.w600,
    );

    final words = text.split(' ');

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: words.map((word) {
          final isMention = word.startsWith('@') && word.length > 1;
          return TextSpan(
            text: '$word ',
            style: isMention ? baseStyle.copyWith(color: cs.primary, fontWeight: FontWeight.w800) : baseStyle,
          );
        }).toList(),
      ),
    );
  }
}

class _CompanyLogo extends StatelessWidget {
  final String? logoUrl;
  final String companyName;

  final BoxFit fit;
  final double padding;

  const _CompanyLogo({
    required this.logoUrl,
    required this.companyName,
    this.fit = BoxFit.contain,
    this.padding = 4,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final url = (logoUrl ?? '').trim();
    if (url.isNotEmpty) {
      return Container(
        color: cs.surface,
        alignment: Alignment.center,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Image.network(
            url,
            width: double.infinity,
            height: double.infinity,
            fit: fit,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                ),
              );
            },
            errorBuilder: (_, __, ___) => _fallback(cs),
          ),
        ),
      );
    }

    return _fallback(cs);
  }

  Widget _fallback(ColorScheme cs) {
    final letter = companyName.trim().isNotEmpty ? companyName.trim()[0].toUpperCase() : '?';

    return Container(
      color: cs.primary.withOpacity(0.08),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: cs.primary,
        ),
      ),
    );
  }
}

// ================== GLOW BLOB ==================
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
