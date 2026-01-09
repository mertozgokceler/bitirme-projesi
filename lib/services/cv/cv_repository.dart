import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CvInfo {
  final String url;
  final String? fileName;
  final String? storagePath;
  final DateTime? updatedAt;

  const CvInfo({
    required this.url,
    this.fileName,
    this.storagePath,
    this.updatedAt,
  });

  bool get hasCv => url.trim().isNotEmpty;
}

class CvRepository {
  final FirebaseFirestore _fs;
  final FirebaseStorage _st;

  CvRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _st = storage ?? FirebaseStorage.instance;

  // ---------------------------
  // Premium
  // ---------------------------
  /// users/{uid}.premiumUntil (Timestamp) -> şimdi'den büyükse premium aktif
  Future<bool> isPremiumActive(String uid) async {
    final doc = await _fs.collection('users').doc(uid).get();
    final data = doc.data();

    final premiumUntil = data?['premiumUntil'];
    if (premiumUntil is! Timestamp) return false;

    return premiumUntil.toDate().isAfter(DateTime.now());
  }

  Timestamp _startOfTodayTs() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return Timestamp.fromDate(startOfDay);
  }

  /// Bugün kaç analiz yapılmış? (createdAt >= startOfDay)
  /// ✅ Index uyumu için orderBy ekliyoruz (uid + createdAt DESC index'ini kullanır)
  /// Not: createdAt serverTimestamp ile yazılıyor.
  Future<int> countTodayAnalyses(String uid) async {
    final startTs = _startOfTodayTs();

    try {
      final agg = await _fs
          .collection('cvAnalyses')
          .where('uid', isEqualTo: uid)
          .where('createdAt', isGreaterThanOrEqualTo: startTs)
          .orderBy('createdAt', descending: true)
          .count()
          .get();

      // ✅ null gelirse 0 bas
      final c = agg.count;
      return c == null ? 0 : c;
    } catch (_) {
      // ✅ fallback: normal query
      final q = await _fs
          .collection('cvAnalyses')
          .where('uid', isEqualTo: uid)
          .where('createdAt', isGreaterThanOrEqualTo: startTs)
          .orderBy('createdAt', descending: true)
          .get();

      return q.docs.length;
    }
  }

  // ---------------------------
  // CV Resolve
  // ---------------------------
  /// CV bulma stratejisi:
  /// A) users doc içinde cvPdfUrl/cvPdfStoragePath varsa direkt kullan.
  /// B) yoksa Storage'da users/{uid}/cv/ klasörünü listele, en yeni PDF'i bul.
  ///    Bulursa users doc'una yazar (bundan sonra tanır).
  Future<CvInfo?> resolveCvFromFirestoreOrStorage(String uid) async {
    final userDocRef = _fs.collection('users').doc(uid);

    final userDoc = await userDocRef.get();
    final data = userDoc.data();

    final url = data?['cvPdfUrl'] as String?;
    final name = data?['cvPdfFileName'] as String?;
    final path = data?['cvPdfStoragePath'] as String?;
    final ts = data?['cvPdfUpdatedAt'];

    DateTime? dt;
    if (ts is Timestamp) dt = ts.toDate();

    if (url != null && url.trim().isNotEmpty) {
      return CvInfo(url: url, fileName: name, storagePath: path, updatedAt: dt);
    }

    // Storage list fallback
    final folderRef = _st.ref('users/$uid/cv');
    final list = await folderRef.listAll();

    if (list.items.isEmpty) return null;

    Reference? newestRef;
    DateTime? newestTime;

    for (final item in list.items) {
      try {
        final meta = await item.getMetadata();
        final updated = meta.updated;
        if (updated == null) continue;

        if (newestTime == null || updated.isAfter(newestTime!)) {
          newestTime = updated;
          newestRef = item;
        }
      } catch (_) {}
    }

    newestRef ??= list.items.first;

    final foundUrl = await newestRef!.getDownloadURL();
    final foundName = newestRef.name;
    final foundPath = newestRef.fullPath;

    // users doc'a yaz
    await userDocRef.set({
      'cvPdfUrl': foundUrl,
      'cvPdfFileName': foundName,
      'cvPdfStoragePath': foundPath,
      'cvPdfUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return CvInfo(
      url: foundUrl,
      fileName: foundName,
      storagePath: foundPath,
      updatedAt: newestTime,
    );
  }

  // ---------------------------
  // Upload / Delete
  // ---------------------------
  Future<CvInfo> uploadCvPdf({
    required String uid,
    required Uint8List bytes,
    required String originalFileName,
  }) async {
    final safeName =
    originalFileName.replaceAll(RegExp(r'[^a-zA-Z0-9\.\-_ ]'), '_');
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final path = 'users/$uid/cv/${nowMs}_$safeName';
    final ref = _st.ref(path);

    final meta = SettableMetadata(
      contentType: 'application/pdf',
      customMetadata: {'originalFileName': originalFileName},
    );

    final task = await ref.putData(bytes, meta);
    final url = await task.ref.getDownloadURL();

    await _fs.collection('users').doc(uid).set({
      'cvPdfUrl': url,
      'cvPdfFileName': originalFileName,
      'cvPdfStoragePath': path,
      'cvPdfUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return CvInfo(
      url: url,
      fileName: originalFileName,
      storagePath: path,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> deleteCv({
    required String uid,
    String? storagePathFromState,
  }) async {
    final docRef = _fs.collection('users').doc(uid);

    // önce doc'tan path oku (state boş olabilir)
    final doc = await docRef.get();
    final path =
        (doc.data()?['cvPdfStoragePath'] as String?) ?? storagePathFromState;

    if (path != null && path.trim().isNotEmpty) {
      await _st.ref(path).delete();
    }

    await docRef.set({
      'cvPdfUrl': FieldValue.delete(),
      'cvPdfFileName': FieldValue.delete(),
      'cvPdfUpdatedAt': FieldValue.delete(),
      'cvPdfStoragePath': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  // ---------------------------
  // Analyses
  // ---------------------------
  Future<({String id, Map<String, dynamic> data})?> loadLatestAnalysis(
      String uid) async {
    final q = await _fs
        .collection('cvAnalyses')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;

    final doc = q.docs.first;
    return (id: doc.id, data: doc.data());
  }

  Future<String> createAnalysis({
    required String uid,
    required String cvUrl,
    String? targetRole,
  }) async {
    final ref = await _fs.collection('cvAnalyses').add({
      'uid': uid,
      'cvUrl': cvUrl,
      'targetRole': targetRole,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'queued',
    });
    return ref.id;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchAnalysis(String analysisId) {
    return _fs.collection('cvAnalyses').doc(analysisId).snapshots();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchHistory({
    required String uid,
    int limit = 25,
  }) async {
    final q = await _fs
        .collection('cvAnalyses')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return q.docs;
  }
}
