// lib/tabs/home_tab.dart

import 'dart:convert';
import 'dart:math';

import 'package:lottie/lottie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';

import '../screens/news_list_screen.dart';
import '../screens/news_detail_screen.dart';
import '../utils/premium_utils.dart';
import '../widgets/stories_strip.dart';


class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String _firstName = '';
  String? _userPhotoUrl;
  bool _isLoadingUserData = true;
  String _motivationQuote = '';

  // ✅ Kullanıcı map'ini tut: UI hard-gate için şart
  Map<String, dynamic> _currentUserMap = {};

  List<dynamic> _newsArticles = [];
  bool _isLoadingNews = true;
  bool _isSuggestionsExpanded = true;

  final String _newsApiKey = dotenv.env['GNEWS_API_KEY'] ?? '';

  // =========================================================
  // ✅ Future cache + cleanup guard
  // =========================================================
  Future<Map<String, Map<String, dynamic>>>? _jobsFuture;
  String _jobsKey = '';
  String _lastCleanupKey = '';

  Future<Map<String, Map<String, dynamic>>>? _companiesFuture;
  String _companiesKey = '';

  @override
  void initState() {
    super.initState();
    _loadMotivationQuote();
    _fetchUserData();
    _fetchTechNews();
  }

  // =========================================================
  // USER
  // =========================================================
  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingUserData = false);
      return;
    }

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!mounted) return;

      if (doc.exists) {
        final userData = doc.data() ?? {};
        setState(() {
          _currentUserMap = Map<String, dynamic>.from(userData);

          _firstName =
              (userData['name'] as String?)?.split(' ').first ?? 'Kullanıcı';
          _userPhotoUrl = userData['photoUrl'] as String?;
          _isLoadingUserData = false;
        });
      } else {
        setState(() => _isLoadingUserData = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUserData = false);
    }
  }

  Widget _buildStoriesSection() {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(isDark ? 0.78 : 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outline.withOpacity(0.75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Hikayeler',
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          const StoriesStrip(),
        ],
      ),
    );
  }


  // =========================================================
  // MOTIVATION
  // =========================================================
  Future<void> _loadMotivationQuote() async {
    try {
      final raw = await rootBundle.loadString('assets/data/motivations.txt');
      final lines = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (lines.isEmpty) return;

      final random = Random();
      final pick = lines[random.nextInt(lines.length)];
      if (mounted) setState(() => _motivationQuote = pick);
    } catch (e) {
      debugPrint('Motivation load error: $e');
    }
  }

  // =========================================================
  // NEWS
  // =========================================================
  Future<void> _fetchTechNews() async {
    debugPrint('GNEWS_API_KEY: $_newsApiKey');
    if (_newsApiKey.isEmpty) {
      debugPrint('HATA: GNEWS_API_KEY .env dosyasında bulunamadı.');
      if (mounted) setState(() => _isLoadingNews = false);
      return;
    }

    if (mounted) setState(() => _isLoadingNews = true);

    try {
      final url = Uri.parse(
        'https://gnews.io/api/v4/top-headlines'
            '?category=technology'
            '&lang=tr'
            '&country=tr'
            '&max=20'
            '&token=$_newsApiKey',
      );

      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _newsArticles = data['articles'] ?? [];
          _isLoadingNews = false;
        });
      } else {
        debugPrint('GNews Haber API Hatası: ${response.statusCode}');
        setState(() {
          _newsArticles = [];
          _isLoadingNews = false;
        });
      }
    } catch (e) {
      debugPrint('GNews Haber Çekme Hatası: $e');
      if (mounted) {
        setState(() {
          _newsArticles = [];
          _isLoadingNews = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    await _fetchUserData();
    await _fetchTechNews();
  }

  // =========================================================
  // STREAMS
  // =========================================================
  Stream<QuerySnapshot<Map<String, dynamic>>> _postStream() {
    return FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  // ✅ FIX: score>=40, orderBy(score), limit
  Stream<QuerySnapshot<Map<String, dynamic>>> _topMatchStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('userMatches')
        .doc(user.uid)
        .collection('matches')
        .where('score', isGreaterThanOrEqualTo: 40)
        .orderBy('score', descending: true)
        .limit(10)
        .snapshots();
  }

  String _formatTime(dynamic ts) {
    if (ts is! Timestamp) return '';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return 'Şimdi';
    if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  // =========================================================
  // JOBS / COMPANIES BULK FETCH
  // =========================================================
  Future<Map<String, Map<String, dynamic>>> _fetchJobsByIds(
      List<String> jobIds) async {
    final cleaned =
    jobIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (cleaned.isEmpty) return {};

    final out = <String, Map<String, dynamic>>{};
    const chunkSize = 30;

    for (var i = 0; i < cleaned.length; i += chunkSize) {
      final chunk = cleaned.sublist(i, (i + chunkSize).clamp(0, cleaned.length));
      final qs = await FirebaseFirestore.instance
          .collection('jobs')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final d in qs.docs) {
        out[d.id] = {
          ...d.data(),
          'id': d.id,
          'jobId': d.id,
        };
      }
    }
    return out;
  }

  void _ensureJobsFuture(List<String> jobIds) {
    final ids = jobIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
      ..sort();
    final newKey = ids.join('|');

    if (_jobsFuture == null || newKey != _jobsKey) {
      _jobsKey = newKey;
      _jobsFuture = _fetchJobsByIds(ids);
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchCompaniesByIds(
      List<String> uids) async {
    final cleaned =
    uids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (cleaned.isEmpty) return {};

    final out = <String, Map<String, dynamic>>{};
    const chunkSize = 30;

    for (var i = 0; i < cleaned.length; i += chunkSize) {
      final chunk = cleaned.sublist(i, (i + chunkSize).clamp(0, cleaned.length));
      final qs = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final d in qs.docs) {
        out[d.id] = d.data();
      }
    }
    return out;
  }

  void _ensureCompaniesFuture(List<String> companyIds) {
    final ids = companyIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
      ..sort();
    final newKey = ids.join('|');

    if (_companiesFuture == null || newKey != _companiesKey) {
      _companiesKey = newKey;
      _companiesFuture = _fetchCompaniesByIds(ids);
    }
  }

  Future<void> _deleteStaleMatches(String uid, List<String> matchDocIds) async {
    if (matchDocIds.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final baseRef = FirebaseFirestore.instance
        .collection('userMatches')
        .doc(uid)
        .collection('matches');

    for (final id in matchDocIds) {
      batch.delete(baseRef.doc(id));
    }
    await batch.commit();
  }

  void _scheduleCleanupIfNeeded(String uid, List<String> staleDocIds) {
    if (staleDocIds.isEmpty) return;

    final ids = List<String>.from(staleDocIds)..sort();
    final cleanupKey = ids.join('|');

    if (cleanupKey == _lastCleanupKey) return;
    _lastCleanupKey = cleanupKey;

    Future.microtask(() async {
      try {
        await _deleteStaleMatches(uid, ids);
      } catch (e) {
        debugPrint('Cleanup error: $e');
      }
    });
  }

  String _extractJobId(Map<String, dynamic> m) {
    final direct = (m['jobId'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    if (m['jobSnapshot'] is Map) {
      final job = Map<String, dynamic>.from(m['jobSnapshot']);
      final fromSnap1 = (job['jobId'] ?? '').toString().trim();
      if (fromSnap1.isNotEmpty) return fromSnap1;

      final fromSnap2 = (job['id'] ?? '').toString().trim();
      if (fromSnap2.isNotEmpty) return fromSnap2;
    }

    return '';
  }

  // =========================================================
  // ✅ UI HARD GATES (Remote + Level)
  // =========================================================
  bool _workModelEligible(Map<String, dynamic> user, Map<String, dynamic> job) {
    final wm = (job['workModel'] ?? '').toString().trim().toLowerCase();
    if (wm.isEmpty) return true;

    final prefs = (user['workModelPrefs'] is Map)
        ? Map<String, dynamic>.from(user['workModelPrefs'])
        : <String, dynamic>{};

    final r = prefs['remote'] == true;
    final h = prefs['hybrid'] == true;
    final o = prefs['on-site'] == true;

    if (wm == 'remote') return r;
    if (wm == 'hybrid') return h;
    if (wm == 'on-site') return o;
    return false;
  }

  int? _levelRank(String s) {
    final x = s.trim().toLowerCase();
    if (x == 'intern') return 0;
    if (x == 'junior') return 1;
    if (x == 'mid') return 2;
    if (x == 'senior') return 3;
    return null;
  }

  bool _levelEligible(Map<String, dynamic> user, Map<String, dynamic> job) {
    final u = _levelRank((user['level'] ?? user['seniority'] ?? '').toString());
    final j = _levelRank((job['level'] ?? '').toString());

    if (j == null) return true; // job level yoksa engelleme
    if (u == null) return true; // user level yoksa engelleme
    return u >= j;
  }

  // =========================================================
  // UI
  // =========================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoadingUserData) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeHeader(context),
            _buildSuggestionSection(),
            const SizedBox(height: 10),
            _buildMotivationBubble(context),
            const SizedBox(height: 10),
            _buildNewsSection(),
            const SizedBox(height: 10),
            _buildStoriesSection(),
            const SizedBox(height: 10),
            _buildFeedFromPosts(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final displayName = _firstName.isEmpty ? 'Tekrar merhaba!' : _firstName;
    final onHeader = cs.onPrimary;
    final bool isPremium = isPremiumActiveFromUserDoc(_currentUserMap);


    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF6E44FF), Color(0xFF00C4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.28 : 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isPremium ? 2.6 : 0), // çerçeve kalınlığı hissi
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isPremium
                  ? Border.all(color: const Color(0xFFEFBF04), width: 2.6)
                  : null,
            ),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: onHeader.withOpacity(isDark ? 0.14 : 0.18),
              backgroundImage:
              _userPhotoUrl != null ? NetworkImage(_userPhotoUrl!) : null,
              child: _userPhotoUrl == null
                  ? Icon(Icons.person, color: onHeader, size: 28)
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: TextStyle(
                  color: onHeader,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  TextSpan(
                    text: 'Hoş geldin, ',
                    style: TextStyle(
                      color: onHeader.withOpacity(0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(
                    text: displayName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ================== SANA ÖZEL EŞLEŞMELER ==================
  Widget _buildSuggestionSection() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: cs.surface,
        border: Border.all(color: cs.outline.withOpacity(0.80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sana Özel Eşleşmeler',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () =>
                    setState(() => _isSuggestionsExpanded = !_isSuggestionsExpanded),
                child: Row(
                  children: [
                    Text(
                      _isSuggestionsExpanded ? 'Gizle' : 'Göster',
                      style:
                      TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isSuggestionsExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: cs.onSurface,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _isSuggestionsExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            secondChild: const SizedBox.shrink(),

            // ✅ sabit yükseklik
            firstChild: SizedBox(
              height: 180,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _topMatchStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _errorBox('Eşleşme akışı hatası: ${snapshot.error}');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) return _emptySuggestions();

                  int toIntScore(dynamic v) {
                    if (v == null) return 0;
                    if (v is int) return v;
                    if (v is num) return v.toInt();
                    if (v is String) return int.tryParse(v.trim()) ?? 0;
                    return 0;
                  }

                  final rawItems = docs
                      .map((d) {
                    final m = d.data();
                    final score = toIntScore(m['score']);
                    return <String, dynamic>{
                      ...m,
                      '_scoreInt': score,
                      '_docId': d.id,
                    };
                  })
                      .where((m) => (m['_scoreInt'] as int) >= 40)
                      .toList();

                  if (rawItems.isEmpty) return _emptySuggestions();

                  final jobIds = rawItems
                      .map((m) {
                    final jid = _extractJobId(m);
                    if (jid.isNotEmpty) return jid;
                    return (m['_docId'] ?? '').toString().trim();
                  })
                      .where((id) => id.isNotEmpty)
                      .toList();

                  if (jobIds.isEmpty) {
                    return _errorBox(
                      'Eşleşme verisinde jobId bulunamadı.\n'
                          'Çözüm: match dokümanlarında jobId alanını doldur ya da docId=jobId standardına geç.',
                    );
                  }

                  _ensureJobsFuture(jobIds);

                  return FutureBuilder<Map<String, Map<String, dynamic>>>(
                    future: _jobsFuture,
                    builder: (context, jobsSnap) {
                      if (jobsSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (jobsSnap.hasError) {
                        return _errorBox('Job çekme/kontrol hatası: ${jobsSnap.error}');
                      }

                      final jobsMap = jobsSnap.data ?? {};
                      final existingIds = jobsMap.keys.toSet();

                      // ✅ 1) Job var mı?
                      final baseFiltered = rawItems.where((m) {
                        final jobId = (() {
                          final jid = _extractJobId(m);
                          if (jid.isNotEmpty) return jid;
                          return (m['_docId'] ?? '').toString().trim();
                        })();
                        return jobId.isNotEmpty && existingIds.contains(jobId);
                      }).toList();

                      // stale cleanup
                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null) {
                        final staleDocIds = rawItems
                            .where((m) {
                          final jobId = (() {
                            final jid = _extractJobId(m);
                            if (jid.isNotEmpty) return jid;
                            return (m['_docId'] ?? '').toString().trim();
                          })();
                          return jobId.isNotEmpty && !existingIds.contains(jobId);
                        })
                            .map((m) => (m['_docId'] ?? '').toString().trim())
                            .where((x) => x.isNotEmpty)
                            .toList();

                        _scheduleCleanupIfNeeded(user.uid, staleDocIds);
                      }

                      if (baseFiltered.isEmpty) return _emptySuggestions();

                      // ✅ 2) UI hard-gate: workModel + level
                      final filtered = baseFiltered.where((m) {
                        final jobId = (() {
                          final jid = _extractJobId(m);
                          if (jid.isNotEmpty) return jid;
                          return (m['_docId'] ?? '').toString().trim();
                        })();

                        final job = jobsMap[jobId];
                        if (job == null) return false;

                        if (!_workModelEligible(_currentUserMap, job)) return false;
                        if (!_levelEligible(_currentUserMap, job)) return false;

                        return true;
                      }).toList();

                      if (filtered.isEmpty) return _emptySuggestions();

                      // ✅ companyIds
                      final companyIds = <String>{};
                      for (final m in filtered) {
                        final jobId = (() {
                          final jid = _extractJobId(m);
                          if (jid.isNotEmpty) return jid;
                          return (m['_docId'] ?? '').toString().trim();
                        })();

                        final jobFromDb = jobsMap[jobId] ?? <String, dynamic>{};
                        final cid = (jobFromDb['companyId'] ??
                            jobFromDb['companyUid'] ??
                            jobFromDb['ownerId'] ??
                            jobFromDb['createdBy'] ??
                            '')
                            .toString()
                            .trim();
                        if (cid.isNotEmpty) companyIds.add(cid);
                      }

                      _ensureCompaniesFuture(companyIds.toList());

                      return FutureBuilder<Map<String, Map<String, dynamic>>>(
                        future: _companiesFuture,
                        builder: (context, compSnap) {
                          if (compSnap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (compSnap.hasError) {
                            return _errorBox('Company fetch hatası: ${compSnap.error}');
                          }

                          final companiesMap = compSnap.data ?? {};

                          return ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final m = filtered[index];
                              final score = (m['_scoreInt'] as int);

                              final jobId = (() {
                                final jid = _extractJobId(m);
                                if (jid.isNotEmpty) return jid;
                                return (m['_docId'] ?? '').toString().trim();
                              })();

                              // ✅ KURAL: sadece jobs/{id} kaynağı
                              final job = jobsMap[jobId] ?? <String, dynamic>{};

                              final companyId = (job['companyId'] ??
                                  job['companyUid'] ??
                                  job['ownerId'] ??
                                  job['createdBy'] ??
                                  '')
                                  .toString()
                                  .trim();

                              final companyDoc =
                                  companiesMap[companyId] ?? <String, dynamic>{};

                              final company = (job['companyName'] ??
                                  job['company'] ??
                                  companyDoc['name'] ??
                                  'Şirket')
                                  .toString();

                              final position =
                              (job['title'] ?? job['position'] ?? 'Pozisyon')
                                  .toString();
                              final location =
                              (job['location'] ?? job['city'] ?? '—').toString();

                              // ✅ logo öncelik sırası
                              final logoUrl = (job['companyLogoUrl'] ??
                                  job['logoUrl'] ??
                                  job['logo'] ??
                                  job['companyLogo'] ??
                                  companyDoc['photoUrl'] ??
                                  '')
                                  .toString();

                              final safeLogo = logoUrl.trim().isEmpty ? null : logoUrl.trim();

                              final workModel = (job['workModel'] ?? 'Hybrid').toString();
                              final level = (job['level'] ?? 'Junior').toString();
                              final skills = (job['skills'] as List?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                                  const <String>[];

                              // ✅ Güven rozet alanları (match doc üzerinden)
                              final confidenceBadge =
                              (m['confidenceBadge'] ?? '').toString().trim();
                              final confidenceScore = (m['confidenceScore'] is num)
                                  ? (m['confidenceScore'] as num).toDouble()
                                  : double.tryParse(
                                  (m['confidenceScore'] ?? '').toString().trim()) ??
                                  0.0;

                              return _SuggestionCard(
                                company: company,
                                position: position,
                                location: location,
                                matchRate: score,
                                companyLogoUrl: safeLogo,
                                workModel: workModel,
                                level: level,
                                skills: skills,

                                confidenceBadge:
                                confidenceBadge.isEmpty ? null : confidenceBadge,
                                confidenceScore: confidenceScore,

                                isNew: (job['isNew'] == true) || (m['isNew'] == true),
                                isTrending: (job['isTrending'] == true) || (m['isTrending'] == true),
                                isBoosted: (job['isBoosted'] == true) || (m['isBoosted'] == true),
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
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withOpacity(0.6)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Eşleşme ve güven skorları, yüklenen CV ve profil bilgilerine göre otomatik hesaplanır. '
                        'Bu skorlar yalnızca yönlendirme amaçlıdır; nihai değerlendirme işveren tarafından yapılır.',
                    style: TextStyle(
                      fontSize: 12.2,
                      height: 1.25,
                      color: cs.onSurface.withOpacity(0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeIcon(BuildContext context, {double size = 50}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withOpacity(isDark ? 0.22 : 0.14),
        border: Border.all(color: cs.primary.withOpacity(0.35)),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.2),
        child: Image.asset(
          'assets/icons/reach.png',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.auto_awesome_rounded,
            color: cs.primary,
            size: size * 0.60,
          ),
        ),
      ),
    );
  }

  Widget _buildMotivationBubble(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final quote = _motivationQuote.isNotEmpty
        ? _motivationQuote
        : 'Bugün bir şey yap. Küçük de olsa.';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: cs.surface.withOpacity(isDark ? 0.72 : 0.90),
        border: Border.all(color: cs.outline.withOpacity(0.75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.20 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _badgeIcon(context, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              quote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: cs.onSurface.withOpacity(0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: Text(msg, style: TextStyle(color: cs.onSurface)),
    );
  }

  Widget _emptySuggestions() {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 180, // 🔒 KRİTİK: taşmayı bitiren kilit
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🎞️ ANİMASYON (ORTADA)
            SizedBox(
              height: 78, // ⬅️ daha küçüğü gerekmez
              child: Lottie.asset(
                'assets/lottie/empty2.json',
                repeat: true,
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 8),

            // ✨ BAŞLIK
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Henüz sana özel eşleşme yok',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.6,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // 📌 AÇIKLAMA
            Text(
              'Profilini güçlendirdikçe ve yeni ilanlar geldikçe burada sana özel eşleşmeleri göreceksin.',
              textAlign: TextAlign.center,
              maxLines: 3, // 🔒
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.2,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ================== GÜNDEM ==================
  Widget _buildNewsSection() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final buttonBg = cs.surface;
    final buttonTextColor = cs.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
          const EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Gündem',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewsListScreen(
                        articles: _newsArticles,
                        isLoading: _isLoadingNews,
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  backgroundColor: buttonBg,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: cs.outline),
                  ),
                ),
                child: Text(
                  'Tümünü Gör',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: buttonTextColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 230,
          child: _isLoadingNews
              ? const Center(child: CircularProgressIndicator())
              : (_newsArticles.isNotEmpty ? _buildNewsList() : _buildStaticFallbackNews()),
        ),
      ],
    );
  }

  Widget _buildNewsList() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _newsArticles.length > 5 ? 5 : _newsArticles.length,
      itemBuilder: (context, index) {
        final Map<String, dynamic> article = _newsArticles[index] as Map<String, dynamic>;

        final String title = article['title']?.toString() ?? 'Başlıksız';
        final String? imageUrl = (article['image'] ?? article['urlToImage']) as String?;

        String source = 'Haber';
        if (article['source'] != null && article['source']['name'] != null) {
          source = article['source']['name'].toString();
        }

        return Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewsDetailScreen(article: article),
                ),
              );
            },
            child: _NewsCard(
              title: title,
              source: source,
              imageUrl: imageUrl,
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaticFallbackNews() {
    final fallbackNews = [
      {'title': 'Flutter 4.0 Duyuruldu: Yenilikler Neler?', 'source': 'Flutter Dev Blog'},
      {'title': 'Yapay Zeka Etik Kuralları Gündemde', 'source': 'TechCrunch'},
      {'title': 'Yeni Nesil Veritabanı Teknolojileri', 'source': 'InfoWorld'},
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: fallbackNews.length,
      itemBuilder: (context, index) {
        final item = fallbackNews[index];
        return Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: _NewsCard(
            title: item['title']!,
            source: item['source']!,
            imageUrl: null,
          ),
        );
      },
    );
  }

  // ================== GERÇEK POST AKIŞI ==================
  Widget _buildFeedFromPosts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
          const EdgeInsets.only(left: 16.0, right: 16.0, top: 32.0, bottom: 8.0),
          child: Text(
            'Akış',
            style:
            Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _postStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Henüz kimse bir şey paylaşmadı.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }

            final docs = snapshot.data!.docs;

            return ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();

                final postMap = <String, dynamic>{
                  'userName': data['userName'] ?? 'Kullanıcı',
                  'userTitle': data['userTitle'] ?? '',
                  'userAvatarUrl': data['userAvatarUrl'],
                  'postText': data['text'] ?? '',
                  'postImageUrl': data['imageUrl'],
                  'timeAgo': _formatTime(data['createdAt']),
                };

                return _PostCard(
                  postId: doc.id,
                  postData: postMap,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ================== HELPERS ==================
Color matchColor(int score) {
  final s = score.clamp(0, 100) / 100.0;
  return Color.lerp(const Color(0xFFE53935), const Color(0xFF43A047), s)!;
}

// ================== SUGGESTION CARD ==================
class _SuggestionCard extends StatelessWidget {
  final String company, position, location;
  final int matchRate;
  final String? companyLogoUrl;

  final String workModel; // Remote / Hybrid / On-site
  final String level; // Intern / Junior / Mid / Senior
  final List<String> skills;

  final bool isBoosted;
  final bool isTrending;
  final bool isNew;

  // ✅ Güven rozet alanları
  final String? confidenceBadge; // low/medium/high
  final double confidenceScore; // 0..1

  const _SuggestionCard({
    required this.company,
    required this.position,
    required this.location,
    required this.matchRate,
    this.companyLogoUrl,
    this.workModel = 'Hybrid',
    this.level = 'Junior',
    this.skills = const [],
    this.isBoosted = false,
    this.isTrending = false,
    this.isNew = false,
    this.confidenceBadge,
    this.confidenceScore = 0.0,
  });

  bool get _hasConfidence => (confidenceBadge ?? '').trim().isNotEmpty;



  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final subtitleColor = cs.onSurface.withOpacity(0.70);
    final borderColor =
    isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08);

    final surfaceHi = cs.surface;
    final surfaceLo = cs.surface.withOpacity(0.94);

    final chipLabels = <String>[
      workModel.trim(),
      level.trim(),
      ...skills.map((e) => e.trim()),
    ].where((e) => e.isNotEmpty).toList();

    final badge = (confidenceBadge ?? '').trim();
    final isLow = badge.toLowerCase() == 'low';

    return SizedBox(
      width: 240,
      height: 196,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [surfaceHi, surfaceLo],
            ),
            border: Border.all(width: 1, color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: ClipOval(
                      child: Container(
                        color: isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.grey.shade100,
                        child: _CompanyLogo(
                          logoUrl: companyLogoUrl,
                          companyName: company,
                          fit: BoxFit.contain,
                          padding: 4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      company,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: matchColor(matchRate),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '%$matchRate',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                position,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),

              const SizedBox(height: 6),

              // Kart yüksekliği sabit -> chip sayısını 3 ile sınırlı tut.
              _ChipsRow(
                labels: chipLabels.take(3).toList(),
                isDark: isDark,
              ),

              const SizedBox(height: 6),

              // ✅ Trend pill + Güven rozeti aynı satırda
              // ✅ Trend pill + Güven rozeti (sığmazsa alta iner, overflow biter)
              Row(
                children: [
                  _buildPill(matchRate),
                  if (_hasConfidence) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _ConfidenceTag(
                          badge: badge,
                          score: confidenceScore,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const Spacer(),

              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: subtitleColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: subtitleColor),
                    ),
                  ),
                  if (isNew) ...[
                    const SizedBox(width: 6),
                    const _TinyTag(text: 'Yeni', color: Color(0xFF4FC3F7)),
                  ],
                  if (isTrending) ...[
                    const SizedBox(width: 6),
                    const _TinyTag(text: 'Gündem', color: Color(0xFF34C579)),
                  ],
                  if (isBoosted) ...[
                    const SizedBox(width: 6),
                    const _TinyTag(text: 'Boost', color: Color(0xFFE57AFF)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPill(int matchRate) {
    Color color;
    IconData icon;
    String label;

    if (matchRate >= 75) {
      color = const Color(0xFF34C579);
      icon = Icons.trending_up_rounded;
      label = 'Trend';
    } else if (matchRate >= 60) {
      color = const Color(0xFFFFD166);
      icon = Icons.bolt_rounded;
      label = 'Hızlı eşleşme';
    } else {
      color = const Color(0xFFE53935);
      icon = Icons.warning_amber_rounded;
      label = 'Düşük eşleşme';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceTag extends StatelessWidget {
  final String badge; // low/medium/high
  final double score; // 0..1 (şimdilik kullanılmayacak)

  const _ConfidenceTag({required this.badge, required this.score});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = badge.toLowerCase();

    late final String text;
    late final IconData icon;
    late final Color color;

    if (b == 'high') {
      text = 'Güven Yüksek';
      icon = Icons.verified_rounded;
      color = const Color(0xFF34C579);
    } else if (b == 'medium') {
      text = 'Güven Orta';
      icon = Icons.shield_rounded;
      color = const Color(0xFFFFD166);
    } else {
      text = 'Güven Düşük';
      icon = Icons.info_outline_rounded;
      color = const Color(0xFFE53935);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.2,
              fontWeight: FontWeight.w900,
              color: cs.onSurface.withOpacity(0.92),
            ),
          ),
        ],
      ),
    );
  }
}


class _ChipsRow extends StatelessWidget {
  final List<String> labels;
  final bool isDark;

  const _ChipsRow({required this.labels, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => _MiniChip(label: labels[i], isDark: isDark),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final bool isDark;

  const _MiniChip({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white.withOpacity(0.92) : Colors.black.withOpacity(0.85),
        ),
      ),
    );
  }
}

class _TinyTag extends StatelessWidget {
  final String text;
  final Color color;

  const _TinyTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

// ================== NEWS CARD ==================
class _NewsCard extends StatelessWidget {
  final String title;
  final String source;
  final String? imageUrl;

  const _NewsCard({
    required this.title,
    required this.source,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final borderColor = cs.outline;
    final cardColor = cs.surface;
    final shadowColor = Colors.black.withOpacity(isDark ? 0.30 : 0.10);

    final titleColor = cs.onSurface;
    final sourceColor = cs.primary;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/icons/news1.png', width: 26, height: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: sourceColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (imageUrl != null)
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: NetworkImage(imageUrl!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
            maxLines: imageUrl != null ? 2 : 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ================= POST CARD (senin kodun: aynen) =================
class _PostCard extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> postData;

  const _PostCard({
    required this.postId,
    required this.postData,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final avatarUrl = postData['userAvatarUrl'] as String?;
    final userName = postData['userName'] ?? '';
    final userTitle = (postData['userTitle'] ?? '').toString();
    final postText = (postData['postText'] ?? '').toString();
    final postImageUrl = postData['postImageUrl'] as String?;
    final timeAgo = (postData['timeAgo'] ?? '').toString();

    final subtle = cs.onSurface.withOpacity(0.62);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline),
      ),
      elevation: 0,
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.surface,
                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: (avatarUrl == null || avatarUrl.isNotEmpty == false)
                      ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.8))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      if (userTitle.isNotEmpty)
                        Text(
                          userTitle,
                          style: TextStyle(
                            color: subtle,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(timeAgo, style: TextStyle(color: subtle, fontSize: 12)),
              ],
            ),
          ),
          if (postText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(postText, style: TextStyle(color: cs.onSurface)),
            ),
          if (postImageUrl != null && postImageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Image.network(postImageUrl),
            ),
          _CommentsPreview(
            postId: postId,
            onOpenComments: () => _openComments(context),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(postId)
                  .collection('likes')
                  .snapshots(),
              builder: (context, likeSnapshot) {
                final currentUser = FirebaseAuth.instance.currentUser;
                final likesDocs = likeSnapshot.data?.docs ?? [];
                final likeCount = likesDocs.length;
                final bool isLiked =
                    currentUser != null && likesDocs.any((d) => d.id == currentUser.uid);

                const likeLabel = 'Beğen';

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('posts')
                      .doc(postId)
                      .collection('saves')
                      .snapshots(),
                  builder: (context, saveSnapshot) {
                    final currentUser = FirebaseAuth.instance.currentUser;
                    final savesDocs = saveSnapshot.data?.docs ?? [];
                    final bool isSaved =
                        currentUser != null && savesDocs.any((d) => d.id == currentUser.uid);

                    final saveLabel = isSaved ? 'Kaydedildi' : 'Kaydet';

                    final likeColor = isLiked ? cs.primary : cs.onSurface.withOpacity(0.65);
                    final commentColor = cs.onSurface.withOpacity(0.65);
                    final shareColor = cs.onSurface.withOpacity(0.65);
                    final saveColor =
                    isSaved ? const Color(0xFFFFA726) : cs.onSurface.withOpacity(0.65);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (likeCount > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2),
                            child: Text(
                              '$likeCount beğeni',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.55),
                              ),
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: _actionButton(
                                  icon: isLiked
                                      ? Icons.thumb_up_alt
                                      : Icons.thumb_up_alt_outlined,
                                  label: likeLabel,
                                  color: likeColor,
                                  onPressed: () => _toggleLike(context, isLiked),
                                ),
                              ),
                            ),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: _actionButton(
                                  icon: Icons.comment_outlined,
                                  label: 'Yorum',
                                  color: commentColor,
                                  onPressed: () => _openComments(context),
                                ),
                              ),
                            ),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: _actionButton(
                                  icon: Icons.share_outlined,
                                  label: 'Paylaş',
                                  color: shareColor,
                                  onPressed: () => _sharePost(context),
                                ),
                              ),
                            ),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: _actionButton(
                                  icon: isSaved ? Icons.bookmark : Icons.bookmark_outline,
                                  label: saveLabel,
                                  color: saveColor,
                                  onPressed: () => _toggleSave(context, isSaved),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Future<void> _toggleLike(BuildContext context, bool currentlyLiked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beğenmek için giriş yapmalısın.')),
      );
      return;
    }

    final likeRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(user.uid);

    try {
      if (currentlyLiked) {
        await likeRef.delete();
      } else {
        await likeRef.set({
          'userId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beğeni işlemi sırasında hata: $e')),
      );
    }
  }

  Future<void> _toggleSave(BuildContext context, bool currentlySaved) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydetmek için giriş yapmalısın.')),
      );
      return;
    }

    final firestore = FirebaseFirestore.instance;

    final postSaveRef =
    firestore.collection('posts').doc(postId).collection('saves').doc(user.uid);
    final userSaveRef =
    firestore.collection('users').doc(user.uid).collection('savedPosts').doc(postId);

    try {
      if (currentlySaved) {
        await Future.wait([
          postSaveRef.delete(),
          userSaveRef.delete(),
        ]);
      } else {
        final now = FieldValue.serverTimestamp();

        await Future.wait([
          postSaveRef.set({'userId': user.uid, 'createdAt': now}),
          userSaveRef.set({'postId': postId, 'userId': user.uid, 'createdAt': now}),
        ]);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme işlemi sırasında hata: $e')),
      );
    }
  }

  // ================== MENTION STREAM HELPER (B KISMI) ==================
  Stream<QuerySnapshot<Map<String, dynamic>>> mentionStream(String q) {
    final qq = q.trim().toLowerCase();
    if (qq.isEmpty) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .orderBy('usernameLower')
        .startAt([qq])
        .endAt(['$qq\uf8ff'])
        .limit(10)
        .snapshots();
  }

  void _openComments(BuildContext context) {
    final TextEditingController commentCtrl = TextEditingController();

    String mentionQuery = '';
    bool showMentions = false;

    Stream<QuerySnapshot<Map<String, dynamic>>> _mentionStream(String q) {
      final qq = q.trim().toLowerCase();
      if (qq.isEmpty) return const Stream.empty();

      return FirebaseFirestore.instance
          .collection('users')
          .orderBy('usernameLower')
          .startAt([qq])
          .endAt(['$qq\uf8ff'])
          .limit(8)
          .snapshots();
    }

    String _extractMentionQuery(String text, int cursor) {
      if (cursor < 0) return '';
      final c = cursor.clamp(0, text.length);
      final before = text.substring(0, c);
      final at = before.lastIndexOf('@');
      if (at == -1) return '';

      final q = before.substring(at + 1);
      if (q.contains(RegExp(r'\s'))) return '';
      return q;
    }

    void _insertMention(String username) {
      final text = commentCtrl.text;
      final sel = commentCtrl.selection;
      final cursor =
      sel.baseOffset < 0 ? text.length : sel.baseOffset.clamp(0, text.length);

      final before = text.substring(0, cursor);
      final after = text.substring(cursor);

      final at = before.lastIndexOf('@');
      if (at == -1) return;

      final newText = before.substring(0, at) + '@$username ' + after;
      commentCtrl.text = newText;

      final newCursor = (before.substring(0, at) + '@$username ').length;
      commentCtrl.selection = TextSelection.collapsed(offset: newCursor);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final cs2 = Theme.of(ctx).colorScheme;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void onTextChanged(String v) {
              final cursor = commentCtrl.selection.baseOffset;
              final q = _extractMentionQuery(v, cursor);

              if (q.isEmpty) {
                if (showMentions) {
                  setModalState(() {
                    showMentions = false;
                    mentionQuery = '';
                  });
                }
                return;
              }

              setModalState(() {
                showMentions = true;
                mentionQuery = q;
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, controller) {
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs2.outline.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Yorumlar',
                      style: TextStyle(fontWeight: FontWeight.bold, color: cs2.onSurface),
                    ),
                    Divider(color: cs2.outline),

                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('posts')
                            .doc(postId)
                            .collection('comments')
                            .orderBy('createdAt', descending: false)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return Center(
                              child: Text('Henüz yorum yok.',
                                  style: TextStyle(color: cs2.onSurface)),
                            );
                          }

                          return ListView.builder(
                            controller: controller,
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final data = docs[index].data();
                              final name = (data['userName'] ?? 'Kullanıcı').toString();
                              final text = (data['text'] ?? '').toString();
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: cs2.surface,
                                  child: Icon(Icons.person,
                                      size: 18, color: cs2.onSurface.withOpacity(0.8)),
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: cs2.onSurface,
                                  ),
                                ),
                                subtitle: _CommentText(text: text),
                              );
                            },
                          );
                        },
                      ),
                    ),

                    if (showMentions)
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _mentionStream(mentionQuery),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const SizedBox.shrink();
                          }

                          final uDocs = snap.data?.docs ?? [];

                          return Container(
                            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            constraints: const BoxConstraints(maxHeight: 220),
                            decoration: BoxDecoration(
                              color: cs2.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs2.outline),
                            ),
                            child: uDocs.isEmpty
                                ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Sonuç yok: @$mentionQuery',
                                style:
                                TextStyle(color: cs2.onSurface.withOpacity(0.8)),
                              ),
                            )
                                : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shrinkWrap: true,
                              itemCount: uDocs.length,
                              separatorBuilder: (_, __) => Divider(
                                  height: 1, color: cs2.outline.withOpacity(0.7)),
                              itemBuilder: (context, i) {
                                final u = uDocs[i].data();
                                final uname =
                                (u['username'] ?? '').toString().trim();
                                final photoUrl =
                                (u['photoUrl'] ?? '').toString().trim();
                                if (uname.isEmpty) return const SizedBox.shrink();

                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: cs2.surface,
                                    backgroundImage:
                                    photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                                    child: photoUrl.isEmpty
                                        ? Icon(Icons.person,
                                        size: 16,
                                        color: cs2.onSurface.withOpacity(0.7))
                                        : null,
                                  ),
                                  title: Text(
                                    uname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: cs2.onSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onTap: () {
                                    _insertMention(uname);
                                    setModalState(() {
                                      showMentions = false;
                                      mentionQuery = '';
                                    });
                                  },
                                );
                              },
                            ),
                          );
                        },
                      ),

                    Divider(height: 1, color: cs2.outline),

                    Padding(
                      padding: EdgeInsets.only(
                        left: 8,
                        right: 8,
                        top: 8,
                        bottom: MediaQuery.of(ctx).viewInsets.bottom + 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: commentCtrl,
                              minLines: 1,
                              maxLines: 4,
                              onChanged: onTextChanged,
                              onTap: () => onTextChanged(commentCtrl.text),
                              decoration: InputDecoration(
                                hintText: 'Yorum yaz... (@ ile etiketle)',
                                border: const OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(12)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                  const BorderRadius.all(Radius.circular(12)),
                                  borderSide: BorderSide(color: cs2.outline),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                  const BorderRadius.all(Radius.circular(12)),
                                  borderSide: BorderSide(color: cs2.primary),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: Icon(Icons.send, color: cs2.primary),
                            onPressed: () async {
                              final txt = commentCtrl.text.trim();
                              if (txt.isEmpty) return;

                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Yorum yapmak için giriş yapmalısın.')),
                                );
                                return;
                              }

                              try {
                                final userDoc = await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .get();
                                final userData = userDoc.data();

                                String userName;
                                if (userData != null &&
                                    (userData['username'] != null || userData['name'] != null)) {
                                  userName =
                                      (userData['username'] ?? userData['name']).toString();
                                } else if (user.email != null) {
                                  userName = user.email!.split('@').first;
                                } else {
                                  userName = user.displayName ?? 'Kullanıcı';
                                }

                                await FirebaseFirestore.instance
                                    .collection('posts')
                                    .doc(postId)
                                    .collection('comments')
                                    .add({
                                  'userId': user.uid,
                                  'userName': userName,
                                  'text': txt,
                                  'createdAt': FieldValue.serverTimestamp(),
                                });

                                commentCtrl.clear();
                                setModalState(() {
                                  showMentions = false;
                                  mentionQuery = '';
                                });
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Yorum eklenirken hata: $e')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _sharePost(BuildContext context) async {
    final text = (postData['postText'] ?? '').toString();
    final imageUrl = (postData['postImageUrl'] ?? '').toString();

    final buffer = StringBuffer();
    if (text.isNotEmpty) buffer.writeln(text);
    if (imageUrl.isNotEmpty) buffer.writeln(imageUrl);

    final content = buffer.isEmpty ? 'TechConnect gönderisi' : buffer.toString();

    try {
      await Share.share(content);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paylaşım sırasında hata: $e')),
      );
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
      ),
    );
  }
}

class _CommentsPreview extends StatelessWidget {
  final String postId;
  final VoidCallback onOpenComments;

  const _CommentsPreview({
    required this.postId,
    required this.onOpenComments,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .orderBy('createdAt', descending: true)
          .limit(2)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final docs = snapshot.data!.docs;
        final totalCount = snapshot.data!.size;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onOpenComments,
                child: Text(
                  'Tüm yorumları gör ($totalCount)',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...docs.map((doc) {
                final data = doc.data();
                final name = (data['userName'] ?? 'Kullanıcı').toString();
                final text = (data['text'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                      Expanded(
                        child: _CommentText(text: text),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}

class _CommentText extends StatelessWidget {
  final String text;

  const _CommentText({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final baseStyle = DefaultTextStyle.of(context).style.copyWith(
      fontSize: 13,
      color: cs.onSurface,
    );

    final words = text.split(' ');

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: words.map((word) {
          final isMention = word.startsWith('@') && word.length > 1;
          return TextSpan(
            text: '$word ',
            style: isMention
                ? baseStyle.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            )
                : baseStyle,
          );
        }).toList(),
      ),
    );
  }
}

class _CompanyLogo extends StatelessWidget {
  final String? logoUrl;
  final String companyName;

  final BoxFit fit;
  final double padding;

  const _CompanyLogo({
    required this.logoUrl,
    required this.companyName,
    this.fit = BoxFit.contain,
    this.padding = 4,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final url = (logoUrl ?? '').trim();
    if (url.isNotEmpty) {
      return Container(
        color: cs.surface,
        alignment: Alignment.center,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Image.network(
            url,
            width: double.infinity,
            height: double.infinity,
            fit: fit,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                ),
              );
            },
            errorBuilder: (_, __, ___) => _fallback(cs),
          ),
        ),
      );
    }

    return _fallback(cs);
  }

  Widget _fallback(ColorScheme cs) {
    final letter =
    companyName.trim().isNotEmpty ? companyName.trim()[0].toUpperCase() : '?';

    return Container(
      color: cs.primary.withOpacity(0.08),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: cs.primary,
        ),
      ),
    );
  }
}