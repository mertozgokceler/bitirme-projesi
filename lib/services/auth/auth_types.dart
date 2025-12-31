enum AuthProviderType {
  google,
  github,
  apple,
}

extension AuthProviderTypeX on AuthProviderType {
  String get id {
    switch (this) {
      case AuthProviderType.google:
        return 'google';
      case AuthProviderType.github:
        return 'github';
      case AuthProviderType.apple:
        return 'apple';
    }
  }

  String get firebaseProviderId {
    switch (this) {
      case AuthProviderType.google:
        return 'google.com';
      case AuthProviderType.github:
        return 'github.com';
      case AuthProviderType.apple:
        return 'apple.com';
    }
  }
}
