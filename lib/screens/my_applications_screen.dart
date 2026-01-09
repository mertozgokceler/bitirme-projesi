// lib/screens/my_applications_screen.dart

import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'job_test_screen.dart';

// =====================
// SINGLE SOURCE OF TRUTH: STAGE
// =====================

enum AppStageKey {
  rejected,
  testAssigned,
  testSubmitted,
  interview,
  failedTest,
  review,
}

class AppStageInfo {
  final AppStageKey key;
  final String label;
  final Color color;
  const AppStageInfo(this.key, this.label, this.color);
}

AppStageInfo computeStage(Map<String, dynamic> app) {
  final status = (app['status'] ?? '').toString().trim(); // new/seen/accepted/rejected
  final stage = (app['stage'] ?? '').toString().trim(); // test_pending/interview/...

  final test = (app['test'] is Map)
      ? Map<String, dynamic>.from(app['test'] as Map)
      : <String, dynamic>{};

  final required = test['required'] == true;
  final testStatus = (test['status'] ?? '').toString().trim(); // assigned/submitted/passed/failed

  // 1) Red her zaman üstte
  if (status == 'rejected' || stage == 'rejected') {
    return const AppStageInfo(AppStageKey.rejected, 'Reddedildi', Colors.red);
  }

  // 2) Test zorunluysa pipeline testStatus'a göre akar
  if (required) {
    if (testStatus == 'assigned') {
      return const AppStageInfo(AppStageKey.testAssigned, 'Test bekliyor', Colors.orange);
    }
    if (testStatus == 'submitted') {
      return const AppStageInfo(AppStageKey.testSubmitted, 'Değerlendiriliyor', Colors.purple);
    }
    if (testStatus == 'passed') {
      return const AppStageInfo(AppStageKey.interview, 'Mülakat aşaması', Colors.green);
    }
    if (testStatus == 'failed') {
      return const AppStageInfo(AppStageKey.failedTest, 'Test başarısız', Colors.red);
    }

    // required ama testStatus bozuk/boşsa güvenli fallback
    return const AppStageInfo(AppStageKey.testAssigned, 'Test bekliyor', Colors.orange);
  }

  // 3) Test yoksa stage/status’a göre
  if (stage == 'interview') {
    return const AppStageInfo(AppStageKey.interview, 'Mülakat aşaması', Colors.green);
  }

  // status accepted ama test yoksa da mülakata gidebilir
  if (status == 'accepted') {
    return const AppStageInfo(AppStageKey.interview, 'Mülakat aşaması', Colors.green);
  }

  // 4) default
  return const AppStageInfo(AppStageKey.review, 'İnceleniyor', Colors.grey);
}

// =====================
// PREMIUM UI HELPERS (CvAnalysis look & feel)
// =====================

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

Widget _glassCard(
    BuildContext context, {
      required Widget child,
      EdgeInsets padding = const EdgeInsets.all(14),
      BorderRadius borderRadius = const BorderRadius.all(Radius.circular(18)),
    }) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  return ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(isDark ? 0.78 : 0.92),
          borderRadius: borderRadius,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.28 : 0.45),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 22,
              spreadRadius: 2,
              color: Colors.black.withOpacity(isDark ? 0.22 : 0.08),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

Widget _iconPill(BuildContext context, IconData icon, {Color? color}) {
  final theme = Theme.of(context);
  return Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceVariant.withOpacity(
        theme.brightness == Brightness.dark ? 0.18 : 0.65,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: theme.colorScheme.outlineVariant.withOpacity(0.25),
      ),
    ),
    child: Center(
      child: Icon(icon, color: color ?? theme.colorScheme.onSurfaceVariant),
    ),
  );
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

Widget _primaryGradientButton(
    BuildContext context, {
      required String text,
      required VoidCallback? onPressed,
      IconData? icon,
    }) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  final disabled = onPressed == null;

  const gradient = LinearGradient(colors: [Color(0xFF6D5DF6), Color(0xFF4FC3F7)]);

  return SizedBox(
    height: 44,
    child: disabled
        ? ElevatedButton.icon(
      onPressed: null,
      icon: Icon(icon ?? Icons.lock_outline, size: 18),
      label: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    )
        : DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D5DF6).withOpacity(isDark ? 0.40 : 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon ?? Icons.arrow_forward_rounded, size: 18, color: Colors.white),
        label: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.2,
            shadows: [Shadow(offset: Offset(0, 1), blurRadius: 3, color: Colors.black26)],
          ),
        ),
      ),
    ),
  );
}

// =====================
// SCREEN
// =====================

