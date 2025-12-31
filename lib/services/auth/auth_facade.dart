import 'package:firebase_auth/firebase_auth.dart';

import 'auth_errors.dart';
import 'auth_types.dart';
import 'user_service.dart';

import 'providers/google_auth_provider.dart';
import 'providers/apple_auth_provider.dart';
import 'providers/github_auth_provider.dart';

class AuthFacade {
  final FirebaseAuth _auth;
  final UserService _userService;

  // Provider adapters
  final GoogleAuthProviderAdapter _google;
  final AppleAuthProviderAdapter _apple;
  final GithubAuthProviderAdapter _github;

  AuthFacade({
    FirebaseAuth? auth,
    UserService? userService,
    GoogleAuthProviderAdapter? google,
    AppleAuthProviderAdapter? apple,
    GithubAuthProviderAdapter? github,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _userService = userService ?? UserService(),
        _google = google ?? GoogleAuthProviderAdapter(),
        _apple = apple ?? AppleAuthProviderAdapter(),
        _github = github ??
            GithubAuthProviderAdapter(
              clientId: 'YOUR_GITHUB_CLIENT_ID',
              redirectScheme: 'techconnect',
              redirectPath: 'auth/github',
            );

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn(AuthProviderType type) async {
    try {
      switch (type) {
        case AuthProviderType.google:
          final cred = await _google.getCredential();
          final uc = await _auth.signInWithCredential(cred);
          await _afterSignIn(uc, providerId: type.firebaseProviderId);
          return uc;

        case AuthProviderType.apple:
          final apple = await _apple.getCredentialWithProfile();
          final uc = await _auth.signInWithCredential(apple.credential);
          await _afterSignIn(
            uc,
            providerId: type.firebaseProviderId,
            displayName: apple.displayName,
          );
          return uc;

        case AuthProviderType.github:
          final cred = await _github.getCredential();
          final uc = await _auth.signInWithCredential(cred);
          await _afterSignIn(uc, providerId: type.firebaseProviderId);
          return uc;
      }
    } catch (e) {
      // Normalize
      throw AuthErrorMapper.from(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _google.signOutSilently();
    } catch (_) {
      // ignore
    }
    await _auth.signOut();
  }

  /// Account linking (opsiyonel ama production’da lazım)
  Future<UserCredential> link(AuthProviderType type) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure(AuthFailureCode.firebaseAuth, 'Önce giriş yapmalısın.');
    }

    try {
      AuthCredential cred;

      switch (type) {
        case AuthProviderType.google:
          cred = await _google.getCredential();
          break;
        case AuthProviderType.apple:
          final apple = await _apple.getCredentialWithProfile();
          cred = apple.credential;
          break;
        case AuthProviderType.github:
          cred = await _github.getCredential();
          break;
      }

      final uc = await user.linkWithCredential(cred);
      await _afterSignIn(uc, providerId: type.firebaseProviderId);
      return uc;
    } catch (e) {
      throw AuthErrorMapper.from(e);
    }
  }

  Future<void> _afterSignIn(
      UserCredential uc, {
        required String providerId,
        String? displayName,
        String? photoUrl,
      }) async {
    final user = uc.user;
    if (user == null) {
      throw const AuthFailure(AuthFailureCode.firebaseAuth, 'Giriş tamamlanamadı (user null).');
    }

    await _userService.upsertFromFirebaseUser(
      user: user,
      providerId: providerId,
      displayName: displayName,
      photoUrl: photoUrl,
    );
  }
}
