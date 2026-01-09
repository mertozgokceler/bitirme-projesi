import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/call_service.dart';
import '../services/call_controller.dart';
import '../services/chat_repository.dart';
import '../services/chat_media_service.dart';

import '../widgets/chat/audio_message_bubble.dart';
import '../widgets/chat/message_bubbles.dart';

import 'call_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final Map<String, dynamic> otherUser;
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

class ChatBgPreset {
  final List<Color> light;
  final List<Color> dark;
  const ChatBgPreset({required this.light, required this.dark});
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _messageController = TextEditingController();

  final _auth = FirebaseAuth.instance;

  late final ChatRepository _repo;
  late final ChatMediaService _media;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _imagePicker = ImagePicker();

  CallController? _callController;
  bool _startingCall = false;

  bool _isComposing = false;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordDuration = 0;
  String? _recordingPath;

  Map<String, dynamic>? _currentUserData;
  bool _isLoadingUserData = true;

  int _selectedBackgroundIndex = 0;
  String get _bgPrefsKey => 'chat_bg_v2_${widget.chatId}';

  final List<ChatBgPreset> _bgPresets = const [
    ChatBgPreset(
      light: [Color(0xFFF4EFEF), Color(0xFFFFFFFF)],
      dark: [Color(0xFF060A14), Color(0xFF1A2A5E)],
    ),
    ChatBgPreset(
      light: [Color(0xFFE8F5E9), Color(0xFFFFFFFF)],
      dark: [Color(0xFF04110A), Color(0xFF0E3B25)],
    ),
    ChatBgPreset(
      light: [Color(0xFFE3F2FD), Color(0xFFFFFFFF)],
      dark: [Color(0xFF070B12), Color(0xFF2C1B4A)],
    ),
    ChatBgPreset(
      light: [Color(0xFFFFF8E1), Color(0xFFFFFFFF)],
      dark: [Color(0xFF120A05), Color(0xFF4A240E)],
    ),
  ];

  ChatBgPreset get _preset {
    final i = _selectedBackgroundIndex.clamp(0, _bgPresets.length - 1);
    return _bgPresets[i];
  }

  // ✅ Okundu throttle (rebuild spam engeli)
  Timer? _readThrottle;
  String? _lastReadSignature;