class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cs = Theme.of(context).colorScheme;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Giriş yapmış kullanıcı bulunamadı.')),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('Başvurularım'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: cs.onSurface,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: _glassCard(
                context,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                borderRadius: BorderRadius.circular(16),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorWeight: 3,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Hepsi'),
                    Tab(text: 'Beklemede'),
                    Tab(text: 'Kabul'),
                    Tab(text: 'Red'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
            Positioned(top: -120, left: -80, child: _GlowBlob(size: 260, color: cs.primary.withOpacity(0.20))),
            Positioned(bottom: -140, right: -90, child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18))),
            SafeArea(
              child: TabBarView(
                children: [
                  _MyApplicationsList(uid: uid, statuses: null),
                  _MyApplicationsList(uid: uid, statuses: const ['new', 'seen']),
                  _MyApplicationsList(uid: uid, statuses: const ['accepted']),
                  _MyApplicationsList(uid: uid, statuses: const ['rejected']),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyApplicationsList extends StatelessWidget {
  final String uid;
  final List<String>? statuses;

  const _MyApplicationsList({
    required this.uid,
    required this.statuses,
  });

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collectionGroup('applications')
        .where('applicantId', isEqualTo: uid);

    if (statuses != null) {
      q = q.where('status', whereIn: statuses);
    }

    q = q.orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Başvurular okunamadı: ${snap.error}'));
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _glassCard(
                context,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 34),
                    SizedBox(height: 10),
                    Text('Bu filtrede başvuru yok.', style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();

            final jobTitle = (m['jobTitle'] ?? '').toString().trim();
            final companyName = (m['companyName'] ?? '').toString().trim();
            final status = (m['status'] ?? 'new').toString().trim();

            final createdAt = _tsToDateTime(m['createdAt']);
            final decisionAt = _tsToDateTime(m['decisionAt']);

            final test = (m['test'] is Map) ? Map<String, dynamic>.from(m['test'] as Map) : <String, dynamic>{};

            final testId = (test['testId'] ?? 'default').toString().trim();
            final jobId = (m['jobId'] ?? '').toString().trim();
            final appPath = d.reference.path;

            final stageInfo = computeStage(m);
            final canEnterTest = stageInfo.key == AppStageKey.testAssigned;

            return _MyAppTile(
              jobTitle: jobTitle.isEmpty ? '(Pozisyon adı yok)' : jobTitle,
              companyName: companyName,
              status: status,
              createdAt: createdAt,
              decisionAt: decisionAt,
              stageInfo: stageInfo,
              canEnterTest: canEnterTest,
              docPath: appPath,
              jobId: jobId,
              testId: testId.isEmpty ? 'default' : testId,
              onTap: () {
                _openMyApplicationDetailSheet(
                  context: context,
                  data: m,
                  docPath: appPath,
                );
              },
            );
          },
        );
      },
    );
  }

  DateTime? _tsToDateTime(dynamic x) {
    if (x == null) return null;
    if (x is Timestamp) return x.toDate();
    return null;
  }

  void _openMyApplicationDetailSheet({
    required BuildContext context,
    required Map<String, dynamic> data,
    required String docPath,
  }) {
    final jobTitle = (data['jobTitle'] ?? '').toString().trim();
    final companyName = (data['companyName'] ?? '').toString().trim();
    final status = (data['status'] ?? 'new').toString().trim();

    final createdAt = _tsToDateTime(data['createdAt']);
    final decisionAt = _tsToDateTime(data['decisionAt']);

    final test = (data['test'] is Map) ? Map<String, dynamic>.from(data['test'] as Map) : <String, dynamic>{};

    final testStatus = (test['status'] ?? '').toString().trim();
    final score = test['score'];

    final email = (data['email'] ?? '').toString().trim();
    final phone = (data['phone'] ?? '').toString().trim();
    final portfolio = (data['portfolio'] ?? '').toString().trim();
    final linkedin = (data['linkedin'] ?? '').toString().trim();
    final cover = (data['coverLetter'] ?? '').toString().trim();
    final cvUrl = (data['cvUrl'] ?? '').toString().trim();

    final stageInfo = computeStage(data);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return Stack(
          children: [
            Container(decoration: BoxDecoration(gradient: _bgGradient(ctx))),
            Positioned(top: -120, left: -80, child: _GlowBlob(size: 240, color: cs.primary.withOpacity(0.18))),
            Positioned(bottom: -140, right: -90, child: _GlowBlob(size: 260, color: cs.tertiary.withOpacity(0.16))),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 10,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                ),
                child: _glassCard(
                  ctx,
                  borderRadius: BorderRadius.circular(20),
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                jobTitle.isEmpty ? '(Pozisyon adı yok)' : jobTitle,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                            ),
                            _StatusPill(status: status, forApplicant: true),
                          ],
                        ),
                        if (companyName.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(companyName, style: TextStyle(color: Theme.of(ctx).hintColor, fontWeight: FontWeight.w700)),
                        ],
                        const SizedBox(height: 14),

                        _kv(ctx, 'Durum', _statusLabel(status, forApplicant: true)),
                        _kv(ctx, 'Aşama', stageInfo.label),
                        if (testStatus.isNotEmpty) _kv(ctx, 'Test', _testLabel(testStatus)),
                        if (score != null) _kv(ctx, 'Skor', score.toString()),
                        _kv(ctx, 'Başvuru Tarihi', _fmt(createdAt)),
                        if (decisionAt != null) _kv(ctx, 'Karar Tarihi', _fmt(decisionAt)),
                        _kv(ctx, 'Kayıt Yolu', docPath),

                        const SizedBox(height: 10),
                        Divider(color: Theme.of(ctx).dividerColor.withOpacity(0.5), height: 22),

                        if (email.isNotEmpty) _kv(ctx, 'E-posta', email),
                        if (phone.isNotEmpty) _kv(ctx, 'Telefon', phone),
                        if (portfolio.isNotEmpty) _kv(ctx, 'Portföy', portfolio),
                        if (linkedin.isNotEmpty) _kv(ctx, 'LinkedIn', linkedin),
                        if (cvUrl.isNotEmpty) _kv(ctx, 'CV', cvUrl),

                        if (cover.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Ön Yazı', style: TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          Text(cover, style: const TextStyle(height: 1.3)),
                        ],

                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? '-' : v,
              style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.$y $hh:$mm';
  }

  String _testLabel(String s) {
    switch (s) {
      case 'assigned':
        return 'Atandı';
      case 'submitted':
        return 'Gönderildi';
      case 'passed':
        return 'Geçti';
      case 'failed':
        return 'Kaldı';
      default:
        return s;
    }
  }
}

