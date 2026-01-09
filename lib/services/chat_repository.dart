import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ChatRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ChatRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get myUid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> chatRef(String chatId) =>
      _firestore.collection('chats').doc(chatId);

  CollectionReference<Map<String, dynamic>> messagesRef(String chatId) =>
      chatRef(chatId).collection('messages');

  /// ✅ unread reset + bozuk literal alan temizliği
  Future<void> resetUnreadForMe(String chatId) async {
    final uid = myUid;
    if (uid == null) return;

    try {
      // doğru şema
      await chatRef(chatId).update({
        'unread.$uid': 0,
      });

      // bazı eski set/merge hatasıyla oluşan literal alanı silmeye çalışma
      // (Firestore'da "unread.<uid>" diye ayrı alan açılmışsa)
      // Not: Her projede çalışır; bazı edge-case'lerde sessizce fail olabilir, sorun değil.
      await chatRef(chatId).update({
        FieldPath(['unread.$uid']): FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('DEBUG[repo] resetUnreadForMe error: $e');
    }
  }

  /// ✅ Lazy migration: unread map yoksa oluştur / eksik uid varsa ekle
  Future<void> ensureUnreadMap({
    required Transaction tx,
    required DocumentReference<Map<String, dynamic>> chatRef,
    required List<String> users,
    required Map<String, dynamic> chatData,
  }) async {
    final unreadRaw = chatData['unread'];

    if (unreadRaw is! Map) {
      tx.set(
        chatRef,
        {
          'unread': {for (final u in users) u: 0},
        },
        SetOptions(merge: true),
      );
      return;
    }

    final unreadMap = Map<String, dynamic>.from(unreadRaw);
    final patch = <String, int>{};

    for (final u in users) {
      if (!unreadMap.containsKey(u)) patch[u] = 0;
    }

    if (patch.isNotEmpty) {
      tx.set(
        chatRef,
        {'unread': patch},
        SetOptions(merge: true),
      );
    }
  }

  /// ✅ Mesaj yaz + lastMessage + unread increment (WP mantığı)
  Future<void> writeMessageBatch({
    required String chatId,
    required String otherUid,
    required Map<String, dynamic> messageData,
    required String lastMessagePreview,
    required String lastMessageType,
  }) async {
    final uid = myUid;
    if (uid == null) return;

    final other = otherUid.trim();
    if (other.isEmpty) return;

    final cRef = chatRef(chatId);
    final mRef = messagesRef(chatId).doc();

    await _firestore.runTransaction((tx) async {
      final chatSnap = await tx.get(cRef);
      final chatData = chatSnap.data() ?? <String, dynamic>{};

      final users = List<String>.from(chatData['users'] ?? <String>[uid, other]);
      if (!users.contains(uid)) users.add(uid);
      if (!users.contains(other)) users.add(other);

      await ensureUnreadMap(
        tx: tx,
        chatRef: cRef,
        users: users,
        chatData: chatData,
      );

      // 1) message
      tx.set(mRef, {
        ...messageData,
        'senderId': uid,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // 2) chat meta + unread update
      tx.set(
        cRef,
        {
          'users': users,
          'hasMessages': true,
          'lastMessage': lastMessagePreview,
          'lastMessageType': lastMessageType,
          'lastMessageSenderId': uid,
          'lastMessageTimestamp': FieldValue.serverTimestamp(),

          // WP: karşı tarafın unread++ , sende 0
          'unread.$other': FieldValue.increment(1),
          'unread.$uid': 0,
        },
        SetOptions(merge: true),
      );
    });
  }

  /// ✅ Okundu: mesajların isRead true + chat unread sıfırla
  Future<void> markMessagesAsRead({
    required String chatId,
    required String otherUid,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> messages,
  }) async {
    final uid = myUid;
    if (uid == null) return;

    final other = otherUid.trim();
    if (other.isEmpty) return;

    final batch = _firestore.batch();
    bool needsCommit = false;

    for (final doc in messages) {
      final data = doc.data();
      final senderId = (data['senderId'] ?? '').toString();
      final isRead = data['isRead'] == true;

      if (senderId == other && !isRead) {
        batch.update(doc.reference, {'isRead': true});
        needsCommit = true;
      }
    }

    if (!needsCommit) {
      // yine de unread garantile
      await resetUnreadForMe(chatId);
      return;
    }

    try {
      await batch.commit();
    } catch (e) {
      debugPrint('DEBUG[repo] markMessagesAsRead batch error: $e');
    }

    await resetUnreadForMe(chatId);
  }

  /// Chat stream helper
  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String chatId) {
    return messagesRef(chatId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}
