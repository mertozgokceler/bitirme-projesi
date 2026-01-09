// lib/screens/new_chat_search_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_detail_screen.dart';
import '../utils/chat_utils.dart';
import '../services/call_service.dart';

class NewChatSearchScreen extends StatefulWidget {
  final CallService callService;

  const NewChatSearchScreen({
    super.key,
    required this.callService,
  });

  @override
  State<NewChatSearchScreen> createState() => _NewChatSearchScreenState();
}

class _NewChatSearchScreenState extends State<NewChatSearchScreen> {
  final _qCtrl = TextEditingController();
  final _fs = FirebaseFirestore.instance;

  // global search results
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  Future<List<Map<String, dynamic>>>? _connectionsUsersFuture;
  List<String> _lastConnUids = [];

  String trLower(String s) =>
      s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
  String _endBound(String s) => '$s\uf8ff';

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  // ========= GLOBAL SEARCH (users) =========
  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
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
      final key = trLower(q.trim());
      final end = _endBound(key);

      final q1 = _fs
          .collection('users')
          .where('isSearchable', isEqualTo: true)
          .orderBy('usernameLower')
          .startAt([key])
          .endAt([end])
          .limit(20)
          .get();

      final q2 = _fs
          .collection('users')
          .where('isSearchable', isEqualTo: true)
          .orderBy('nameLower')
          .startAt([key])
          .endAt([end])
          .limit(20)
          .get();

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
            'location': data['location'],
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

  // ========= OPEN CHAT (NO CREATE) =========
  Future<void> _openChatWithUser(Map<String, dynamic> otherUser) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final currentUid = currentUser.uid;
    final otherUid = (otherUser['uid'] ?? '').toString();
    if (otherUid.isEmpty) return;

