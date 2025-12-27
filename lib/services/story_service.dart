import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class StoryService {
  StoryService._();

  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static final _storage = FirebaseStorage.instance;

  static CollectionReference<Map<String, dynamic>> _itemsCol(String uid) =>
      _db.collection('stories').doc(uid).collection('items');

  static DocumentReference<Map<String, dynamic>> _ownerMetaDoc(String uid) =>
      _db.collection('stories').doc(uid);

  static CollectionReference<Map<String, dynamic>> _connectionsCol(String uid) =>
      _db.collection('connections').doc(uid).collection('list');

  static CollectionReference<Map<String, dynamic>> _storyFeedItemsCol(String viewerUid) =>
      _db.collection('storyFeed').doc(viewerUid).collection('items');

  static String _uidOrThrow() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Giriş yapmış kullanıcı yok.');
    return uid;
  }

  static String _guessExt({required bool isVideo}) => isVideo ? 'mp4' : 'jpg';

  static String _storagePath({
    required String uid,
    required String itemId,
    required String ext,
  }) =>
      'stories/$uid/$itemId.$ext';

  static Future<String> addStory({
    File? file,
    Uint8List? bytes,
    required bool isVideo,
    String? caption,
    int ttlHours = 24,
  }) async {
    final uid = _uidOrThrow();

    if (file == null && bytes == null) {
      throw ArgumentError('file veya bytes vermelisin.');
    }

    final itemRef = _itemsCol(uid).doc();
    final itemId = itemRef.id;

    final ext = _guessExt(isVideo: isVideo);
    final storagePath = _storagePath(uid: uid, itemId: itemId, ext: ext);
    final storageRef = _storage.ref(storagePath);

    UploadTask task;

    if (kIsWeb) {
      if (bytes == null) throw ArgumentError('Web için bytes zorunlu.');
      final meta = SettableMetadata(contentType: isVideo ? 'video/mp4' : 'image/jpeg');
      task = storageRef.putData(bytes, meta);
    } else {
      if (file == null) throw ArgumentError('Mobil için file zorunlu.');
      final meta = SettableMetadata(contentType: isVideo ? 'video/mp4' : 'image/jpeg');
      task = storageRef.putFile(file, meta);
    }

    final snap = await task;
    final url = await snap.ref.getDownloadURL();

    final expiresAt = Timestamp.fromDate(DateTime.now().add(Duration(hours: ttlHours)));

    await itemRef.set({
      'type': isVideo ? 'video' : 'image',
      'mediaUrl': url,
      'storagePath': storagePath,
      'caption': (caption ?? '').trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      'ownerUid': uid,
    }, SetOptions(merge: true));

    await _ownerMetaDoc(uid).set({
      'ownerUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      'lastItemId': itemId,
      'lastType': isVideo ? 'video' : 'image',
      'lastMediaUrl': url,
    }, SetOptions(merge: true));

    return itemId;
  }

  static Future<void> deleteStoryItem({
    required String ownerUid,
    required String itemId,
  }) async {
    final itemDoc = await _itemsCol(ownerUid).doc(itemId).get();
    if (!itemDoc.exists) return;

    final data = itemDoc.data() ?? {};
    final storagePath = (data['storagePath'] ?? '') as String;

    await _itemsCol(ownerUid).doc(itemId).delete();

    if (storagePath.isNotEmpty) {
      try {
        await _storage.ref(storagePath).delete();
      } catch (_) {}
    }

    await _ownerMetaDoc(ownerUid).set({
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMyStoryItems({
    int limit = 50,
    bool onlyNotExpired = true,
  }) {
    final uid = _uidOrThrow();

    Query<Map<String, dynamic>> q =
    _itemsCol(uid).orderBy('createdAt', descending: true).limit(limit);

    if (onlyNotExpired) {
      q = q.where('expiresAt', isGreaterThan: Timestamp.now());
    }

    return q.snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamStoryItemsOfUser({
    required String ownerUid,
    int limit = 50,
    bool onlyNotExpired = true,
  }) {
    Query<Map<String, dynamic>> q =
    _itemsCol(ownerUid).orderBy('createdAt', descending: false).limit(limit);

    if (onlyNotExpired) {
      q = q.where('expiresAt', isGreaterThan: Timestamp.now());
    }

    return q.snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamStoryFeedForMe({
    int limit = 50,
    bool onlyNotExpired = true,
  }) {
    final uid = _uidOrThrow();

    Query<Map<String, dynamic>> q =
    _storyFeedItemsCol(uid).orderBy('updatedAt', descending: true).limit(limit);

    if (onlyNotExpired) {
      q = q.where('expiresAt', isGreaterThan: Timestamp.now());
    }

    return q.snapshots();
  }

  static Future<List<Map<String, dynamic>>> fetchStoriesMetaFromConnections({
    int limitConnections = 80,
  }) async {
    final uid = _uidOrThrow();

    final conSnap =
    await _connectionsCol(uid).limit(limitConnections).get();

    if (conSnap.docs.isEmpty) return [];

    final futures = conSnap.docs.map((d) {
      return _ownerMetaDoc(d.id).get();
    }).toList();

    final snaps = await Future.wait(futures);

    final out = <Map<String, dynamic>>[];

    for (final s in snaps) {
      if (!s.exists) continue;

      final data = s.data()!;
      final exp = data['expiresAt'];

      if (exp is Timestamp && exp.toDate().isBefore(DateTime.now())) {
        continue;
      }

      out.add(data);
    }

    out.sort((a, b) {
      final ta = a['updatedAt'] as Timestamp?;
      final tb = b['updatedAt'] as Timestamp?;

      final da = ta?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = tb?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

      return db.compareTo(da);
    });

    return out;
  }

  static Future<bool> isConnectedWith(String otherUid) async {
    final uid = _uidOrThrow();
    final doc = await _connectionsCol(uid).doc(otherUid).get();
    return doc.exists;
  }
}
