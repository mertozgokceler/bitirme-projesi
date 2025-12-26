// lib/screens/create_post_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _textController = TextEditingController();

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _picker = ImagePicker();

  bool _isLoading = false;

  // Üst bar için kullanıcı bilgileri
  String _headerName = 'Herhangi bir kişi';
  String? _userAvatarUrl;

  // Seçilen resim
  XFile? _pickedImage;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _loadUserInfo();
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  Future<void> _loadUserInfo() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();

      setState(() {
        _headerName =
            (data?['name'] as String?) ?? user.displayName ??
                'Herhangi bir kişi';
        _userAvatarUrl =
            (data?['photoUrl'] as String?) ?? user.photoURL; // Firestore > Auth
      });
    } catch (_) {
      // sessiz geç
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? img =
      await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (img == null) return;
      setState(() {
        _pickedImage = img;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resim seçilirken hata oluştu: $e')),
      );
    }
  }

  Future<String?> _uploadImageIfNeeded(User user) async {
    if (_pickedImage == null) return null;

    try {
      final file = File(_pickedImage!.path);
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('post_images')
          .child(user.uid)
          .child('${DateTime
          .now()
          .millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(file);
      final url = await storageRef.getDownloadURL();
      return url;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resim yüklenemedi: $e')),
      );
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gönderi paylaşmak için giriş yapmalısın.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Kullanıcı bilgileri
      final userDoc =
      await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();

      final userName =
          (userData?['name'] as String?) ?? user.email ?? 'Kullanıcı';
      final userTitle = (userData?['title'] as String?) ?? '';
      final userAvatarUrl = userData?['photoUrl'] as String? ?? user.photoURL;

      // Resim seçildiyse Storage’a yükle
      final imageUrl = await _uploadImageIfNeeded(user);

      await _firestore.collection('posts').add({
        'userId': user.uid,
        'userName': userName,
        'userTitle': userTitle,
        'userAvatarUrl': userAvatarUrl,
        'text': _textController.text.trim(),
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gönderin paylaşıldı.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gönderi paylaşırken hata oluştu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;

    final hasText = _textController.text
        .trim()
        .isNotEmpty;
    final canPost = hasText && !_isLoading;

    final bgColor =
    isDark ? const Color(0xFF111418) : Theme
        .of(context)
        .scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage:
              _userAvatarUrl != null ? NetworkImage(_userAvatarUrl!) : null,
              child: _userAvatarUrl == null
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              _headerName,
              style: Theme
                  .of(context)
                  .textTheme
                  .bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 18),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ElevatedButton(
              onPressed: canPost ? _submit : null,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: canPost
                    ? const Color(0xFF6E44FF)
                    : (isDark ? Colors.grey.shade800 : Colors.grey.shade400),
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text(
                'Postala',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Metin alanı (üstte)
            Expanded(
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _textController,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontSize: 18,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Düşüncelerinizi paylaşın...',
                      hintStyle: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                      ),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                    ),
                    validator: (value) {
                      if (value == null || value
                          .trim()
                          .isEmpty) {
                        return 'Gönderi metni boş olamaz.';
                      }
                      if (value
                          .trim()
                          .length < 3) {
                        return 'Biraz daha detay yaz lütfen.';
                      }
                      return null;
                    },
                  ),
                ),
              ),
            ),

            // Seçilen resim varsa, yazının ALTINDA göster
            if (_pickedImage != null)
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image.file(
                      File(_pickedImage!.path),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),

            // Alt sağ köşe: çerçeveli resim + plus ikonları
            Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery
                    .of(context)
                    .padding
                    .bottom + 8,
                right: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _bottomIconButton(
                    icon: Icons.image_outlined,
                    onTap: _isLoading ? null : _pickImage,
                  ),
                  const SizedBox(width: 8),
                  _bottomIconButton(
                    icon: Icons.add,
                    onTap: () {
                      // Şimdilik boş; ileride anket/link vs. ekleyebilirsin
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ek seçenekler yakında.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomIconButton({
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(50),
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle, // 🔥 tamamen yuvarlak form
          border: Border.all(
            color: isDark ? Colors.white30 : Colors.grey.shade400,
            width: 1.3,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 24,
            color: isDark ? Colors.grey.shade100 : Colors.grey.shade800,
          ),
        ),
      ),
    );
  }
}