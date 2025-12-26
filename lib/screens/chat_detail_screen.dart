// lib/screens/chat_detail_screen.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/call_service.dart';
import '../services/call_controller.dart';
import 'call_screen.dart';

import '../in_app_notification.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final Map<String, dynamic> otherUser;

  /// ✅ DI: CallService app-level tek instance olmalı.
  final CallService callService;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    required this.otherUser,
    required this.callService,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

/// ✅ Light + Dark preset (gradient)
class ChatBgPreset {
  final List<Color> light;
  final List<Color> dark;
  const ChatBgPreset({required this.light, required this.dark});
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _messageController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _imagePicker = ImagePicker();

  /// ✅ Call: controller ekran bazlı, service app-level
  CallController? _callController;
  bool _startingCall = false;

  bool _isComposing = false;
  Map<String, dynamic>? _currentUserData;
  bool _isLoadingUserData = true;

  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordDuration = 0;
  String? _recordingPath;

  int _selectedBackgroundIndex = 0;

  // ✅ Bariz fark eden presetler (dark modda net değişsin diye “uçurum” yaptım)
  final List<ChatBgPreset> _bgPresets = const [
    ChatBgPreset(
      light: [Color(0xFFF4EFEF), Color(0xFFFFFFFF)],
      dark: [Color(0xFF060A14), Color(0xFF1A2A5E)], // Navy
    ),
    ChatBgPreset(
      light: [Color(0xFFE8F5E9), Color(0xFFFFFFFF)],
      dark: [Color(0xFF04110A), Color(0xFF0E3B25)], // Green
    ),
    ChatBgPreset(
      light: [Color(0xFFE3F2FD), Color(0xFFFFFFFF)],
      dark: [Color(0xFF070B12), Color(0xFF2C1B4A)], // Purple
    ),
    ChatBgPreset(
      light: [Color(0xFFFFF8E1), Color(0xFFFFFFFF)],
      dark: [Color(0xFF120A05), Color(0xFF4A240E)], // Amber/Brown
    ),
  ];

  // ✅ Chat bazlı kalıcılık (chatId)
  String get _bgPrefsKey => 'chat_bg_v2_${widget.chatId}';

  @override
  void initState() {
    super.initState();

    _loadBg();
    _loadCurrentUserData();

    _messageController.addListener(() {
      final isNotEmpty = _messageController.text.trim().isNotEmpty;
      if (_isComposing != isNotEmpty) {
        setState(() => _isComposing = isNotEmpty);
      }
    });
  }

  ChatBgPreset get _preset {
    final i = _selectedBackgroundIndex.clamp(0, _bgPresets.length - 1);
    return _bgPresets[i];
  }

