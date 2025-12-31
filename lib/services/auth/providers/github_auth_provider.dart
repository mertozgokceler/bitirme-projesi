import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

class GithubAuthProviderAdapter {
  // TODO: Burayı kendi GitHub OAuth App bilgilerinle doldur.
  // GitHub OAuth App > Client ID
  final String clientId;

  // Callback scheme: örn "techconnect"
  // redirectUri: techconnect://auth/github
  final String redirectScheme;
  final String redirectPath;

  // GitHub OAuth scopes (ihtiyacın kadar)
  final List<String> scopes;

  GithubAuthProviderAdapter({
    required this.clientId,
    required this.redirectScheme,
    this.redirectPath = 'auth/github',
    this.scopes = const ['read:user', 'user:email'],
  });

  String get _redirectUri => '$redirectScheme://$redirectPath';

  Future<AuthCredential> getCredential() async {
    final state = _randomString(32);
    final verifier = _randomString(64);
    final challenge = _codeChallenge(verifier);

    final scopeStr = scopes.join(' ');

    final authUrl = Uri.https('github.com', '/login/oauth/authorize', {
      'client_id': clientId,
      'redirect_uri': _redirectUri,
      'scope': scopeStr,
      'state': state,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    }).toString();

    final callbackUrl = await FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: redirectScheme,
    );

    final uri = Uri.parse(callbackUrl);
    final code = uri.queryParameters['code'];
    final returnedState = uri.queryParameters['state'];
    final error = uri.queryParameters['error'];

    if (error != null && error.isNotEmpty) {
      if (error.toLowerCase().contains('access_denied')) {
        throw Exception('cancelled');
      }
      throw Exception('GitHub OAuth hata: $error');
    }

    if (code == null || code.isEmpty) {
      throw Exception('GitHub code alınamadı.');
    }

    if (returnedState != state) {
      throw Exception('GitHub OAuth state uyuşmuyor.');
    }

    final token = await _exchangeCodeForToken(
      code: code,
      codeVerifier: verifier,
      redirectUri: _redirectUri,
    );

    return GithubAuthProvider.credential(token);
  }

  Future<String> _exchangeCodeForToken({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final url = Uri.https('github.com', '/login/oauth/access_token');
    final res = await http.post(
      url,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'client_id': clientId,
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('GitHub token exchange başarısız: ${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final token = (body['access_token'] ?? '').toString();

    if (token.isEmpty) {
      final err = (body['error_description'] ?? body['error'] ?? 'unknown').toString();
      throw Exception('GitHub token alınamadı: $err');
    }

    return token;
  }

  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  String _codeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }
}