    final chatId = buildChatId(currentUid, otherUid);

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(
          chatId: chatId,
          otherUser: otherUser,
          callService: widget.callService,
        ),
      ),
    );
  }

  // ========= CONNECTION USERS (BATCH FETCH) =========
  Future<List<Map<String, dynamic>>> _fetchUsersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];

    const chunkSize = 10; // Firestore whereIn limit
    final List<Map<String, dynamic>> out = [];

    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        (i + chunkSize > ids.length) ? ids.length : i + chunkSize,
      );

      final snap = await _fs
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final d in snap.docs) {
        final data = d.data();
        out.add({
          'uid': d.id,
          'name': (data['name'] ?? '').toString(),
          'username': (data['username'] ?? '').toString(),
          'photoUrl': data['photoUrl'],
          'role': data['role'],
          'location': data['location'],
        });
      }
    }

    // keep connections order
    final map = {
      for (final u in out) (u['uid'] ?? '').toString(): u,
    };
    return ids.where(map.containsKey).map((id) => map[id]!).toList();
  }

  // ========= UI helpers =========
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
      title: const Text('Yeni Sohbet'),
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

  Widget _glassCard(BuildContext context, {required Widget child}) {
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

  Widget _sectionHeader(BuildContext context, String title, {IconData? icon}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.65)),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: cs.onSurface.withOpacity(0.80),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userTile(BuildContext context, Map<String, dynamic> u) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final photoUrl = (u['photoUrl'] ?? '').toString();
    final name = (u['name'] ?? '').toString().trim();
    final username = (u['username'] ?? '').toString().trim();
    final role = (u['role'] ?? '').toString().trim();
    final location = (u['location'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: _glassCard(
        context,
        child: ListTile(
          onTap: () => _openChatWithUser(u),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(2.2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.outline.withOpacity(0.60)),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: cs.surface,
              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child: photoUrl.isEmpty
                  ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.75))
                  : null,
            ),
          ),
          title: Text(
            name.isEmpty ? '(İsimsiz)' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (username.isNotEmpty)
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: cs.primary.withOpacity(0.95),
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
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(0.78),
                      ),
                    ),
                  ),
                if (location.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(0.65),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6E44FF), Color(0xFF00C4FF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.18 : 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Text(
              'Sohbet',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterLocal(List<Map<String, dynamic>> list, String q) {
    if (q.trim().isEmpty) return list;
    final key = trLower(q.trim());
    bool hit(String v) => trLower(v).contains(key);

    return list.where((u) {
      final name = (u['name'] ?? '').toString();
      final username = (u['username'] ?? '').toString();
      final role = (u['role'] ?? '').toString();
      final loc = (u['location'] ?? '').toString();
      return hit(name) || hit(username) || hit(role) || hit(loc);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Stack(
      children: [
        Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _buildTopBar(),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: _glassCard(
                  context,
                  child: TextField(
                    controller: _qCtrl,
                    autofocus: true,
                    style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Bağlantılarında veya kullanıcılar arasında ara',
                      hintStyle: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withOpacity(0.60),
                      ),
                      prefixIcon: Icon(Icons.search, color: cs.onSurface.withOpacity(0.55)),
                      suffixIcon: _qCtrl.text.isEmpty
                          ? null
                          : IconButton(
                        onPressed: () {
                          _qCtrl.clear();
                          _search('');
                          setState(() {});
                        },
                        icon: Icon(Icons.close_rounded,
                            color: cs.onSurface.withOpacity(0.55)),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: cs.surface.withOpacity(isDark ? 0.10 : 0.40),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    onChanged: (v) {
                      setState(() {});
                      _search(v);
                    },
                  ),
                ),
              ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      backgroundColor: cs.onSurface.withOpacity(isDark ? 0.08 : 0.06),
                    ),
                  ),
                ),
              Expanded(
                child: (uid == null)
                    ? Center(
                  child: Text(
                    'Giriş yapmalısın.',
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.80),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _fs
                      .collection('connections')
                      .doc(uid)
                      .collection('list')
                      .orderBy('createdAt', descending: true)
                      .limit(200)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final connDocs = snap.data?.docs ?? [];
                    final connUids = connDocs.map((d) => d.id).toList();

                    // cache future when connections list changes
                    final bool changed = connUids.length != _lastConnUids.length ||
                        !_listEquals(connUids, _lastConnUids);

                    if (changed) {
                      _lastConnUids = List<String>.from(connUids);
                      _connectionsUsersFuture = _fetchUsersByIds(_lastConnUids);
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      children: [
                        _sectionHeader(context, 'Bağlantıların',
                            icon: Icons.people_alt_rounded),
                        if (connUids.isEmpty)
                          _glassCard(
                            context,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Henüz bağlantın yok.',
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.80),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          )
                        else
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: _connectionsUsersFuture,
                            builder: (context, us) {
                              if (us.connectionState == ConnectionState.waiting) {
                                return _glassCard(
                                  context,
                                  child: const ListTile(title: Text('Yükleniyor...')),
                                );
                              }

                              final users = us.data ?? [];
                              final filteredConnections =
                              _filterLocal(users, _qCtrl.text);

                              if (filteredConnections.isEmpty) {
                                return _glassCard(
                                  context,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      'Bağlantılarında sonuç bulunamadı.',
                                      style: TextStyle(
                                        color: cs.onSurface.withOpacity(0.80),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: filteredConnections
                                    .map((u) => _userTile(context, u))
                                    .toList(),
                              );
                            },
                          ),

                        if (_qCtrl.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _sectionHeader(context, 'Diğer kullanıcılar',
                              icon: Icons.public_rounded),
                          if (_results.isEmpty && !_loading)
                            _glassCard(
                              context,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Sonuç bulunamadı.',
                                  style: TextStyle(
                                    color: cs.onSurface.withOpacity(0.80),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                          else
                            ..._results
                                .where((u) =>
                            !_lastConnUids.contains((u['uid'] ?? '').toString()))
                                .map((u) => _userTile(context, u)),
                        ],
                      ],
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

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
