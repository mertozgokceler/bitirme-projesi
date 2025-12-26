import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CompanyMyJobsScreen extends StatelessWidget {
  const CompanyMyJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Giriş yapmış kullanıcı bulunamadı.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('İlanlarım')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('jobs')
            .where('companyId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Hata: ${snap.error}'));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Henüz ilan oluşturmadın.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final d = docs[i];
              final jobId = d.id;
              final m = d.data();

              final title = (m['title'] ?? '').toString().trim();
              final companyName = (m['companyName'] ?? '').toString().trim();
              final location = (m['location'] ?? '').toString().trim();
              final workModel = (m['workModel'] ?? '').toString().trim();
              final level = (m['level'] ?? '').toString().trim();
              final isActive = (m['isActive'] == true);

              return _JobCard(
                title: title.isEmpty ? '(Pozisyon adı yok)' : title,
                company: companyName.isEmpty ? '(Şirket adı yok)' : companyName,
                location: location.isEmpty ? 'Konum yok' : location,
                meta: '${workModel.isEmpty ? "?" : workModel} • ${level.isEmpty ? "?" : level}',
                isActive: isActive,
                applicationsCountStream: FirebaseFirestore.instance
                    .collection('jobs')
                    .doc(jobId)
                    .collection('applications')
                    .snapshots()
                    .map((s) => s.docs.length),
                onTap: () {
                  _openJobBottomSheet(context, jobId, m);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _openJobBottomSheet(
      BuildContext context,
      String jobId,
      Map<String, dynamic> job,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _JobDetailSheet(jobId: jobId, job: job),
    );
  }
}

class _JobCard extends StatelessWidget {
  final String title;
  final String company;
  final String location;
  final String meta;
  final bool isActive;
  final Stream<int> applicationsCountStream;
  final VoidCallback onTap;

