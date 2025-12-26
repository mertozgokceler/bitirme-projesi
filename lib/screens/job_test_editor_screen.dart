import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class JobTestEditorScreen extends StatefulWidget {
  final String jobId;
  const JobTestEditorScreen({super.key, required this.jobId});

  @override
  State<JobTestEditorScreen> createState() => _JobTestEditorScreenState();
}

class _JobTestEditorScreenState extends State<JobTestEditorScreen> {
  bool _saving = false;

  final _titleCtrl = TextEditingController(text: 'İlan Testi');
  final _passCtrl = TextEditingController(text: '70');

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _testDoc => FirebaseFirestore
      .instance
      .collection('jobs')
      .doc(widget.jobId)
      .collection('tests')
      .doc('default');

  CollectionReference<Map<String, dynamic>> get _qCol =>
      _testDoc.collection('questions');

  Future<void> _loadMeta() async {
    try {
      final d = await _testDoc.get();
      if (!d.exists) return;

      final m = d.data() ?? {};
      final t = (m['title'] ?? '').toString().trim();
      final p = (m['passPercent'] ?? 70).toString();

      if (!mounted) return;
      if (t.isNotEmpty) _titleCtrl.text = t;
      _passCtrl.text = p;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test bilgisi okunamadı: $e')),
      );
    }
  }

  Future<void> _saveMeta() async {
    if (_saving) return;

    final pass = int.tryParse(_passCtrl.text.trim()) ?? 70;
    if (pass < 0 || pass > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçme yüzdesi 0-100 arası olmalı.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _testDoc.set({
        'title': _titleCtrl.text.trim().isEmpty ? 'İlan Testi' : _titleCtrl.text.trim(),
        'passPercent': pass,
        'updatedAt': FieldValue.serverTimestamp(),
        // createdAt ilk oluşumda set edilir, merge ile tekrar yazsa da sorun değil
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test kaydedildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addQuestionDialog() async {
    final qCtrl = TextEditingController();
    final aCtrl = TextEditingController();
    final bCtrl = TextEditingController();
    final cCtrl = TextEditingController();
    final dCtrl = TextEditingController();

    String correct = 'A';
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            Future<void> submit() async {
              if (saving) return;

              final q = qCtrl.text.trim();
              if (q.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Soru boş olamaz.')),
                );
                return;
              }

              setStateSB(() => saving = true);
              try {
                await _qCol.add({
                  'question': q,
                  'A': aCtrl.text.trim(),
                  'B': bCtrl.text.trim(),
                  'C': cCtrl.text.trim(),
                  'D': dCtrl.text.trim(),
                  'correct': correct, // A/B/C/D
                  'points': 1,
                  'createdAt': FieldValue.serverTimestamp(),
                });

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Soru eklendi.')),
                  );
                }
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Soru eklenemedi: $e')),
                );
              } finally {
                if (ctx.mounted) setStateSB(() => saving = false);
              }
            }

            return AlertDialog(
              title: const Text('Soru Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: qCtrl,
                      decoration: const InputDecoration(labelText: 'Soru'),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: aCtrl, decoration: const InputDecoration(labelText: 'A')),
                    TextField(controller: bCtrl, decoration: const InputDecoration(labelText: 'B')),
                    TextField(controller: cCtrl, decoration: const InputDecoration(labelText: 'C')),
                    TextField(controller: dCtrl, decoration: const InputDecoration(labelText: 'D')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: correct,
                      decoration: const InputDecoration(labelText: 'Doğru Cevap'),
                      items: const [
                        DropdownMenuItem(value: 'A', child: Text('A')),
                        DropdownMenuItem(value: 'B', child: Text('B')),
                        DropdownMenuItem(value: 'C', child: Text('C')),
                        DropdownMenuItem(value: 'D', child: Text('D')),
                      ],
                      onChanged: (v) => setStateSB(() => correct = v ?? 'A'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: saving ? null : submit,
                  child: saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteQuestion(String qId) async {
    try {
      await _qCol.doc(qId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Soru silindi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silme hatası: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Düzenleme Editörü'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveMeta,
            child: _saving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('Kaydet'),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQuestionDialog,
        icon: const Icon(Icons.add),
        label: const Text('Soru Ekle'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Test Başlığı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Geçme Yüzdesi (örn. 70)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text('Sorular', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _qCol.orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Sorular okunamadı: ${snap.error}'),
                );
              }

              final qs = snap.data?.docs ?? [];
              if (qs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Henüz soru yok. “Soru Ekle” ile ekle.'),
                );
              }

              return Column(
                children: qs.map((d) {
                  final m = d.data();
                  final q = (m['question'] ?? '').toString();
                  final correct = (m['correct'] ?? 'A').toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q, style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(
                                'Doğru: $correct',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _deleteQuestion(d.id),
                          icon: const Icon(Icons.delete_outline),
                        )
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 70),
        ],
      ),
    );
  }
}
