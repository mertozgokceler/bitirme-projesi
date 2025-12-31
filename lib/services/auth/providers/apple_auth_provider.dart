import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AppleAuthProviderAdapter {
  /// Apple fullName sadece ilk girişte gelir.
  /// Facade bunu user_service'e taşıyacak.
  Future<({AuthCredential credential, String? displayName, String? email})> getCredentialWithProfile() async {
    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final idToken = apple.identityToken;
    final authCode = apple.authorizationCode;

    if (idToken == null || idToken.isEmpty) {
      throw Exception('Apple identityToken alınamadı.');
    }

    final oauth = OAuthProvider('apple.com').credential(
      idToken: idToken,
      accessToken: authCode, // Firebase Apple provider burada authCode kabul eder
    );

    final given = apple.givenName?.trim();
    final family = apple.familyName?.trim();
    String? displayName;
    if ((given?.isNotEmpty == true) || (family?.isNotEmpty == true)) {
      displayName = '${given ?? ''} ${family ?? ''}'.trim();
    }

    return (credential: oauth, displayName: displayName, email: apple.email);
  }
}
