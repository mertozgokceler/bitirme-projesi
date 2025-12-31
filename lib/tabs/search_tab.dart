import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/connection_requests_screen.dart';
import '../screens/user_profile_screen.dart';
import '../theme/app_colors.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showHistory = _qCtrl.text.isEmpty && _history.isNotEmpty;

    final usernameStyle = TextStyle(
      color: AppColors.subtleText(theme),
    );

    final isQueryEmpty = _qCtrl.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanıcı Ara'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Bağlantı istekleri',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ConnectionRequestsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _qCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Kullanıcı adı veya Ad Soyad',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Arama geçmişini sil',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _clearHistory,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _search(_qCtrl.text.trim()),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (showHistory)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Align(
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
            ),
          if (isQueryEmpty)
            Expanded(
              child: _recentLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_recentViewed.isEmpty
                  ? Center(
                child: Text(
                  'Henüz herhangi bir kullanıcı aramadın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.subtleText(theme)),
                ),
              )
                  : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      children: [
                        const Text(
                          'Son Baktığın Hesaplar',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
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
                    child: ListView.separated(
                      itemCount: _recentViewed.length,
                      separatorBuilder: (_, __) =>
                      const Divider(height: 1, thickness: 0.5),
                      itemBuilder: (context, i) {
                        final u = _recentViewed[i];
                        final name = (u['name'] ?? '').toString().trim();
                        final username =
                        (u['username'] ?? '').toString().trim();
                        final role = (u['role'] ?? '').toString().trim();
                        final uid = (u['uid'] ?? '').toString();
                        final ts = (u['ts'] ?? 0) as int;

                        final when = _formatRelativeTime(ts);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: u['photoUrl'] != null
                                ? NetworkImage(u['photoUrl'])
                                : null,
                            child: u['photoUrl'] == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(
                            name.isEmpty ? '(İsimsiz)' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                                ),
                              if (when.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    when,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.subtleText(theme),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: 'Listeden kaldır',
                            icon: Icon(
                              Icons.close,
                              color: AppColors.subtleText(theme),
                            ),
                            onPressed: () => _removeRecentViewed(uid),
                          ),
                          onTap: () async {
                            await _addRecentViewed(uid);
                            final currentUserId =
                                FirebaseAuth.instance.currentUser!.uid;

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
              )),
            )
          else
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('Sonuç yok'))
                  : ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, __) =>
                const Divider(height: 1, thickness: 0.5),
                itemBuilder: (context, i) {
                  final u = _results[i];
                  final name = (u['name'] ?? '').toString().trim();
                  final username = (u['username'] ?? '').toString().trim();
                  final role = (u['role'] ?? '').toString().trim();

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: u['photoUrl'] != null
                          ? NetworkImage(u['photoUrl'])
                          : null,
                      child: u['photoUrl'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(
                      name.isEmpty ? '(İsimsiz)' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: role.isNotEmpty
                        ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: usernameStyle,
                        ),
                        Text(
                          role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                        : Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: usernameStyle,
                    ),
                    onTap: () async {
                      final currentUserId =
                          FirebaseAuth.instance.currentUser!.uid;

                      final uid = (u['uid'] ?? '').toString();
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
              ),
            ),
        ],
      ),
    );
  }
}