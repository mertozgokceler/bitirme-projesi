import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_detail_screen.dart';
import '../utils/chat_utils.dart';
import '../services/call_service.dart';

class NewChatSearchScreen extends StatefulWidget {
  const NewChatSearchScreen({super.key});

  @override
  State<NewChatSearchScreen> createState() => _NewChatSearchScreenState();
}

class _NewChatSearchScreenState extends State<NewChatSearchScreen> {
  final _qCtrl = TextEditingController();
  final _fs = FirebaseFirestore.instance;
  final CallService _callService = CallService();

  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  String trLower(String s) =>
      s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
  String _endBound(String s) => '$s\uf8ff';

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final key = trLower(q);
      final end = _endBound(key);

      final q1 = _fs
          .collection('users')
          .where('isSearchable', isEqualTo: true)
          .orderBy('usernameLower')
          .startAt([key]).endAt([end]).limit(20).get();

      final q2 = _fs
          .collection('users')
          .where('isSearchable', isEqualTo: true)
          .orderBy('nameLower')
          .startAt([key]).endAt([end]).limit(20).get();

      final snaps = await Future.wait([q1, q2]);

      final Map<String, Map<String, dynamic>> uniq = {};
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      for (final s in snaps) {
        for (final d in s.docs) {
          if (d.id == currentUserId) continue;

          final data = d.data();
          uniq[d.id] = {
            'uid': d.id,
            'name': (data['name'] ?? '').toString(),
            'username': (data['username'] ?? '').toString(),
            'photoUrl': data['photoUrl'],
            'role': data['role'],
          };
        }
      }

      if (!mounted) return;
      setState(() {
        _results = uniq.values.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arama hatası: $e')),
      );
    }
  }

  Future<void> _startChatWithUser(Map<String, dynamic> otherUser) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final currentUid = currentUser.uid;
    final otherUid = (otherUser['uid'] ?? '').toString();
    if (otherUid.isEmpty) return;

    final chatId = buildChatId(currentUid, otherUid);
    final chatRef = _fs.collection('chats').doc(chatId);

    // ✅ ÖNEMLİ: Yeni sohbet oluşturmak "mesaj" değildir.
    // Bu yüzden lastMessage / lastMessageSenderId / lastMessageTimestamp YAZMIYORUZ.
    // Bildirimler sadece messages alt koleksiyonuna gerçek mesaj gelince tetiklenmeli.
    await chatRef.set({
      'users': [currentUid, otherUid],
      'archivedBy': <String>[],
      'clearedAt': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
      'isArchived': false, // sende chat ekranı bunu kullanıyorsa kalsın
    }, SetOptions(merge: true));

    if (!mounted) return;

    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(
          chatId: chatId,
          otherUser: otherUser,
          callService: _callService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Sohbet Başlat')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _qCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Kullanıcı adı veya Ad Soyad',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? Center(
              child: Text(
                _qCtrl.text.isEmpty
                    ? 'Sohbet etmek için bir kullanıcı arayın.'
                    : 'Sonuç bulunamadı.',
              ),
            )
                : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final u = _results[index];
                return ListTile(
                  onTap: () => _startChatWithUser(u),
                  leading: CircleAvatar(
                    backgroundImage: u['photoUrl'] != null
                        ? NetworkImage(u['photoUrl'])
                        : null,
                    child: u['photoUrl'] == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text((u['name'] ?? '').toString()),
                  subtitle: Text('@${(u['username'] ?? '').toString()}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
