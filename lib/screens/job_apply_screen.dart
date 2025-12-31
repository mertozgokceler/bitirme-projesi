import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class JobApplyScreen extends StatefulWidget {
  final String jobId;
  final Map<String, dynamic> job;

  const JobApplyScreen({
    super.key,
    required this.jobId,
    required this.job,
  });

  @override
  State<JobApplyScreen> createState() => _JobApplyScreenState();
}

class _JobApplyScreenState extends State<JobApplyScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  bool _submitting = false;
  bool _uploadingCv = false;

  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _portfolioCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();
  final _coverCtrl = TextEditingController();

  PlatformFile? _cvFile;
  String? _cvDownloadUrl;

  Map<String, dynamic> get _applyFields =>
      (widget.job['applyFields'] as Map?)?.cast<String, dynamic>() ?? {};

  bool _isOn(String key) => _applyFields[key] == true;

  late final List<String> _steps;

  bool get _isLast => _page == _steps.length - 1;

  @override
  void initState() {
    super.initState();

    final order = ['phone', 'email', 'cv', 'portfolio', 'linkedin', 'coverLetter'];
    _steps = order.where(_isOn).toList();
    if (_steps.isEmpty) _steps.add('email');

    final u = FirebaseAuth.instance.currentUser;
    if (u != null && _emailCtrl.text.trim().isEmpty) {
      final em = (u.email ?? '').trim();
      if (em.isNotEmpty) _emailCtrl.text = em;
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _portfolioCtrl.dispose();
    _linkedinCtrl.dispose();
    _coverCtrl.dispose();
    super.dispose();
  }

  // -------------------- helpers --------------------

  String _jobTitle() => (widget.job['title'] ?? 'Başvuru').toString().trim().isEmpty
      ? 'Başvuru'
      : (widget.job['title'] ?? 'Başvuru').toString().trim();

  String _companyName() =>
      (widget.job['companyName'] ?? 'Şirket').toString().trim().isEmpty
          ? 'Şirket'
          : (widget.job['companyName'] ?? 'Şirket').toString().trim();

  String _location() => (widget.job['location'] ?? 'Konum')
      .toString()
      .trim()
      .isEmpty
      ? 'Konum'
      : (widget.job['location'] ?? 'Konum').toString().trim();

  String _labelFor(String key) {
    switch (key) {
      case 'phone':
        return 'Telefon numaran';
      case 'email':
        return 'E-posta adresin';
      case 'cv':
        return 'CV yükle';
      case 'portfolio':
        return 'Portföy linkin';
      case 'linkedin':
        return 'LinkedIn profilin';
      case 'coverLetter':
        return 'Ön yazı';
      default:
        return key;
    }
  }

  String _descFor(String key) {
    switch (key) {
      case 'phone':
        return 'Hızlı iletişim için kullanılır.';
      case 'email':
        return 'Başvurunla ilgili dönüş bu adrese gelir.';
      case 'cv':
        return 'PDF/DOC/DOCX yükleyebilirsin.';
      case 'portfolio':
        return 'Projelerini tek linkte göster.';
      case 'linkedin':
        return 'Profilin ile kendini öne çıkar.';
      case 'coverLetter':
        return 'Kısa ve net: neden sen?';
      default:
        return '';
    }
  }

  IconData _iconFor(String key) {
    switch (key) {
      case 'phone':
        return Icons.phone_rounded;
      case 'email':
        return Icons.alternate_email_rounded;
      case 'cv':
        return Icons.upload_file_rounded;
      case 'portfolio':
        return Icons.language_rounded;
      case 'linkedin':
        return Icons.badge_rounded;
      case 'coverLetter':
        return Icons.edit_note_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  // -------------------- validation --------------------

  bool _validateStep(String step) {
    switch (step) {
      case 'phone':
        return _phoneCtrl.text.trim().isNotEmpty;
      case 'email':
        final v = _emailCtrl.text.trim();
        return v.isNotEmpty && v.contains('@');
      case 'cv':
        return _cvFile != null || _cvDownloadUrl != null;
      case 'portfolio':
        return _portfolioCtrl.text.trim().isNotEmpty;
      case 'linkedin':
        return _linkedinCtrl.text.trim().isNotEmpty;
      case 'coverLetter':
        final v = _coverCtrl.text.trim();
        return v.isNotEmpty && v.length >= 30;
      default:
        return true;
    }
  }

  String _errorFor(String step) {
    switch (step) {
      case 'phone':
        return 'Telefon boş olamaz.';
      case 'email':
        return 'Geçerli bir e-posta yaz.';
      case 'cv':
        return 'CV dosyası seçmelisin.';
      case 'portfolio':
        return 'Portföy linki boş olamaz.';
      case 'linkedin':
        return 'LinkedIn linki boş olamaz.';
      case 'coverLetter':
        return 'Ön yazı en az 30 karakter olmalı.';
      default:
        return 'Bu adım eksik.';
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // -------------------- file pick/upload --------------------

  Future<void> _pickCv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      setState(() {
        _cvFile = result.files.first;
        _cvDownloadUrl = null;
      });
    } catch (e) {
      _snack('Dosya seçme hatası: $e');
    }
  }

  Future<String?> _uploadCvIfNeeded() async {
    if (_cvDownloadUrl != null) return _cvDownloadUrl;
    if (_cvFile == null) return null;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final path = _cvFile!.path;
    if (path == null) return null;

    setState(() => _uploadingCv = true);

    try {
      final ext = (_cvFile!.extension ?? 'file').toLowerCase();
      final fileName = 'cv_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final ref = FirebaseStorage.instance
          .ref()
          .child('job_applications')
          .child(widget.jobId)
          .child(user.uid)
          .child(fileName);

      await ref.putFile(File(path));

      final url = await ref.getDownloadURL();
      if (mounted) setState(() => _cvDownloadUrl = url);
      return url;
    } catch (e) {
      _snack('CV yükleme hatası: $e');
      return null;
    } finally {
      if (mounted) setState(() => _uploadingCv = false);
    }
  }

  // -------------------- navigation --------------------

  Future<void> _next() async {
    final step = _steps[_page];

    if (step == 'cv') {
      if (_cvFile == null && _cvDownloadUrl == null) {
        _snack(_errorFor(step));
        return;
      }
      final url = await _uploadCvIfNeeded();
      if (url == null) {
        _snack('CV yüklenemedi.');
        return;
      }
    } else {
      if (!_validateStep(step)) {
        _snack(_errorFor(step));
        return;
      }
    }

    if (_isLast) {
      await _submit();
      return;
    }

    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_page == 0) {
      Navigator.pop(context);
      return;
    }
    _pageCtrl.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  // -------------------- submit --------------------

  Future<void> _submit() async {
    if (_submitting) return;

    for (final s in _steps) {
      if (s == 'cv') {
        final url = await _uploadCvIfNeeded();
        if (url == null) {
          _snack('CV zorunlu ama yüklenemedi.');
          return;
        }
      } else if (!_validateStep(s)) {
        _snack('Eksik adım: ${_labelFor(s)}');
        return;
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Giriş yapmış kullanıcı yok.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final u = userDoc.data() ?? {};

      final rawName = (u['name'] ?? '').toString().trim();
      final username = (u['username'] ?? '').toString().trim();
      final photoUrl = (u['photoUrl'] ?? '').toString().trim();

      String applicantName = rawName;
      if (applicantName.isEmpty && (user.displayName ?? '').trim().isNotEmpty) {
        applicantName = user.displayName!.trim();
      }
      if (applicantName.isEmpty && (user.email ?? '').trim().isNotEmpty) {
        applicantName = user.email!.split('@').first;
      }
      if (applicantName.isEmpty) applicantName = 'Aday';

      final data = <String, dynamic>{
        'applicantId': user.uid,
        'applicantName': applicantName,
        'applicantUsername': username,
        'applicantPhotoUrl': photoUrl,
        'applicantEmailAuth': (user.email ?? '').trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'new',
        'jobId': widget.jobId,
        'jobTitle': widget.job['title'],
        'companyId': widget.job['companyId'],
        'companyName': widget.job['companyName'],
      };

      if (_isOn('phone')) data['phone'] = _phoneCtrl.text.trim();
      if (_isOn('email')) data['email'] = _emailCtrl.text.trim();
      if (_isOn('portfolio')) data['portfolio'] = _portfolioCtrl.text.trim();
      if (_isOn('linkedin')) data['linkedin'] = _linkedinCtrl.text.trim();
      if (_isOn('coverLetter')) data['coverLetter'] = _coverCtrl.text.trim();
      if (_isOn('cv')) data['cvUrl'] = _cvDownloadUrl;

      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .collection('applications')
          .add(data);

      if (!mounted) return;
      _snack('Başvurun gönderildi 🎉');
      Navigator.pop(context);
    } catch (e) {
      _snack('Başvuru kaydı hatası: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // -------------------- premium UI bits --------------------

  List<Color> _heroGradient(bool isDark) {
    if (isDark) {
      return const [
        Color(0xFF6D5DF6),
        Color(0xFF4FC3F7),
        Color(0xFF00E5FF),
      ];
    }
    return const [
      Color(0xFF5C7CFA),
      Color(0xFF4FC3F7),
      Color(0xFF7C4DFF),
    ];
  }

  Color _glassBg(bool isDark) => isDark
      ? const Color(0xFF11121A).withOpacity(0.78)
      : Colors.white.withOpacity(0.78);

  Color _glassBorder(bool isDark) => isDark
      ? Colors.white.withOpacity(0.10)
      : Colors.black.withOpacity(0.08);

  Widget _pillCounter(bool isDark) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.10) : Colors.white.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Text(
        '${_page + 1}/${_steps.length}',
        style: t.textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _progressBar(bool isDark) {
    final total = _steps.length;
    final p = total <= 1 ? 1.0 : (_page + 1) / total;

    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(isDark ? 0.16 : 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: MediaQuery.of(context).size.width * 0.78 * p,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: const [Color(0xFFFFFFFF), Color(0xFFB3E5FC)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final t = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: _glassBg(isDark),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _glassBorder(isDark), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.40 : 0.10),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [Color(0xFF6D5DF6), Color(0xFF4FC3F7)]
                        : const [Color(0xFF5C7CFA), Color(0xFF4FC3F7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? const Color(0xFF6D5DF6) : const Color(0xFF5C7CFA))
                          .withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: t.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: t.textTheme.bodySmall?.copyWith(
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white.withOpacity(0.72) : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  InputDecoration _premiumInput({
    required bool isDark,
    required String hint,
    required IconData icon,
  }) {
    final base = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.10),
        width: 1,
      ),
    );

    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? Colors.white.withOpacity(0.55) : Colors.black.withOpacity(0.45),
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon, size: 20, color: isDark ? Colors.white.withOpacity(0.80) : const Color(0xFF334155)),
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.03),
      border: base,
      enabledBorder: base,
      focusedBorder: base.copyWith(
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF4FC3F7).withOpacity(0.70) : const Color(0xFF5C7CFA).withOpacity(0.70),
          width: 1.4,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildStepWidget(bool isDark, String step) {
    final t = Theme.of(context);

    switch (step) {
      case 'phone':
        return _stepCard(
          isDark: isDark,
          icon: _iconFor(step),
          title: _labelFor(step),
          subtitle: _descFor(step),
          child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
            decoration: _premiumInput(
              isDark: isDark,
              hint: '05xx xxx xx xx',
              icon: Icons.phone_rounded,
            ),
          ),
        );

      case 'email':
        return _stepCard(
          isDark: isDark,
          icon: _iconFor(step),
          title: _labelFor(step),
          subtitle: _descFor(step),
          child: TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
            decoration: _premiumInput(
              isDark: isDark,
              hint: 'ornek@mail.com',
              icon: Icons.alternate_email_rounded,
            ),
          ),
        );

      case 'cv':
        return _stepCard(
          isDark: isDark,
          icon: _iconFor(step),
          title: _labelFor(step),
          subtitle: _descFor(step),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.10),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_rounded,
                        size: 20,
                        color: isDark ? Colors.white.withOpacity(0.80) : const Color(0xFF334155)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _cvFile?.name ??
                            (_cvDownloadUrl != null ? 'CV yüklendi ✅' : 'Henüz dosya seçilmedi'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_uploadingCv)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploadingCv ? null : _pickCv,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Dosya Seç'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                        side: BorderSide(
                          color: isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _cvFile != null && _cvDownloadUrl == null
                    ? (_uploadingCv ? 'Yükleniyor...' : 'İlerle dediğinde CV otomatik yüklenecek.')
                    : 'PDF/DOC/DOCX desteklenir.',
                style: t.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white.withOpacity(0.65) : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        );

      case 'portfolio':
        return _stepCard(
          isDark: isDark,
          icon: _iconFor(step),
          title: _labelFor(step),
          subtitle: _descFor(step),
          child: TextField(
            controller: _portfolioCtrl,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
            decoration: _premiumInput(
              isDark: isDark,
              hint: 'https://...',
              icon: Icons.language_rounded,
            ),
          ),
        );

      case 'linkedin':
        return _stepCard(
          isDark: isDark,
          icon: _iconFor(step),
          title: _labelFor(step),
          subtitle: _descFor(step),
          child: TextField(
            controller: _linkedinCtrl,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
            decoration: _premiumInput(
              isDark: isDark,
              hint: 'https://linkedin.com/in/...',
              icon: Icons.badge_rounded,
            ),
          ),
        );

      case 'coverLetter':
        return _stepCard(
          isDark: isDark,
          icon: _iconFor(step),
          title: _labelFor(step),
          subtitle: _descFor(step),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _coverCtrl,
                minLines: 6,
                maxLines: 10,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
                decoration: _premiumInput(
                  isDark: isDark,
                  hint: 'Kısaca kendini anlat, neden uygunsun...',
                  icon: Icons.edit_note_rounded,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'En az 30 karakter yaz.',
                style: t.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white.withOpacity(0.65) : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _bottomBar(bool isDark) {
    final t = Theme.of(context);

    final String primaryLabel = _isLast ? 'Başvur' : 'İlerle';

    final bool disabled = _submitting || _uploadingCv;

    final Color applyTextColor = isDark ? const Color(0xFF0B1220) : Colors.white; // daha koyu
    final TextStyle applyTextStyle = t.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: 0.2,
      color: applyTextColor,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: disabled ? null : _back,
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white.withOpacity(0.92) : const Color(0xFF0F172A),
                  side: BorderSide(
                    color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.10),
                    width: 1,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  backgroundColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.02),
                ),
                child: Text(
                  _page == 0 ? 'Vazgeç' : 'Geri',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: isDark
                  ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [Color(0xFF6D5DF6), Color(0xFF4FC3F7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6D5DF6).withOpacity(0.38),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: disabled ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Text(primaryLabel, style: applyTextStyle),
                ),
              )
                  : ElevatedButton(
                onPressed: disabled ? null : _next,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _submitting
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : Text(
                  primaryLabel,
                  style: t.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- build --------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final topBg = _heroGradient(isDark);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0D14) : const Color(0xFFF6F7FB),
      body: Stack(
        children: [
          // HERO GRADIENT
          Container(
            height: 270,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: topBg,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // dark vignette
          if (isDark)
            Container(
              height: 270,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.10),
                    Colors.black.withOpacity(0.35),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

          SafeArea(
            child: Column(
              children: [
                // TOP BAR
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Başvuru',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      _pillCounter(isDark),
                    ],
                  ),
                ),

                // HERO CONTENT
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _jobTitle(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _companyName(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 18, color: Colors.white.withOpacity(0.92)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _location(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.92),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.78,
                          child: _progressBar(isDark),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // BODY
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0B0D14) : const Color(0xFFF6F7FB),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.45 : 0.12),
                          blurRadius: 22,
                          offset: const Offset(0, -6),
                        )
                      ],
                    ),
                    child: PageView.builder(
                      controller: _pageCtrl,
                      itemCount: _steps.length,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) {
                        final step = _steps[i];
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
                          child: _buildStepWidget(isDark, step),
                        );
                      },
                    ),
                  ),
                ),

                // BOTTOM
                _bottomBar(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
