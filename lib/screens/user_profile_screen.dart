// lib/screens/user_profile_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId; // Görüntülenen kullanıcı
  final String currentUserId; // Giriş yapmış kullanıcı

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.currentUserId,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

/// LinkedIn tarzı bağlantı durumu
class _ConnectionStatus {
  final bool isConnected; // İki taraf da bağlantı
  final bool outgoing; // Ben gönderdim, o daha kabul etmedi
  final bool incoming; // O gönderdi, bende bekliyor

  const _ConnectionStatus({
    this.isConnected = false,
    this.outgoing = false,
    this.incoming = false,
  });
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _updatingCover = false;
  bool _actionLoading = false;

  late Future<_ConnectionStatus> _connFuture;

  @override
  void initState() {
    super.initState();
    _connFuture = _loadConnectionStatus();
  }

  Future<_ConnectionStatus> _loadConnectionStatus() async {
    // Kendi profilimse bağlantı durumu gereksiz
    if (widget.userId == widget.currentUserId) {
      return const _ConnectionStatus();
    }

    final fs = FirebaseFirestore.instance;
    final me = widget.currentUserId;
    final other = widget.userId;

    // 1) Zaten bağlantı var mı?
    final connDoc = await fs
        .collection('connections')
        .doc(me)
        .collection('list')
        .doc(other)
        .get();

    if (connDoc.exists) {
      return const _ConnectionStatus(isConnected: true);
    }

    // 2) Benim gönderdiğim bekleyen istek var mı? (outgoing)
    final outDoc = await fs
        .collection('connectionRequests')
        .doc(me)
        .collection('outgoing')
        .doc(other)
        .get();

    if (outDoc.exists) {
      return const _ConnectionStatus(outgoing: true);
    }

    // 3) Bana gelen bekleyen istek var mı? (incoming)
    final inDoc = await fs
        .collection('connectionRequests')
        .doc(me)
        .collection('incoming')
        .doc(other)
        .get();

    if (inDoc.exists) {
      return const _ConnectionStatus(incoming: true);
    }

    // 4) Hiçbir şey yok
    return const _ConnectionStatus();
  }

  Future<void> _refreshConnectionStatus() async {
    setState(() {
      _connFuture = _loadConnectionStatus();
    });
  }

  Future<void> _changeCoverPhoto() async {
    if (_updatingCover) return;
    setState(() => _updatingCover = true);

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        setState(() => _updatingCover = false);
        return;
      }

      final file = File(picked.path);

