import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CompanyIncomingApplicationsScreen extends StatelessWidget {
  const CompanyIncomingApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Giriş yapmış kullanıcı bulunamadı.')),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gelen Başvurular'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Yeni/Okundu'),
              Tab(text: 'Kabul'),
              Tab(text: 'Red'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _IncomingGroupedByJob(companyId: uid, statuses: const ['new', 'seen']),
            _IncomingGroupedByJob(companyId: uid, statuses: const ['accepted']),
            _IncomingGroupedByJob(companyId: uid, statuses: const ['rejected']),
          ],
        ),
      ),
    );
  }
}

class _IncomingGroupedByJob extends StatelessWidget {
  final String companyId;
  final List<String> statuses;

  const _IncomingGroupedByJob({
    required this.companyId,
    required this.statuses,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('companyId', isEqualTo: companyId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, jobsSnap) {
        if (jobsSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (jobsSnap.hasError) {
          return Center(child: Text('İlanlar okunamadı: ${jobsSnap.error}'));
        }

        final jobDocs = jobsSnap.data?.docs ?? [];
        if (jobDocs.isEmpty) {
          return const Center(child: Text('Henüz ilanın yok.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: jobDocs.length,
          itemBuilder: (context, i) {
            final jobDoc = jobDocs[i];
            final jobId = jobDoc.id;
            final job = jobDoc.data();

            final jobTitle = (job['title'] ?? '').toString().trim();
            final companyName = (job['companyName'] ?? '').toString().trim();

            return _JobApplicationsSection(
              jobId: jobId,
              jobTitle: jobTitle.isEmpty ? '(Pozisyon adı yok)' : jobTitle,
              companyName: companyName,
              statuses: statuses,
            );
          },
        );
      },
    );
  }
}

class _JobApplicationsSection extends StatelessWidget {
  final String jobId;
  final String jobTitle;
  final String companyName;
  final List<String> statuses;

  const _JobApplicationsSection({
    required this.jobId,
    required this.jobTitle,
    required this.companyName,
    required this.statuses,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(jobTitle: jobTitle),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('jobs')
                .doc(jobId)
                .collection('applications')
                .where('status', whereIn: statuses)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, appsSnap) {
              if (appsSnap.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (appsSnap.hasError) {
                return Text('Başvurular okunamadı: ${appsSnap.error}');
              }

              final apps = appsSnap.data?.docs ?? [];
              if (apps.isEmpty) {
                return const Text('Bu filtrede başvuru yok.');
              }

              return Column(
                children: apps.map((d) {
                  final m = d.data();

                  final applicantId = (m['applicantId'] ?? '').toString().trim();
                  final status = (m['status'] ?? 'new').toString().trim();

                  final email = (m['email'] ?? '').toString().trim();
                  final phone = (m['phone'] ?? '').toString().trim();

                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _ApplicationTileWithUser(
                      applicantId: applicantId,
                      jobTitle: jobTitle,
                      companyName: companyName,
                      email: email,
                      phone: phone,
                      status: status,
                      onTap: () {
                        _openDetailSheet(
                          context: context,
                          jobTitle: jobTitle,
                          companyName: companyName,
                          app: m,
                          docId: d.id,
                          jobId: jobId,
                          applicantId: applicantId,
                        );
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openDetailSheet({
    required BuildContext context,
    required String jobTitle,
    required String companyName,
    required Map<String, dynamic> app,
    required String docId,
    required String jobId,
    required String applicantId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: applicantId.isEmpty
              ? null
              : FirebaseFirestore.instance.collection('users').doc(applicantId).get(),
          builder: (ctx, userSnap) {
            final u = userSnap.data?.data() ?? {};

            final name = (u['name'] ?? '').toString().trim();
            final username = (u['username'] ?? '').toString().trim();
            final photoUrl = (u['photoUrl'] ?? '').toString().trim();

            final email = (app['email'] ?? '').toString().trim();
            final phone = (app['phone'] ?? '').toString().trim();
            final portfolio = (app['portfolio'] ?? '').toString().trim();
            final linkedin = (app['linkedin'] ?? '').toString().trim();
            final cover = (app['coverLetter'] ?? '').toString().trim();
            final cvUrl = (app['cvUrl'] ?? '').toString().trim();
            final status = (app['status'] ?? 'new').toString().trim();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                  top: 8,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                            child: photoUrl.isEmpty ? const Icon(Icons.person) : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? '(isim yok)' : name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (username.isNotEmpty)
                                  Text(
                                    '@$username',
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                          _StatusPill(status: status),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _kvCopy(ctx, 'İlan', jobTitle),
                      if (companyName.trim().isNotEmpty) _kvCopy(ctx, 'Şirket', companyName),
                      if (applicantId.isNotEmpty) _kvCopy(ctx, 'Kullanıcı ID', applicantId),

                      const SizedBox(height: 14),
                      if (email.isNotEmpty) _kvCopy(ctx, 'E-posta', email),
                      if (phone.isNotEmpty) _kvCopy(ctx, 'Telefon', phone),
                      if (portfolio.isNotEmpty) _kvCopy(ctx, 'Portföy', portfolio),
                      if (linkedin.isNotEmpty) _kvCopy(ctx, 'LinkedIn', linkedin),
                      if (cvUrl.isNotEmpty) _kvCopy(ctx, 'CV', cvUrl),

                      if (cover.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Ön Yazı', style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            _copyIcon(ctx, cover),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(cover),
                      ],

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await FirebaseFirestore.instance
                                    .collection('jobs')
                                    .doc(jobId)
                                    .collection('applications')
                                    .doc(docId)
                                    .update({'status': 'seen'});
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Okundu'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final appRef = FirebaseFirestore.instance
                                    .collection('jobs')
                                    .doc(jobId)
                                    .collection('applications')
                                    .doc(docId);

                                // ✅ tekrar tekrar basınca ezme
                                final appSnap = await appRef.get();
                                final appData = appSnap.data() ?? {};
                                final currentStatus = (appData['status'] ?? '').toString();
                                final currentTest = (appData['test'] as Map?)?.cast<String, dynamic>() ?? {};
                                final currentTestStatus = (currentTest['status'] ?? '').toString();

                                if (currentStatus == 'accepted' && currentTestStatus == 'assigned') {
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  return;
                                }

                                final testRef = FirebaseFirestore.instance
                                    .collection('jobs')
                                    .doc(jobId)
                                    .collection('tests')
                                    .doc('default');

                                final testSnap = await testRef.get();
                                final hasActiveTest =
                                    testSnap.exists && (testSnap.data()?['isActive'] == true);

                                if (hasActiveTest) {
                                  await appRef.update({
                                    'status': 'accepted',
                                    'stage': 'test_pending',
                                    'decisionAt': FieldValue.serverTimestamp(),

                                    'test.required': true,
                                    'test.testId': 'default',
                                    'test.status': 'assigned',
                                    'test.assignedAt': FieldValue.serverTimestamp(),
                                    'test.score': 0,
                                  });
                                } else {
                                  await appRef.update({
                                    'status': 'accepted',
                                    'stage': 'interview',
                                    'decisionAt': FieldValue.serverTimestamp(),
                                  });
                                }

                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Kabul'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection('jobs')
                                .doc(jobId)
                                .collection('applications')
                                .doc(docId)
                                .update({
                              'status': 'rejected',
                              'stage': 'rejected',
                              'decisionAt': FieldValue.serverTimestamp(),
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.close),
                          label: const Text('Reddet'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _kvCopy(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(k, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(child: Text(v)),
          const SizedBox(width: 8),
          _copyIcon(context, v),
        ],
      ),
    );
  }

  Widget _copyIcon(BuildContext context, String value) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: const Icon(Icons.copy, size: 18),
      onPressed: value.trim().isEmpty
          ? null
          : () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kopyalandı')),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String jobTitle;
  const _Header({required this.jobTitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(jobTitle, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

class _ApplicationTileWithUser extends StatelessWidget {
  final String applicantId;

  final String jobTitle;
  final String companyName;
  final String email;
  final String phone;
  final String status;
  final VoidCallback onTap;

  const _ApplicationTileWithUser({
    required this.applicantId,
    required this.jobTitle,
    required this.companyName,
    required this.email,
    required this.phone,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08);

    if (applicantId.isEmpty) {
      return _ApplicationTile(
        jobTitle: jobTitle,
        companyName: companyName,
        applicantName: '(isim yok)',
        photoUrl: '',
        email: email,
        phone: phone,
        status: status,
        onTap: onTap,
        border: border,
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(applicantId).get(),
      builder: (context, snap) {
        final u = snap.data?.data() ?? {};
        final name = (u['name'] ?? '').toString().trim();
        final photoUrl = (u['photoUrl'] ?? '').toString().trim();

        return _ApplicationTile(
          jobTitle: jobTitle,
          companyName: companyName,
          applicantName: name.isEmpty ? '(isim yok)' : name,
          photoUrl: photoUrl,
          email: email,
          phone: phone,
          status: status,
          onTap: onTap,
          border: border,
        );
      },
    );
  }
}

class _ApplicationTile extends StatelessWidget {
  final String jobTitle;
  final String companyName;
  final String applicantName;
  final String photoUrl;
  final String email;
  final String phone;
  final String status;
  final VoidCallback onTap;
  final Color border;

  const _ApplicationTile({
    required this.jobTitle,
    required this.companyName,
    required this.applicantName,
    required this.photoUrl,
    required this.email,
    required this.phone,
    required this.status,
    required this.onTap,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
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
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child: photoUrl.isEmpty ? const Icon(Icons.person, size: 20) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(applicantName, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('İlan: $jobTitle', maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (companyName.trim().isNotEmpty)
                    Text('Şirket: $companyName', style: TextStyle(color: Colors.grey.shade600)),
                  if (email.isNotEmpty || phone.isNotEmpty) const SizedBox(height: 6),
                  if (email.isNotEmpty) Text(email, style: TextStyle(color: Colors.grey.shade600)),
                  if (phone.isNotEmpty) Text(phone, style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 6),
                  Text('Detay için dokun', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
            _StatusPill(status: status),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    String label = 'Yeni';
    Color tint = Theme.of(context).colorScheme.primary;

    if (status == 'seen') {
      label = 'Okundu';
      tint = Colors.grey;
    }
    if (status == 'accepted') {
      label = 'Kabul';
      tint = Colors.green;
    }
    if (status == 'rejected') {
      label = 'Red';
      tint = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: tint.withOpacity(0.12),
      ),
      child: Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w700)),
    );
  }
}
