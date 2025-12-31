import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  final FirebaseFirestore _db;

  UserService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> userRef(String uid) =>
      _db.collection('users').doc(uid);

  Future<void> upsertFromFirebaseUser({
    required User user,
    required String providerId,
    String? displayName,
    String? photoUrl,
  }) async {
    final ref = userRef(user.uid);
    final snap = await ref.get();

    final now = FieldValue.serverTimestamp();

    final base = <String, dynamic>{
      'uid': user.uid,
      'email': user.email,
      'providers': FieldValue.arrayUnion([providerId]),
      'lastLoginAt': now,
    };

    if (!snap.exists) {
      // create
      final create = <String, dynamic>{
        ...base,
        'createdAt': now,
        'name': (displayName?.trim().isNotEmpty == true)
            ? displayName!.trim()
            : (user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : null),
        'photoUrl': (photoUrl?.trim().isNotEmpty == true)
            ? photoUrl!.trim()
            : (user.photoURL?.trim().isNotEmpty == true ? user.photoURL!.trim() : null),

        // TechConnect özelinde başlangıç alanları (istersen sadeleştir)
        'type': 'individual', // veya senin sisteminde default neyse
        'isCompany': false,
        'premiumUntil': null,
      }..removeWhere((k, v) => v == null);

      await ref.set(create, SetOptions(merge: true));
      return;
    }

    // update
    final update = <String, dynamic>{
      ...base,
    };

    // Sadece boşsa doldur: user’ın adı/foto’su sonradan gelmeyebilir (Apple)
    final data = snap.data() ?? {};
    final existingName = (data['name'] ?? '')?.toString().trim();
    final existingPhoto = (data['photoUrl'] ?? '')?.toString().trim();

    final resolvedName = (displayName?.trim().isNotEmpty == true)
        ? displayName!.trim()
        : (user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : null);

    final resolvedPhoto = (photoUrl?.trim().isNotEmpty == true)
        ? photoUrl!.trim()
        : (user.photoURL?.trim().isNotEmpty == true ? user.photoURL!.trim() : null);

    if ((existingName == null || existingName.isEmpty) && (resolvedName?.isNotEmpty == true)) {
      update['name'] = resolvedName;
    }

    if ((existingPhoto == null || existingPhoto.isEmpty) && (resolvedPhoto?.isNotEmpty == true)) {
      update['photoUrl'] = resolvedPhoto;
    }

    await ref.set(update, SetOptions(merge: true));
  }
}
