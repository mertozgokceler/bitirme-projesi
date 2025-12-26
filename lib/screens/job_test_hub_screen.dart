import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'job_test_editor_screen.dart';

class JobTestHubScreen extends StatelessWidget {
  const JobTestHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Giriş yapmış şirket bulunamadı.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('İlan Testi Oluştur')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('jobs')
            .where('companyId', isEqualTo: uid)
        // ✅ AKTİF filtresi: sende hangi alan varsa onu kullan
        // .where('isActive', isEqualTo: true)
        // veya:
        // .where('status', isEqualTo: 'active')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('İlanlar okunamadı: ${snap.error}'));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Henüz ilanın yok.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final jobDoc = docs[i];
              final jobId = jobDoc.id;
              final job = jobDoc.data();

              final title = (job['title'] ?? '').toString().trim();
              final companyName = (job['companyName'] ?? '').toString().trim();

              return _JobTestCard(
                jobId: jobId,
                title: title.isEmpty ? '(Pozisyon adı yok)' : title,
                companyName: companyName,
              );
            },
          );
        },
      ),
    );
  }
}

class _JobTestCard extends StatelessWidget {
  final String jobId;
  final String title;
  final String companyName;

  const _JobTestCard({
    required this.jobId,
    required this.title,
    required this.companyName,
  });

  Future<bool> _hasTest() async {
    final doc = await FirebaseFirestore.instance
        .collection('jobs')
        .doc(jobId)
        .collection('tests')
        .doc('default')
        .get();
    return doc.exists;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border =
    isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          const Icon(Icons.work_outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                if (companyName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(companyName, style: TextStyle(color: Colors.grey.shade600)),
                ],
                const SizedBox(height: 8),
                FutureBuilder<bool>(
                  future: _hasTest(),
                  builder: (context, snap) {
                    final has = snap.data == true;
                    return Text(
                      has ? 'Test: Var ✅' : 'Test: Yok',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => JobTestEditorScreen(jobId: jobId),
                ),
              );
            },
            child: const Text('Aç'),
          ),
        ],
      ),
    );
  }
}
