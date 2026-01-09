import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'chat_repository.dart';

class ChatMediaService {
  final FirebaseStorage _storage;
  final ChatRepository _repo;

  ChatMediaService({
    FirebaseStorage? storage,
    required ChatRepository repo,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _repo = repo;

  String detectFileType(String ext) {
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

  String getFileIconAsset(String fileName) {
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

  String formatFileSize(int bytes) {
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

  Future<String> _uploadFile({
    required File file,
    required String folder,
    required String chatId,
    required String fileName,
  }) async {
    final ref = _storage.ref().child('$folder/$chatId/$fileName');
    final snap = await ref.putFile(file).whenComplete(() {});
    return await snap.ref.getDownloadURL();
  }

  /// ✅ Dosyayı upload eder, sonra repo ile mesajı yazar (unread + lastMessage dahil)
  Future<void> uploadAndSendMedia({
    required String chatId,
    required String otherUid,
    required File file,
    required String folder,
    required String messageType,
    required String lastMessagePreview,
    String? originalName,
    int? size,
  }) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${originalName ?? 'media'}';
      final url = await _uploadFile(
        file: file,
        folder: folder,
        chatId: chatId,
        fileName: fileName,
      );

      final data = <String, dynamic>{'type': messageType};

      if (messageType == 'image') {
        data['imageUrl'] = url;
      } else if (messageType == 'video') {
        data['videoUrl'] = url;
      } else if (messageType == 'audio') {
        data['audioUrl'] = url;
        if (size != null) data['fileSize'] = size;
      } else {
        data['fileUrl'] = url;
        data['fileName'] = originalName ?? 'Dosya';
        if (size != null) data['fileSize'] = size;
      }

      await _repo.writeMessageBatch(
        chatId: chatId,
        otherUid: otherUid,
        messageData: data,
        lastMessagePreview: lastMessagePreview,
        lastMessageType: messageType,
      );
    } catch (e) {
      debugPrint('DEBUG[media] uploadAndSendMedia error: $e');
      rethrow;
    }
  }
}
