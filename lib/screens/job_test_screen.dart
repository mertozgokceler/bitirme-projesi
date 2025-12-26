import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class JobTestScreen extends StatefulWidget {
  final String jobId;
  final String applicationPath; // jobs/{jobId}/applications/{docId}
  final String testId;

  const JobTestScreen({
    super.key,
    required this.jobId,
    required this.applicationPath,
    this.testId = 'default',
  });

  @override
  State<JobTestScreen> createState() => _JobTestScreenState();
}

class _JobTestScreenState extends State<JobTestScreen> {
  bool _submitting = false;

  /// qId -> selected letter: 'A'/'B'/'C'/'D'
  final Map<String, String> _answers = {};

  CollectionReference<Map<String, dynamic>> get _qRef => FirebaseFirestore.instance
      .collection('jobs')
      .doc(widget.jobId)
      .collection('tests')
      .doc(widget.testId)
      .collection('questions');

  CollectionReference<Map<String, dynamic>> get _attemptsRef => FirebaseFirestore.instance
      .collection('jobs')
      .doc(widget.jobId)
      .collection('tests')
      .doc(widget.testId)
      .collection('attempts');

  Future<void> _submit(List<QueryDocumentSnapshot<Map<String, dynamic>>> qs) async {
    if (_submitting) return;

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giriş yapmış kullanıcı yok.')),
      );
      return;
    }

    // tüm sorular cevaplandı mı?
    for (final q in qs) {
      if (!_answers.containsKey(q.id)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tüm soruları cevapla.')),
        );
        return;
      }
    }

    setState(() => _submitting = true);

    debugPrint('SUBMIT uid=$uid jobId=${widget.jobId} testId=${widget.testId}');
    debugPrint('SUBMIT applicationPath=${widget.applicationPath}');

    try {
      // skor hesapla
      int total = 0;
      int correctCount = 0;

      for (final d in qs) {
        final m = d.data();
        final correct = (m['correct'] ?? 'A').toString().trim();
        final points = (m['points'] is num) ? (m['points'] as num).toInt() : 1;

        total += points;

        final picked = _answers[d.id] ?? '';
        if (picked == correct) correctCount += points;
      }

      final scorePercent = total == 0 ? 0 : ((correctCount / total) * 100).round();

      final attemptDoc = _attemptsRef.doc();
      final appRef = FirebaseFirestore.instance.doc(widget.applicationPath);

      // ✅ 0) uygulama dokümanı gerçekten var mı?
      final appSnap = await appRef.get();
      if (!appSnap.exists) {
        throw 'Application bulunamadı: ${widget.applicationPath}';
      }

      // ✅ 0.1) application test map ve status kontrol (UI guard)
      final appData = (appSnap.data() as Map<String, dynamic>?);
      final testMap = (appData?['test'] as Map?)?.cast<String, dynamic>();
      if (testMap == null) {
        throw 'Application test alanı yok.';
      }
      final status = (testMap['status'] ?? '').toString();
      if (status != 'assigned') {
        // rules zaten bunu enforce ediyor; burada kullanıcıya daha net mesaj
        throw 'Bu test şu an gönderilemez. (status=$status)';
      }

      // ✅ 1) attempt kaydı
      final attemptPayload = <String, dynamic>{
        'applicantId': uid,
        'applicationPath': widget.applicationPath,
        'jobId': widget.jobId,
        'testId': widget.testId,
        'status': 'submitted',
        'answers': Map<String, dynamic>.from(_answers),
        'scorePercent': scorePercent.toDouble(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      await attemptDoc.set(attemptPayload);
      debugPrint('attemptDoc.set OK id=${attemptDoc.id}');

      // ✅ 2) application güncelle (dot notation YOK)
      final oldTest = (appData?['test'] as Map?)?.cast<String, dynamic>() ?? {};

      await appRef.update({
        'stage': 'test_submitted',
        'test': {
          ...oldTest,
          'status': 'submitted',
          'attemptId': attemptDoc.id,
          'submittedAt': FieldValue.serverTimestamp(),
          'score': scorePercent,
        },
      });

      debugPrint('appRef.update OK');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test gönderildi. Skor: %$scorePercent')),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('SUBMIT FAIL => $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test gönderilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('İlan Testi')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _qRef.orderBy('createdAt', descending: false).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Sorular okunamadı: ${snap.error}'));
          }

          final qs = snap.data?.docs ?? [];
          if (qs.isEmpty) {
            return const Center(child: Text('Bu test için henüz soru eklenmemiş.'));
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: qs.length,
                  itemBuilder: (context, i) {
                    final d = qs[i];
                    final q = d.data();

                    final question = (q['question'] ?? '').toString().trim();

                    final a = (q['A'] ?? '').toString().trim();
                    final b = (q['B'] ?? '').toString().trim();
                    final c = (q['C'] ?? '').toString().trim();
                    final dd = (q['D'] ?? '').toString().trim();

                    final options = <Map<String, String>>[
                      {'key': 'A', 'text': a},
                      {'key': 'B', 'text': b},
                      {'key': 'C', 'text': c},
                      {'key': 'D', 'text': dd},
                    ].where((x) => (x['text'] ?? '').trim().isNotEmpty).toList();

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}) ${question.isEmpty ? '(Soru yok)' : question}',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 10),
                            if (options.isEmpty)
                              Text(
                                'Şık yok (A/B/C/D boş).',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            for (final opt in options)
                              RadioListTile<String>(
                                dense: true,
                                value: opt['key']!,
                                groupValue: _answers[d.id],
                                onChanged: _submitting
                                    ? null
                                    : (v) {
                                  if (v == null) return;
                                  setState(() => _answers[d.id] = v);
                                },
                                title: Text('${opt['key']}) ${opt['text']}'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : () => _submit(qs),
                    child: _submitting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Testi Gönder'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
