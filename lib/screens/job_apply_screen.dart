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

  @override
  void initState() {
    super.initState();

    final order = ['phone', 'email', 'cv', 'portfolio', 'linkedin', 'coverLetter'];
    _steps = order.where(_isOn).toList();

    // hiç alan seçilmediyse email zorunlu olsun
    if (_steps.isEmpty) _steps.add('email');

    // email varsa auto doldur
    final u = FirebaseAuth.instance.currentUser;
    if (u != null && (_emailCtrl.text.trim().isEmpty)) {
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

  String _jobTitle() => (widget.job['title'] ?? 'Başvuru').toString();

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
        return 'Ön yazı boş olamaz (en az 30 karakter).';
      default:
        return 'Bu adım eksik.';
    }
  }

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dosya seçme hatası: $e')),
      );
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

      await ref.putFile(
        File(path),
        SettableMetadata(contentType: 'application/octet-stream'),
      );

      final url = await ref.getDownloadURL();
      if (mounted) setState(() => _cvDownloadUrl = url);
      return url;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CV yükleme hatası: $e')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _uploadingCv = false);
    }
  }

  Future<void> _next() async {
    final step = _steps[_page];

    if (step == 'cv') {
      if (_cvFile == null && _cvDownloadUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorFor(step))),
        );
        return;
      }
      final url = await _uploadCvIfNeeded();
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CV yüklenemedi.')),
        );
        return;
      }
    } else {
      if (!_validateStep(step)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorFor(step))),
        );
        return;
      }
    }

    if (_page < _steps.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      await _submit();
    }
  }

  void _back() {
    if (_page == 0) {
      Navigator.pop(context);
      return;
    }
    _pageCtrl.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;

    for (final s in _steps) {
      if (s == 'cv') {
        final url = await _uploadCvIfNeeded();
        if (url == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CV zorunlu ama yüklenemedi.')),
          );
          return;
        }
      } else if (!_validateStep(s)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eksik adım: ${_labelFor(s)}')),
        );
        return;
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giriş yapmış kullanıcı yok.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // ✅ users/{uid} snapshot çek -> applicantName boş kalmasın
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

        // ✅ collectionGroup query için
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Başvurun gönderildi.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Başvuru kaydı hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_steps.length, (i) {
        final active = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withOpacity(0.35),
          ),
        );
      }),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _stepWidget(String step) {
    switch (step) {
      case 'phone':
        return _cardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_labelFor(step),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: '05xx xxx xx xx',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        );

      case 'email':
        return _cardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_labelFor(step),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'ornek@mail.com',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        );

      case 'cv':
        return _cardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_labelFor(step),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withOpacity(0.35)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _cvFile?.name ??
                            (_cvDownloadUrl != null ? 'CV yüklendi ✅' : 'Henüz dosya seçilmedi'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _uploadingCv ? null : _pickCv,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Seç'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_cvFile != null && _cvDownloadUrl == null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _uploadingCv ? 'Yükleniyor...' : 'İleri dediğinde CV otomatik yüklenecek.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                    if (_uploadingCv)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
            ],
          ),
        );

      case 'portfolio':
        return _cardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_labelFor(step),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _portfolioCtrl,
                decoration: const InputDecoration(
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        );

      case 'linkedin':
        return _cardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_labelFor(step),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _linkedinCtrl,
                decoration: const InputDecoration(
                  hintText: 'https://linkedin.com/in/...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        );

      case 'coverLetter':
        return _cardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_labelFor(step),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _coverCtrl,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: 'Kısaca kendini anlat, neden uygunsun...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Text('En az 30 karakter yaz.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        );

      default:
        return _cardShell(child: Text('Bilinmeyen adım: $step'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _jobTitle();

    return Scaffold(
      appBar: AppBar(title: const Text('Başvuru')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            _dots(),
            const SizedBox(height: 10),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _steps.length,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: _stepWidget(_steps[i]),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (_submitting || _uploadingCv) ? null : _back,
                      child: Text(_page == 0 ? 'Vazgeç' : 'Geri'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_submitting || _uploadingCv) ? null : _next,
                      child: _submitting
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : Text(_page == _steps.length - 1 ? 'Gönder' : 'İleri'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
