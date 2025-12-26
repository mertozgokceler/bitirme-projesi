import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class CertificatesCvScreen extends StatefulWidget {
  const CertificatesCvScreen({super.key});

  @override
  State<CertificatesCvScreen> createState() => _CertificatesCvScreenState();
}

class _CertificatesCvScreenState extends State<CertificatesCvScreen> {
  bool _isLoadingCv = true;
  String? _cvUrl;
  String? _cvName;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    _loadCvInfo();
  }

  Future<void> _loadCvInfo() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingCv = false;
      });
      return;
    }

    try {
      final doc =
      await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists) {
        setState(() {
          _cvUrl = doc.data()?['cvUrl'] as String?;
          _cvName = doc.data()?['cvName'] as String?;
          _isLoadingCv = false;
        });
      } else {
        setState(() {
          _isLoadingCv = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingCv = false;
      });
    }
  }

  Future<void> _pickAndUploadCv() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final fileName = result.files.single.name;

    setState(() {
      _isLoadingCv = true;
    });

    try {
      final ref = _storage
          .ref()
          .child('users')
          .child(user.uid)
          .child('cv')
          .child(fileName);

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await _firestore.collection('users').doc(user.uid).update({
        'cvUrl': url,
        'cvName': fileName,
      });

      setState(() {
        _cvUrl = url;
        _cvName = fileName;
        _isLoadingCv = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CV başarıyla yüklendi.')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoadingCv = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CV yüklenirken hata oluştu: $e')),
        );
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı açılamadı.')),
        );
      }
    }
  }

  Future<void> _addCertificate() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Sertifika adı input’u
    String? certTitle;
    await showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Sertifika Başlığı'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Örn: Google Cloud Fundamentals',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                certTitle = controller.text.trim();
                Navigator.of(context).pop();
              },
              child: const Text('Devam'),
            ),
          ],
        );
      },
    );

    if (certTitle == null || certTitle!.isEmpty) return;

    // Dosya seç
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );

    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final fileName = result.files.single.name;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sertifika yükleniyor...')),
    );

    try {
      final ref = _storage
          .ref()
          .child('users')
          .child(user.uid)
          .child('certificates')
          .child(fileName);

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('certificates')
          .add({
        'title': certTitle,
        'fileUrl': url,
        'fileName': fileName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sertifika eklendi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sertifika yüklenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _deleteCertificate(String certId, String fileName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sertifikayı Sil'),
        content: const Text('Bu sertifikayı silmek istediğine emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Firestore’dan sil
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('certificates')
          .doc(certId)
          .delete();

      // Storage’dan silmeye çalış (başarısız olursa da sorun değil)
      final ref = _storage
          .ref()
          .child('users')
          .child(user.uid)
          .child('certificates')
          .child(fileName);

      await ref.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sertifika silindi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sertifika silinirken hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sertifikalarım ve CV'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // CV Kartı
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: isDark ? 0 : 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.description_outlined, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'CV Dosyam',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isLoadingCv)
                    const Center(child: CircularProgressIndicator())
                  else if (_cvUrl == null)
                    const Text(
                      'Henüz bir CV yüklemedin.',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(
                        _cvName ?? 'CV.pdf',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'PDF • Dokunarak açabilirsiniz',
                        style: TextStyle(fontSize: 12),
                      ),
                      onTap: () {
                        if (_cvUrl != null) {
                          _openUrl(_cvUrl!);
                        }
                      },
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _pickAndUploadCv,
                      icon: const Icon(Icons.upload_file),
                      label: Text(
                        _cvUrl == null ? 'CV Yükle' : 'CV Güncelle',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Sertifikalar Kartı
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: isDark ? 0 : 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.workspace_premium_outlined, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Sertifikalarım',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addCertificate,
                        icon: const Icon(Icons.add),
                        label: const Text('Ekle'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),

                  // Sertifikalar listesi
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _auth.currentUser == null
                        ? const Stream.empty()
                        : _firestore
                        .collection('users')
                        .doc(_auth.currentUser!.uid)
                        .collection('certificates')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (!snapshot.hasData ||
                          snapshot.data!.docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Text(
                            'Henüz eklenmiş sertifikan yok.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      final docs = snapshot.data!.docs;

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) =>
                        const Divider(height: 8),
                        itemBuilder: (context, index) {
                          final cert = docs[index].data();
                          final certId = docs[index].id;
                          final title = cert['title'] as String? ?? 'Sertifika';
                          final fileName =
                              cert['fileName'] as String? ?? 'Dosya';
                          final fileUrl =
                          cert['fileUrl'] as String?;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.insert_drive_file_outlined,
                            ),
                            title: Text(
                              title,
                              style:
                              const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              fileName,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () {
                              if (fileUrl != null) {
                                _openUrl(fileUrl);
                              }
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                _deleteCertificate(certId, fileName);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
