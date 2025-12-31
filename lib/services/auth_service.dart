import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> login({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Register akışında Firestore transaction patlarsa “hayalet auth user” bırakmamak için.
  Future<void> deleteCurrentUserIfAny() async {
    final u = _auth.currentUser;
    if (u == null) return;
    try {
      await u.delete();
    } catch (_) {
      // requires-recent-login gibi durumlarda patlayabilir.
      // Yeni oluşturulan kullanıcıda genelde sorun çıkmaz.
    }
  }
}
