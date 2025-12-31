class UsernameTakenException implements Exception {
  final String message;
  UsernameTakenException([this.message = 'Bu kullanıcı adı alınmış.']);
  @override
  String toString() => message;
}

class ProfileMissingException implements Exception {
  final String message;
  ProfileMissingException([this.message = 'Profil bulunamadı.']);
  @override
  String toString() => message;
}

class RegisterRollbackException implements Exception {
  final String message;
  RegisterRollbackException([this.message = 'Kayıt sırasında hata oluştu.']);
  @override
  String toString() => message;
}
