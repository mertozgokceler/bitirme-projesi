// lib/screens/edit_profile_screen.dart

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialUserData;

  const EditProfileScreen({super.key, required this.initialUserData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _roleController;
  late final TextEditingController _locationController;

  // Şirket özel alanları
  late final TextEditingController _companyWebsiteController;
  late final TextEditingController _companyFoundedYearController;
  late final TextEditingController _companyEmployeeCountController;

  late final bool _isCompany;
  late List<String> _selectedSkills;

  // ✅ Sadece individual için kullanılacak
  static const List<String> _levels = ['Intern', 'Junior', 'Mid', 'Senior'];
  String _level = 'Intern';

  // Firestore key: on-site (backend ile aynı)
  final Map<String, bool> _workModelPrefs = {
    'remote': false,
    'hybrid': true,
    'on-site': false,
  };

  File? _imageFile;
  String? _networkImageUrl;
  bool _isLoading = false;

  // ---- UI helpers ----
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

  LinearGradient _glassBlueGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
        const Color(0xFF4F8CFF).withOpacity(0.18),
        const Color(0xFF6FB1FF).withOpacity(0.12),
        const Color(0xFF9FD3FF).withOpacity(0.10),
      ]
          : [
        const Color(0xFF4F8CFF).withOpacity(0.14),
        const Color(0xFF6FB1FF).withOpacity(0.10),
        const Color(0xFF9FD3FF).withOpacity(0.08),
      ],
    );
  }

  Color _cardBorder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.16) : Colors.black.withOpacity(0.08);
  }

  Color _cardFill(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.07) : Colors.white.withOpacity(0.72);
  }

  TextStyle _sectionTitleStyle(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return (t.titleMedium ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: -0.2,
    );
  }

  @override
  void initState() {
    super.initState();

    final data = widget.initialUserData;

    _isCompany = (data['isCompany'] == true) || (data['type'] == 'company');

    final String initialCompanyName =
    (data['companyName'] ?? (data['company'] is Map ? data['company']['name'] : '') ?? '') as String;
    final String initialPersonName = (data['name'] ?? '') as String;
    final String initialDisplayName = _isCompany ? initialCompanyName : initialPersonName;

    final String initialActivity = (data['companyActivity'] ??
        (data['company'] is Map ? data['company']['activity'] : null) ??
        data['role'] ??
        '') as String;

    final String initialWebsite =
    (data['companyWebsite'] ?? (data['company'] is Map ? data['company']['website'] : '') ?? '') as String;

    final int? initialFoundedYear =
    (data['companyFoundedYear'] ?? (data['company'] is Map ? data['company']['foundedYear'] : null)) as int?;
    final int? initialEmployeeCount =
    (data['companyEmployeeCount'] ?? (data['company'] is Map ? data['company']['employeeCount'] : null)) as int?;

    _nameController = TextEditingController(text: initialDisplayName);
    _usernameController = TextEditingController(text: (data['username'] ?? '').toString());
    _bioController = TextEditingController(text: (data['bio'] ?? '').toString());
    _roleController = TextEditingController(text: initialActivity);
    _locationController = TextEditingController(text: (data['location'] ?? '').toString());

    _networkImageUrl =
    (data['photoUrl'] ?? '').toString().trim().isEmpty ? null : (data['photoUrl'] as String?);

    _companyWebsiteController = TextEditingController(text: initialWebsite);
    _companyFoundedYearController =
        TextEditingController(text: initialFoundedYear != null ? initialFoundedYear.toString() : '');
    _companyEmployeeCountController =
        TextEditingController(text: initialEmployeeCount != null ? initialEmployeeCount.toString() : '');

    _selectedSkills = (data['skills'] as List<dynamic>?)?.cast<String>() ?? [];

    // ✅ Individual ise mevcut değerleri oku
    if (!_isCompany) {
      final lv = (data['level'] ?? '').toString().trim();
      if (_levels.contains(lv)) _level = lv;

      final prefs = data['workModelPrefs'];
      if (prefs is Map) {
        _workModelPrefs['remote'] = prefs['remote'] == true;
        _workModelPrefs['hybrid'] = prefs['hybrid'] == true;
        _workModelPrefs['on-site'] = prefs['on-site'] == true;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _roleController.dispose();
    _locationController.dispose();
    _companyWebsiteController.dispose();
    _companyFoundedYearController.dispose();
    _companyEmployeeCountController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 55,
    );
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  // ✅ Skill normalize (TR + whitespace + lower)
  String _normSkill(String s) {
    var x = s.trim().toLowerCase();
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
    x = x.replaceAll(RegExp(r'\s+'), ' ');
    return x;
  }

  void _showSkillsBottomSheet() {
    // ---- KATEGORİLİ SKILL HAVUZU ----
    final Map<String, List<String>> skillGroups = {
      'All': [
        'JavaScript','Python','Java','C#','PHP','C++','TypeScript','Ruby','Swift','Go','Kotlin','Rust','Dart','Scala','SQL',
        'HTML','CSS','React','Angular','Vue.js','Svelte','Next.js','Nuxt.js','Redux','MobX','Tailwind CSS','Bootstrap','Material UI','Chakra UI',
        'Webpack','Vite','Babel','Node.js','Express.js','NestJS','Django','FastAPI','Flask','Spring','Spring Boot','ASP.NET','ASP.NET Core',
        'Laravel','Symfony','Ruby on Rails','Flutter','React Native','SwiftUI','Jetpack Compose','Android SDK','iOS SDK',
        'MySQL','PostgreSQL','SQLite','MongoDB','Redis','Elasticsearch','Firebase','Firestore','DynamoDB','Cassandra',
        'AWS','Azure','Google Cloud','Docker','Kubernetes','Helm','Terraform','Ansible','Jenkins','GitHub Actions','GitLab CI','CircleCI',
        'NGINX','Apache','REST API','GraphQL','gRPC','WebSocket','Socket.IO','Swagger','OpenAPI',
        'TensorFlow','PyTorch','Keras','Scikit-learn','Pandas','NumPy','OpenCV','YOLO','LangChain','OpenAI API',
        'RabbitMQ','Kafka','ActiveMQ','Redis Streams',
        'JUnit','Mockito','Jest','Mocha','Chai','Cypress','Playwright','Selenium','PyTest',
        'JWT','OAuth','OAuth2','OpenID Connect','Keycloak','Firebase Auth','Auth0',
        'Git','GitHub','GitLab','Bitbucket','Postman','Insomnia','Linux','Unix','Bash','PowerShell',
        'Unity','Unreal Engine','Godot','OpenGL','DirectX',
        'Microservices','Monolithic Architecture','Clean Architecture','Domain Driven Design','Event Driven Architecture','CQRS','CI/CD','Agile','Scrum','Kanban',
      ],
      'Frontend': [
        'JavaScript','TypeScript','HTML','CSS','React','Angular','Vue.js','Svelte','Next.js','Nuxt.js','Redux','MobX',
        'Tailwind CSS','Bootstrap','Material UI','Chakra UI','Webpack','Vite','Babel',
      ],
      'Backend': [
        'Node.js','Express.js','NestJS','Python','Django','FastAPI','Flask','Java','Spring','Spring Boot','C#','ASP.NET','ASP.NET Core','PHP','Laravel','Symfony','Ruby','Ruby on Rails',
        'REST API','GraphQL','gRPC','Swagger','OpenAPI',
      ],
      'Mobile': [
        'Flutter','Dart','React Native','Swift','SwiftUI','Kotlin','Jetpack Compose','Android SDK','iOS SDK',
      ],
      'DevOps': [
        'AWS','Azure','Google Cloud','Docker','Kubernetes','Helm','Terraform','Ansible','Jenkins','GitHub Actions','GitLab CI','CircleCI','NGINX','Apache','CI/CD',
      ],
      'Data/AI': [
        'TensorFlow','PyTorch','Keras','Scikit-learn','Pandas','NumPy','OpenCV','YOLO','LangChain','OpenAI API','Elasticsearch',
      ],
      'Database': [
        'SQL','MySQL','PostgreSQL','SQLite','MongoDB','Redis','Firestore','Firebase','DynamoDB','Cassandra','Elasticsearch',
      ],
      'Testing': [
        'JUnit','Mockito','Jest','Mocha','Chai','Cypress','Playwright','Selenium','PyTest',
      ],
      'Security': [
        'JWT','OAuth','OAuth2','OpenID Connect','Keycloak','Firebase Auth','Auth0',
      ],
      'Tools': [
        'Git','GitHub','GitLab','Bitbucket','Postman','Insomnia','Linux','Bash','PowerShell',
      ],
      'Other': [
        'RabbitMQ','Kafka','ActiveMQ','Redis Streams','Unity','Unreal Engine','Godot','OpenGL','DirectX',
        'Microservices','Clean Architecture','Domain Driven Design','Event Driven Architecture','CQRS','Agile','Scrum','Kanban',
      ],
    };

    final tabs = skillGroups.keys.toList(growable: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final searchCtrl = TextEditingController();
        String query = '';
        int tabIndex = 0;

        List<String> _sortedUnique(List<String> list) {
          final set = <String>{...list};
          final out = set.toList();
          out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return out;
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final cs = theme.colorScheme;

            final activeTab = tabs[tabIndex];
            final baseList = _sortedUnique(skillGroups[activeTab] ?? const []);

            final q = _normSkill(query);
            final filtered = q.isEmpty ? baseList : baseList.where((s) => _normSkill(s).contains(q)).toList(growable: false);

            final selectedSorted = [..._selectedSkills]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            return DraggableScrollableSheet(
              initialChildSize: 0.86,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              builder: (context, scrollCtrl) {
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _glassBlueGradient(context),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                        border: Border.all(color: Colors.white.withOpacity(0.22), width: 1.1),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 34,
                            spreadRadius: 8,
                            color: Colors.black.withOpacity(0.22),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          Container(
                            width: 46,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          const SizedBox(height: 14),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Yetenekler',
                                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _selectedSkills.isEmpty
                                      ? null
                                      : () => setModalState(() {
                                    _selectedSkills.clear();
                                    query = '';
                                    searchCtrl.clear();
                                  }),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Temizle'),
                                ),
                              ],
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.20),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withOpacity(0.28)),
                              ),
                              child: TextField(
                                controller: searchCtrl,
                                onChanged: (v) => setModalState(() => query = v),
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  hintText: 'Ara: react, docker, java...',
                                  hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.65)),
                                  prefixIcon: Icon(Icons.search, color: cs.onSurface.withOpacity(0.75)),
                                  suffixIcon: query.trim().isEmpty
                                      ? null
                                      : IconButton(
                                    icon: Icon(Icons.clear, color: cs.onSurface.withOpacity(0.75)),
                                    onPressed: () => setModalState(() {
                                      query = '';
                                      searchCtrl.clear();
                                    }),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(
                            height: 44,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              scrollDirection: Axis.horizontal,
                              itemBuilder: (context, i) {
                                final isActive = i == tabIndex;
                                final label = tabs[i];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => setModalState(() => tabIndex = i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: isActive ? Colors.white.withOpacity(0.30) : Colors.white.withOpacity(0.16),
                                      border: Border.all(
                                        color: isActive ? Colors.white.withOpacity(0.36) : Colors.white.withOpacity(0.22),
                                      ),
                                    ),
                                    child: Text(
                                      label,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemCount: tabs.length,
                            ),
                          ),

                          if (selectedSorted.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Seçilenler (${selectedSorted.length})',
                                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 42,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                scrollDirection: Axis.horizontal,
                                itemCount: selectedSorted.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (context, i) {
                                  final s = selectedSorted[i];
                                  return Chip(
                                    label: Text(s),
                                    backgroundColor: Colors.white.withOpacity(0.20),
                                    shape: StadiumBorder(
                                      side: BorderSide(color: Colors.white.withOpacity(0.26)),
                                    ),
                                    onDeleted: () => setModalState(() {
                                      _selectedSkills.remove(s);
                                    }),
                                  );
                                },
                              ),
                            ),
                          ],

                          const SizedBox(height: 10),

                          Expanded(
                            child: filtered.isEmpty
                                ? const Center(child: Text('Sonuç yok. Daha net yaz.'))
                                : ListView.builder(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 98),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final skill = filtered[index];
                                final isSelected = _selectedSkills.contains(skill);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: Colors.white.withOpacity(isSelected ? 0.22 : 0.14),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(isSelected ? 0.34 : 0.24),
                                    ),
                                  ),
                                  child: ListTile(
                                    onTap: () => setModalState(() {
                                      if (isSelected) {
                                        _selectedSkills.remove(skill);
                                      } else {
                                        _selectedSkills.add(skill);
                                      }
                                    }),
                                    title: Text(
                                      skill,
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                    subtitle: q.isNotEmpty
                                        ? Text('Eşleşti: "$query"', style: theme.textTheme.bodySmall)
                                        : null,
                                    trailing: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 160),
                                      child: isSelected
                                          ? Icon(Icons.check_circle, key: ValueKey('on_$skill'), color: cs.primary)
                                          : Icon(Icons.add_circle_outline, key: ValueKey('off_$skill'), color: cs.onSurface.withOpacity(0.65)),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.22))),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Seçili: ${_selectedSkills.length}',
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {});
                                    Navigator.pop(context);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: const Text('Bitti'),
                                ),
                              ],
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
      },
    );
  }

  Widget _workPrefTile(String key, String label, IconData icon) {
    final isOn = _workModelPrefs[key] == true;
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _workModelPrefs[key] = !isOn),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withOpacity(0.65)),
          color: isOn ? cs.primary.withOpacity(0.12) : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isOn ? cs.primary : cs.onSurface).withOpacity(0.10),
                border: Border.all(color: (isOn ? cs.primary : cs.outline).withOpacity(0.40)),
              ),
              child: Icon(icon, size: 20, color: isOn ? cs.primary : cs.onSurface.withOpacity(0.85)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Switch(
              value: isOn,
              onChanged: (v) => setState(() => _workModelPrefs[key] = v),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      String? newPhotoUrl;
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      if (_imageFile != null) {
        final ref = FirebaseStorage.instance.ref().child('profile_images').child('$uid.jpg');
        await ref.putFile(_imageFile!);
        newPhotoUrl = await ref.getDownloadURL();
      }

      final displayName = _nameController.text.trim();
      final username = _usernameController.text.trim();
      final bio = _bioController.text.trim();
      final location = _locationController.text.trim();
      final roleOrActivity = _roleController.text.trim();

      final website = _companyWebsiteController.text.trim();
      final foundedYearText = _companyFoundedYearController.text.trim();
      final employeeCountText = _companyEmployeeCountController.text.trim();

      final foundedYear = foundedYearText.isNotEmpty ? int.tryParse(foundedYearText) : null;
      final employeeCount = employeeCountText.isNotEmpty ? int.tryParse(employeeCountText) : null;

      // ✅ skillsNormalized üret
      final skillsNorm = _selectedSkills.map(_normSkill).where((e) => e.isNotEmpty).toList();

      final Map<String, dynamic> dataToUpdate = {
        'username': username,
        'usernameLower': username.toLowerCase(),
        'bio': bio,
        'location': location,
        'skills': _selectedSkills,
        'skillsNormalized': skillsNorm,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (!_isCompany) {
        dataToUpdate.addAll({
          'name': displayName,
          'nameLower': displayName.toLowerCase(),
          'role': roleOrActivity,
          'level': _levels.contains(_level) ? _level : 'Intern',
          'workModelPrefs': {
            'remote': _workModelPrefs['remote'] == true,
            'hybrid': _workModelPrefs['hybrid'] == true,
            'on-site': _workModelPrefs['on-site'] == true,
          },
        });
      } else {
        final companyName = displayName;
        final companyActivity = roleOrActivity;

        dataToUpdate.addAll({
          'companyName': companyName,
          'companyActivity': companyActivity,
          if (website.isNotEmpty) 'companyWebsite': website,
          if (foundedYear != null) 'companyFoundedYear': foundedYear,
          if (employeeCount != null) 'companyEmployeeCount': employeeCount,
        });

        final existingCompany =
            (widget.initialUserData['company'] as Map<String, dynamic>?) ?? <String, dynamic>{};

        dataToUpdate['company'] = {
          ...existingCompany,
          'name': companyName,
          'activity': companyActivity,
          if (website.isNotEmpty) 'website': website,
          if (foundedYear != null) 'foundedYear': foundedYear,
          if (employeeCount != null) 'employeeCount': employeeCount,
        };

        dataToUpdate.addAll({
          'level': FieldValue.delete(),
          'workModelPrefs': FieldValue.delete(),
        });
      }

      if (newPhotoUrl != null) {
        dataToUpdate['photoUrl'] = newPhotoUrl;
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update(dataToUpdate);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profil başarıyla güncellendi!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bir hata oluştu: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Stack(
      children: [
        // Background
        Container(
          decoration: BoxDecoration(
            gradient: _bgGradient(context),
          ),
        ),
        // Soft glow blobs
        Positioned(
          top: -120,
          left: -80,
          child: _GlowBlob(size: 260, color: cs.primary.withOpacity(0.20)),
        ),
        Positioned(
          bottom: -140,
          right: -90,
          child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18)),
        ),

        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'Profili Düzenle',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.2),
            ),
            centerTitle: false,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.25 : 0.04),
                    border: Border(
                      bottom: BorderSide(color: _cardBorder(context)),
                    ),
                  ),
                ),
              ),
            ),
          ),

          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(context),

                  const SizedBox(height: 14),

                  _SectionCard(
                    title: 'Temel Bilgiler',
                    child: Column(
                      children: [
                        _buildTextField(
                          controller: _nameController,
                          label: _isCompany ? 'Şirket Adı' : 'Ad Soyad',
                          icon: _isCompany ? Icons.business_outlined : Icons.person_outline,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _usernameController,
                          label: 'Kullanıcı Adı',
                          icon: Icons.alternate_email,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _roleController,
                          label: _isCompany ? 'Sektör / Faaliyet Alanı' : 'Unvan / Rol',
                          icon: Icons.work_outline,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _locationController,
                          label: _isCompany ? 'Şirket Konumu (örn: İstanbul)' : 'Konum (örn: İstanbul)',
                          icon: Icons.location_on_outlined,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  if (!_isCompany) ...[
                    _SectionCard(
                      title: 'Kariyer Tercihleri',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Seviye', style: _sectionTitleStyle(context)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _levels.contains(_level) ? _level : 'Intern',
                            items: _levels.map((x) => DropdownMenuItem<String>(value: x, child: Text(x))).toList(growable: false),
                            onChanged: (v) => setState(() => _level = (v ?? 'Intern')),
                            decoration: _inputDecoration(
                              context,
                              label: '',
                              icon: Icons.stairs_outlined,
                            ).copyWith(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text('Çalışma Tercihi', style: _sectionTitleStyle(context)),
                          const SizedBox(height: 8),
                          Column(
                            children: [
                              _workPrefTile('remote', 'Remote', Icons.wifi_tethering),
                              const SizedBox(height: 10),
                              _workPrefTile('hybrid', 'Hybrid', Icons.sync_alt_rounded),
                              const SizedBox(height: 10),
                              _workPrefTile('on-site', 'On-site', Icons.apartment_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (_isCompany) ...[
                    _SectionCard(
                      title: 'Şirket Detayları',
                      child: Column(
                        children: [
                          _buildTextField(
                            controller: _companyWebsiteController,
                            label: 'Website (örn: https://techconnect.com)',
                            icon: Icons.language_outlined,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _companyFoundedYearController,
                            label: 'Kuruluş Yılı (örn: 2015)',
                            icon: Icons.calendar_today_outlined,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _companyEmployeeCountController,
                            label: 'Çalışan Sayısı (örn: 25)',
                            icon: Icons.people_outline,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  _SectionCard(
                    title: _isCompany ? 'Hakkımızda' : 'Hakkımda',
                    child: _buildTextField(
                      controller: _bioController,
                      label: _isCompany ? 'Şirket Tanımı (kısa ve net)' : 'Bio (kısa, net, güçlü)',
                      icon: Icons.info_outline,
                      maxLines: 4,
                    ),
                  ),

                  const SizedBox(height: 14),

                  _SectionCard(
                    title: _isCompany ? 'Teknolojiler / Uzmanlıklar' : 'Yetenekler',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SkillBox(
                          selected: _selectedSkills,
                          onRemove: (s) => setState(() => _selectedSkills.remove(s)),
                          onAdd: _showSkillsBottomSheet,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'İpucu: 8–15 arası seç. 40 teknoloji yazınca kimse etkilenmiyor; sadece gürültü.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.70),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Save Bar
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _cardFill(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _cardBorder(context)),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 30,
                          spreadRadius: 4,
                          color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.25 : 0.12),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Değişiklikleri Kaydet',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isCompany ? 'Şirket profilini güncelliyorsun' : 'Profilin eşleşmeleri etkiler',
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.70)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                                : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.check_rounded),
                                SizedBox(width: 8),
                                Text('Kaydet', style: TextStyle(fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final title = _isCompany ? 'Şirket Profilini Düzenle' : 'Profilini Düzenle';
    final subtitle = _isCompany
        ? 'Logo, açıklama ve uzmanlıklarını net yaz. Şirket profili “ciddiyet” satmalı.'
        : 'Bio + yetenek + tercihlerin eşleşmeleri direkt etkiler. Şişirme yazma.';

    final ImageProvider<Object>? imgProvider = _imageFile != null
        ? FileImage(_imageFile!)
        : (_networkImageUrl != null ? NetworkImage(_networkImageUrl!) : null);

    final hasImage = imgProvider != null;


    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: _glassBlueGradient(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(
                blurRadius: 30,
                spreadRadius: 6,
                color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.25 : 0.10),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary.withOpacity(0.45), width: 2),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 18,
                          spreadRadius: 2,
                          color: cs.primary.withOpacity(0.18),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: hasImage
                          ? Image(
                        image: imgProvider!,
                        fit: BoxFit.cover,
                      )
                          : Container(
                        color: Colors.white.withOpacity(0.10),
                        child: Icon(
                          _isCompany ? Icons.business_rounded : Icons.person_rounded,
                          size: 40,
                          color: cs.onSurface.withOpacity(0.80),
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary,
                        border: Border.all(color: Colors.white.withOpacity(0.85)),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 14,
                            spreadRadius: 2,
                            color: Colors.black.withOpacity(0.18),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.72),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context, {required String label, required IconData icon}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InputDecoration(
      labelText: label.isEmpty ? null : label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.80),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outline.withOpacity(0.40))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outline.withOpacity(0.40))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary.withOpacity(0.80), width: 1.4)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final effectiveKeyboardType = keyboardType ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text);
    final effectiveAction = maxLines > 1 ? TextInputAction.newline : TextInputAction.next;

    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: effectiveKeyboardType,
      textInputAction: effectiveAction,
      decoration: _inputDecoration(context, label: label, icon: icon),
    );
  }
}

// --------------------- UI Widgets ---------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color border = theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08);
    Color fill = theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.72);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                blurRadius: 24,
                spreadRadius: 4,
                color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.22 : 0.10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.75),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillBox extends StatelessWidget {
  final List<String> selected;
  final void Function(String s) onRemove;
  final VoidCallback onAdd;

  const _SkillBox({
    required this.selected,
    required this.onRemove,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.10),
        ),
        color: theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.60),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final skill in selected)
            Chip(
              label: Text(skill, style: const TextStyle(fontWeight: FontWeight.w900)),
              onDeleted: () => onRemove(skill),
              deleteIcon: const Icon(Icons.close_rounded),
              shape: StadiumBorder(
                side: BorderSide(
                  color: theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.10),
                ),
              ),
              backgroundColor: theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.80),
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded),
            label: const Text('Yetenek Ekle', style: TextStyle(fontWeight: FontWeight.w900)),
            onPressed: onAdd,
            shape: StadiumBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
              ),
            ),
          ),
        ],
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
            colors: [
              color,
              color.withOpacity(0.0),
            ],
          ),
        ),
      ),
    );
  }
}
