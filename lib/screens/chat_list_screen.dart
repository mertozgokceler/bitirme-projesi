// lib/screens/chat_list_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/call_service.dart';
import 'chat_detail_screen.dart';
import 'new_chat_search_screen.dart';

class ChatListScreen extends StatefulWidget {
  final CallService callService;

  const ChatListScreen({
    super.key,
    required this.callService,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _showArchived = false; // ✅ Sohbetler / Arşiv toggle

  // ====== WhatsApp-style: hard delete all messages in chat for both ======
  Future<void> _deleteChatForEveryone(String chatId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final chatRef = _firestore.collection('chats').doc(chatId);

    try {
      // 1) delete messages in pages (batch of <= 450 to be safe)
      while (true) {
        final qs = await chatRef
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(450)
            .get();

        if (qs.docs.isEmpty) break;

        final batch = _firestore.batch();
        for (final d in qs.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }

      // 2) reset chat doc so it disappears from both users' lists
      await chatRef.set({
        'hasMessages': false,
        'lastMessage': '',
        'lastMessageType': null,
        'lastMessageSenderId': null,
        'lastMessageTimestamp': null,
        'archivedBy': <String>[],
        'deletedAllAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Chat delete for everyone error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sohbet silinemedi.')),
        );
      }
    }
  }

  Future<void> _toggleArchive(String chatId, bool shouldArchive) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore.collection('chats').doc(chatId).update({
        'archivedBy': shouldArchive
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
      });

      // ✅ UX: arşivden çıkarınca direkt sohbetlere dön
      if (!shouldArchive && mounted && _showArchived) {
        setState(() => _showArchived = false);
      }
    } catch (e) {
      debugPrint('Archive update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arşivleme işlemi başarısız oldu.')),
        );
      }
    }
  }

  void _showChatOptions({
    required String chatId,
    required Map<String, dynamic> chatData,
  }) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final List<dynamic> archivedBy = chatData['archivedBy'] ?? [];
    final bool isArchivedForUser = archivedBy.contains(uid);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(isDark ? 0.75 : 0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outline.withOpacity(0.70)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.22 : 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(
                    isArchivedForUser
                        ? Icons.unarchive_rounded
                        : Icons.archive_rounded,
                    color: cs.onSurface,
                  ),
                  title: Text(
                    isArchivedForUser ? 'Arşivden çıkar' : 'Arşive taşı',
                    style: TextStyle(color: cs.onSurface),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _toggleArchive(chatId, !isArchivedForUser);
                  },
                ),
                Divider(height: 0, color: cs.outline.withOpacity(0.40)),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: Colors.redAccent),
                  title: const Text(
                    'Sohbeti Sil',
                    style: TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.w900),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) {
                        final tt = Theme.of(ctx);
                        final ccs = tt.colorScheme;
                        final dark = tt.brightness == Brightness.dark;

                        return AlertDialog(
                          backgroundColor:
                          ccs.surface.withOpacity(dark ? 0.90 : 0.98),
                          surfaceTintColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: ccs.outline.withOpacity(0.55)),
                          ),
                          title: Text(
                            'Sohbet tamamen silinsin mi?',
                            style: TextStyle(
                              color: ccs.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          content: Text(
                            'Bu işlem mesajları iki taraftan da kaldırır ve sohbet listeden düşer.',
                            style: TextStyle(
                              color: ccs.onSurface.withOpacity(0.75),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: Text(
                                'Vazgeç',
                                style: TextStyle(
                                  color: ccs.onSurface.withOpacity(0.75),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text(
                                'Sil',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );

                    if (confirm == true) {
                      await _deleteChatForEveryone(chatId);
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  // ====== UI ======
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

  PreferredSizeWidget _buildTopBar() {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return AppBar(
      title: Text(_showArchived ? 'Arşiv' : 'Sohbetler'),
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: cs.onSurface),
      titleTextStyle: TextStyle(
        color: cs.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(isDark ? 0.70 : 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withOpacity(0.70)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _segmentedHeader() {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return _glassCard(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showArchived = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: !_showArchived
                        ? cs.primary.withOpacity(isDark ? 0.35 : 0.16)
                        : Colors.transparent,
                    border: Border.all(
                      color: !_showArchived
                          ? cs.primary.withOpacity(isDark ? 0.55 : 0.35)
                          : cs.outline.withOpacity(0.35),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Sohbetler',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showArchived = true),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _showArchived
                        ? cs.primary.withOpacity(isDark ? 0.35 : 0.16)
                        : Colors.transparent,
                    border: Border.all(
                      color: _showArchived
                          ? cs.primary.withOpacity(isDark ? 0.55 : 0.35)
                          : cs.outline.withOpacity(0.35),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Arşiv',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
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

  Widget _buildChatTile({
    required String chatId,
    required Map<String, dynamic> chatData,
    required String currentUserUid,
    required String otherUserUid,
    required Map<String, dynamic> otherUserData,
    required String snippet,
  }) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;
    final unreadMap = (chatData['unread'] as Map?) ?? {};
    final int unreadFromMap =
        (unreadMap[currentUserUid] as num?)?.toInt() ?? 0;

    final dottedKey = 'unread.$currentUserUid';
    final int unreadFromDotted =
        (chatData[dottedKey] as num?)?.toInt() ?? 0;

    final int unreadCount = unreadFromMap != 0 ? unreadFromMap : unreadFromDotted;



    final otherUserName =
    (otherUserData['name'] ?? 'Bilinmeyen Kullanıcı').toString();
    final otherUserPhotoUrl = otherUserData['photoUrl'] as String?;

    final List<dynamic> archivedBy = chatData['archivedBy'] ?? [];
    final bool isArchivedForUser = archivedBy.contains(currentUserUid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      child: _glassCard(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(2.2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.outline.withOpacity(0.60)),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundImage:
              (otherUserPhotoUrl != null && otherUserPhotoUrl.isNotEmpty)
                  ? NetworkImage(otherUserPhotoUrl)
                  : null,
              backgroundColor: cs.surface,
              child: (otherUserPhotoUrl == null || otherUserPhotoUrl.isEmpty)
                  ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.75))
                  : null,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  otherUserName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isArchivedForUser
                        ? cs.onSurface.withOpacity(0.60)
                        : cs.onSurface,
                  ),
                ),
              ),
              if (isArchivedForUser)
                Icon(Icons.archive_rounded,
                    size: 16, color: cs.onSurface.withOpacity(0.55)),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              snippet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isArchivedForUser
                    ? cs.onSurface.withOpacity(0.45)
                    : cs.onSurface.withOpacity(0.70),
              ),
            ),
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatDetailScreen(
                  chatId: chatId,
                  otherUser: otherUserData..['uid'] = otherUserUid,
                  callService: widget.callService,
                ),
              ),
            );
          },
          onLongPress: () => _showChatOptions(chatId: chatId, chatData: chatData),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6E44FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                iconColor: cs.onSurface.withOpacity(0.60),
                color: cs.surface.withOpacity(isDark ? 0.92 : 0.98),
                surfaceTintColor: Colors.transparent,
                onSelected: (value) async {
                  if (value == 'archive') {
                    await _toggleArchive(chatId, !isArchivedForUser);
                  } else if (value == 'delete') {
                    await _deleteChatForEveryone(chatId);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(
                      isArchivedForUser ? 'Arşivden Çıkar' : 'Arşive Taşı',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Sohbeti Sil',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = _auth.currentUser?.uid;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    if (currentUserUid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sohbetler')),
        body: const Center(child: Text('Sohbetleri görmek için giriş yapmalısınız.')),
      );
    }

    // ✅ Stream: arşiv toggle’a göre filtre
    final baseQuery = _firestore
        .collection('chats')
        .where('users', arrayContains: currentUserUid)
        .where('hasMessages', isEqualTo: true)
        .orderBy('lastMessageTimestamp', descending: true);

    final stream = baseQuery.snapshots();

    return Stack(
      children: [
        Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _buildTopBar(),
          floatingActionButton: _showArchived
              ? null // ✅ Arşivde yeni sohbet başlatma kapalı (istersen açarsın)
              : FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NewChatSearchScreen(callService: widget.callService),
                ),
              );
            },
            backgroundColor: const Color(0xFF6E44FF),
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            child: const Icon(Icons.add_comment_rounded),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: _segmentedHeader(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _glassCard(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: _showArchived ? 'Arşivde ara...' : 'Sohbetlerde ara...',
                      hintStyle: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withOpacity(0.60),
                      ),
                      prefixIcon: Icon(Icons.search, color: cs.onSurface.withOpacity(0.55)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: cs.surface.withOpacity(isDark ? 0.10 : 0.40),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    onChanged: (_) {},
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Hata: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    final rawDocs = snapshot.data!.docs;

                    // ✅ Client-side filter: archivedBy contains uid?
                    final docs = rawDocs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final List<dynamic> archivedBy = (data['archivedBy'] ?? const []);
                      final isArchivedForUser = archivedBy.contains(currentUserUid);
                      return _showArchived ? isArchivedForUser : !isArchivedForUser;
                    }).toList();

                    if (docs.isEmpty) {
                      return Center(
                        child: _glassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _showArchived ? 'Arşiv boş.' : 'Hiç sohbetiniz yok.',
                              style: TextStyle(
                                color: cs.onSurface.withOpacity(0.80),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final chatDoc = docs[index];
                        final chatData = chatDoc.data() as Map<String, dynamic>;

                        final List<String> userIds =
                        List<String>.from(chatData['users'] ?? const []);

                        final otherUserUid = userIds.firstWhere(
                              (u) => u != currentUserUid,
                          orElse: () => '',
                        );
                        if (otherUserUid.isEmpty) return const SizedBox.shrink();

                        return FutureBuilder<DocumentSnapshot>(
                          future: _firestore.collection('users').doc(otherUserUid).get(),
                          builder: (context, userSnapshot) {
                            if (userSnapshot.connectionState == ConnectionState.waiting) {
                              return _glassCard(
                                child: const ListTile(title: Text('Yükleniyor...')),
                              );
                            }
                            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                              return _glassCard(
                                child: const ListTile(title: Text('Kullanıcı bulunamadı')),
                              );
                            }

                            final otherUserData =
                            userSnapshot.data!.data() as Map<String, dynamic>;

                            final type = (chatData['lastMessageType'] as String?) ?? 'text';
                            String snippet;
                            if (type == 'audio') {
                              snippet = 'Sesli mesaj';
                            } else if (type == 'image') {
                              snippet = 'Fotoğraf';
                            } else if (type == 'video') {
                              snippet = 'Video';
                            } else {
                              snippet = (chatData['lastMessage'] as String? ?? '').trim();
                              if (snippet.isEmpty) snippet = 'Mesaj';
                            }

                            return _buildChatTile(
                              chatId: chatDoc.id,
                              chatData: chatData,
                              currentUserUid: currentUserUid,
                              otherUserUid: otherUserUid,
                              otherUserData: otherUserData,
                              snippet: snippet,
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
      ],
    );
  }
}