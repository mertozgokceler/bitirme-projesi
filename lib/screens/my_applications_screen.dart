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

  // status accepted ama test yoksa da mülakata gidebilir (senin modelin böyle)
  if (status == 'accepted') {
    return const AppStageInfo(AppStageKey.interview, 'Mülakat aşaması', Colors.green);
  }

  // 4) default
  return const AppStageInfo(AppStageKey.review, 'İnceleniyor', Colors.grey);
}

// =====================
// SCREEN
// =====================

class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Giriş yapmış kullanıcı bulunamadı.')),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Başvurularım'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Align(
              alignment: Alignment.center,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                labelPadding: const EdgeInsets.symmetric(horizontal: 18),
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 3,
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
        body: TabBarView(
          children: [
            _MyApplicationsList(uid: uid, statuses: null), // HEPSİ
            _MyApplicationsList(uid: uid, statuses: const ['new', 'seen']),
            _MyApplicationsList(uid: uid, statuses: const ['accepted']),
            _MyApplicationsList(uid: uid, statuses: const ['rejected']),
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
          return const Center(child: Text('Bu filtrede başvuru yok.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
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

            final test = (m['test'] is Map)
                ? Map<String, dynamic>.from(m['test'] as Map)
                : <String, dynamic>{};

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

    final test = (data['test'] is Map)
        ? Map<String, dynamic>.from(data['test'] as Map)
        : <String, dynamic>{};

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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          jobTitle.isEmpty ? '(Pozisyon adı yok)' : jobTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _StatusPill(status: status, forApplicant: true),
                    ],
                  ),
                  if (companyName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(companyName, style: TextStyle(color: Colors.grey.shade600)),
                  ],
                  const SizedBox(height: 14),

                  _kv('Durum', _statusLabel(status, forApplicant: true)),
                  _kv('Aşama', stageInfo.label),
                  if (testStatus.isNotEmpty) _kv('Test', _testLabel(testStatus)),
                  if (score != null) _kv('Skor', score.toString()),

                  _kv('Başvuru Tarihi', _fmt(createdAt)),
                  if (decisionAt != null) _kv('Karar Tarihi', _fmt(decisionAt)),
                  _kv('Kayıt Yolu', docPath),

                  const Divider(height: 24),

                  if (email.isNotEmpty) _kv('E-posta', email),
                  if (phone.isNotEmpty) _kv('Telefon', phone),
                  if (portfolio.isNotEmpty) _kv('Portföy', portfolio),
                  if (linkedin.isNotEmpty) _kv('LinkedIn', linkedin),
                  if (cvUrl.isNotEmpty) _kv('CV', cvUrl),

                  if (cover.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Ön Yazı', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(cover),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(child: Text(v)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.work_outline),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(jobTitle, style: const TextStyle(fontWeight: FontWeight.w900)),
                  if (companyName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(companyName, style: TextStyle(color: Colors.grey.shade600)),
                  ],

                  const SizedBox(height: 8),
                  _StagePill(stageInfo: stageInfo),

                  const SizedBox(height: 8),
                  Text(
                    'Başvuru: ${_fmt(createdAt)}'
                        '${decisionAt != null ? '  •  Karar: ${_fmt(decisionAt)}' : ''}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),

                  if (canEnterTest) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
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
                        icon: const Icon(Icons.quiz_outlined, size: 18),
                        label: const Text('Teste Gir'),
                      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: stageInfo.color.withOpacity(0.12),
      ),
      child: Text(
        stageInfo.label,
        style: TextStyle(color: stageInfo.color, fontWeight: FontWeight.w800),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: map.color.withOpacity(0.12),
      ),
      child: Text(
        map.label,
        style: TextStyle(color: map.color, fontWeight: FontWeight.w800),
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