  @override
  void initState() {
    super.initState();

    _repo = ChatRepository();
    _media = ChatMediaService(repo: _repo);

    // sohbet açılınca unread reset
    _repo.resetUnreadForMe(widget.chatId);

    _loadBg();
    _loadCurrentUserData();

    _messageController.addListener(() {
      final isNotEmpty = _messageController.text.trim().isNotEmpty;
      if (_isComposing != isNotEmpty) {
        if (mounted) setState(() => _isComposing = isNotEmpty);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _audioPlayer.dispose();
    _readThrottle?.cancel();
    super.dispose();
  }

  Future<void> _loadBg() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt(_bgPrefsKey);
      if (!mounted) return;
      if (idx != null && idx >= 0 && idx < _bgPresets.length) {
        setState(() => _selectedBackgroundIndex = idx);
      }
    } catch (_) {}
  }

  Future<void> _saveBg(int idx) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_bgPrefsKey, idx);
    } catch (_) {}
  }

  Future<void> _loadCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingUserData = false);
      return;
    }

    try {
      final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await doc.get();
      if (!mounted) return;
      setState(() {
        _currentUserData = snap.data();
        _isLoadingUserData = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingUserData = false);
    }
  }

  // ---------------------------
  // URL / Image preview
  // ---------------------------
  Future<void> _openUrlExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  // ---------------------------
  // ✅ Okundu (POST-FRAME + THROTTLE)
  // ---------------------------
  void _scheduleMarkRead(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // signature: en yeni mesaj id + count (yeter)
    final sig = '${docs.first.id}_${docs.length}';
    if (_lastReadSignature == sig) return;
    _lastReadSignature = sig;

    _readThrottle?.cancel();
    _readThrottle = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      final otherUid = (widget.otherUser['uid'] as String?)?.trim() ?? '';
      if (otherUid.isEmpty) return;
      await _repo.markMessagesAsRead(
        chatId: widget.chatId,
        otherUid: otherUid,
        messages: docs,
      );
    });
  }

  // ---------------------------
  // Send text
  // ---------------------------
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final otherUid = (widget.otherUser['uid'] as String?)?.trim();
    if (otherUid == null || otherUid.isEmpty) return;

    await _repo.writeMessageBatch(
      chatId: widget.chatId,
      otherUid: otherUid,
      messageData: {'type': 'text', 'text': text},
      lastMessagePreview: text,
      lastMessageType: 'text',
    );

    _messageController.clear();
  }

  // ---------------------------
  // Audio message record
  // ---------------------------
  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;

    try {
      final tempDir = Directory.systemTemp;
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
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_isRecording || !mounted) return;
        setState(() => _recordDuration++);
      });
    } catch (_) {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _stopRecordingAndSend() async {
    _recordingTimer?.cancel();
    String? path;

    final otherUid = (widget.otherUser['uid'] as String?)?.trim();
    if (otherUid == null || otherUid.isEmpty) return;

    try {
      path = await _audioRecorder.stop();
      if (mounted) setState(() => _isRecording = false);

      if (path == null || _recordDuration <= 0) return;

      final file = File(path);
      if (!await file.exists()) return;

      // audio upload + send
      await _media.uploadAndSendMedia(
        chatId: widget.chatId,
        otherUid: otherUid,
        file: file,
        folder: 'chat_audio',
        messageType: 'audio',
        lastMessagePreview: 'Sesli mesaj',
        originalName: 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
    } catch (_) {
      // ignore
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

  // ---------------------------
  // Attachments
  // ---------------------------
  Future<void> _pickAndSendAttachment() async {
    final otherUid = (widget.otherUser['uid'] as String?)?.trim();
    if (otherUid == null || otherUid.isEmpty) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg', 'jpeg', 'png', 'heic', 'webp',
        'mp4', 'mov', 'mkv',
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
        'zip', 'rar', '7z', 'txt', 'rtf',
        'mp3', 'wav', 'aac', 'm4a',
      ],
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final path = picked.path;
    if (path == null) return;

    final file = File(path);
    final ext = (picked.extension ?? '').toLowerCase();
    final detected = _media.detectFileType(ext);

    String folder;
    String messageType;
    String lastMessagePreview;

    switch (detected) {
      case 'image':
        folder = 'chat_images';
        messageType = 'image';
        lastMessagePreview = 'Fotoğraf';
        break;
      case 'video':
        folder = 'chat_videos';
        messageType = 'video';
        lastMessagePreview = 'Video';
        break;
      case 'audio':
        folder = 'chat_audio';
        messageType = 'audio';
        lastMessagePreview = 'Sesli mesaj';
        break;
      default:
        folder = 'chat_files';
        messageType = detected; // pdf/word/excel/powerpoint/archive/file...
        lastMessagePreview = detected.toUpperCase();
        break;
    }

    await _media.uploadAndSendMedia(
      chatId: widget.chatId,
      otherUid: otherUid,
      file: file,
      folder: folder,
      messageType: messageType,
      lastMessagePreview: lastMessagePreview,
      originalName: picked.name,
      size: picked.size,
    );
  }

  Future<void> _pickFromCamera() async {
    final otherUid = (widget.otherUser['uid'] as String?)?.trim();
    if (otherUid == null || otherUid.isEmpty) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
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
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'photo') {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (picked == null) return;
      final file = File(picked.path);

      await _media.uploadAndSendMedia(
        chatId: widget.chatId,
        otherUid: otherUid,
        file: file,
        folder: 'chat_images',
        messageType: 'image',
        lastMessagePreview: 'Fotoğraf',
        originalName: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } else {
      final picked = await _imagePicker.pickVideo(source: ImageSource.camera);
      if (picked == null) return;
      final file = File(picked.path);

      await _media.uploadAndSendMedia(
        chatId: widget.chatId,
        otherUid: otherUid,
        file: file,
        folder: 'chat_videos',
        messageType: 'video',
        lastMessagePreview: 'Video',
        originalName: 'camera_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
    }
  }

  // ---------------------------
  // Build
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isDark = t.brightness == Brightness.dark;

    final myUid = _auth.currentUser?.uid;
    if (myUid == null) {
      return const Scaffold(body: Center(child: Text('Giriş gerekli.')));
    }

    final otherName =
    (widget.otherUser['name'] ?? widget.otherUser['username'] ?? 'Sohbet')
        .toString();
    final otherPhotoUrl = (widget.otherUser['photoUrl'] as String?) ?? '';

    final preset = _preset;
    final bgColors = isDark ? preset.dark : preset.light;

    final meBubble = isDark
        ? const Color(0xFFE57AFF).withOpacity(0.30)
        : const Color(0xFFE57AFF).withOpacity(0.22);
    final otherBubble = isDark
        ? t.colorScheme.surfaceVariant.withOpacity(0.88)
        : Colors.white.withOpacity(0.92);
    final meText = Colors.white;
    final otherText = t.textTheme.bodyLarge?.color ??
        (isDark ? Colors.white : Colors.black87);
    final metaText = isDark ? Colors.white60 : Colors.black45;
    final readTick = t.colorScheme.primary;
    final bubbleBorder = isDark ? Colors.white10 : Colors.black12;
    final shadowOpacity = isDark ? 0.20 : 0.06;

    // accent blend
    final accent = isDark ? preset.dark.last : preset.light.first;

    Color bubbleColor(bool isMe) {
      if (isMe) {
        return Color.alphaBlend(
            accent.withOpacity(isDark ? 0.18 : 0.10), meBubble);
      }
      return Color.alphaBlend(
          accent.withOpacity(isDark ? 0.12 : 0.06), otherBubble);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark
            ? t.colorScheme.surface.withOpacity(0.92)
            : t.colorScheme.surface.withOpacity(0.78),
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage:
              otherPhotoUrl.isNotEmpty ? NetworkImage(otherPhotoUrl) : null,
              child: otherPhotoUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 12),
            Text(otherName,
                style: t.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          // ✅ SESLİ ARAMA GERİ GELDİ
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: _startingCall
                ? null
                : () async {
              final otherUid =
                  (widget.otherUser['uid'] as String?)?.trim() ?? '';
              if (otherUid.isEmpty) return;
              if (_callController != null) return;

              final mic = await Permission.microphone.request();
              if (!mic.isGranted) return;

              setState(() => _startingCall = true);

              try {
                final controller = CallController(widget.callService);
                _callController = controller;

                final meName =
                (_currentUserData?['name'] ??
                    _currentUserData?['username'] ??
                    'User')
                    .toString();

                await controller.startOutgoing(
                  calleeId: otherUid,
                  calleeName: otherName,
                  callerName: meName,
                  type: CallType.audio,
                  onRemoteEnded: () {
                    // CallScreen zaten auto-close dinliyor, ama kalsın.
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
              } catch (_) {
                try {
                  await _callController?.disposeAll(writeEnded: false);
                } catch (_) {}
                _callController = null;
              } finally {
                if (mounted) setState(() => _startingCall = false);
              }
            },
          ),

          // ✅ VIDEO ARAMA (mevcut kodun aynısı)
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: _startingCall
                ? null
                : () async {
              final otherUid =
                  (widget.otherUser['uid'] as String?)?.trim() ?? '';
              if (otherUid.isEmpty) return;
              if (_callController != null) return;

              final mic = await Permission.microphone.request();
              final cam = await Permission.camera.request();
              if (!mic.isGranted || !cam.isGranted) return;

              setState(() => _startingCall = true);

              try {
                final controller = CallController(widget.callService);
                _callController = controller;

                final meName =
                (_currentUserData?['name'] ??
                    _currentUserData?['username'] ??
                    'User')
                    .toString();

                await controller.startOutgoing(
                  calleeId: otherUid,
                  calleeName: otherName,
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
              } catch (_) {
                try {
                  await _callController?.disposeAll(writeEnded: false);
                } catch (_) {}
                _callController = null;
              } finally {
                if (mounted) setState(() => _startingCall = false);
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
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
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _repo.messagesStream(widget.chatId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child: Text('Hata: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData ||
                        snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('Henüz mesaj yok.'));
                    }

                    final docs = snapshot.data!.docs;

                    // ✅ build içinde yazma yok → post-frame + throttle
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _scheduleMarkRead(docs);
                    });

                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();

                        final deletedFor =
                            (data['deletedFor'] as List?) ?? const [];
                        if (deletedFor.contains(myUid)) {
                          return const SizedBox.shrink();
                        }

                        final isMe = (data['senderId'] ?? '') == myUid;
                        final ts = data['timestamp'] as Timestamp?;
                        final isRead = data['isRead'] == true;
                        final type = (data['type'] as String? ?? 'text')
                            .toLowerCase();

                        final myPhotoUrl =
                            (_currentUserData?['photoUrl'] as String?) ??
                                '';
                        final avatarUrl =
                        isMe ? myPhotoUrl : otherPhotoUrl;

                        Widget content;

                        if (type == 'audio') {
                          final url = (data['audioUrl'] ?? '').toString();
                          final duration =
                              (data['duration'] as num?)?.toInt() ?? 0;
                          content = AudioMessageBubble(
                            audioUrl: url,
                            duration: duration,
                            isMe: isMe,
                            timestamp: ts,
                            isRead: isRead,
                            audioPlayer: _audioPlayer,
                            meBubble: meBubble,
                            otherBubble: otherBubble,
                            meText: meText,
                            otherText: otherText,
                            metaText: metaText,
                            readTick: readTick,
                            shadowOpacity: shadowOpacity,
                            bubbleBorder: bubbleBorder,
                          );
                        } else if (type == 'image') {
                          final url =
                          (data['imageUrl'] ?? '').toString();
                          content = MessageBubbles.imageBubble(
                            url: url,
                            isMe: isMe,
                            timestamp: ts,
                            isRead: isRead,
                            onPreview: _showImagePreview,
                            metaText: metaText,
                            readTick: readTick,
                          );
                        } else if (type == 'video') {
                          final url =
                          (data['videoUrl'] ?? '').toString();
                          content = MessageBubbles.videoBubble(
                            url: url,
                            isMe: isMe,
                            timestamp: ts,
                            isRead: isRead,
                            openUrl: _openUrlExternal,
                            bubbleColor: bubbleColor(isMe),
                            bubbleBorder: bubbleBorder,
                            shadowOpacity: shadowOpacity,
                            meText: meText,
                            otherText: otherText,
                            metaText: metaText,
                            readTick: readTick,
                          );
                        } else if (type == 'pdf' ||
                            type == 'word' ||
                            type == 'excel' ||
                            type == 'powerpoint' ||
                            type == 'archive' ||
                            type == 'file') {
                          final fileUrl = data['fileUrl'] as String?;
                          final fileName =
                              (data['fileName'] as String?) ?? 'Dosya';
                          final iconPath =
                          _media.getFileIconAsset(fileName);

                          content = MessageBubbles.fileBubble(
                            fileName: fileName,
                            fileUrl: fileUrl,
                            iconPath: iconPath,
                            isMe: isMe,
                            timestamp: ts,
                            isRead: isRead,
                            openUrl: _openUrlExternal,
                            bubbleColor: bubbleColor(isMe),
                            bubbleBorder: bubbleBorder,
                            shadowOpacity: shadowOpacity,
                            meText: meText,
                            otherText: otherText,
                            metaText: metaText,
                            readTick: readTick,
                          );
                        } else {
                          final text = (data['text'] ?? '').toString();
                          content = MessageBubbles.textBubble(
                            text: text,
                            isMe: isMe,
                            timestamp: ts,
                            isRead: isRead,
                            bubbleColor: bubbleColor(isMe),
                            bubbleBorder: bubbleBorder,
                            shadowOpacity: shadowOpacity,
                            meText: meText,
                            otherText: otherText,
                            metaText: metaText,
                            readTick: readTick,
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe) ...[
                                CircleAvatar(
                                  radius: 16,
                                  backgroundImage: avatarUrl.isNotEmpty
                                      ? NetworkImage(avatarUrl)
                                      : null,
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
                                  backgroundImage: avatarUrl.isNotEmpty
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  child: avatarUrl.isEmpty
                                      ? const Icon(Icons.person, size: 18)
                                      : null,
                                ),
                              ],
                            ],
                          ),
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
    );
  }

  Widget _buildMessageInput(BuildContext context) {
    final t = Theme.of(context);
    final isDark = t.brightness == Brightness.dark;

    final inputBg =
    isDark ? t.colorScheme.surface.withOpacity(0.92) : Colors.white.withOpacity(0.95);
    final inputText =
        t.textTheme.bodyLarge?.color ?? (isDark ? Colors.white : Colors.black87);
    final hintText = (t.textTheme.bodyMedium?.color ??
        (isDark ? Colors.white70 : Colors.black54))
        .withOpacity(0.85);
    final iconMuted = hintText;
    final brand = const Color(0xFFE57AFF);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: _isRecording
                  ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.mic, color: Colors.redAccent),
                  Text('$_recordDuration s',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: inputText)),
                  Text('Kaydediliyor...', style: TextStyle(color: hintText)),
                ],
              )
                  : Row(
                children: [
                  Icon(Icons.emoji_emotions_outlined,
                      color: iconMuted, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: TextStyle(color: inputText),
                      cursorColor: brand,
                      decoration: InputDecoration(
                        hintText: 'Mesajınızı yazın…',
                        hintStyle: TextStyle(color: hintText),
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
                    icon: Icon(Icons.attach_file, color: iconMuted),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: _pickFromCamera,
                    icon: Icon(Icons.camera_alt_outlined, color: iconMuted),
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
              decoration: BoxDecoration(color: brand, shape: BoxShape.circle),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isComposing
                    ? const Icon(Icons.send,
                    key: ValueKey('send'),
                    color: Colors.white,
                    size: 22)
                    : Icon(_isRecording ? Icons.stop : Icons.mic,
                    key: const ValueKey('mic'),
                    color: Colors.white,
                    size: 25),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
