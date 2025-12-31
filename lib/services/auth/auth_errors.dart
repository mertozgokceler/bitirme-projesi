import 'package:firebase_auth/firebase_auth.dart';

class AuthFailure implements Exception {
  final AuthFailureCode code;
  final String message;
  final Object? cause;

  const AuthFailure(this.code, this.message, {this.cause});

  @override
  String toString() => 'AuthFailure($code): $message';
}

enum AuthFailureCode {
  cancelledByUser,
  network,
  invalidConfig,
  providerError,
  firebaseAuth,
  accountExistsDifferentCredential,
  requiresRecentLogin,
  unknown,
}

class AuthErrorMapper {
  static AuthFailure from(Object e) {
    // Firebase
    if (e is FirebaseAuthException) {
      final code = e.code;
      switch (code) {
        case 'user-cancelled':
          return AuthFailure(AuthFailureCode.cancelledByUser, 'Giriş iptal edildi.', cause: e);
        case 'network-request-failed':
          return AuthFailure(AuthFailureCode.network, 'Ağ hatası. İnternet bağlantını kontrol et.', cause: e);
        case 'account-exists-with-different-credential':
          return AuthFailure(
            AuthFailureCode.accountExistsDifferentCredential,
            'Bu e-posta başka bir giriş yöntemiyle kayıtlı. Hesap bağlama gerekli.',
            cause: e,
          );
        case 'requires-recent-login':
          return AuthFailure(
            AuthFailureCode.requiresRecentLogin,
            'Güvenlik nedeniyle tekrar giriş yapman gerekiyor.',
            cause: e,
          );
        case 'invalid-credential':
        case 'credential-already-in-use':
        case 'user-disabled':
        case 'operation-not-allowed':
        case 'invalid-email':
          return AuthFailure(AuthFailureCode.firebaseAuth, e.message ?? 'Kimlik doğrulama hatası.', cause: e);
        default:
          return AuthFailure(AuthFailureCode.firebaseAuth, e.message ?? 'Giriş hatası.', cause: e);
      }
    }

    // Generic
    final msg = e.toString();

    // Common cancel patterns from providers
    if (msg.toLowerCase().contains('canceled') ||
        msg.toLowerCase().contains('cancelled') ||
        msg.toLowerCase().contains('cancel')) {
      return AuthFailure(AuthFailureCode.cancelledByUser, 'Giriş iptal edildi.', cause: e);
    }

    // Network-ish
    if (msg.toLowerCase().contains('network') ||
        msg.toLowerCase().contains('socket') ||
        msg.toLowerCase().contains('timed out') ||
        msg.toLowerCase().contains('timeout')) {
      return AuthFailure(AuthFailureCode.network, 'Ağ hatası. İnternet bağlantını kontrol et.', cause: e);
    }

    return AuthFailure(AuthFailureCode.unknown, 'Beklenmeyen bir hata oluştu.', cause: e);
  }
}