      final ref = FirebaseStorage.instance
          .ref()
          .child('cover_photos')
          .child('${widget.userId}.jpg');

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'coverPhotoUrl': url});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kapak fotoğrafı güncellenemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingCover = false);
      }
    }
  }

  // ---------- BAĞLANTI AKSİYONLARI (LinkedIn mantığı) ----------

  Future<void> _sendConnectionRequest() async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);

    final fs = FirebaseFirestore.instance;
    final me = widget.currentUserId;
    final other = widget.userId;

    try {
      final batch = fs.batch();

      // Bana gelen kutusuna (other -> incoming)
      final incomingRef = fs
          .collection('connectionRequests')
          .doc(other)
          .collection('incoming')
          .doc(me);

      // Benim giden kutuma (me -> outgoing)
      final outgoingRef = fs
          .collection('connectionRequests')
          .doc(me)
          .collection('outgoing')
          .doc(other);

      final payload = {
        'from': me,
        'to': other,
        'createdAt': FieldValue.serverTimestamp(),
      };

      batch.set(incomingRef, payload);
      batch.set(outgoingRef, payload);

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı isteği gönderildi.')),
      );
      await _refreshConnectionStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek gönderilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _cancelConnectionRequest() async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);

    final fs = FirebaseFirestore.instance;
    final me = widget.currentUserId;
    final other = widget.userId;

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
      await _refreshConnectionStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek iptal edilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _acceptConnectionRequest() async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);

    final fs = FirebaseFirestore.instance;
    final me = widget.currentUserId;
    final other = widget.userId;

    try {
      final batch = fs.batch();
      final now = FieldValue.serverTimestamp();

      // 1) İstek kayıtlarını sil
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

      // 2) Bağlantı listelerine ekle (iki taraflı)
      final myConnRef =
      fs.collection('connections').doc(me).collection('list').doc(other);
      final otherConnRef =
      fs.collection('connections').doc(other).collection('list').doc(me);

      final payload = {
        'status': 'connected',
        'createdAt': now,
        'updatedAt': now,
      };

      batch.set(myConnRef, payload);
      batch.set(otherConnRef, payload);

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı isteği kabul edildi.')),
      );
      await _refreshConnectionStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek kabul edilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }



  Future<void> _declineConnectionRequest() async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);

    final fs = FirebaseFirestore.instance;
    final me = widget.currentUserId;
    final other = widget.userId;

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
      await _refreshConnectionStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek reddedilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  /// 🔥 Bağlantıyı kaldır (iki taraftan da connections sil)
  Future<void> _removeConnection() async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);

    final fs = FirebaseFirestore.instance;
    final me = widget.currentUserId;
    final other = widget.userId;

    try {
      final batch = fs.batch();

      final myRef = fs
          .collection('connections')
          .doc(me)
          .collection('list')
          .doc(other);

      final otherRef = fs
          .collection('connections')
          .doc(other)
          .collection('list')
          .doc(me);

      batch.delete(myRef);
      batch.delete(otherRef);

      await batch.commit();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı kaldırıldı.')),
      );

      await _refreshConnectionStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bağlantı kaldırılamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.userId == widget.currentUserId;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .get(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Kullanıcı bulunamadı.'));
          }

          final data = snap.data!.data()!;

          final name = (data['name'] ?? '').toString().trim();
          final username = (data['username'] ?? '').toString().trim();
          final photoUrl = data['photoUrl'];

          final role = (data['role'] ?? '').toString().trim();
          final location = (data['location'] ?? '').toString().trim();
          final bio = (data['bio'] ?? '').toString().trim();
          final coverPhoto = data['coverPhotoUrl'];

          final List<String> skills = (data['skills'] is List)
              ? (data['skills'] as List)
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
              : <String>[];

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // =============== KAPAK + AVATAR ===============
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Kapak
                    Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        image: coverPhoto != null
                            ? DecorationImage(
                          image: NetworkImage(coverPhoto),
                          fit: BoxFit.cover,
                        )
                            : null,
                        gradient: coverPhoto == null
                            ? const LinearGradient(
                          colors: [
                            Color(0xFF1976D2),
                            Color(0xFF42A5F5),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                            : null,
                      ),
                    ),

                    // Kapak değiştir butonu (sadece kendi profili)
                    if (isOwner)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.55),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: _updatingCover ? null : _changeCoverPhoto,
                          icon: _updatingCover
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Icon(Icons.camera_alt, size: 18),
                          label: const Text(
                            'Kapak fotoğrafı',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),

                    // Avatar (sol altta, kapağın üstüne taşmış)
                    Positioned(
                      left: 16,
                      bottom: -40,
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor:
                        Theme.of(context).scaffoldBackgroundColor,
                        child: CircleAvatar(
                          radius: 42,
                          backgroundImage: photoUrl != null
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl == null
                              ? const Icon(Icons.person, size: 42)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 56), // avatar boşluğu

                // =============== İSİM + ÜNVAN + ŞEHİR + USERNAME ===============
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? '(İsimsiz)' : name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),

                      if (role.isNotEmpty)
                        Text(
                          role,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade400,
                          ),
                        ),

                      if (location.isNotEmpty)
                        Text(
                          location,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),

                      if (username.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // =============== AKSİYON BUTONLARI (BAĞLANTI / MESAJ) ===============
                if (!isOwner)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: FutureBuilder<_ConnectionStatus>(
                      future: _connFuture,
                      builder: (context, snapStatus) {
                        if (snapStatus.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final status =
                            snapStatus.data ?? const _ConnectionStatus();

                        Widget leftButton;

                        if (status.isConnected) {
                          // ✅ Zaten bağlantılı → BAĞLANTIYI KALDIR
                          leftButton = OutlinedButton.icon(
                            onPressed: _actionLoading ? null : _removeConnection,
                            style: OutlinedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            icon: const Icon(Icons.link_off),
                            label: const Text('Bağlantıyı kaldır'),
                          );
                        } else if (status.outgoing) {
                          // 📤 Benim gönderdiğim bekleyen istek
                          leftButton = OutlinedButton(
                            onPressed: _actionLoading
                                ? null
                                : _cancelConnectionRequest,
                            style: OutlinedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: _actionLoading
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                                : const Text('İstek gönderildi'),
                          );
                        } else if (status.incoming) {
                          // 📥 Bana gelen istek
                          leftButton = Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _actionLoading
                                      ? null
                                      : _acceptConnectionRequest,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(999),
                                    ),
                                  ),
                                  child: _actionLoading
                                      ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                      : const Text('Kabul et'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _actionLoading
                                      ? null
                                      : _declineConnectionRequest,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(999),
                                    ),
                                  ),
                                  child: const Text('Reddet'),
                                ),
                              ),
                            ],
                          );

                          return leftButton;
                        } else {
                          // Hiç ilişki yok → Bağlantı ekle
                          leftButton = ElevatedButton(
                            onPressed: _actionLoading
                                ? null
                                : _sendConnectionRequest,
                            style: ElevatedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: _actionLoading
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Text('Bağlantı ekle'),
                          );
                        }

                        // Normal durumda: sol buton + sağda "Mesaj gönder"
                        return Row(
                          children: [
                            Expanded(child: leftButton),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  // TODO: Mesaj ekranına git
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(999),
                                  ),
                                ),
                                child: const Text('Mesaj gönder'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 16),

                // =============== HAKKINDA ===============
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'Hakkında',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color:
                      isDark ? const Color(0xFF1F1F1F) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      bio.isEmpty
                          ? 'Bu kullanıcı henüz bir bio eklemedi.'
                          : bio,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                        isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // =============== YETENEKLER ===============
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'Yetenekler',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: skills.isEmpty
                      ? Text(
                    'Henüz eklenmiş bir yetenek yok.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  )
                      : Wrap(
                    spacing: 8,
                    runSpacing: -4,
                    children: skills
                        .map(
                          (s) => Chip(
                        label: Text(s),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                      ),
                    )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}
