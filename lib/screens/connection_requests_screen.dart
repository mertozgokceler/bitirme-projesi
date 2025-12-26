// lib/screens/connection_requests_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'user_profile_screen.dart';

class ConnectionRequestsScreen extends StatefulWidget {
  const ConnectionRequestsScreen({super.key});

  @override
  State<ConnectionRequestsScreen> createState() =>
      _ConnectionRequestsScreenState();
}

class _ConnectionRequestsScreenState extends State<ConnectionRequestsScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loadingAction = false;

  String get _currentUid => _auth.currentUser!.uid;

  // ---------------- INCOMING / OUTGOING STREAMLERİ ----------------

  Stream<QuerySnapshot<Map<String, dynamic>>> _incomingStream() {
    return _fs
        .collection('connectionRequests')
        .doc(_currentUid)
        .collection('incoming')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _outgoingStream() {
    return _fs
        .collection('connectionRequests')
        .doc(_currentUid)
        .collection('outgoing')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ---------------- AKSİYONLAR (KABUL / RED / İPTAL) ----------------

  Future<void> _acceptRequest(String otherUserId) async {
    if (_loadingAction) return;
    setState(() => _loadingAction = true);

    final fs = _fs;
    final me = _currentUid;
    final other = otherUserId;

    try {
      final batch = fs.batch();

      // İstek kayıtlarını sil
      final myIncomingRef = fs
          .collection('connectionRequests')
          .doc(me)
          .collection('incoming')
          .doc(other);

      final otherOutgoingRef = fs
          .collection('connectionRequests')
          .doc(other)
          .collection('outgoing')
          .doc(me);

      batch.delete(myIncomingRef);
      batch.delete(otherOutgoingRef);

      // Bağlantı listelerine ekle (iki taraflı)
      final myConnRef =
      fs.collection('connections').doc(me).collection('list').doc(other);
      final otherConnRef =
      fs.collection('connections').doc(other).collection('list').doc(me);

      final payload = {
        'createdAt': FieldValue.serverTimestamp(),
      };

      batch.set(myConnRef, payload);
      batch.set(otherConnRef, payload);

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı isteği kabul edildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek kabul edilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  Future<void> _declineRequest(String otherUserId) async {
    if (_loadingAction) return;
    setState(() => _loadingAction = true);

    final fs = _fs;
    final me = _currentUid;
    final other = otherUserId;

    try {
      final batch = fs.batch();

      final myIncomingRef = fs
          .collection('connectionRequests')
          .doc(me)
          .collection('incoming')
          .doc(other);

      final otherOutgoingRef = fs
          .collection('connectionRequests')
          .doc(other)
          .collection('outgoing')
          .doc(me);

      batch.delete(myIncomingRef);
      batch.delete(otherOutgoingRef);

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı isteği reddedildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek reddedilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  Future<void> _cancelOutgoing(String otherUserId) async {
    if (_loadingAction) return;
    setState(() => _loadingAction = true);

    final fs = _fs;
    final me = _currentUid;
    final other = otherUserId;

    try {
      final batch = fs.batch();

      final incomingRef = fs
          .collection('connectionRequests')
          .doc(other)
          .collection('incoming')
          .doc(me);

      final outgoingRef = fs
          .collection('connectionRequests')
          .doc(me)
          .collection('outgoing')
          .doc(other);

      batch.delete(incomingRef);
      batch.delete(outgoingRef);

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı isteği iptal edildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek iptal edilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bağlantı İstekleri'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Gelenler'),
              Tab(text: 'Gönderilenler'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // GELEN İSTEKLER
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _incomingStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Gelen bağlantı isteğin yok.'),
                  );
                }

                final docs = snap.data!.docs;

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1, thickness: 0.4),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final d = docs[index];
                    final otherId = d.id; // incoming/{otherId}
                    return _UserPreviewTile(
                      userId: otherId,
                      currentUserId: _currentUid,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _loadingAction
                                ? null
                                : () => _declineRequest(otherId),
                            child: const Text('Reddet'),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: _loadingAction
                                ? null
                                : () => _acceptRequest(otherId),
                            style: ElevatedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: _loadingAction
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Text('Kabul et'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),

            // GÖNDERİLEN İSTEKLER
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _outgoingStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Gönderilmiş bağlantı isteğin yok.'),
                  );
                }

                final docs = snap.data!.docs;

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1, thickness: 0.4),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final d = docs[index];
                    final otherId = d.id; // outgoing/{otherId}

                    return _UserPreviewTile(
                      userId: otherId,
                      currentUserId: _currentUid,
                      trailing: TextButton(
                        onPressed: _loadingAction
                            ? null
                            : () => _cancelOutgoing(otherId),
                        child: _loadingAction
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Text('İsteği iptal et'),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Küçük kullanıcı kartı: foto + isim + rol + şehir
class _UserPreviewTile extends StatelessWidget {
  final String userId;
  final String currentUserId;
  final Widget? trailing;

  const _UserPreviewTile({
    required this.userId,
    required this.currentUserId,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: fs.collection('users').doc(userId).get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const ListTile(
            title: Text('Yükleniyor...'),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          return const ListTile(
            title: Text('Kullanıcı bulunamadı'),
          );
        }

        final data = snap.data!.data()!;
        final name = (data['name'] ?? '').toString().trim();
        final username = (data['username'] ?? '').toString().trim();
        final role = (data['role'] ?? '').toString().trim();
        final location = (data['location'] ?? '').toString().trim();
        final photoUrl = data['photoUrl'];

        return ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  userId: userId,
                  currentUserId: currentUserId,
                ),
              ),
            );
          },
          leading: CircleAvatar(
            backgroundImage:
            photoUrl != null ? NetworkImage(photoUrl) : null,
            child:
            photoUrl == null ? const Icon(Icons.person) : null,
          ),
          title: Text(
            name.isEmpty ? '(İsimsiz)' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (role.isNotEmpty)
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              if (location.isNotEmpty)
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey[700],
                  ),
                ),
              if (username.isNotEmpty)
                Text(
                  '@$username',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.grey[600],
                  ),
                ),
            ],
          ),
          trailing: trailing,
        );
      },
    );
  }
}
