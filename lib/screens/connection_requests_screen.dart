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

  Future<void> _acceptRequest(String otherUserId) async {
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

      final myConnRef =
      fs.collection('connections').doc(me).collection('list').doc(other);
      final otherConnRef =
      fs.collection('connections').doc(other).collection('list').doc(me);

      final payload = {'createdAt': FieldValue.serverTimestamp()};

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

  PreferredSizeWidget _buildTopBar() {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return AppBar(
      title: const Text('Bağlantı İstekleri'),
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: cs.onSurface),
      titleTextStyle: TextStyle(
        color: cs.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(54),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(isDark ? 0.60 : 0.90),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline.withOpacity(0.70)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: TabBar(
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: cs.onPrimary,
            unselectedLabelColor: cs.onSurface.withOpacity(0.72),
            labelStyle: const TextStyle(fontWeight: FontWeight.w900),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6E44FF), Color(0xFF00C4FF)],
              ),
            ),
            tabs: const [
              Tab(text: 'Gelenler'),
              Tab(text: 'Gönderilenler'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String text) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(isDark ? 0.72 : 0.92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cs.outline.withOpacity(0.70)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.20 : 0.06),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined, size: 38, color: cs.primary),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.86),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listShell({required Widget child}) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(isDark ? 0.70 : 0.92),
        borderRadius: BorderRadius.circular(24),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DefaultTabController(
      length: 2,
      child: Stack(
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
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _buildTopBar(),
            body: TabBarView(
              children: [
                // GELENLER (tam genişlik kart)
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _incomingStream(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return _emptyState('Gelen bağlantı isteğin yok.');
                    }

                    final docs = snap.data!.docs;

                    return _listShell(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final otherId = docs[index].id;
                          return _WideRequestTile(
                            userId: otherId,
                            currentUserId: _currentUid,
                            mode: _WideRequestTileMode.incoming,
                            loading: _loadingAction,
                            onAccept: () => _acceptRequest(otherId),
                            onDecline: () => _declineRequest(otherId),
                          );
                        },
                      ),
                    );
                  },
                ),

                // GÖNDERİLENLER (tam genişlik kart)
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _outgoingStream(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return _emptyState('Gönderilmiş bağlantı isteğin yok.');
                    }

                    final docs = snap.data!.docs;

                    return _listShell(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final otherId = docs[index].id;
                          return _WideRequestTile(
                            userId: otherId,
                            currentUserId: _currentUid,
                            mode: _WideRequestTileMode.outgoing,
                            loading: _loadingAction,
                            onCancel: () => _cancelOutgoing(otherId),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
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
          gradient: RadialGradient(colors: [color, color.withOpacity(0.0)]),
        ),
      ),
    );
  }
}

enum _WideRequestTileMode { incoming, outgoing }

class _WideRequestTile extends StatelessWidget {
  final String userId;
  final String currentUserId;
  final _WideRequestTileMode mode;
  final bool loading;

  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;

  const _WideRequestTile({
    required this.userId,
    required this.currentUserId,
    required this.mode,
    required this.loading,
    this.onAccept,
    this.onDecline,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: fs.collection('users').doc(userId).get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _shell(
            context,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Yükleniyor...'),
                ],
              ),
            ),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          return _shell(
            context,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Kullanıcı bulunamadı',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          );
        }

        final data = snap.data!.data()!;
        final name = (data['name'] ?? '').toString().trim();
        final username = (data['username'] ?? '').toString().trim();
        final role = (data['role'] ?? '').toString().trim();
        final photoUrl = (data['photoUrl'] ?? '').toString().trim();

        return _shell(
          context,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    padding: const EdgeInsets.all(2.2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.outline.withOpacity(0.60)),
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: cs.surface,
                      backgroundImage:
                      photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                      child: photoUrl.isEmpty
                          ? Icon(Icons.person,
                          color: cs.onSurface.withOpacity(0.75))
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Metinler (geniş alan)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? '(İsimsiz)' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        if (username.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: cs.primary.withOpacity(0.95),
                              ),
                            ),
                          ),
                        if (role.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              role,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface.withOpacity(0.78),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Aksiyonlar (overflow yapmayacak şekilde kompakt)
                  if (mode == _WideRequestTileMode.incoming)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: loading ? null : onDecline,
                          style: TextButton.styleFrom(
                            foregroundColor: cs.onSurface.withOpacity(0.82),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Reddet',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _PrimaryMiniButton(
                          loading: loading,
                          label: 'Kabul',
                          onPressed: onAccept!,
                        ),
                      ],
                    )
                  else
                    TextButton.icon(
                      onPressed: loading ? null : onCancel,
                      icon: loading
                          ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.close_rounded, size: 18),
                      label: const Text(
                        'İptal',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.onSurface.withOpacity(0.82),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _shell(BuildContext context, {required Widget child}) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(isDark ? 0.62 : 0.92),
        borderRadius: BorderRadius.circular(16), // kutu hissi
        border: Border.all(color: cs.outline.withOpacity(0.70)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.16 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PrimaryMiniButton extends StatelessWidget {
  final bool loading;
  final String label;
  final VoidCallback onPressed;

  const _PrimaryMiniButton({
    required this.loading,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: loading ? 0.75 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: loading ? null : onPressed,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6E44FF), Color(0xFF00C4FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
