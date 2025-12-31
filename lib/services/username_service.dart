import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_exceptions.dart';
import '../core/tr_lower.dart';

class UsernameService {
  UsernameService({FirebaseFirestore? fs})
      : _fs = fs ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;

  /// username normalize: trim + trLower
  String normalize(String username) => trLower(username.trim());

  /// Sadece UX için (asıl doğruluk transaction’da)
  Future<bool> isTaken(String usernameLower) async {
    final doc = await _fs.collection('usernames').doc(usernameLower).get();
    return doc.exists;
  }

  /// Transaction içinde username rezerve et
  Future<void> reserveTx({
    required Transaction tx,
    required String usernameLower,
    required String uid,
  }) async {
    final ref = _fs.collection('usernames').doc(usernameLower);
    final snap = await tx.get(ref);
    if (snap.exists) throw UsernameTakenException();
    tx.set(ref, {'uid': uid});
  }
}