  const _JobCard({
    required this.title,
    required this.company,
    required this.location,
    required this.meta,
    required this.isActive,
    required this.applicationsCountStream,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF111318) : Colors.white;
    final borderColor =
    isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.grey.shade200,
              ),
              child: Icon(
                Icons.work_outline,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    company,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white.withOpacity(0.85) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$location • $meta',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Chip(
                        icon: isActive ? Icons.check_circle : Icons.pause_circle,
                        label: isActive ? 'Aktif' : 'Pasif',
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder<int>(
                        stream: applicationsCountStream,
                        builder: (context, snap) {
                          final count = snap.data ?? 0;
                          return _Chip(
                            icon: Icons.inbox_outlined,
                            label: '$count başvuru',
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_up, color: isDark ? Colors.white54 : Colors.black45),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isDark ? Colors.white70 : Colors.black54),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _JobDetailSheet extends StatelessWidget {
  final String jobId;
  final Map<String, dynamic> job;

  const _JobDetailSheet({required this.jobId, required this.job});

  @override
  Widget build(BuildContext context) {
    final title = (job['title'] ?? '').toString().trim();
    final company = (job['companyName'] ?? '').toString().trim();
    final location = (job['location'] ?? '').toString().trim();
    final desc = (job['description'] ?? '').toString().trim();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) {
        return SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                title.isEmpty ? '(Pozisyon adı yok)' : title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '${company.isEmpty ? "(Şirket adı yok)" : company} • ${location.isEmpty ? "Konum yok" : location}',
                style: TextStyle(color: Colors.grey.shade600),
              ),

              const SizedBox(height: 14),
              const Text('İlan Açıklaması', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(desc.isEmpty ? 'Açıklama yok.' : desc),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CompanyEditJobScreen(jobId: jobId, job: job),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('İlanı Düzenle'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CompanyEditJobScreen extends StatefulWidget {
  final String jobId;
  final Map<String, dynamic> job;

  const CompanyEditJobScreen({
    super.key,
    required this.jobId,
    required this.job,
  });

  @override
  State<CompanyEditJobScreen> createState() => _CompanyEditJobScreenState();
}

class _CompanyEditJobScreenState extends State<CompanyEditJobScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _companyNameCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _minSalaryCtrl;
  late final TextEditingController _maxSalaryCtrl;
  late final TextEditingController _skillsCtrl;

  // ✅ seçenekler tek kaynak
  static const List<String> _workModels = ['Remote', 'Hybrid', 'On-site'];
  static const List<String> _levels = ['Intern', 'Junior', 'Mid', 'Senior'];

  late String _workModel;
  late String _level;
  late bool _isActive;

  bool _saving = false;

  String _normalizeWorkModel(String v) {
    final x = v.trim().toLowerCase();
    if (x == 'remote') return 'Remote';
    if (x == 'hybrid') return 'Hybrid';
    if (x == 'onsite' || x == 'on-site' || x == 'on site') return 'On-site';
    return 'Hybrid';
  }

  String _normalizeLevel(String v) {
    final x = v.trim().toLowerCase();
    if (x == 'intern') return 'Intern';
    if (x == 'junior') return 'Junior';
    if (x == 'mid' || x == 'middle') return 'Mid';
    if (x == 'senior') return 'Senior';
    return 'Intern';
  }

  @override
  void initState() {
    super.initState();
    final j = widget.job;

    _titleCtrl = TextEditingController(text: (j['title'] ?? '').toString());
    _companyNameCtrl = TextEditingController(text: (j['companyName'] ?? '').toString());
    _locationCtrl = TextEditingController(text: (j['location'] ?? '').toString());
    _descCtrl = TextEditingController(text: (j['description'] ?? '').toString());

    _minSalaryCtrl = TextEditingController(
      text: (j['minSalary'] == null) ? '' : j['minSalary'].toString(),
    );
    _maxSalaryCtrl = TextEditingController(
      text: (j['maxSalary'] == null) ? '' : j['maxSalary'].toString(),
    );

    final skills = (j['skills'] as List?)?.map((e) => e.toString()).toList() ?? [];
    _skillsCtrl = TextEditingController(text: skills.join(', '));

    // ✅ normalize ederek patlamayı bitiriyoruz
    _workModel = _normalizeWorkModel((j['workModel'] ?? 'Hybrid').toString());
    _level = _normalizeLevel((j['level'] ?? 'Intern').toString());
    _isActive = (j['isActive'] == true);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _companyNameCtrl.dispose();
    _locationCtrl.dispose();
    _descCtrl.dispose();
    _minSalaryCtrl.dispose();
    _maxSalaryCtrl.dispose();
    _skillsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    int? minSalary;
    int? maxSalary;

    if (_minSalaryCtrl.text.trim().isNotEmpty) {
      minSalary = int.tryParse(_minSalaryCtrl.text.trim());
    }
    if (_maxSalaryCtrl.text.trim().isNotEmpty) {
      maxSalary = int.tryParse(_maxSalaryCtrl.text.trim());
    }
    if (minSalary != null && maxSalary != null && maxSalary < minSalary) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maksimum maaş minimum maaştan küçük olamaz.')),
      );
      return;
    }

    final skillsRaw = _skillsCtrl.text.trim();
    final skills = skillsRaw.isEmpty
        ? <String>[]
        : skillsRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).update({
        'title': _titleCtrl.text.trim(),
        'companyName': _companyNameCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'workModel': _workModel,
        'level': _level,
        'minSalary': minSalary,
        'maxSalary': maxSalary,
        'skills': skills,
        'description': _descCtrl.text.trim(),
        'isActive': _isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İlan güncellendi.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Güncelleme hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ value güvenliği: listede yoksa null
    final safeWorkModel = _workModels.contains(_workModel) ? _workModel : null;
    final safeLevel = _levels.contains(_level) ? _level : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('İlanı Düzenle'),
        actions: const [],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  decoration: _dec('Pozisyon başlığı'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _companyNameCtrl,
                  decoration: _dec('Şirket adı'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _locationCtrl,
                  decoration: _dec('Lokasyon'),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: safeWorkModel,
                        decoration: _dec('Çalışma şekli'),
                        items: const [
                          DropdownMenuItem(value: 'Remote', child: Text('Remote')),
                          DropdownMenuItem(value: 'Hybrid', child: Text('Hybrid')),
                          DropdownMenuItem(value: 'On-site', child: Text('On-site')),
                        ],
                        onChanged: (v) => setState(() => _workModel = v ?? 'Hybrid'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: safeLevel,
                        decoration: _dec('Seviye'),
                        items: const [
                          DropdownMenuItem(value: 'Intern', child: Text('Intern')),
                          DropdownMenuItem(value: 'Junior', child: Text('Junior')),
                          DropdownMenuItem(value: 'Mid', child: Text('Mid')),
                          DropdownMenuItem(value: 'Senior', child: Text('Senior')),
                        ],
                        onChanged: (v) => setState(() => _level = v ?? 'Intern'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minSalaryCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _dec('Min maaş', hint: 'Opsiyonel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxSalaryCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _dec('Max maaş', hint: 'Opsiyonel'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _skillsCtrl,
                  decoration: _dec('Yetkinlikler', hint: 'Flutter, Firebase, ...'),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _descCtrl,
                  minLines: 5,
                  maxLines: 10,
                  decoration: _dec('İlan açıklaması'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Zorunlu';
                    if (v.trim().length < 30) return 'Biraz daha detay yaz.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('İlan aktif'),
                  subtitle:
                  Text(_isActive ? 'Adaylar ilanınla karşılaşabilir.' : 'İlan yayından kalkar.'),
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