  Future<void> _loadBg() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt(_bgPrefsKey);
      if (!mounted) return;
      if (idx != null && idx >= 0 && idx < _bgPresets.length) {
        setState(() => _selectedBackgroundIndex = idx);
      }
    } catch (e) {
      debugPrint('DEBUG[chat_bg] load error: $e');
    }
  }

  Future<void> _saveBg(int idx) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_bgPrefsKey, idx);
    } catch (e) {
      debugPrint('DEBUG[chat_bg] save error: $e');
    }
  }

  Future<void> _loadCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingUserData = false);
      return;
    }
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (mounted) {
        setState(() {
          _currentUserData = doc.data();
          _isLoadingUserData = false;
        });
      }
    } catch (e) {
      debugPrint("Kullanıcı verisi yüklenirken hata: $e");
      if (mounted) setState(() => _isLoadingUserData = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _audioPlayer.dispose();

    // ✅ call cleanup
    _callController = null;

    super.dispose();
  }

  // -------------------------------------------------
  // Helpers
  // -------------------------------------------------

  String _detectFileType(String ext) {
    final e = ext.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(e)) return 'image';
    if (['mp4', 'mov', 'mkv'].contains(e)) return 'video';
    if (['mp3', 'wav', 'aac', 'm4a'].contains(e)) return 'audio';
    if (e == 'pdf') return 'pdf';
    if (['doc', 'docx'].contains(e)) return 'word';
    if (['xls', 'xlsx'].contains(e)) return 'excel';
    if (['ppt', 'pptx'].contains(e)) return 'powerpoint';
    if (['zip', 'rar', '7z'].contains(e)) return 'archive';
    if (['txt', 'rtf'].contains(e)) return 'text';
    return 'file';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _getFileIconAsset(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'assets/icons/pdf.png';
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return 'assets/icons/doc.png';
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return 'assets/icons/xls.png';
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return 'assets/icons/ppt.png';
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
      return 'assets/icons/zip.png';
    }
    return 'assets/icons/doc.png';
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    return DateFormat('HH:mm').format(timestamp.toDate());
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    final t = Theme.of(context);
    final ui = ChatUI.of(t);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? ui.error : ui.snackBg,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openUrlExternal(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!launched) _snack('Açılamadı. Uygun bir uygulama yok.', isError: true);
    } catch (e) {
      debugPrint('URL açma hatası: $e');
      _snack('Açılamadı.', isError: true);
    }
  }

  Future<void> _showImagePreview(String imageUrl) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Center(
          child: InteractiveViewer(
            child: Image.network(imageUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------
  // Okundu
  // -------------------------------------------------

  void _markMessagesAsRead(List<QueryDocumentSnapshot> messages) {
    if (!mounted) return;
    final otherUserId = widget.otherUser['uid'] as String?;
    if (otherUserId == null) return;

    final batch = _firestore.batch();
    bool needsCommit = false;

    for (var doc in messages) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      if (data['senderId'] == otherUserId && (data['isRead'] != true)) {
        batch.update(doc.reference, {'isRead': true});
        needsCommit = true;
      }
    }

    if (needsCommit) {
      batch.commit().catchError((e) => debugPrint("Okundu update hatası: $e"));
    }
  }

  // -------------------------------------------------
  // Metin Mesaj
  // -------------------------------------------------

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = _auth.currentUser;
    final otherUserId = widget.otherUser['uid'] as String?;
    if (currentUser == null || otherUserId == null) return;

    final timestamp = FieldValue.serverTimestamp();
    final chatRef = _firestore.collection('chats').doc(widget.chatId);

    await chatRef.collection('messages').add({
      'type': 'text',
      'text': text,
      'senderId': currentUser.uid,
      'timestamp': timestamp,
      'isRead': false,
    });

    await chatRef.set({
      'users': [currentUser.uid, otherUserId],
      'lastMessage': text,
      'lastMessageSenderId': currentUser.uid,
      'lastMessageTimestamp': timestamp,
      'isArchived': false,
    }, SetOptions(merge: true));

    _messageController.clear();
  }

  // -------------------------------------------------
  // Sesli Mesaj
  // -------------------------------------------------

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _snack('Sesli mesaj için mikrofon izni gerekli.', isError: true);
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      _recordingPath =
      '${tempDir.path}/audio_message_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _recordingPath!,
      );

      setState(() {
        _isRecording = true;
        _recordDuration = 0;
      });

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_isRecording || !mounted) {
          timer.cancel();
          return;
        }
        setState(() => _recordDuration++);
      });
    } catch (e) {
      debugPrint("Kayıt başlatılamadı: $e");
      _snack('Kayıt başlatılamadı.', isError: true);
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _stopRecordingAndSend() async {
    _recordingTimer?.cancel();
    String? path;

    try {
      path = await _audioRecorder.stop();
      if (mounted) setState(() => _isRecording = false);

      if (path == null || _recordDuration <= 0) return;

      final file = File(path);
      if (!await file.exists()) throw Exception("Kaydedilen dosya yok.");

      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final ref = _storage.ref().child('chat_audio/${widget.chatId}/$fileName');
      final snapshot = await ref.putFile(file).whenComplete(() {});
      final url = await snapshot.ref.getDownloadURL();

      final currentUser = _auth.currentUser;
      final otherUserId = widget.otherUser['uid'] as String?;
      if (currentUser == null || otherUserId == null) return;

      final timestamp = FieldValue.serverTimestamp();
      final chatRef = _firestore.collection('chats').doc(widget.chatId);

      await chatRef.collection('messages').add({
        'type': 'audio',
        'audioUrl': url,
        'duration': _recordDuration,
        'senderId': currentUser.uid,
        'timestamp': timestamp,
        'isRead': false,
      });

      await chatRef.set({
        'users': [currentUser.uid, otherUserId],
        'lastMessage': 'Sesli Mesaj',
        'lastMessageSenderId': currentUser.uid,
        'lastMessageTimestamp': timestamp,
        'isArchived': false,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Sesli mesaj gönderilemedi: $e");
      _snack('Sesli mesaj gönderilemedi.', isError: true);
    } finally {
      if (path != null) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _recordDuration = 0);
    }
  }

  // -------------------------------------------------
  // Attachments
  // -------------------------------------------------

  Future<bool> _showAttachmentConfirm({
    required String title,
    required String subtitle,
    File? file,
    bool isImage = false,
    int? size,
  }) async {
    final t = Theme.of(context);
    final ui = ChatUI.of(t);

    return await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: ui.dialogBg,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isImage && file != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(file,
                        width: 180, height: 180, fit: BoxFit.cover),
                  ),
                ),
              Text(subtitle,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (size != null) ...[
                const SizedBox(height: 8),
                Text(_formatFileSize(size),
                    style: TextStyle(color: ui.mutedText)),
              ],
              const SizedBox(height: 10),
              Text('Bu dosyayı göndermek istiyor musun?',
                  style: TextStyle(color: ui.mutedText)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('İptal')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Gönder')),
          ],
        );
      },
    ) ??
        false;
  }

  Future<void> _pickAndSendAttachment() async {
    final currentUser = _auth.currentUser;
    final otherUserId = widget.otherUser['uid'] as String?;
    if (currentUser == null || otherUserId == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: [
          'jpg', 'jpeg', 'png', 'heic', 'webp',
          'mp4', 'mov', 'mkv',
          'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'zip', 'rar', '7z', 'txt', 'rtf',
          'mp3', 'wav', 'aac', 'm4a',
        ],
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final path = picked.path;
      if (path == null) return;

      final file = File(path);
      final ext = (picked.extension ?? '').toLowerCase();
      final detectedType = _detectFileType(ext);

      String folder;
      String messageType;
      String lastMessagePreview;
      String title;

      switch (detectedType) {
        case 'image':
          folder = 'chat_images';
          messageType = 'image';
          lastMessagePreview = 'Fotoğraf';
          title = 'Fotoğraf';
          break;
        case 'video':
          folder = 'chat_videos';
          messageType = 'video';
          lastMessagePreview = 'Video';
          title = 'Video';
          break;
        case 'pdf':
          folder = 'chat_files';
          messageType = 'pdf';
          lastMessagePreview = 'PDF';
          title = 'PDF Dosyası';
          break;
        case 'word':
          folder = 'chat_files';
          messageType = 'word';
          lastMessagePreview = 'Word';
          title = 'Word Belgesi';
          break;
        case 'excel':
          folder = 'chat_files';
          messageType = 'excel';
          lastMessagePreview = 'Excel';
          title = 'Excel Dosyası';
          break;
        case 'powerpoint':
          folder = 'chat_files';
          messageType = 'powerpoint';
          lastMessagePreview = 'PowerPoint';
          title = 'PowerPoint Sunumu';
          break;
        case 'archive':
          folder = 'chat_files';
          messageType = 'archive';
          lastMessagePreview = 'Arşiv';
          title = 'Arşiv Dosyası';
          break;
        case 'text':
          folder = 'chat_files';
          messageType = 'file';
          lastMessagePreview = 'Metin Dosyası';
          title = 'Metin Dosyası';
          break;
        default:
          folder = 'chat_files';
          messageType = 'file';
          lastMessagePreview = 'Dosya';
          title = 'Dosya';
      }

      final confirmed = await _showAttachmentConfirm(
        title: title,
        subtitle: picked.name,
        file: detectedType == 'image' ? file : null,
        isImage: detectedType == 'image',
        size: picked.size,
      );
      if (!confirmed) return;

      await _uploadAndSendMedia(
        file: file,
        folder: folder,
        messageType: messageType,
        lastMessagePreview: lastMessagePreview,
        originalName: picked.name,
        size: picked.size,
      );
    } catch (e) {
      debugPrint('Dosya seçme/gönderme hatası: $e');
      _snack('Dosya gönderilemedi.', isError: true);
    }
  }

  Future<void> _pickFromCamera() async {
    final currentUser = _auth.currentUser;
    final otherUserId = widget.otherUser['uid'] as String?;
    if (currentUser == null || otherUserId == null) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Fotoğraf çek'),
                onTap: () => Navigator.of(ctx).pop('photo'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Video çek'),
                onTap: () => Navigator.of(ctx).pop('video'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (choice == null) return;

    try {
      if (choice == 'photo') {
        final picked = await _imagePicker.pickImage(
            source: ImageSource.camera, imageQuality: 85);
        if (picked == null) return;

        final file = File(picked.path);
        final confirmed = await _showAttachmentConfirm(
          title: 'Fotoğraf',
          subtitle: 'Yeni çekilen fotoğraf',
          file: file,
          isImage: true,
        );
        if (!confirmed) return;

        await _uploadAndSendMedia(
          file: file,
          folder: 'chat_images',
          messageType: 'image',
          lastMessagePreview: 'Fotoğraf',
          originalName: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
      } else {
        final picked = await _imagePicker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(minutes: 5),
        );
        if (picked == null) return;

        final file = File(picked.path);
        final confirmed = await _showAttachmentConfirm(
          title: 'Video',
          subtitle: 'Yeni çekilen video',
        );
        if (!confirmed) return;

        await _uploadAndSendMedia(
          file: file,
          folder: 'chat_videos',
          messageType: 'video',
          lastMessagePreview: 'Video',
          originalName: 'camera_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
      }
    } catch (e) {
      debugPrint('Kamera ile medya gönderilemedi: $e');
      _snack('Medya gönderilemedi.', isError: true);
    }
  }

  Future<void> _uploadAndSendMedia({
    required File file,
    required String folder,
    required String messageType,
    required String lastMessagePreview,
    String? originalName,
    int? size,
  }) async {
    final currentUser = _auth.currentUser;
    final otherUserId = widget.otherUser['uid'] as String?;
    if (currentUser == null || otherUserId == null) return;

    final chatRef = _firestore.collection('chats').doc(widget.chatId);

    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${originalName ?? 'media'}';
      final ref = _storage.ref().child('$folder/${widget.chatId}/$fileName');

      final snapshot = await ref.putFile(file).whenComplete(() {});
      final url = await snapshot.ref.getDownloadURL();

      final timestamp = FieldValue.serverTimestamp();

      final data = <String, dynamic>{
        'type': messageType,
        'senderId': currentUser.uid,
        'timestamp': timestamp,
        'isRead': false,
      };

      if (messageType == 'image') {
        data['imageUrl'] = url;
      } else if (messageType == 'video') {
        data['videoUrl'] = url;
      } else {
        data['fileUrl'] = url;
        data['fileName'] = originalName ?? 'Dosya';
        if (size != null) data['fileSize'] = size;
      }

      await chatRef.collection('messages').add(data);

      await chatRef.set({
        'users': [currentUser.uid, otherUserId],
        'lastMessage': lastMessagePreview,
        'lastMessageSenderId': currentUser.uid,
        'lastMessageTimestamp': timestamp,
        'isArchived': false,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Medya upload/gönderme hatası: $e');
      _snack('Medya gönderilemedi.', isError: true);
    }
  }

  // -------------------------------------------------
  // Mesaj Silme
  // -------------------------------------------------

  void _showMessageOptions(
      String messageId, Map<String, dynamic> messageData, bool isMe) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Benden sil'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _deleteMessageForMe(messageId);
                },
              ),
              if (isMe) ...[
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: Colors.redAccent),
                  title: const Text('Herkesten sil',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Herkesten silinsin mi?'),
                        content: const Text(
                            'Bu mesaj iki taraftan da silinecek. Emin misin?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(dctx).pop(false),
                              child: const Text('Vazgeç')),
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text('Sil',
                                style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _deleteMessageForEveryone(messageId);
                    }
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMessageForMe(String messageId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final msgRef = _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId);
      await msgRef.set({'deletedFor': FieldValue.arrayUnion([uid])},
          SetOptions(merge: true));
    } catch (e) {
      debugPrint("Benden sil hatası: $e");
      _snack('Mesaj senden silinemedi.', isError: true);
    }
  }

  Future<void> _deleteMessageForEveryone(String messageId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final msgRef = _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId);
      final snap = await msgRef.get();
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null || data['senderId'] != uid) {
        _snack('Sadece kendi mesajını herkesten silebilirsin.', isError: true);
        return;
      }

      await msgRef.delete();
      _snack('Mesaj herkesten silindi.');
    } catch (e) {
      debugPrint("Herkesten sil hatası: $e");
      _snack('Mesaj herkesten silinemedi.', isError: true);
    }
  }

  // -------------------------------------------------
  // Background Picker
  // -------------------------------------------------

  void _showBackgroundPicker() {
    final rootContext = context;
    final isDark = Theme.of(rootContext).brightness == Brightness.dark;

    showModalBottomSheet(
      context: rootContext,
      backgroundColor: Theme.of(rootContext).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sohbet arka planı',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(_bgPresets.length, (index) {
                    final preset = _bgPresets[index];
                    final colors = isDark ? preset.dark : preset.light;
                    final isSelected = index == _selectedBackgroundIndex;

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        if (!mounted) return;
                        setState(() => _selectedBackgroundIndex = index);
                        await _saveBg(index);
                        if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: colors,
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(rootContext).colorScheme.primary
                                : Colors.grey.shade400,
                            width: isSelected ? 3 : 1,
                          ),
                        ),
                        child: isSelected
                            ? Icon(
                          Icons.check,
                          color: Theme.of(rootContext).colorScheme.primary,
                          size: 20,
                        )
                            : null,
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------
  // Build
  // -------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ui = ChatUI.of(t);
    final isDark = t.brightness == Brightness.dark;

    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sohbet')),
        body: const Center(child: Text("Kullanıcı bulunamadı.")),
      );
    }

    final otherName =
    (widget.otherUser['name'] ?? widget.otherUser['username'] ?? 'Sohbet')
        .toString();
    final otherPhotoUrl = (widget.otherUser['photoUrl'] as String?) ?? '';

    final preset = _preset;
    final bgColors = isDark ? preset.dark : preset.light;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ui.overlayStyle,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: ui.appBarBg,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage:
                otherPhotoUrl.isNotEmpty ? NetworkImage(otherPhotoUrl) : null,
                child: otherPhotoUrl.isEmpty
                    ? Icon(Icons.person, color: ui.onAvatar)
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(otherName,
                      style: t.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('çevrimiçi',
                      style: t.textTheme.labelSmall
                          ?.copyWith(color: ui.mutedText)),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.videocam),
              onPressed: _startingCall
                  ? null
                  : () async {
                final otherUserId = widget.otherUser['uid'] as String?;
                if (otherUserId == null) return;

                if (_callController != null) return;

                // 🎯 Kamera + Mikrofon izni
                final mic = await Permission.microphone.request();
                final cam = await Permission.camera.request();

                if (!mic.isGranted || !cam.isGranted) {
                  _snack(
                    'Görüntülü arama için kamera ve mikrofon izni gerekli.',
                    isError: true,
                  );
                  return;
                }

                setState(() => _startingCall = true);

                try {
                  final controller = CallController(widget.callService);
                  _callController = controller;

                  final meName = (_currentUserData?['name'] ??
                      _currentUserData?['username'] ??
                      'User')
                      .toString();

                  final calleeName = (otherName).toString();

                  await controller.startOutgoing(
                    calleeId: otherUserId,
                    calleeName: calleeName,
                    callerName: meName,
                    type: CallType.video,
                    onRemoteEnded: () {
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                  );

                  if (!mounted) return;

                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => CallScreen(controller: controller),
                    ),
                  );
                  await controller.disposeAll(writeEnded: true);
                  _callController = null;

                } catch (e) {
                  _snack('Görüntülü arama başlatılamadı.', isError: true);
                  try {
                    await _callController?.disposeAll(writeEnded: false);
                  } catch (_) {}
                  _callController = null;
                } finally {
                  if (mounted) setState(() => _startingCall = false);
                }
              },
            ),

            IconButton(
              icon: _startingCall
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.call),
              onPressed: _startingCall
                  ? null
                  : () async {
                final otherUserId = widget.otherUser['uid'] as String?;
                if (otherUserId == null) return;

                if (_callController != null) return;

                final mic = await Permission.microphone.request();
                if (!mic.isGranted) {
                  _snack('Arama için mikrofon izni gerekli.', isError: true);
                  return;
                }

                setState(() => _startingCall = true);

                try {
                  final controller = CallController(widget.callService);
                  _callController = controller;

                  // ✅ BENİM İSMİM (myName yoktu, hata buradan geliyordu)
                  final meName = (_currentUserData?['name'] ??
                      _currentUserData?['username'] ??
                      'User')
                      .toString();

                  // ✅ karşı tarafın adı (sende zaten var diye kullanıyorum)
                  final calleeName = (otherName).toString();

                  await controller.startOutgoing(
                    calleeId: otherUserId,
                    calleeName: calleeName,
                    callerName: meName,
                    type: CallType.audio,
                    onRemoteEnded: () {
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                  );

                  if (!mounted) return;

                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => CallScreen(controller: controller),
                    ),
                  );
                  await controller.disposeAll(writeEnded: true);
                  _callController = null;

                } catch (e) {
                  _snack('Arama başlatılamadı.', isError: true);
                  try {
                    await _callController?.disposeAll(writeEnded: false);
                  } catch (_) {}
                  _callController = null;
                } finally {
                  if (mounted) setState(() => _startingCall = false);
                }
              },

            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'theme') _showBackgroundPicker();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'theme', child: Text('Temayı Değiştir')),
              ],
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            // ✅ opacity yok. Dark modda net fark olsun.
            gradient: LinearGradient(
              colors: bgColors,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: _isLoadingUserData
                      ? const Center(child: CircularProgressIndicator())
                      : StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('chats')
                        .doc(widget.chatId)
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                            child: Text(
                                'Mesajlar yüklenirken hata: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData ||
                          snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('Henüz mesaj yok.'));
                      }

                      final docs = snapshot.data!.docs;
                      _markMessagesAsRead(docs);

                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};

                          final deletedFor =
                              (data['deletedFor'] as List?) ?? const [];
                          if (deletedFor.contains(currentUserId)) {
                            return const SizedBox.shrink();
                          }

                          final isMe = data['senderId'] == currentUserId;
                          final ts = data['timestamp'] as Timestamp?;
                          final isRead = data['isRead'] as bool? ?? false;

                          final myPhotoUrl =
                              (_currentUserData?['photoUrl'] as String?) ??
                                  '';
                          final avatarUrl =
                          isMe ? myPhotoUrl : otherPhotoUrl;

                          final type =
                          (data['type'] as String? ?? 'text').toLowerCase();

                          final Widget content = switch (type) {
                            'audio' => _buildAudioBubble(
                                context, data, isMe, ts, isRead),
                            'image' => _buildImageBubble(
                                context, data, isMe, ts, isRead),
                            'video' => _buildVideoBubble(
                                context, data, isMe, ts, isRead),
                            'pdf' ||
                            'word' ||
                            'excel' ||
                            'powerpoint' ||
                            'archive' ||
                            'file' =>
                                _buildFileBubble(
                                    context, data, isMe, ts, isRead),
                            _ => _buildTextBubble(context,
                                (data['text'] as String? ?? ''), isMe, ts, isRead),
                          };

                          return GestureDetector(
                            onLongPress: () =>
                                _showMessageOptions(doc.id, data, isMe),
                            child: _buildMessageRow(
                                content, isMe, avatarUrl),
                          );
                        },
                      );
                    },
                  ),
                ),
                _buildMessageInput(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------
  // Row + Bubbles
  // -------------------------------------------------

  Widget _buildMessageRow(Widget content, bool isMe, String avatarUrl) {
    final ui = ChatUI.of(Theme.of(context));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment:
        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundImage:
              avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: content),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundImage:
              avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty
                  ? Icon(Icons.person, size: 18, color: ui.onAvatar)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaRow(bool isMe, Timestamp? timestamp, bool isRead) {
    final ui = ChatUI.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_formatTimestamp(timestamp),
              style: TextStyle(fontSize: 12, color: ui.metaText)),
          if (isMe) ...[
            const SizedBox(width: 4),
            Icon(Icons.done_all,
                size: 16, color: isRead ? ui.readTick : ui.metaText),
          ],
        ],
      ),
    );
  }

  Widget _buildBubbleContainer({
    required bool isMe,
    required Widget child,
  }) {
    final ui = ChatUI.of(Theme.of(context));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ Dark modda “daha görünür” olsun diye hafif preset tint
    final preset = _preset;
    final accent = (isDark ? preset.dark.last : preset.light.first);

    final Color bubbleColor = isMe
        ? Color.alphaBlend(accent.withOpacity(isDark ? 0.18 : 0.10), ui.meBubble)
        : Color.alphaBlend(
        accent.withOpacity(isDark ? 0.12 : 0.06), ui.otherBubble);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
          bottomRight: isMe ? Radius.zero : const Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(ui.shadowOpacity),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
        border: Border.all(color: ui.bubbleBorder),
      ),
      child: child,
    );
  }

  Widget _buildTextBubble(
      BuildContext context,
      String text,
      bool isMe,
      Timestamp? timestamp,
      bool isRead,
      ) {
    final ui = ChatUI.of(Theme.of(context));
    return Column(
      crossAxisAlignment:
      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _buildBubbleContainer(
          isMe: isMe,
          child: Text(text,
              style: TextStyle(color: isMe ? ui.meText : ui.otherText)),
        ),
        const SizedBox(height: 4),
        _buildMetaRow(isMe, timestamp, isRead),
      ],
    );
  }

  Widget _buildImageBubble(
      BuildContext context,
      Map<String, dynamic> data,
      bool isMe,
      Timestamp? timestamp,
      bool isRead,
      ) {
    final url = data['imageUrl'] as String?;
    if (url == null || url.isEmpty) {
      return _buildTextBubble(
          context, '[Görsel bulunamadı]', isMe, timestamp, isRead);
    }

    return Column(
      crossAxisAlignment:
      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _showImagePreview(url),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
            ),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              width: 220,
              height: 220,
              errorBuilder: (_, __, ___) => Container(
                width: 220,
                height: 220,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _buildMetaRow(isMe, timestamp, isRead),
      ],
    );
  }

  Widget _buildVideoBubble(
      BuildContext context,
      Map<String, dynamic> data,
      bool isMe,
      Timestamp? timestamp,
      bool isRead,
      ) {
    final ui = ChatUI.of(Theme.of(context));
    final url = data['videoUrl'] as String?;
    if (url == null || url.isEmpty) {
      return _buildTextBubble(
          context, '[Video bulunamadı]', isMe, timestamp, isRead);
    }

    return Column(
      crossAxisAlignment:
      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _openUrlExternal(url),
          child: _buildBubbleContainer(
            isMe: isMe,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam, color: isMe ? ui.meText : ui.otherText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isMe ? ui.meText : ui.otherText,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.play_circle_fill,
                    color: isMe ? ui.meText : ui.otherText),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        _buildMetaRow(isMe, timestamp, isRead),
      ],
    );
  }

  Widget _buildFileBubble(
      BuildContext context,
      Map<String, dynamic> data,
      bool isMe,
      Timestamp? timestamp,
      bool isRead,
      ) {
    final ui = ChatUI.of(Theme.of(context));
    final fileUrl = data['fileUrl'] as String?;
    final fileName = (data['fileName'] as String?) ?? 'Dosya';
    final iconPath = _getFileIconAsset(fileName);

    return Column(
      crossAxisAlignment:
      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: fileUrl != null ? () => _openUrlExternal(fileUrl) : null,
          child: _buildBubbleContainer(
            isMe: isMe,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(iconPath, width: 28, height: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isMe ? ui.meText : ui.otherText,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        _buildMetaRow(isMe, timestamp, isRead),
      ],
    );
  }

  Widget _buildAudioBubble(
      BuildContext context,
      Map<String, dynamic> data,
      bool isMe,
      Timestamp? timestamp,
      bool isRead,
      ) {
    final url = data['audioUrl'] as String?;
    final duration = data['duration'] as int? ?? 0;
    if (url == null || url.isEmpty) {
      return _buildTextBubble(
          context, '[Ses dosyası bulunamadı]', isMe, timestamp, isRead);
    }

    final ui = ChatUI.of(Theme.of(context));

    return _AudioMessageBubble(
      audioUrl: url,
      duration: duration,
      isMe: isMe,
      timestamp: timestamp,
      isRead: isRead,
      audioPlayer: _audioPlayer,
      meBubble: ui.meBubble,
      otherBubble: ui.otherBubble,
      meText: ui.meText,
      otherText: ui.otherText,
      metaText: ui.metaText,
      readTick: ui.readTick,
      shadowOpacity: ui.shadowOpacity,
      bubbleBorder: ui.bubbleBorder,
    );
  }

  // -------------------------------------------------
  // Input
  // -------------------------------------------------

  Widget _buildMessageInput(BuildContext context) {
    final ui = ChatUI.of(Theme.of(context));

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: ui.inputBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ui.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(ui.shadowOpacity),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _isRecording
                  ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.mic, color: ui.recordRed),
                  Text(
                    _formatDuration(_recordDuration),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ui.inputText),
                  ),
                  Text('Kaydediliyor...',
                      style: TextStyle(color: ui.mutedText)),
                ],
              )
                  : Row(
                children: [
                  Icon(Icons.emoji_emotions_outlined,
                      color: ui.iconMuted, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: TextStyle(color: ui.inputText),
                      cursorColor: ui.brand,
                      decoration: InputDecoration(
                        hintText: 'Mesajınızı yazın…',
                        hintStyle: TextStyle(color: ui.hintText),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted:
                      _isComposing ? (_) => _sendMessage() : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _pickAndSendAttachment,
                    icon: Icon(Icons.attach_file, color: ui.iconMuted),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: _pickFromCamera,
                    icon: Icon(Icons.camera_alt_outlined,
                        color: ui.iconMuted),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onLongPressStart: _isComposing ? null : (_) => _startRecording(),
            onLongPressEnd:
            _isComposing ? null : (_) => _stopRecordingAndSend(),
            onTap: _isComposing ? _sendMessage : null,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ui.actionBtn,
                shape: BoxShape.circle,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: _isComposing
                    ? const Icon(Icons.send,
                    key: ValueKey('send'),
                    color: Colors.white,
                    size: 22)
                    : Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  key: const ValueKey('mic'),
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===========================================================
/// ✅ Chat UI kararları (tek yer)
/// ===========================================================
class ChatUI {
  final Color brand;

  final Color appBarBg;
  final SystemUiOverlayStyle overlayStyle;

  final Color meBubble;
  final Color otherBubble;
  final Color meText;
  final Color otherText;

  final Color inputBg;
  final Color inputText;
  final Color hintText;
  final Color iconMuted;

  final Color border;
  final Color bubbleBorder;
  final double shadowOpacity;

  final Color metaText;
  final Color readTick;
  final Color recordRed;

  final Color sheetBg;
  final Color dialogBg;

  final Color snackBg;
  final Color error;

  final Color mutedText;
  final Color onAvatar;
  final Color actionBtn;

  ChatUI._({
    required this.brand,
    required this.appBarBg,
    required this.overlayStyle,
    required this.meBubble,
    required this.otherBubble,
    required this.meText,
    required this.otherText,
    required this.inputBg,
    required this.inputText,
    required this.hintText,
    required this.iconMuted,
    required this.border,
    required this.bubbleBorder,
    required this.shadowOpacity,
    required this.metaText,
    required this.readTick,
    required this.recordRed,
    required this.sheetBg,
    required this.dialogBg,
    required this.snackBg,
    required this.error,
    required this.mutedText,
    required this.onAvatar,
    required this.actionBtn,
  });

  static ChatUI of(ThemeData t) {
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    const brand = Color(0xFFE57AFF);

    return ChatUI._(
      brand: brand,
      appBarBg:
      isDark ? cs.surface.withOpacity(0.92) : cs.surface.withOpacity(0.78),
      overlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      meBubble: isDark ? brand.withOpacity(0.30) : brand.withOpacity(0.22),
      otherBubble: isDark
          ? cs.surfaceVariant.withOpacity(0.88)
          : Colors.white.withOpacity(0.92),
      meText: Colors.white,
      otherText: t.textTheme.bodyLarge?.color ??
          (isDark ? Colors.white : Colors.black87),
      inputBg: isDark ? cs.surface.withOpacity(0.92) : Colors.white.withOpacity(0.95),
      inputText: t.textTheme.bodyLarge?.color ??
          (isDark ? Colors.white : Colors.black87),
      hintText: (t.textTheme.bodyMedium?.color ??
          (isDark ? Colors.white70 : Colors.black54))
          .withOpacity(0.85),
      iconMuted: (t.textTheme.bodyMedium?.color ??
          (isDark ? Colors.white70 : Colors.black54))
          .withOpacity(0.85),
      border: isDark ? Colors.white12 : Colors.black12,
      bubbleBorder: isDark ? Colors.white10 : Colors.black12,
      shadowOpacity: isDark ? 0.20 : 0.06,
      metaText: isDark ? Colors.white60 : Colors.black45,
      readTick: cs.primary,
      recordRed: Colors.redAccent,
      sheetBg: cs.surface,
      dialogBg: cs.surface,
      snackBg: isDark ? cs.surface : cs.inverseSurface,
      error: Colors.redAccent,
      mutedText: isDark ? Colors.white70 : Colors.black54,
      onAvatar: Colors.white,
      actionBtn: isDark ? brand.withOpacity(0.95) : brand,
    );
  }
}

// -------------------------------------------------
// Audio bubble (tema parametreli)
// -------------------------------------------------

class _AudioMessageBubble extends StatefulWidget {
  final String audioUrl;
  final int duration;
  final bool isMe;
  final Timestamp? timestamp;
  final bool isRead;
  final AudioPlayer audioPlayer;

  final Color meBubble;
  final Color otherBubble;
  final Color meText;
  final Color otherText;
  final Color metaText;
  final Color readTick;
  final double shadowOpacity;
  final Color bubbleBorder;

  const _AudioMessageBubble({
    required this.audioUrl,
    required this.duration,
    required this.isMe,
    required this.timestamp,
    required this.isRead,
    required this.audioPlayer,
    required this.meBubble,
    required this.otherBubble,
    required this.meText,
    required this.otherText,
    required this.metaText,
    required this.readTick,
    required this.shadowOpacity,
    required this.bubbleBorder,
  });

  @override
  State<_AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<_AudioMessageBubble> {
  PlayerState? _playerState;
  StreamSubscription? _sub;
  String? _playingUrl;

  @override
  void initState() {
    super.initState();
    _sub = widget.audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (_playingUrl == widget.audioUrl) {
        setState(() => _playerState = state);
      } else if (_playerState == PlayerState.playing) {
        setState(() => _playerState = PlayerState.stopped);
      }
    });

    widget.audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      if (_playingUrl == widget.audioUrl) {
        setState(() {
          _playerState = PlayerState.completed;
          _playingUrl = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_playingUrl == widget.audioUrl) {
      widget.audioPlayer.stop();
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      final isPlaying = (_playerState == PlayerState.playing) &&
          (_playingUrl == widget.audioUrl);

      if (isPlaying) {
        await widget.audioPlayer.pause();
        if (mounted) setState(() => _playingUrl = null);
        return;
      }

      if (widget.audioPlayer.state == PlayerState.playing) {
        await widget.audioPlayer.stop();
      }

      await widget.audioPlayer.play(UrlSource(widget.audioUrl));
      if (mounted) setState(() => _playingUrl = widget.audioUrl);
    } catch (e) {
      debugPrint("Ses oynatma hatası: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ses dosyası oynatılamadı.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() {
        _playerState = PlayerState.stopped;
        _playingUrl = null;
      });
    }
  }

  String _fmtDuration(int seconds) {
    final m = (seconds / 60).floor();
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '';
    return DateFormat('HH:mm').format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    final bool isPlaying = (_playerState == PlayerState.playing) &&
        (_playingUrl == widget.audioUrl);
    final bubble = widget.isMe ? widget.meBubble : widget.otherBubble;
    final txt = widget.isMe ? widget.meText : widget.otherText;

    return Column(
      crossAxisAlignment:
      widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: bubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: widget.isMe ? const Radius.circular(16) : Radius.zero,
              bottomRight: widget.isMe ? Radius.zero : const Radius.circular(16),
            ),
            border: Border.all(color: widget.bubbleBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(widget.shadowOpacity),
                blurRadius: 6,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _toggle,
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                    color: txt),
                visualDensity: VisualDensity.compact,
              ),
              Text(_fmtDuration(widget.duration),
                  style: TextStyle(color: txt.withOpacity(0.85))),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_fmtTs(widget.timestamp),
                  style: TextStyle(fontSize: 12, color: widget.metaText)),
              if (widget.isMe) ...[
                const SizedBox(width: 4),
                Icon(Icons.done_all,
                    size: 16,
                    color: widget.isRead ? widget.readTick : widget.metaText),
              ]
            ],
          ),
        ),
      ],
    );
  }
}
