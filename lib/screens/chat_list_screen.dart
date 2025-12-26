import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_detail_screen.dart';
import 'new_chat_search_screen.dart';
import '../services/call_service.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final CallService _callService = CallService();

  Future<void> _toggleArchive(String chatId, bool shouldArchive) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore.collection('chats').doc(chatId).update({
        'archivedBy': shouldArchive
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
      });
    } catch (e) {
      debugPrint('Arşiv güncelleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arşivleme işlemi başarısız oldu.')),
        );
      }
    }
  }

  Future<void> _clearChatForCurrentUser(String chatId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore.collection('chats').doc(chatId).update({
        'clearedAt.$uid': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Sohbet temizleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sohbet silinemedi.')),
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
    final c = ChatColors.of(t);

    final List<dynamic> archivedBy = chatData['archivedBy'] ?? [];
    final bool isArchivedForUser = archivedBy.contains(uid);

    showModalBottomSheet(
      context: context,
      backgroundColor: c.sheetBg,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: c.cardBorder),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isArchivedForUser
                      ? Icons.unarchive_rounded
                      : Icons.archive_rounded,
                  color: c.icon,
                ),
                title: Text(
                  isArchivedForUser ? 'Arşivden çıkar' : 'Arşive taşı',
                  style: TextStyle(color: c.textPrimary),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _toggleArchive(chatId, !isArchivedForUser);
                },
              ),
              Divider(height: 0, color: c.divider),
              ListTile(
                leading: Icon(Icons.delete_forever_rounded, color: c.danger),
                title: Text(
                  'Sohbeti sil',
                  style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) {
                      final tt = Theme.of(ctx);
                      final cc = ChatColors.of(tt);

                      return AlertDialog(
                        backgroundColor: cc.dialogBg,
                        surfaceTintColor: Colors.transparent,
                        title: Text(
                          'Sohbet silinsin mi?',
                          style: TextStyle(color: cc.textPrimary),
                        ),
                        content: Text(
                          'Bu işlem sadece senin hesabın için geçerli olacak. '
                              'Sohbet, diğer kullanıcıdan silinmeyecek. '
                              'Yeni mesaj gelirse sohbet tekrar görünür.',
                          style: TextStyle(color: cc.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            style: ButtonStyle(
                              foregroundColor:
                              WidgetStatePropertyAll(cc.textSecondary),
                              overlayColor: WidgetStatePropertyAll(
                                cc.brand.withOpacity(0.12),
                              ),
                            ),
                            child: const Text('Vazgeç'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: ButtonStyle(
                              foregroundColor: WidgetStatePropertyAll(cc.danger),
                              overlayColor: WidgetStatePropertyAll(
                                cc.danger.withOpacity(0.12),
                              ),
                            ),
                            child: const Text('Sil'),
                          ),
                        ],
                      );
                    },
                  );

                  if (confirm == true) {
                    await _clearChatForCurrentUser(chatId);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = _auth.currentUser?.uid;
    final t = Theme.of(context);
    final c = ChatColors.of(t);

    if (currentUserUid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sohbetler')),
        body: const Center(
          child: Text('Sohbetleri görmek için giriş yapmalısınız.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sohbetler')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const NewChatSearchScreen()),
          );
        },
        backgroundColor: c.brand,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: const Icon(Icons.add_comment_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Sohbetlerde ara...',
                hintStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary,
                ),
                prefixIcon: Icon(Icons.search, color: c.iconMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: c.searchBg,
              ),
              onChanged: (_) {},
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chats')
                  .where('users', arrayContains: currentUserUid)
                  .orderBy('lastMessageTimestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Bir hata oluştu.'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Hiç sohbetiniz yok.'));
                }

                final chatDocs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: chatDocs.length,
                  itemBuilder: (context, index) {
                    final chatDoc = chatDocs[index];
                    final chatData = chatDoc.data() as Map<String, dynamic>;

                    final clearedAtMapRaw = chatData['clearedAt'];
                    Timestamp? clearedAtForUser;
                    if (clearedAtMapRaw is Map) {
                      final val = clearedAtMapRaw[currentUserUid];
                      if (val is Timestamp) clearedAtForUser = val;
                    }

                    final List<String> userIds = List.from(chatData['users']);
                    final otherUserUid = userIds.firstWhere(
                          (uid) => uid != currentUserUid,
                      orElse: () => '',
                    );
                    if (otherUserUid.isEmpty) return const SizedBox.shrink();

                    return StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('chats')
                          .doc(chatDoc.id)
                          .collection('messages')
                          .orderBy('timestamp', descending: true)
                          .limit(10)
                          .snapshots(),
                      builder: (context, msgSnapshot) {
                        if (msgSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return _SkeletonTile(colors: c);
                        }

                        if (!msgSnapshot.hasData ||
                            msgSnapshot.data!.docs.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        final msgDocs = msgSnapshot.data!.docs;

                        QueryDocumentSnapshot? lastVisibleMsg;
                        Map<String, dynamic>? lastVisibleData;

                        for (var msgDoc in msgDocs) {
                          final data = msgDoc.data() as Map<String, dynamic>;
                          final ts = data['timestamp'] as Timestamp?;
                          final List<dynamic> deletedFor =
                              data['deletedFor'] ?? [];

                          if (deletedFor.contains(currentUserUid)) continue;

                          if (clearedAtForUser != null &&
                              ts != null &&
                              ts.compareTo(clearedAtForUser) <= 0) {
                            continue;
                          }

                          lastVisibleMsg = msgDoc;
                          lastVisibleData = data;
                          break;
                        }

                        if (lastVisibleMsg == null || lastVisibleData == null) {
                          return const SizedBox.shrink();
                        }

                        String snippet;
                        final type = lastVisibleData['type'] as String? ?? 'text';
                        if (type == 'audio') {
                          snippet = 'Sesli mesaj';
                        } else {
                          snippet =
                              (lastVisibleData['text'] as String? ?? '').trim();
                          if (snippet.isEmpty) snippet = 'Mesaj';
                        }

                        final List<dynamic> archivedBy =
                            chatData['archivedBy'] ?? [];
                        final bool isArchivedForUser =
                        archivedBy.contains(currentUserUid);

                        return FutureBuilder<DocumentSnapshot>(
                          future: _firestore
                              .collection('users')
                              .doc(otherUserUid)
                              .get(),
                          builder: (context, userSnapshot) {
                            if (userSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return _SkeletonTile(colors: c);
                            }
                            if (!userSnapshot.hasData ||
                                !userSnapshot.data!.exists) {
                              return const ListTile(
                                title: Text('Kullanıcı bulunamadı'),
                              );
                            }

                            final otherUserData =
                            userSnapshot.data!.data() as Map<String, dynamic>;
                            final otherUserName =
                                otherUserData['name'] ?? 'Bilinmeyen Kullanıcı';
                            final otherUserPhotoUrl = otherUserData['photoUrl'];

                            return Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: c.cardBg,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                Border.all(color: c.cardBorder, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: c.cardShadow,
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundImage: otherUserPhotoUrl != null
                                      ? NetworkImage(otherUserPhotoUrl)
                                      : null,
                                  backgroundColor: c.avatarBg,
                                  child: otherUserPhotoUrl == null
                                      ? Icon(Icons.person, color: c.icon)
                                      : null,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        otherUserName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: isArchivedForUser
                                              ? c.textSecondary
                                              : c.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (isArchivedForUser)
                                      Icon(Icons.archive_rounded,
                                          size: 16, color: c.iconMuted),
                                  ],
                                ),
                                subtitle: Text(
                                  snippet,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isArchivedForUser
                                        ? c.textMuted
                                        : c.textSecondary,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => ChatDetailScreen(
                                        chatId: chatDoc.id,
                                        otherUser: otherUserData
                                          ..['uid'] = otherUserUid,
                                        callService: _callService, // ✅ FIX
                                      ),
                                    ),
                                  );
                                },
                                onLongPress: () {
                                  _showChatOptions(
                                    chatId: chatDoc.id,
                                    chatData: chatData,
                                  );
                                },
                                trailing: PopupMenuButton<String>(
                                  iconColor: c.iconMuted,
                                  color: c.menuBg,
                                  surfaceTintColor: Colors.transparent,
                                  onSelected: (value) async {
                                    if (value == 'archive') {
                                      await _toggleArchive(
                                          chatDoc.id, !isArchivedForUser);
                                    } else if (value == 'delete') {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) {
                                          final tt = Theme.of(ctx);
                                          final cc = ChatColors.of(tt);

                                          return AlertDialog(
                                            backgroundColor: cc.dialogBg,
                                            surfaceTintColor: Colors.transparent,
                                            title: Text('Sohbet silinsin mi?',
                                                style: TextStyle(
                                                    color: cc.textPrimary)),
                                            content: Text(
                                              'Bu işlem sadece senin hesabın için geçerli olacak. '
                                                  'Sohbet, diğer kullanıcıdan silinmeyecek. '
                                                  'Yeni mesaj gelirse sohbet tekrar görünür.',
                                              style: TextStyle(
                                                  color: cc.textSecondary),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(false),
                                                child: const Text('Vazgeç'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(true),
                                                style: ButtonStyle(
                                                  foregroundColor:
                                                  WidgetStatePropertyAll(
                                                      cc.danger),
                                                ),
                                                child: const Text('Sil'),
                                              ),
                                            ],
                                          );
                                        },
                                      );

                                      if (confirm == true) {
                                        await _clearChatForCurrentUser(chatDoc.id);
                                      }
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'archive',
                                      child: Text(
                                        isArchivedForUser
                                            ? 'Arşivden çıkar'
                                            : 'Arşive taşı',
                                        style: TextStyle(color: c.textPrimary),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        'Sohbeti sil',
                                        style: TextStyle(
                                          color: c.danger,
                                          fontWeight: FontWeight.w600,
                                        ),
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
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  final ChatColors colors;
  const _SkeletonTile({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: colors.skeleton1),
      title: Container(height: 16, width: 100, color: colors.skeleton1),
      subtitle: Container(height: 12, width: 150, color: colors.skeleton2),
    );
  }
}

class ChatColors {
  final Color brand;
  final Color danger;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color icon;
  final Color iconMuted;

  final Color searchBg;

  final Color cardBg;
  final Color cardBorder;
  final Color cardShadow;

  final Color avatarBg;

  final Color sheetBg;
  final Color dialogBg;
  final Color menuBg;
  final Color divider;

  final Color skeleton1;
  final Color skeleton2;

  ChatColors._({
    required this.brand,
    required this.danger,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.icon,
    required this.iconMuted,
    required this.searchBg,
    required this.cardBg,
    required this.cardBorder,
    required this.cardShadow,
    required this.avatarBg,
    required this.sheetBg,
    required this.dialogBg,
    required this.menuBg,
    required this.divider,
    required this.skeleton1,
    required this.skeleton2,
  });

  static ChatColors of(ThemeData t) {
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final brand = const Color(0xFFE57AFF);
    final danger = Colors.redAccent;

    final cardBg = isDark ? const Color(0xFF0F1116) : Colors.white;
    final sheetBg = isDark ? const Color(0xFF121317) : Colors.white;
    final dialogBg = isDark ? const Color(0xFF121317) : Colors.white;
    final menuBg = isDark ? const Color(0xFF1A1C22) : Colors.white;

    final cardBorder = isDark ? Colors.white10 : Colors.black12;
    final divider = isDark ? Colors.white10 : Colors.black12;

    final cardShadow = Colors.black.withOpacity(isDark ? 0.18 : 0.10);

    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white70 : Colors.black54;
    final textMuted = isDark ? Colors.white54 : Colors.black45;

    final icon = isDark ? Colors.white : cs.onSurface;
    final iconMuted = isDark ? Colors.white60 : Colors.black45;

    final searchBg = isDark ? const Color(0xFF1A1C22) : Colors.grey.shade200;

    final avatarBg =
    isDark ? const Color(0xFF1A1C22) : cs.surfaceContainerHighest;

    final skeleton1 = isDark ? Colors.white12 : Colors.grey.shade300;
    final skeleton2 = isDark ? Colors.white10 : Colors.grey.shade200;

    return ChatColors._(
      brand: brand,
      danger: danger,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      icon: icon,
      iconMuted: iconMuted,
      searchBg: searchBg,
      cardBg: cardBg,
      cardBorder: cardBorder,
      cardShadow: cardShadow,
      avatarBg: avatarBg,
      sheetBg: sheetBg,
      dialogBg: dialogBg,
      menuBg: menuBg,
      divider: divider,
      skeleton1: skeleton1,
      skeleton2: skeleton2,
    );
  }
}
