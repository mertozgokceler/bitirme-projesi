import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/cv_analysis_provider.dart';

class CvAnalysisScreen extends StatefulWidget {
  const CvAnalysisScreen({super.key});

  @override
  State<CvAnalysisScreen> createState() => _CvAnalysisScreenState();
}

class _CvAnalysisScreenState extends State<CvAnalysisScreen> {
  bool _booted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_booted) return;
    _booted = true;

    Future.microtask(() => context.read<CvAnalysisProvider>().bootstrap());
  }

  // ---------------------------
  // UI helpers (Premium standard)
  // ---------------------------
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

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(isDark ? 0.78 : 0.92),
            borderRadius: BorderRadius.circular(18),
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

  Widget _iconPill(IconData icon, {Color? color}) {
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

  Widget _premiumButton({
    required String text,
    required VoidCallback? onPressed,
    bool loading = false,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final disabled = onPressed == null;

    final gradient = danger
        ? const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFB71C1C)])
        : const LinearGradient(colors: [Color(0xFF6D5DF6), Color(0xFF4FC3F7)]);

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: disabled
          ? ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: loading
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
      )
          : DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (danger ? Colors.red : const Color(0xFF6D5DF6))
                  .withOpacity(isDark ? 0.40 : 0.28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: loading
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : Text(
            text,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.3,
              shadows: [
                Shadow(offset: Offset(0, 1), blurRadius: 3, color: Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------
  // helpers
  // ---------------------------
  String _safeStr(dynamic x) => x == null ? '' : x.toString().trim();

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

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

  Future<void> _openPdf(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('CV linki bozuk.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _toast('PDF açılamadı.');
  }

  Future<void> _pickAndUploadPdf(CvAnalysisProvider p) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final Uint8List? bytes = picked.bytes;
      final String fileName = picked.name;

      if (bytes == null) {
        _toast('PDF okunamadı (bytes null).');
        return;
      }

      await p.uploadCvPdf(bytes: bytes, fileName: fileName);
      _toast('CV yüklendi / güncellendi.');
    } catch (e) {
      _toast('Yükleme hatası: $e');
    }
  }

  Future<void> _confirmDelete(CvAnalysisProvider p) async {
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await p.deleteCv();
        _toast('CV silindi.');
      } catch (e) {
        _toast('Silme hatası: $e');
      }
    }
  }

  // ---------------------------
  // NEW: Credits Card
  // ---------------------------
  Widget _creditCard(CvAnalysisProvider p) {
    final theme = Theme.of(context);

    final limit = p.dailyLimit;
    final used = p.usedToday;
    final left = p.remainingToday;

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: Lottie.asset(
                  'assets/lottie/twinkle.json',
                  fit: BoxFit.contain,
                  repeat: true,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Günlük CV Analiz Kredisi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              if (p.creditsLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _iconPill(Icons.bolt_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Kalan: $left / $limit',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: left == 0 ? Colors.red : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Text(
                'Kullanılan: $used',
                style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: theme.colorScheme.surfaceVariant.withOpacity(
                theme.brightness == Brightness.dark ? 0.14 : 0.55,
              ),
              border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
            ),
            child: Text(
              p.isPremium
                  ? 'Not: Premium üyeler günlük 15 kez CV analizi yapabilir.'
                  : 'Not: Premium değilsen günlük sadece 3 analiz hakkın var. Premium ile günlük 15 hak alırsın.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: p.creditsLoading ? null : () => p.refreshCredits(),
              icon: const Icon(Icons.refresh),
              label: const Text('Yenile'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Consumer<CvAnalysisProvider>(
      builder: (context, p, _) {
        final hasCv = p.hasCv;
        final cvUrl = p.cv?.url ?? '';
        final cvName = p.cv?.fileName;
        final updated = p.cv?.updatedAt == null ? '-' : p.cv!.updatedAt!.toLocal().toString();

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('AI CV Analiz'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: cs.onSurface,
          ),
          body: Stack(
            children: [
              Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
              Positioned(top: -120, left: -80, child: _GlowBlob(size: 260, color: cs.primary.withOpacity(0.20))),
              Positioned(bottom: -140, right: -90, child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18))),
              SafeArea(
                child: p.loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  children: [
                    _glassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasCv ? 'CV bulundu' : 'CV bulunamadı',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _iconPill(Icons.description_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Dosya: ${cvName ?? '-'}',
                                  style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _iconPill(Icons.update_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Güncelleme: $updated',
                                  style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          if (p.busy) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: const LinearProgressIndicator(minHeight: 8),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // CV actions
                    if (hasCv) ...[
                      _actionTile(
                        icon: Icons.picture_as_pdf_outlined,
                        title: 'CV’yi Görüntüle',
                        subtitle: cvName ?? 'PDF',
                        onTap: (p.busy || p.analyzing) ? null : () => _openPdf(cvUrl),
                      ),
                      const SizedBox(height: 10),
                      _actionTile(
                        icon: Icons.upload_file_outlined,
                        title: 'CV’yi Güncelle (PDF Yükle)',
                        subtitle: 'Yeni PDF seç → anında değiştir',
                        onTap: (p.busy || p.analyzing) ? null : () => _pickAndUploadPdf(p),
                      ),
                      const SizedBox(height: 10),
                      _actionTile(
                        icon: Icons.delete_outline,
                        title: 'CV’yi Sil',
                        subtitle: 'Storage + Firestore temizlenir',
                        danger: true,
                        onTap: (p.busy || p.analyzing) ? null : () => _confirmDelete(p),
                      ),
                    ] else ...[
                      _actionTile(
                        icon: Icons.upload_file_outlined,
                        title: 'PDF CV Yükle',
                        subtitle: 'CV yoksa buradan ekle',
                        onTap: (p.busy || p.analyzing) ? null : () => _pickAndUploadPdf(p),
                      ),
                      const SizedBox(height: 10),
                    ],

                    const SizedBox(height: 14),

                    // NEW: credits
                    _creditCard(p),

                    const SizedBox(height: 12),

                    _analysisCard(p),

                    const SizedBox(height: 12),

                    _historyCard(p),

                    const SizedBox(height: 12),

                    if (p.analysisDoc != null) _analysisResultCard(p),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _analysisCard(CvAnalysisProvider p) {
    final theme = Theme.of(context);

    final hasCv = p.hasCv;
    final status = _safeStr(p.analysisDoc?['status']).toLowerCase();
    final err = _safeStr(p.analysisDoc?['error']);
    final updated = p.analysisUpdatedAt == null ? '-' : p.analysisUpdatedAt!.toLocal().toString();

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (!hasCv) {
      statusText = 'CV yok. Önce PDF yükle.';
      statusColor = Colors.blueGrey;
      statusIcon = Icons.info_outline;
    } else if (p.analysisId == null) {
      statusText = 'CV hazır. Analizi başlatabilirsin.';
      statusColor = theme.colorScheme.primary;
      statusIcon = Icons.auto_awesome_outlined;
    } else {
      if (status == 'done') {
        statusText = 'Son analiz hazır • $updated';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
      } else if (status == 'running') {
        statusText = 'Analiz çalışıyor...';
        statusColor = Colors.orange;
        statusIcon = Icons.autorenew;
      } else if (status == 'queued') {
        statusText = 'Analiz sırada...';
        statusColor = Colors.blueGrey;
        statusIcon = Icons.hourglass_bottom;
      } else if (status == 'error') {
        statusText = 'Analiz hatası var. Tekrar çalıştırabilirsin.';
        statusColor = Colors.red;
        statusIcon = Icons.error;
      } else {
        statusText = 'Durum: $status • $updated';
        statusColor = Colors.blueGrey;
        statusIcon = Icons.help_outline;
      }
    }

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Analiz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(
            children: [
              _iconPill(statusIcon, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
          if (status == 'error' && err.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.red.withOpacity(theme.brightness == Brightness.dark ? 0.14 : 0.08),
                border: Border.all(color: Colors.red.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.report_gmailerrorred_outlined, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      err,
                      style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _premiumButton(
            text: p.analyzing ? 'Analiz ediliyor...' : 'Analizi Başlat',
            loading: p.analyzing,
            onPressed: (!hasCv || p.busy || p.analyzing)
                ? null
                : () async {
              try {
                await p.runAnalysis();
                _toast('Analiz kuyruğa alındı.');
              } catch (e) {
                _toast('Analiz başlatılamadı: $e');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _historyCard(CvAnalysisProvider p) {
    final theme = Theme.of(context);

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: p.isLoggedIn ? () => p.toggleHistory() : null,
            child: Row(
              children: [
                _iconPill(Icons.history),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Geçmiş Analizlerim',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                if (p.historyLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(p.historyExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            p.historyExpanded
                ? 'Bir analizi seç → aşağıda “Son Analiz” bölümünde açılır.'
                : 'Tıkla → önceki analizlerin listelensin.',
            style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w600),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: p.historyExpanded
                ? Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  if (p.historyError != null) ...[
                    _inlineWarning(p.historyError!),
                    const SizedBox(height: 10),
                  ],
                  if (p.historyDocs.isEmpty && !p.historyLoading)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Henüz analiz yok.',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    )
                  else
                    ...p.historyDocs.map((d) => _historyTile(p, d)),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _inlineWarning(String text) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.60),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(CvAnalysisProvider p, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final theme = Theme.of(context);
    final data = doc.data();
    final status = _safeStr(data['status']).toLowerCase();

    DateTime? t;
    final finishedAt = data['finishedAt'];
    final startedAt = data['startedAt'];
    final createdAt = data['createdAt'];
    if (finishedAt is Timestamp) t = finishedAt.toDate();
    if (t == null && startedAt is Timestamp) t = startedAt.toDate();
    if (t == null && createdAt is Timestamp) t = createdAt.toDate();

    final timeText = t == null ? '-' : t.toLocal().toString();

    final report = (data['report'] is Map) ? Map<String, dynamic>.from(data['report']) : null;
    final overall = _toScore(report?['overallScore']);

    IconData icon;
    Color color;
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

    final isSelected = (p.analysisId == doc.id);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: p.busy ? null : () => p.openHistoryItem(doc),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
          color: theme.colorScheme.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.12 : 0.55),
        ),
        child: Row(
          children: [
            _iconPill(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analiz • ${doc.id.substring(0, doc.id.length >= 6 ? 6 : doc.id.length)}'
                        '${overall == null ? '' : ' • Skor $overall'}'
                        '${isSelected ? ' (Açık)' : ''}',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Durum: $status • $timeText',
                    style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, color: theme.hintColor),
          ],
        ),
      ),
    );
  }

  Widget _analysisResultCard(CvAnalysisProvider p) {
    final theme = Theme.of(context);
    final data = p.analysisDoc ?? {};
    final status = _safeStr(data['status']).toLowerCase();
    final err = _safeStr(data['error']);

    final report = (data['report'] is Map) ? Map<String, dynamic>.from(data['report']) : null;

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Son Analiz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(
            children: [
              _iconPill(
                status == 'done'
                    ? Icons.check_circle
                    : status == 'error'
                    ? Icons.error
                    : status == 'running'
                    ? Icons.autorenew
                    : Icons.hourglass_bottom,
                color: status == 'done'
                    ? Colors.green
                    : status == 'error'
                    ? Colors.red
                    : status == 'running'
                    ? Colors.orange
                    : Colors.blueGrey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Durum: ${status.isEmpty ? '-' : status}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (status == 'error') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.red.withOpacity(theme.brightness == Brightness.dark ? 0.14 : 0.08),
                border: Border.all(color: Colors.red.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.report_problem_outlined, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      err.isEmpty ? 'Hata mesajı yok. Backend error alanını doldurmuyor.' : err,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (status == 'done' && report != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _scoreGauge(title: 'Genel', score: _toScore(report['overallScore']))),
                const SizedBox(width: 10),
                Expanded(child: _scoreGauge(title: 'ATS', score: _toScore((report['ats'] is Map) ? report['ats']['compatScore'] : null))),
                const SizedBox(width: 10),
                Expanded(child: _scoreGauge(title: 'Uyum', score: _toScore((report['roleFit'] is Map) ? report['roleFit']['fitScore'] : null))),
              ],
            ),
            const SizedBox(height: 12),
            Builder(builder: (_) {
              final strengths = (report['strengths'] is List) ? (report['strengths'] as List).length : 0;
              final gaps = (report['gaps'] is List) ? (report['gaps'] as List).length : 0;
              return _rowBars(strengths: strengths, gaps: gaps);
            }),
            const SizedBox(height: 12),
            Text('Parse Quality: ${report['parseQuality'] ?? '-'}',
                style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('Güçlü Yanlar', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            _stringListBlock(report['strengths']),
            const SizedBox(height: 12),
            const Text('Gelişim Alanları', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            _stringListBlock(report['gaps']),
          ],
          if (status == 'done' && report == null) ...[
            const SizedBox(height: 10),
            const Text('Rapor boş geldi. Backend output’u kontrol et.',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }

  Widget _stringListBlock(dynamic raw) {
    if (raw is! List) return const SizedBox.shrink();
    final items = raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in items.take(7)) Text('• $t', style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _scoreGauge({required String title, required int? score}) {
    final theme = Theme.of(context);
    final v = (score ?? 0).clamp(0, 100);
    final frac = v / 100.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
        color: theme.colorScheme.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.12 : 0.55),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          SizedBox(
            height: 74,
            width: 74,
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
                      backgroundColor: theme.dividerColor.withOpacity(0.25),
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
          Text(score == null ? 'yok' : '/100', style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _rowBars({required int strengths, required int gaps}) {
    double toFrac(int n) => (n.clamp(0, 10)) / 10.0;

    Widget bar(String title, int n) {
      final theme = Theme.of(context);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
            color: theme.colorScheme.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.12 : 0.55),
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
                  backgroundColor: theme.dividerColor.withOpacity(0.25),
                ),
              ),
              const SizedBox(height: 6),
              Text('$n madde', style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w600)),
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

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final color = danger ? Colors.red : theme.colorScheme.onSurface;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: _glassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _iconPill(icon, color: danger ? Colors.red : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w900, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, color: theme.hintColor),
          ],
        ),
      ),
    );
  }
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
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}
