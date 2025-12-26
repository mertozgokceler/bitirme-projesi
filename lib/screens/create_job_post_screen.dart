// lib/screens/create_job_post_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

class CreateJobPostScreen extends StatefulWidget {
  const CreateJobPostScreen({super.key});

  @override
  State<CreateJobPostScreen> createState() => _CreateJobPostScreenState();
}

class _CreateJobPostScreenState extends State<CreateJobPostScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _minSalaryCtrl = TextEditingController();
  final _maxSalaryCtrl = TextEditingController();

  // 🔥 skills alanını ikiye böldük
  final _requiredSkillsCtrl = TextEditingController();
  final _niceToHaveSkillsCtrl = TextEditingController();

  final _descriptionCtrl = TextEditingController();

  String _workModel = 'Hybrid';
  String _level = 'Intern';
  bool _isLoading = false;

  // ✅ Başvuruda istenecek alanlar (ilan oluştururken seçilecek)
  final Map<String, bool> _applyFields = {
    'phone': true,
    'email': true,
    'cv': true,
    'portfolio': false,
    'coverLetter': false,
    'linkedin': false,
  };

  final Map<String, String> _applyFieldLabels = {
    'phone': 'Telefon numarası',
    'email': 'E-posta adresi',
    'cv': 'CV (dosya)',
    'portfolio': 'Portföy linki',
    'coverLetter': 'Ön yazı',
    'linkedin': 'LinkedIn profili',
  };

  @override
  void initState() {
    super.initState();
    _prefillCompanyName();
  }

  Future<void> _prefillCompanyName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>? ?? {};
      final name = (data['companyName'] ?? data['name'] ?? '').toString();

      if (name.isNotEmpty && mounted) {
        _companyNameCtrl.text = name;
      }
    } catch (e) {
      debugPrint('DEBUG[job] companyName fetch error: $e');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _companyNameCtrl.dispose();
    _locationCtrl.dispose();
    _minSalaryCtrl.dispose();
    _maxSalaryCtrl.dispose();

    _requiredSkillsCtrl.dispose();
    _niceToHaveSkillsCtrl.dispose();

    _descriptionCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // SKILL PARSE + NORMALIZE
  // ------------------------------------------------------------
  String _normalizeSkill(String s) {
    var x = s.trim().toLowerCase();

    // TR karakter normalize
    x = x
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('ş', 's')
        .replaceAll('Ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('Ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('Ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'c');

    // Çoklu boşlukları teke indir
    x = x.replaceAll(RegExp(r'\s+'), ' ');

    return x;
  }

  List<String> _parseSkills(String raw) {
    if (raw.trim().isEmpty) return [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _unique(List<String> xs) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in xs) {
      if (seen.add(s)) out.add(s);
    }
    return out;
  }

  Future<void> _saveJob() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giriş yapmış bir kullanıcı bulunamadı.')),
      );
      return;
    }

    // En az 1 alan seçilmiş olsun
    final selectedCount = _applyFields.values.where((v) => v == true).length;
    if (selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Başvuru formu için en az 1 alan seçmelisin.')),
      );
      return;
    }

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
        const SnackBar(
            content: Text('Maksimum maaş minimum maaştan küçük olamaz.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // -----------------------------
      // Skills: required + nice-to-have
      // -----------------------------
      final requiredRaw = _requiredSkillsCtrl.text.trim();
      final niceRaw = _niceToHaveSkillsCtrl.text.trim();

      final requiredSkills = _parseSkills(requiredRaw);
      final niceToHaveSkills = _parseSkills(niceRaw);

      // normalized
      final requiredNorm = _unique(
        requiredSkills
            .map(_normalizeSkill)
            .where((e) => e.isNotEmpty)
            .toList(),
      );

      final niceNorm = _unique(
        niceToHaveSkills
            .map(_normalizeSkill)
            .where((e) => e.isNotEmpty)
            .toList(),
      );

      // 🚫 nice içinde required tekrarını temizle
      final niceNormFiltered =
      niceNorm.where((s) => !requiredNorm.contains(s)).toList();

      final niceSkillsFiltered = niceToHaveSkills.where((s) {
        final n = _normalizeSkill(s);
        return n.isNotEmpty && !requiredNorm.contains(n);
      }).toList();

      // ✅ Eski alanlar (geriye uyum): skills = required + nice
      final allSkills = _unique([...requiredSkills, ...niceSkillsFiltered]);
      final allNorm = _unique([...requiredNorm, ...niceNormFiltered]);

      final now = FieldValue.serverTimestamp();

      // ✅ workModel normalize (backend bunu lower-case kıyaslıyor)
      final normalizedWorkModel =
      _workModel.trim().toLowerCase(); // remote | hybrid | on-site
      final cityOrLocationText = _locationCtrl.text.trim();

      // ✅ GEO: Remote değilse + location boş değilse geocode dene
      GeoPoint? jobGeo;
      if (normalizedWorkModel != 'remote' && cityOrLocationText.isNotEmpty) {
        try {
          final locations = await locationFromAddress(cityOrLocationText);
          if (locations.isNotEmpty) {
            final loc = locations.first;
            jobGeo = GeoPoint(loc.latitude, loc.longitude);
          }
        } catch (e) {
          // Geocode patlarsa ilanı engelleme. Sadece geo yazma.
          debugPrint('DEBUG[job] geocoding failed: $e');
        }
      }

      await FirebaseFirestore.instance.collection('jobs').add({
        'title': _titleCtrl.text.trim(),
        'companyId': user.uid,
        'companyName': _companyNameCtrl.text.trim(),

        // UI için yazı
        'location': cityOrLocationText,

        // ✅ Match için geo (GeoPoint)
        'geo': jobGeo,

        // 🔥 ilan meta
        'workModel': normalizedWorkModel, // remote | hybrid | on-site
        'level': _level, // Intern / Junior / Mid / Senior
        'minSalary': minSalary,
        'maxSalary': maxSalary,
        'currency': 'TRY',

        // ✅ geriye uyumluluk
        'skills': allSkills,
        'skillsNormalized': allNorm,

        // ✅ yeni alanlar
        'requiredSkills': requiredSkills,
        'requiredSkillsNormalized': requiredNorm,
        'niceToHaveSkills': niceSkillsFiltered,
        'niceToHaveSkillsNormalized': niceNormFiltered,

        'description': _descriptionCtrl.text.trim(),

        // ✅ başvuru formunu dinamik üretebilmek için
        'applyFields': _applyFields,

        'createdAt': now,
        'updatedAt': now,
        'isActive': true,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İş ilanı başarıyla oluşturuldu.')),
      );

      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('DEBUG[job] save error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İlan kaydedilirken hata oluştu: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('İş İlanı Oluştur'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Pozisyon
                TextFormField(
                  controller: _titleCtrl,
                  decoration: _inputDecoration(
                    'Pozisyon başlığı',
                    hint: 'Örn: Flutter Developer',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Pozisyon başlığı zorunlu';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Şirket adı
                TextFormField(
                  controller: _companyNameCtrl,
                  decoration: _inputDecoration('Şirket adı'),
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Şirket adı zorunlu';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Lokasyon
                TextFormField(
                  controller: _locationCtrl,
                  decoration: _inputDecoration(
                    'Lokasyon',
                    hint: 'Örn: İstanbul',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),

                // Çalışma şekli + Seviye
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _workModel,
                        decoration: _inputDecoration('Çalışma şekli'),
                        items: const [
                          DropdownMenuItem(
                              value: 'Remote', child: Text('Remote')),
                          DropdownMenuItem(
                              value: 'Hybrid', child: Text('Hybrid')),
                          DropdownMenuItem(
                              value: 'On-site', child: Text('On-site')),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => _workModel = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _level,
                        decoration: _inputDecoration('Seviye'),
                        items: const [
                          DropdownMenuItem(
                              value: 'Intern', child: Text('Intern')),
                          DropdownMenuItem(
                              value: 'Junior', child: Text('Junior')),
                          DropdownMenuItem(value: 'Mid', child: Text('Mid')),
                          DropdownMenuItem(
                              value: 'Senior', child: Text('Senior')),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => _level = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Maaş aralığı
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minSalaryCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(
                          'Min maaş (opsiyonel)',
                          hint: 'Örn: 30000',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxSalaryCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(
                          'Max maaş (opsiyonel)',
                          hint: 'Örn: 45000',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ✅ Required Skills
                TextFormField(
                  controller: _requiredSkillsCtrl,
                  decoration: _inputDecoration(
                    'Zorunlu yetkinlikler (Required)',
                    hint: 'Örn: Flutter, Firebase, REST API',
                  ),
                  textInputAction: TextInputAction.newline,
                  validator: (val) {
                    final skills = _parseSkills(val ?? '');
                    if (skills.isEmpty) {
                      return 'En az 1 zorunlu yetkinlik yazmalısın.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // ✅ Nice-to-have Skills
                TextFormField(
                  controller: _niceToHaveSkillsCtrl,
                  decoration: _inputDecoration(
                    'Artı yetkinlikler (Nice-to-have) (opsiyonel)',
                    hint: 'Örn: Docker, CI/CD, Linux',
                  ),
                  textInputAction: TextInputAction.newline,
                ),
                const SizedBox(height: 12),

                // ✅ Başvuruda istenecek alanlar
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Başvuruda istenecek bilgiler',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.black.withOpacity(0.10),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: isDark
                        ? Colors.white.withOpacity(0.03)
                        : Colors.transparent,
                  ),
                  child: Column(
                    children: _applyFields.keys.map((key) {
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_applyFieldLabels[key] ?? key),
                        value: _applyFields[key] ?? false,
                        onChanged: (v) {
                          setState(() => _applyFields[key] = v);
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                // Açıklama
                TextFormField(
                  controller: _descriptionCtrl,
                  decoration: _inputDecoration(
                    'İlan açıklaması',
                    hint: 'Sorumluluklar, gereksinimler, ekstra bilgiler...',
                  ),
                  minLines: 5,
                  maxLines: 10,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'İlan açıklaması zorunlu';
                    }
                    if (val.trim().length < 30) {
                      return 'Biraz daha detaylı açıklama yaz.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Not: Şimdilik ilan direkt "jobs" koleksiyonuna yazılıyor.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveJob,
                    icon: _isLoading
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                        : const Icon(Icons.work_outline),
                    label: Text(_isLoading ? 'Kaydediliyor...' : 'İlanı yayınla'),
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
