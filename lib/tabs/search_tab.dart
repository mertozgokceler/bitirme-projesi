import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/connection_requests_screen.dart';
import '../screens/user_profile_screen.dart';
import '../theme/app_colors.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  static const String kRecentViewedKey = 'recent_viewed_users_v1';

  final _qCtrl = TextEditingController();
  final _fs = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  DateTime _lastType = DateTime.now();
  List<String> _history = [];
  SharedPreferences? _prefs;

  List<Map<String, dynamic>> _recentViewed = [];
  bool _recentLoading = false;

  @override
  void initState() {
    super.initState();
    _qCtrl.addListener(_onChanged);
    _initPrefs();
  }

  @override
  void dispose() {
    _qCtrl.removeListener(_onChanged);
    _qCtrl.dispose();
    super.dispose();
  }

  // =========================================================
  // ✅ BACKGROUND (Home ile aynı dil)
  // =========================================================
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

  // =========================================================
  // PREFS / HISTORY / RECENT
  // =========================================================
  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _history = _prefs?.getStringList('search_history') ?? [];
    });
    await _loadRecentViewed();
  }

  String _formatRelativeTime(int tsMs) {
    if (tsMs <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 10) return 'Şimdi';
    if (diff.inSeconds < 60) return '${diff.inSeconds} sn önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';

    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    return '$d.$m.$y';
  }

  Future<void> _addRecentViewed(String uid) async {
    if (uid.trim().isEmpty) return;

    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kRecentViewedKey) ?? [];

    raw.removeWhere((x) => x.startsWith('$uid|') || x == uid);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    raw.insert(0, '$uid|$nowMs');

    if (raw.length > 30) raw.removeRange(30, raw.length);

    await prefs.setStringList(kRecentViewedKey, raw);
    await _loadRecentViewed();
  }

  Future<void> _removeRecentViewed(String uid) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kRecentViewedKey) ?? [];

    raw.removeWhere((x) => x.startsWith('$uid|') || x == uid);

    await prefs.setStringList(kRecentViewedKey, raw);
    await _loadRecentViewed();
  }

  Future<void> _clearRecentViewed() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove(kRecentViewedKey);
    if (!mounted) return;
    setState(() => _recentViewed.clear());
  }

  Future<void> _loadRecentViewed() async {
    if (!mounted) return;
    setState(() => _recentLoading = true);

    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      final raw = prefs.getStringList(kRecentViewedKey) ?? [];

      final List<Map<String, dynamic>> parsed = [];
      final seen = <String>{};

      for (final s in raw) {
        final parts = s.split('|');
        if (parts.isEmpty) continue;
        final uid = parts[0].trim();
        if (uid.isEmpty) continue;
        if (seen.contains(uid)) continue;
        seen.add(uid);

        int ts = 0;
        if (parts.length >= 2) {
          ts = int.tryParse(parts[1]) ?? 0;
        }
        parsed.add({'uid': uid, 'ts': ts});
      }

      final List<Map<String, dynamic>> enriched = [];
      for (final it in parsed) {
        final uid = it['uid'] as String;
        final ts = it['ts'] as int;

        try {
          final doc = await _fs.collection('users').doc(uid).get();
          if (!doc.exists) continue;
          final data = doc.data() as Map<String, dynamic>? ?? {};
          enriched.add({
            'uid': uid,
            'ts': ts,
            'name': (data['name'] ?? '').toString(),
            'username': (data['username'] ?? '').toString(),
            'photoUrl': data['photoUrl'],
            'role': data['role'],
          });
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _recentViewed = enriched;
        _recentLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _recentLoading = false);
      debugPrint('DEBUG[recent] load error: $e');
    }
  }

  Future<void> _saveHistory() async {
    await _prefs?.setStringList('search_history', _history);
  }

  String trLower(String s) =>
      s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  void _addToHistory(String q) {
    final key = trLower(q);
    if (key.isEmpty) return;
    _history.removeWhere((e) => e == key);
    _history.insert(0, key);
    if (_history.length > 20) _history = _history.sublist(0, 20);
    _saveHistory();
  }

  Future<void> _clearHistory() async {
    await _prefs?.remove('search_history');
    if (!mounted) return;

    setState(() {
      _history.clear();
      _qCtrl.clear();
      _results.clear();
      _loading = false;
    });

    FocusScope.of(context).unfocus();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Arama geçmişi temizlendi')),
    );
  }

  void _onChanged() async {
    _lastType = DateTime.now();
    final captured = _lastType;

    await Future.delayed(const Duration(milliseconds: 350));
    if (captured != _lastType) return;

    _search(_qCtrl.text.trim());
  }

  String _endBound(String s) => '$s\uf8ff';

  Future<void> _search(String q) async {
    if (!mounted) return;

    if (q.isEmpty) {
      setState(() {
        _results.clear();
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      _addToHistory(q);

      final key = trLower(q);
      final end = _endBound(key);

      Future<QuerySnapshot<Map<String, dynamic>>> q1() => _fs
          .collection('users')
          .where('isSearchable', isEqualTo: true)
          .orderBy('usernameLower')
          .startAt([key])
          .endAt([end])
          .limit(20)
          .get();

      Future<QuerySnapshot<Map<String, dynamic>>> q2() => _fs
          .collection('users')
          .where('isSearchable', isEqualTo: true)
          .orderBy('nameLower')
          .startAt([key])
          .endAt([end])
          .limit(20)
          .get();

      var snaps = await Future.wait([q1(), q2()]);

      if (snaps[0].docs.isEmpty && snaps[1].docs.isEmpty) {
        final f1 = _fs
            .collection('users')
            .where('isSearchable', isEqualTo: true)
            .orderBy('username')
            .startAt([q])
            .endAt([_endBound(q)])
            .limit(20)
            .get();

        final f2 = _fs
            .collection('users')
            .where('isSearchable', isEqualTo: true)
            .orderBy('name')
            .startAt([q])
            .endAt([_endBound(q)])
            .limit(20)
            .get();

        snaps = await Future.wait([f1, f2]);
      }

      final Map<String, Map<String, dynamic>> uniq = {};
      for (final s in snaps) {
        for (final d in s.docs) {
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

      final list = uniq.values.toList()
        ..sort((a, b) {
          final aExact = a['username'].toString().toLowerCase() == key ||
              a['name'].toString().toLowerCase().startsWith(key);
          final bExact = b['username'].toString().toLowerCase() == key ||
              b['name'].toString().toLowerCase().startsWith(key);
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;
          return a['name']
              .toString()
              .toLowerCase()
              .compareTo(b['name'].toString().toLowerCase());
        });

      if (!mounted) return;
      setState(() {
        _results = list;
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

  // =========================================================
  // UI HELPERS
  // =========================================================
  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(16, 10, 16, 10),
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
    double radius = 22,
  }) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(isDark ? 0.78 : 0.92),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.outline.withOpacity(0.75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  PreferredSizeWidget _buildTopBar() {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return AppBar(
      title: const Text('Kullanıcı Ara'),
      centerTitle: false,

      // ✅ AppBar'ın arka planını tamamen yok et
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,

      // ✅ yazı/icon rengi
      foregroundColor: cs.onSurface,

      actions: [
        IconButton(
          icon: const Icon(Icons.group_add_outlined),
          tooltip: 'Bağlantı istekleri',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConnectionRequestsScreen()),
            );
          },
        ),
        const SizedBox(width: 6),
      ],
    );
  }


  Widget _buildSearchBox() {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      radius: 22,
      child: Column(
        children: [
          TextField(
            controller: _qCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(_qCtrl.text.trim()),
            decoration: InputDecoration(
              hintText: 'Kullanıcı adı veya Ad Soyad',
              prefixIcon: Icon(Icons.search, color: cs.primary),
              suffixIcon: IconButton(
                tooltip: 'Arama geçmişini sil',
                icon: Icon(Icons.delete_sweep_outlined, color: cs.onSurface.withOpacity(0.75)),
                onPressed: _clearHistory,
              ),
              filled: true,
              fillColor: cs.surface.withOpacity(0.55),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: cs.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: cs.outline.withOpacity(0.8)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: cs.primary, width: 1.4),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                backgroundColor: cs.surface.withOpacity(0.35),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryChips() {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    if (_qCtrl.text.isNotEmpty || _history.isEmpty) return const SizedBox.shrink();

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Arama Geçmişi',
                style: t.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearHistory,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Temizle'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: -6,
              children: _history
                  .map(
                    (h) => InputChip(
                  label: Text(h),
                  onPressed: () {
                    _qCtrl.text = h;
                    _search(h);
                  },
                ),
              )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String text) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: _glassCard(
          margin: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          radius: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded, size: 42, color: cs.primary),
              const SizedBox(height: 10),
              Text(
                text,
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withOpacity(0.85),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userTile({
    required Map<String, dynamic> u,
    required TextStyle usernameStyle,
    required VoidCallback onTap,
    VoidCallback? onRemove,
    String? trailingCaption,
  }) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final name = (u['name'] ?? '').toString().trim();
    final username = (u['username'] ?? '').toString().trim();
    final role = (u['role'] ?? '').toString().trim();
    final photoUrl = (u['photoUrl'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(isDark ? 0.78 : 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withOpacity(0.70)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: cs.surface,
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.75)) : null,
        ),
        title: Text(
          name.isEmpty ? '(İsimsiz)' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: usernameStyle,
            ),
            if (role.isNotEmpty)
              Text(
                role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.78),
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            if (trailingCaption != null && trailingCaption.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  trailingCaption,
                  style: TextStyle(
                    fontSize: 11.3,
                    color: AppColors.subtleText(t),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        trailing: onRemove == null
            ? Icon(Icons.chevron_right_rounded, color: cs.onSurface.withOpacity(0.55))
            : IconButton(
          tooltip: 'Listeden kaldır',
          icon: Icon(Icons.close, color: cs.onSurface.withOpacity(0.55)),
          onPressed: onRemove,
        ),
        onTap: onTap,
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isQueryEmpty = _qCtrl.text.trim().isEmpty;

    final usernameStyle = TextStyle(
      color: AppColors.subtleText(theme),
      fontWeight: FontWeight.w700,
    );

    return Stack(
      children: [
        Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
        Positioned(
          top: -120,
          left: -80,
          child: _GlowBlob(
            size: 260,
            color: theme.colorScheme.primary.withOpacity(0.20),
          ),
        ),
        Positioned(
          bottom: -140,
          right: -90,
          child: _GlowBlob(
            size: 280,
            color: theme.colorScheme.tertiary.withOpacity(0.18),
          ),
        ),

        Scaffold(
          backgroundColor: Colors.transparent,
          // ❌ extendBodyBehindAppBar: true,  // BUNU SİL
          appBar: _buildTopBar(), // Topbar şeffaf olmalı
          body: Column(
            children: [
              _buildSearchBox(),
              _buildHistoryChips(),
              Expanded(
                child: isQueryEmpty
                    ? _buildRecent(usernameStyle)
                    : _buildResults(usernameStyle),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildRecent(TextStyle usernameStyle) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_recentLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_recentViewed.isEmpty) {
      return _emptyState('Henüz herhangi bir kullanıcı aramadın.');
    }

    return Column(
      children: [
        _glassCard(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          radius: 22,
          child: Row(
            children: [
              Text(
                'Son Baktığın Hesaplar',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14.2,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearRecentViewed,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Temizle'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 2, bottom: 16),
            itemCount: _recentViewed.length,
            itemBuilder: (context, i) {
              final u = _recentViewed[i];
              final uid = (u['uid'] ?? '').toString();
              final ts = (u['ts'] ?? 0) as int;
              final when = _formatRelativeTime(ts);

              return _userTile(
                u: u,
                usernameStyle: usernameStyle,
                trailingCaption: when,
                onRemove: () => _removeRecentViewed(uid),
                onTap: () async {
                  await _addRecentViewed(uid);
                  final currentUserId = FirebaseAuth.instance.currentUser!.uid;

                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        userId: uid,
                        currentUserId: currentUserId,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResults(TextStyle usernameStyle) {
    if (_results.isEmpty) {
      return _emptyState('Sonuç yok');
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final u = _results[i];
        final uid = (u['uid'] ?? '').toString();

        return _userTile(
          u: u,
          usernameStyle: usernameStyle,
          onTap: () async {
            final currentUserId = FirebaseAuth.instance.currentUser!.uid;
            await _addRecentViewed(uid);

            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  userId: uid,
                  currentUserId: currentUserId,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ================== GLOW BLOB (Home ile aynı) ==================
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
