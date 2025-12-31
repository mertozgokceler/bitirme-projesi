import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../in_app_notification.dart';
import 'auth_service.dart';

class AuthRepository {
  AuthRepository({
    AuthService? authService,
    FirebaseFirestore? firestore,
  })  : _authService = authService ?? AuthService(),
        _fs = firestore ?? FirebaseFirestore.instance;

  final AuthService _authService;
  final FirebaseFirestore _fs;

  String _trLower(String s) =>
      s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  /// LOGIN FLOW:
  /// - FirebaseAuth login
  /// - rememberMe kaydı
  /// - users/{uid} yoksa => invalid/ghost hesap (signOut)
  /// - patch: nameLower/usernameLower/isSearchable
  /// - inAppNotification init
  Future<LoginFlowResult> loginFlow({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final cred = await _authService.login(email: email, password: password);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rememberMe', rememberMe);

    final uid = cred.user!.uid;

    final ref = _fs.collection('users').doc(uid);
    final doc = await ref.get();

    if (!doc.exists) {
      await _authService.signOut();
      return LoginFlowResult.invalidProfile();
    }

    final data = doc.data()!;
    final String name = (data['name'] ?? '').toString();
    final String username = (data['username'] ?? '').toString();

    final needPatch = (data['isSearchable'] != true) ||
        ((data['nameLower'] ?? '').toString().isEmpty && name.isNotEmpty) ||
        ((data['usernameLower'] ?? '').toString().isEmpty &&
            username.isNotEmpty);

    if (needPatch) {
      await ref.set({
        'isSearchable': true,
        if (name.isNotEmpty) 'nameLower': _trLower(name),
        if (username.isNotEmpty) 'usernameLower': _trLower(username),
      }, SetOptions(merge: true));
    }

    await inAppNotificationService.initForUser(uid);

    return LoginFlowResult.success(
      uid: uid,
      displayName: (data['username'] ?? data['name'] ?? '').toString(),
      userData: data,
    );
  }

  /// REGISTER FLOW (Transaction):
  /// - usernames/{unameLower} rezerve
  /// - users/{uid} yaz
  /// - hata olursa auth user sil (hayalet hesap bırakma)
  Future<RegisterFlowResult> registerFlow({
    required String name,
    required String username,
    required String email,
    required String password,
    required bool isCompany,
    String? taxNo,
    String? companyName,
    String? companyActivity,
    required bool acceptedTerms,
    required bool acceptedPrivacy,
  }) async {
    final uname = username.trim();
    final unameLower = _trLower(uname);

    // quick pre-check (UI hızlı feedback)
    final unameDoc = await _fs.collection('usernames').doc(unameLower).get();
    if (unameDoc.exists) {
      return RegisterFlowResult.usernameTaken();
    }

    // 1) Auth user create
    final cred =
    await _authService.register(email: email.trim(), password: password);
    final uid = cred.user!.uid;

    final String accountType = isCompany ? 'company' : 'individual';

    // 2) Firestore transaction
    try {
      await _fs.runTransaction((tx) async {
        final unameRef = _fs.collection('usernames').doc(unameLower);
        final userRef = _fs.collection('users').doc(uid);

        if ((await tx.get(unameRef)).exists) {
          throw Exception('username_taken');
        }

        tx.set(unameRef, {'uid': uid});

        final userData = <String, dynamic>{
          'name': name.trim(),
          'nameLower': name.trim().isEmpty ? '' : _trLower(name.trim()),
          'username': uname,
          'usernameLower': unameLower,
          'isSearchable': true,
          'email': email.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'active': true,
          'roles': ['user'],
          'type': accountType,
          'isCompany': isCompany,

          // legal
          'acceptedTerms': acceptedTerms,
          'acceptedPrivacy': acceptedPrivacy,
          'acceptedTermsAt': FieldValue.serverTimestamp(),
          'acceptedPrivacyAt': FieldValue.serverTimestamp(),

          // individual defaults
          if (!isCompany) ...{
            'cvParseStatus': 'idle',
            'cvTextHash': '',
            'profileStructured': <String, dynamic>{},
            'profileSummary': '',
            'cvParsedAt': null,
            'cvParseRequestId': '',
            'cvParseError': '',
          },

          // company fields
          if (isCompany) ...{
            'companyName': companyName,
            'companyTaxNo': taxNo,
            'companyActivity': companyActivity,
            'company': {
              'name': companyName,
              'taxNo': taxNo,
              'activity': companyActivity,
            },
          },
        };

        tx.set(userRef, userData);
      });

      return RegisterFlowResult.success(uid: uid);
    } catch (e) {
      // transaction patladıysa auth user'ı temizle
      await _authService.deleteCurrentUserIfAny();
      await _authService.signOut();

      if (e.toString().contains('username_taken')) {
        return RegisterFlowResult.usernameTaken();
      }
      rethrow;
    }
  }
}

class LoginFlowResult {
  final bool ok;
  final bool invalidProfile;
  final String? uid;
  final String? displayName;
  final Map<String, dynamic>? userData;

  const LoginFlowResult._({
    required this.ok,
    required this.invalidProfile,
    this.uid,
    this.displayName,
    this.userData,
  });

  factory LoginFlowResult.success({
    required String uid,
    required String displayName,
    required Map<String, dynamic> userData,
  }) =>
      LoginFlowResult._(
        ok: true,
        invalidProfile: false,
        uid: uid,
        displayName: displayName,
        userData: userData,
      );

  factory LoginFlowResult.invalidProfile() =>
      const LoginFlowResult._(ok: false, invalidProfile: true);
}

class RegisterFlowResult {
  final bool ok;
  final bool usernameTaken;
  final String? uid;

  const RegisterFlowResult._({
    required this.ok,
    required this.usernameTaken,
    this.uid,
  });

  factory RegisterFlowResult.success({required String uid}) =>
      RegisterFlowResult._(ok: true, usernameTaken: false, uid: uid);

  factory RegisterFlowResult.usernameTaken() =>
      const RegisterFlowResult._(ok: false, usernameTaken: true);
}
