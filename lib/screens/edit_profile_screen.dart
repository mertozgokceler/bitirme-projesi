// lib/screens/edit_profile_screen.dart

import 'dart:io';
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

    _networkImageUrl = (data['photoUrl'] ?? '').toString().trim().isEmpty ? null : (data['photoUrl'] as String?);

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
      imageQuality: 50,
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
    final List<String> allSkills = [
      'JavaScript',
      'Python',
      'Java',
      'C#',
      'PHP',
      'C++',
      'TypeScript',
      'Ruby',
      'Swift',
      'Go',
      'Kotlin',
      'Rust',
      'Dart',
      'Scala',
      'SQL',
      'HTML',
      'CSS',
      'React',
      'Angular',
      'Vue.js',
      'Node.js',
      'Django',
      'Spring',
      'ASP.NET',
      'Flutter',
      'React Native',
      'TensorFlow',
      'PyTorch',
      'AWS',
      'Azure',
      'Google Cloud',
      'Docker',
      'Rest Api',
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text('Yetenek Seç', style: Theme.of(context).textTheme.titleLarge),
                  const Divider(height: 24),
                  Expanded(
                    child: ListView.builder(
                      itemCount: allSkills.length,
                      itemBuilder: (context, index) {
                        final skill = allSkills[index];
                        final isSelected = _selectedSkills.contains(skill);
                        return ListTile(
                          title: Text(skill),
                          trailing: IconButton(
                            icon: Icon(
                              isSelected ? Icons.check_circle : Icons.add_circle_outline,
                              color: isSelected ? Colors.green : Colors.grey,
                            ),
                            onPressed: () {
                              setModalState(() {
                                if (isSelected) {
                                  _selectedSkills.remove(skill);
                                } else {
                                  _selectedSkills.add(skill);
                                }
                              });
                              setState(() {});
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _workPrefTile(String key, String label, IconData icon) {
    final isOn = _workModelPrefs[key] == true;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _workModelPrefs[key] = !isOn),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          color: isOn ? Theme.of(context).colorScheme.primary.withOpacity(0.10) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
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

          // individual alanları
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

        // ✅ Şirketlerde individual alanları yanlışlıkla kalmışsa temizle (opsiyonel ama sağlıklı)
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
        const SnackBar(
          content: Text('Profil başarıyla güncellendi!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bir hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profili Düzenle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundImage: _imageFile != null
                      ? FileImage(_imageFile!) as ImageProvider
                      : (_networkImageUrl != null ? NetworkImage(_networkImageUrl!) : null),
                  child: _imageFile == null && _networkImageUrl == null
                      ? const Icon(Icons.person, size: 60)
                      : null,
                ),
                GestureDetector(
                  onTap: _pickImage,
                  child: const CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.camera_alt, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // İSİM
            _buildTextField(
              controller: _nameController,
              label: _isCompany ? 'Şirket Adı' : 'Ad Soyad',
              icon: _isCompany ? Icons.business_outlined : Icons.person_outline,
            ),
            const SizedBox(height: 16),

            // KULLANICI ADI
            _buildTextField(
              controller: _usernameController,
              label: 'Kullanıcı Adı',
              icon: Icons.alternate_email,
            ),
            const SizedBox(height: 16),

            // ROL / SEKTÖR
            _buildTextField(
              controller: _roleController,
              label: _isCompany ? 'Sektör / Faaliyet Alanı' : 'Unvan / Rol',
              icon: Icons.work_outline,
            ),
            const SizedBox(height: 16),

            // KONUM
            _buildTextField(
              controller: _locationController,
              label: _isCompany ? 'Şirket Konumu (örn: İstanbul)' : 'Konum (örn: İstanbul)',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 16),

            // ✅ Individual’a özel: Seviye + Çalışma Tercihi
            if (!_isCompany) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Seviye', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _levels.contains(_level) ? _level : 'Intern',
                items: _levels
                    .map((x) => DropdownMenuItem<String>(value: x, child: Text(x)))
                    .toList(growable: false),
                onChanged: (v) => setState(() => _level = (v ?? 'Intern')),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.stairs_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Çalışma Tercihi', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Column(
                children: [
                  _workPrefTile('remote', 'Remote', Icons.wifi_tethering),
                  const SizedBox(height: 8),
                  _workPrefTile('hybrid', 'Hybrid', Icons.sync_alt_rounded),
                  const SizedBox(height: 8),
                  _workPrefTile('on-site', 'On-site', Icons.apartment_rounded),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // ŞİRKET ÖZEL DETAYLAR
            if (_isCompany) ...[
              _buildTextField(
                controller: _companyWebsiteController,
                label: 'Website (örn: https://techconnect.com)',
                icon: Icons.language_outlined,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _companyFoundedYearController,
                label: 'Kuruluş Yılı (örn: 2015)',
                icon: Icons.calendar_today_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _companyEmployeeCountController,
                label: 'Çalışan Sayısı (örn: 25)',
                icon: Icons.people_outline,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
            ],

            // BİO
            _buildTextField(
              controller: _bioController,
              label: _isCompany ? 'Hakkımızda / Şirket Tanımı' : 'Hakkımda (Bio)',
              icon: Icons.info_outline,
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // SKILLS
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isCompany ? 'Teknolojiler / Uzmanlıklar' : 'Yetenekler',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: [
                  ..._selectedSkills.map(
                        (skill) => Chip(
                      label: Text(skill),
                      onDeleted: () => setState(() => _selectedSkills.remove(skill)),
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.add),
                    label: const Text('Yetenek Ekle'),
                    onPressed: _showSkillsBottomSheet,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Değişiklikleri Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final effectiveKeyboardType = keyboardType ??
        (maxLines > 1 ? TextInputType.multiline : TextInputType.text);

    final effectiveAction = maxLines > 1 ? TextInputAction.newline : TextInputAction.next;

    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: effectiveKeyboardType,
      textInputAction: effectiveAction,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
