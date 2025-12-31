import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthProviderAdapter {
  final GoogleSignIn _googleSignIn;

  GoogleAuthProviderAdapter({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email', 'profile']);

  Future<AuthCredential> getCredential() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('cancelled');
    }

    final auth = await account.authentication;
    final idToken = auth.idToken;
    final accessToken = auth.accessToken;

    if (idToken == null && accessToken == null) {
      throw Exception('Google token alınamadı.');
    }

    return GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<void> signOutSilently() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}