class _MyAppTile extends StatelessWidget {
  final String jobTitle;
  final String companyName;

  final String status;
  final DateTime? createdAt;
  final DateTime? decisionAt;

  final AppStageInfo stageInfo;
  final bool canEnterTest;

  final String docPath;
  final String jobId;
  final String testId;

  final VoidCallback onTap;

  const _MyAppTile({
    required this.jobTitle,
    required this.companyName,
    required this.status,
    required this.createdAt,
    required this.decisionAt,
    required this.stageInfo,
    required this.canEnterTest,
    required this.docPath,
    required this.jobId,
    required this.testId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: _glassCard(
        context,
        padding: const EdgeInsets.all(14),
        borderRadius: BorderRadius.circular(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconPill(context, Icons.work_outline),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(jobTitle, style: const TextStyle(fontWeight: FontWeight.w900)),
                  if (companyName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(companyName, style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w700)),
                  ],

                  const SizedBox(height: 10),
                  _StagePill(stageInfo: stageInfo),

                  const SizedBox(height: 10),
                  Text(
                    'Başvuru: ${_fmt(createdAt)}'
                        '${decisionAt != null ? '  •  Karar: ${_fmt(decisionAt)}' : ''}',
                    style: TextStyle(color: theme.hintColor, fontSize: 12, fontWeight: FontWeight.w700),
                  ),

                  if (canEnterTest) ...[
                    const SizedBox(height: 12),
                    _primaryGradientButton(
                      context,
                      text: 'Teste Gir',
                      icon: Icons.quiz_outlined,
                      onPressed: jobId.trim().isEmpty
                          ? null
                          : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => JobTestScreen(
                              jobId: jobId,
                              applicationPath: docPath,
                              testId: testId.isEmpty ? 'default' : testId,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 10),
            _StatusPill(status: status, forApplicant: true),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.$y $hh:$mm';
  }
}

class _StagePill extends StatelessWidget {
  final AppStageInfo stageInfo;
  const _StagePill({required this.stageInfo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: stageInfo.color.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.12),
        border: Border.all(
          color: stageInfo.color.withOpacity(theme.brightness == Brightness.dark ? 0.26 : 0.22),
        ),
      ),
      child: Text(
        stageInfo.label,
        style: TextStyle(color: stageInfo.color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  final bool forApplicant;
  const _StatusPill({required this.status, required this.forApplicant});

  @override
  Widget build(BuildContext context) {
    final map = _statusUI(status, context, forApplicant: forApplicant);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: map.color.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.12),
        border: Border.all(color: map.color.withOpacity(theme.brightness == Brightness.dark ? 0.28 : 0.22)),
      ),
      child: Text(
        map.label,
        style: TextStyle(color: map.color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _StatusMap {
  final String label;
  final Color color;
  const _StatusMap(this.label, this.color);
}

_StatusMap _statusUI(String status, BuildContext context, {required bool forApplicant}) {
  final cs = Theme.of(context).colorScheme;

  switch (status) {
    case 'seen':
      return _StatusMap(forApplicant ? 'İnceleniyor' : 'Okundu', Colors.grey);
    case 'accepted':
      return const _StatusMap('Kabul', Colors.green);
    case 'rejected':
      return const _StatusMap('Red', Colors.red);
    case 'new':
    default:
      return _StatusMap(forApplicant ? 'Beklemede' : 'Yeni', cs.primary);
  }
}

String _statusLabel(String status, {required bool forApplicant}) {
  switch (status) {
    case 'seen':
      return forApplicant ? 'İnceleniyor' : 'Okundu';
    case 'accepted':
      return 'Kabul';
    case 'rejected':
      return 'Red';
    case 'new':
    default:
      return forApplicant ? 'Beklemede' : 'Yeni';
  }
}
