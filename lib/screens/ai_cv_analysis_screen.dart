import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class CvAnalysisScreen extends StatefulWidget {
  const CvAnalysisScreen({super.key});

  @override
  State<CvAnalysisScreen> createState() => _CvAnalysisScreenState();
}

class _CvAnalysisScreenState extends State<CvAnalysisScreen> {
  bool _loading = true;
  bool _busy = false;

  String? _cvUrl;
  String? _cvFileName;
  String? _cvStoragePath;
  DateTime? _updatedAt;

  // --- Analysis state (cvAnalyses/{analysisId}) ---
  bool _analyzing = false;
  String? _analysisId;
  Map<String, dynamic>? _analysisDoc; // entire cvAnalyses doc
  DateTime? _analysisUpdatedAt;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _analysisSub;

  // --- History state ---
  bool _historyExpanded = false;
  bool _historyLoading = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _historyDocs = [];
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _analysisSub?.cancel();
    super.dispose();
  }

  // ---------------------------
  // 1) CV + Latest analysis bootstrap
  // ---------------------------
  Future<void> _bootstrap() async {
    setState(() => _loading = true);

    await _resolveCvFromFirestoreOrStorage();
    await _loadLatestAnalysisFromCvAnalyses(); // show last analysis if exists

    if (mounted) setState(() => _loading = false);
  }

  /// CV bulma stratejisi:
  /// A) users doc içinde cvPdfUrl/cvPdfStoragePath varsa direkt kullan.
  /// B) yoksa Storage'da users/{uid}/cv/ klasörünü listele, en yeni PDF'i bul.
  ///    Bulursa users doc'una yazar (bundan sonra tanır).
  Future<void> _resolveCvFromFirestoreOrStorage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _clearCv();
      return;
    }

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      final userDoc = await userDocRef.get();
      final data = userDoc.data();

      final url = data?['cvPdfUrl'] as String?;
      final name = data?['cvPdfFileName'] as String?;
      final path = data?['cvPdfStoragePath'] as String?;
      final ts = data?['cvPdfUpdatedAt'];

      DateTime? dt;
      if (ts is Timestamp) dt = ts.toDate();

      if (url != null && url.isNotEmpty) {
        _setCv(url: url, name: name, path: path, updatedAt: dt);
        return;
      }

      // Storage list fallback
      final folderRef = FirebaseStorage.instance.ref('users/${user.uid}/cv');
      final list = await folderRef.listAll();

      if (list.items.isEmpty) {
        _clearCv();
        return;
      }

      Reference? newestRef;
      DateTime? newestTime;

      for (final item in list.items) {
        try {
          final meta = await item.getMetadata();
          final updated = meta.updated;
          if (updated == null) continue;

          if (newestTime == null || updated.isAfter(newestTime!)) {
            newestTime = updated;
            newestRef = item;
          }
        } catch (_) {}
      }

      newestRef ??= list.items.first;

      final foundUrl = await newestRef!.getDownloadURL();
      final foundName = newestRef.name;
      final foundPath = newestRef.fullPath;

      await userDocRef.set({
        'cvPdfUrl': foundUrl,
        'cvPdfFileName': foundName,
        'cvPdfStoragePath': foundPath,
        'cvPdfUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _setCv(url: foundUrl, name: foundName, path: foundPath, updatedAt: newestTime);
    } catch (e) {
      _toast('CV bulunamadı/okunamadı: $e');
      _clearCv();
    }
  }

  void _setCv({
    required String url,
    String? name,
    String? path,
    DateTime? updatedAt,
  }) {
    _cvUrl = url;
    _cvFileName = name;
    _cvStoragePath = path;
    _updatedAt = updatedAt;
  }

  void _clearCv() {
    _cvUrl = null;
    _cvFileName = null;
    _cvStoragePath = null;
    _updatedAt = null;
  }

  // ---------------------------
  // 2) Upload / Replace
  // ---------------------------
  Future<void> _pickAndUploadPdf() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('Önce giriş yapmalısın.');
      return;
    }

    try {
      setState(() => _busy = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final picked = result.files.single;
      final Uint8List? bytes = picked.bytes;
      final String fileName = picked.name;

      if (bytes == null) {
        _toast('PDF okunamadı (bytes null).');
        return;
      }

      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9\.\-_ ]'), '_');
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final path = 'users/${user.uid}/cv/${nowMs}_$safeName';
      final ref = FirebaseStorage.instance.ref(path);

      final meta = SettableMetadata(
        contentType: 'application/pdf',
        customMetadata: {'originalFileName': fileName},
      );

      final task = await ref.putData(bytes, meta);
      final url = await task.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'cvPdfUrl': url,
        'cvPdfFileName': fileName,
        'cvPdfStoragePath': path,
        'cvPdfUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _setCv(url: url, name: fileName, path: path, updatedAt: DateTime.now());

      // CV değişti: ekranda eski analizi “stale” say
      _stopAnalysisListener();
      setState(() {
        _analysisId = null;
        _analysisDoc = null;
        _analysisUpdatedAt = null;
        _analyzing = false;
      });

      // geçmiş listeyi de yenile (expanded ise)
      if (_historyExpanded) {
        await _fetchHistory(force: true);
      }

      _toast('CV yüklendi / güncellendi.');
    } catch (e) {
      _toast('Yükleme hatası: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------
  // 3) View / Delete
  // ---------------------------
  Future<void> _openPdf() async {
    final url = _cvUrl;
    if (url == null || url.isEmpty) {
      _toast('CV yok.');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('CV linki bozuk.');
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _toast('PDF açılamadı.');
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('CV silinsin mi?'),
        content: const Text('Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _deleteCv();
    }
  }

  Future<void> _deleteCv() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      setState(() => _busy = true);

      final doc = await docRef.get();
      final path = doc.data()?['cvPdfStoragePath'] as String?;
      if (path != null && path.isNotEmpty) {
        await FirebaseStorage.instance.ref(path).delete();
      }

      await docRef.set({
        'cvPdfUrl': FieldValue.delete(),
        'cvPdfFileName': FieldValue.delete(),
        'cvPdfUpdatedAt': FieldValue.delete(),
        'cvPdfStoragePath': FieldValue.delete(),
      }, SetOptions(merge: true));

      _clearCv();

      _stopAnalysisListener();
      setState(() {
        _analysisId = null;
        _analysisDoc = null;
        _analysisUpdatedAt = null;
        _analyzing = false;

        // geçmiş
        _historyDocs = [];
        _historyError = null;
        _historyExpanded = false;
      });

      _toast('CV silindi.');
    } catch (e) {
      _toast('Silme hatası: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------
  // 4) Load latest analysis from cvAnalyses
  // ---------------------------
  Future<void> _loadLatestAnalysisFromCvAnalyses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final q = await FirebaseFirestore.instance
          .collection('cvAnalyses')
          .where('uid', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (q.docs.isEmpty) return;

      final doc = q.docs.first;
      final data = doc.data();

      _analysisId = doc.id;
      _analysisDoc = data;

      _analysisUpdatedAt = _pickBestTime(data);

      final status = _safeStr(data['status']).toLowerCase();
      _analyzing = (status == 'queued' || status == 'running');

      _startAnalysisListener(doc.id);
    } catch (_) {
      // sessiz geç
    }
  }

  DateTime? _pickBestTime(Map<String, dynamic>? data) {
    if (data == null) return null;
    final finishedAt = data['finishedAt'];
    final startedAt = data['startedAt'];
    final createdAt = data['createdAt'];

    DateTime? toDt(dynamic x) {
      if (x is Timestamp) return x.toDate();
      return null;
    }

    return toDt(finishedAt) ?? toDt(startedAt) ?? toDt(createdAt);
  }

  // ---------------------------
  // 5) Run analysis (REAL: create cvAnalyses doc)
  // ---------------------------
  Future<void> _runAnalysis() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('Önce giriş yapmalısın.');
      return;
    }

    if (_cvUrl == null || _cvUrl!.isEmpty) {
      _toast('Önce CV yüklemelisin.');
      return;
    }

    try {
      setState(() {
        _analyzing = true;
        _analysisDoc = null;
        _analysisUpdatedAt = null;
      });

      final ref = await FirebaseFirestore.instance.collection('cvAnalyses').add({
        'uid': user.uid,
        'cvUrl': _cvUrl,
        'targetRole': null,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'queued',
      });

      _analysisId = ref.id;

      _startAnalysisListener(ref.id);

      // history açıksa yenile (yeni doc listede görünsün)
      if (_historyExpanded) {
        await _fetchHistory(force: true);
      }

      _toast('Analiz kuyruğa alındı.');
    } catch (e) {
      setState(() => _analyzing = false);
      _toast('Analiz başlatılamadı: $e');
    }
  }

  void _startAnalysisListener(String analysisId) {
    _analysisSub?.cancel();
    _analysisSub = FirebaseFirestore.instance
        .collection('cvAnalyses')
        .doc(analysisId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;

      final status = _safeStr(data['status']).toLowerCase();
      final analyzing = (status == 'queued' || status == 'running');

      if (!mounted) return;
      setState(() {
        _analysisId = analysisId;
        _analysisDoc = data;
        _analysisUpdatedAt = _pickBestTime(data);
        _analyzing = analyzing;
      });
    }, onError: (_) {});
  }

  void _stopAnalysisListener() {
    _analysisSub?.cancel();
    _analysisSub = null;
  }

  // ---------------------------
  // 6) ✅ History (past analyses)
  // ---------------------------
  Future<void> _toggleHistory() async {
    final next = !_historyExpanded;
    setState(() {
      _historyExpanded = next;
      _historyError = null;
    });

    if (next) {
      await _fetchHistory(force: true);
    }
  }

  Future<void> _fetchHistory({bool force = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!force && _historyDocs.isNotEmpty) return;

    setState(() {
      _historyLoading = true;
      _historyError = null;
    });

    try {
      final q = await FirebaseFirestore.instance
          .collection('cvAnalyses')
          .where('uid', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(25)
          .get();

      setState(() {
        _historyDocs = q.docs;
      });
    } catch (e) {
      setState(() {
        _historyError = 'Geçmiş analizler alınamadı: $e';
      });
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _openHistoryItem(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final id = doc.id;
    final data = doc.data();

    _stopAnalysisListener();

    setState(() {
      _analysisId = id;
      _analysisDoc = data;
      _analysisUpdatedAt = _pickBestTime(data);
      final status = _safeStr(data['status']).toLowerCase();
      _analyzing = (status == 'queued' || status == 'running');
    });

    // seçilen analizi realtime dinle (status değişirse güncellensin)
    _startAnalysisListener(id);
  }

  // ---------------------------
  // helpers
  // ---------------------------
  String _safeStr(dynamic x) => x == null ? '' : x.toString().trim();

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------
  // ✅ Graph helpers (Gauge + Mini bars)
  // ---------------------------
  int? _toScore(dynamic x) {
    if (x == null) return null;
    if (x is int) return x.clamp(0, 100);
    if (x is double) return x.round().clamp(0, 100);
    final s = x.toString().trim();
    final n = int.tryParse(s);
    if (n == null) return null;
    return n.clamp(0, 100);
  }

  Color _scoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  Widget _scoreGauge({required String title, required int? score}) {
    final v = (score ?? 0).clamp(0, 100);
    final frac = v / 100.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            width: 72,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: frac),
              builder: (_, value, __) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: value,
                      strokeWidth: 8,
                      backgroundColor: Theme.of(context).dividerColor.withOpacity(0.35),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        score == null ? Colors.grey : _scoreColor(v),
                      ),
                    ),
                    Text(
                      score == null ? '-' : '$v',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            score == null ? 'yok' : '/100',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }

  Widget _rowBars({required int strengths, required int gaps}) {
    double toFrac(int n) => (n.clamp(0, 10)) / 10.0;

    Widget bar(String title, int n) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: toFrac(n),
                  backgroundColor: Theme.of(context).dividerColor.withOpacity(0.35),
                ),
              ),
              const SizedBox(height: 6),
              Text('$n madde', style: TextStyle(color: Theme.of(context).hintColor)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        bar('Güçlü Yanlar', strengths),
        const SizedBox(width: 10),
        bar('Gelişim Alanları', gaps),
      ],
    );
  }

  // ---------------------------
  // UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final hasCv = _cvUrl != null && _cvUrl!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('AI CV Analiz')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _cvInfoCard(hasCv),
          const SizedBox(height: 12),

          // CV actions
          if (hasCv) ...[
            _actionTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'CV’yi Görüntüle',
              subtitle: _cvFileName ?? 'PDF',
              onTap: (_busy || _analyzing) ? null : _openPdf,
            ),
            const SizedBox(height: 8),
            _actionTile(
              icon: Icons.upload_file_outlined,
              title: 'CV’yi Güncelle (PDF Yükle)',
              subtitle: 'Yeni PDF seç → anında değiştir',
              onTap: (_busy || _analyzing) ? null : _pickAndUploadPdf,
            ),
            const SizedBox(height: 8),
            _actionTile(
              icon: Icons.delete_outline,
              title: 'CV’yi Sil',
              subtitle: 'Storage + Firestore temizlenir',
              danger: true,
              onTap: (_busy || _analyzing) ? null : _confirmDelete,
            ),
          ] else ...[
            _actionTile(
              icon: Icons.upload_file_outlined,
              title: 'PDF CV Yükle',
              subtitle: 'CV yoksa buradan ekle',
              onTap: (_busy || _analyzing) ? null : _pickAndUploadPdf,
            ),
            const SizedBox(height: 8),
            _actionTile(
              icon: Icons.edit_document,
              title: 'Sıfırdan CV Oluştur',
              subtitle: 'Form doldur → PDF üret (eklenecek)',
              onTap: (_busy || _analyzing) ? null : () => _toast('Bunu sonra form+PDF olarak yaparız.'),
            ),
          ],

          const SizedBox(height: 14),

          // Analysis card
          _analysisCard(hasCv),

          const SizedBox(height: 12),

          // ✅ History section (same page)
          _historyCard(),

          const SizedBox(height: 12),

          if (_analysisDoc != null) _analysisResultCard(),
        ],
      ),
    );
  }

  Widget _cvInfoCard(bool hasCv) {
    final updated = _updatedAt == null ? '-' : _updatedAt!.toLocal().toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasCv ? 'CV bulundu ✅ (Firebase tanındı)' : 'CV bulunamadı ❌',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Dosya: ${_cvFileName ?? '-'}')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.update_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Güncelleme: $updated')),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _analysisCard(bool hasCv) {
    final updated = _analysisUpdatedAt == null ? '-' : _analysisUpdatedAt!.toLocal().toString();
    final status = _safeStr(_analysisDoc?['status']).toLowerCase();

    String statusText;
    if (!hasCv) {
      statusText = 'CV yokken analiz olmaz. Önce PDF yükle.';
    } else if (_analysisId == null) {
      statusText = 'CV hazır. Butona bas → analiz kuyruğa girer.';
    } else {
      if (status == 'done') statusText = 'Son analiz hazır. (Güncelleme: $updated)';
      else if (status == 'running') statusText = 'Analiz çalışıyor... (başladı: $updated)';
      else if (status == 'queued') statusText = 'Analiz sırada...';
      else if (status == 'error') statusText = 'Analiz hatası var. Tekrar çalıştırabilirsin.';
      else statusText = 'Durum: $status (Güncelleme: $updated)';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analiz',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(statusText),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!hasCv || _busy || _analyzing) ? null : _runAnalysis,
              icon: _analyzing
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(_analyzing ? 'Analiz ediliyor...' : 'Analizi Başlat'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard() {
    final user = FirebaseAuth.instance.currentUser;
    final disabled = user == null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: disabled ? null : _toggleHistory,
            child: Row(
              children: [
                const Icon(Icons.history),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Geçmiş Analizlerim',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                if (_historyLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(_historyExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _historyExpanded
                ? 'Bir analizi seç → aşağıda “Son Analiz” bölümünde açılır.'
                : 'Tıkla → önceki analizlerin listelensin.',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          if (_historyExpanded) ...[
            const SizedBox(height: 12),

            if (_historyError != null) ...[
              Text(_historyError!, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
            ],

            if (_historyDocs.isEmpty && !_historyLoading) ...[
              const Text('Henüz analiz yok.'),
            ] else ...[
              for (final doc in _historyDocs) _historyTile(doc),
            ],
          ],
        ],
      ),
    );
  }

  Widget _historyTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final status = _safeStr(data['status']).toLowerCase();
    final t = _pickBestTime(data);
    final timeText = t == null ? '-' : t.toLocal().toString();

    final report = (data['report'] is Map) ? Map<String, dynamic>.from(data['report']) : null;
    final overall = _toScore(report?['overallScore']);

    IconData icon;
    Color? color;
    if (status == 'done') {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (status == 'error') {
      icon = Icons.error;
      color = Colors.red;
    } else if (status == 'running') {
      icon = Icons.autorenew;
      color = Colors.orange;
    } else {
      icon = Icons.hourglass_bottom;
      color = Colors.blueGrey;
    }

    final isSelected = (_analysisId == doc.id);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        'Analiz • ${doc.id.substring(0, doc.id.length >= 6 ? 6 : doc.id.length)}'
            '${overall == null ? '' : ' • Skor $overall'}'
            '${isSelected ? ' (Açık)' : ''}',
        style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700),
      ),
      subtitle: Text('Durum: $status • $timeText'),
      trailing: const Icon(Icons.chevron_right),
      onTap: _busy ? null : () => _openHistoryItem(doc),
    );
  }

  Widget _analysisResultCard() {
    final data = _analysisDoc ?? {};
    final status = _safeStr(data['status']).toLowerCase();
    final err = _safeStr(data['error']);

    final report = (data['report'] is Map) ? Map<String, dynamic>.from(data['report']) : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Son Analiz',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text('Durum: ${status.isEmpty ? '-' : status}'),

          if (status == 'error' && err.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Hata: $err', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],

          if (status == 'done' && report != null) ...[
            const SizedBox(height: 12),

            // ✅ Gauges (Genel / ATS / Uyum)
            Builder(builder: (_) {
              final overall = _toScore(report['overallScore']);
              final ats = _toScore((report['ats'] is Map) ? report['ats']['compatScore'] : null);
              final fit = _toScore((report['roleFit'] is Map) ? report['roleFit']['fitScore'] : null);

              return Row(
                children: [
                  Expanded(child: _scoreGauge(title: 'Genel', score: overall)),
                  const SizedBox(width: 10),
                  Expanded(child: _scoreGauge(title: 'ATS', score: ats)),
                  const SizedBox(width: 10),
                  Expanded(child: _scoreGauge(title: 'Uyum', score: fit)),
                ],
              );
            }),

            const SizedBox(height: 12),

            // ✅ Mini bars: strengths/gaps count
            Builder(builder: (_) {
              final strengths = (report['strengths'] is List) ? (report['strengths'] as List).length : 0;
              final gaps = (report['gaps'] is List) ? (report['gaps'] as List).length : 0;
              return _rowBars(strengths: strengths, gaps: gaps);
            }),

            const SizedBox(height: 12),

            Text('Parse Quality: ${report['parseQuality'] ?? '-'}'),

            const SizedBox(height: 12),
            const Text('ATS', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Uyum Skoru: ${((report['ats'] is Map) ? (report['ats']['compatScore']) : null) ?? '-'}'),
            Text('Seviye: ${((report['ats'] is Map) ? (report['ats']['level']) : null) ?? '-'}'),

            const SizedBox(height: 12),
            _stringListBlock('Güçlü Yanlar', report['strengths']),
            _stringListBlock('Gelişim Alanları', report['gaps']),

            const SizedBox(height: 12),
            if (report['roleFit'] is Map) ...[
              const Text('Role Fit', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Hedef: ${report['roleFit']['targetRole'] ?? '-'}'),
              Text('Fit Skoru: ${report['roleFit']['fitScore'] ?? '-'} / 100'),
              const SizedBox(height: 8),
              _stringListBlock('Neden', report['roleFit']['why']),
              _stringListBlock('Eksik Skill', report['roleFit']['missingSkills']),
              _stringListBlock('Next Steps', report['roleFit']['nextSteps']),
            ],
          ],

          if (status == 'done' && report == null) ...[
            const SizedBox(height: 10),
            const Text('Rapor boş geldi. Backend output’u kontrol et.'),
          ],
        ],
      ),
    );
  }

  Widget _stringListBlock(String title, dynamic raw) {
    if (raw is! List) return const SizedBox.shrink();
    final items = raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        for (final t in items.take(6)) Text('• $t'),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? Colors.red : null;

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: Theme.of(context).cardColor,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
