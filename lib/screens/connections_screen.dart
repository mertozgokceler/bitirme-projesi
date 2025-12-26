import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('Giriş yapmış kullanıcı bulunamadı.'),
        ),
      );
    }

    final String currentUserId = currentUser.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ağım / Bağlantılarım'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('connections')
            .doc(currentUserId)
            .collection('list')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Bağlantılar alınırken hata: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'Henüz bağlantın yok.\nProfil sayfalarından bağlantı isteği gönderebilirsin.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];

              // doc.id = diğer kullanıcının uid'si
              final String otherUserId = doc.id;

              return _ConnectionUserTile(
                currentUserId: currentUserId,
                otherUserId: otherUserId,
              );
            },
          );
        },
      ),
    );
  }
}

class _ConnectionUserTile extends StatelessWidget {
  final String currentUserId;
  final String otherUserId;

  const _ConnectionUserTile({
    required this.currentUserId,
    required this.otherUserId,
  });

  Future<void> _removeConnection(BuildContext context) async {
    final theme = Theme.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Bağlantıyı kaldır'),
          content: const Text(
            'Bu kişiyle olan bağlantını kaldırmak istediğine emin misin?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Kaldır'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      // 1) Benim tarafımdaki dokümanı sil
      await FirebaseFirestore.instance
          .collection('connections')
          .doc(currentUserId)
          .collection('list')
          .doc(otherUserId)
          .delete();

      // 2) Karşı tarafın tarafındaki dokümanı sil
      await FirebaseFirestore.instance
          .collection('connections')
          .doc(otherUserId)
          .collection('list')
          .doc(currentUserId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı kaldırıldı.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bağlantı kaldırılamadı: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(otherUserId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text('Yükleniyor...'),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const ListTile(
            leading: CircleAvatar(child: Icon(Icons.person_off)),
            title: Text('Kullanıcı bulunamadı'),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final String name = data['name'] ?? 'İsimsiz';
        final String username = data['username'] ?? '';
        final String? photoUrl = data['photoUrl'];
        final String? role = data['role'];
        final String? location = data['location'];

        String subtitleText = '';
        if (role != null && role.isNotEmpty) {
          subtitleText = role;
        }
        if (location != null && location.isNotEmpty) {
          subtitleText =
          subtitleText.isEmpty ? location : '$subtitleText • $location';
        }

        return ListTile(
          leading: CircleAvatar(
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null ? const Icon(Icons.person) : null,
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (username.isNotEmpty) Text('@$username'),
              if (subtitleText.isNotEmpty) Text(subtitleText),
            ],
          ),
          onTap: () {
            // İstersen burada UserProfileScreen'e git
            // Navigator.of(context).push(
            //   MaterialPageRoute(
            //     builder: (_) => UserProfileScreen(
            //       userId: otherUserId,
            //       currentUserId: currentUserId,
            //     ),
            //   ),
            // );
          },
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () async {
              await _removeConnection(context);
            },
          ),
        );
      },
    );
  }
}
