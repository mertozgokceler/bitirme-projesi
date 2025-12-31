import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_exceptions.dart';
import '../core/tr_lower.dart';
import '../in_app_notification.dart';
import 'auth_service.dart';
import 'user_service.dart';
import 'username_service.dart';

class AuthFlow {
  AuthFlow({
    AuthService? authService,
    UserService? userService,
    UsernameService? usernameService,
    FirebaseFirestore? fs,
  })  : _auth = authService ?? AuthService(),
        _user = userService ?? UserService(),
        _uname = usernameService ?? UsernameService(),
        _fs = fs ?? FirebaseFirestore.instance;

  final AuthService _auth;
  final UserService _user;
  final UsernameService _uname;
  final FirebaseFirestore _fs;

  Future<void> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final cred = await _auth.login(email: email.trim(), password: password);
    final uid = cred.user!.uid;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rememberMe', rememberMe);

    final ref = _user.userRef(uid);
    final doc = await ref.get();
    if (!doc.exists) {
      await _auth.signOut();
      throw ProfileMissingException('Profil bulunamadı. Tekrar kayıt ol.');
    }

    final data = doc.data()!;
    await _user.patchSearchableIfMissing(uid: uid, data: data);

    await inAppNotificationService.initForUser(uid);
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String username,
    required bool isCompany,
    String? companyName,
    String? taxNo,
    String? activity,
    required bool acceptedTerms,
    required bool acceptedPrivacy,
  }) async {
    // username normalize
    final unameLower = _uname.normalize(username);

    // UX için hızlı check (zorunlu değil)
    final taken = await _uname.isTaken(unameLower);
    if (taken) throw UsernameTakenException();

    // 1) Auth create
    final cred = await _auth.register(email: email.trim(), password: password);
    final uid = cred.user!.uid;

    try {
      // 2) Transaction: usernames + users
      await _fs.runTransaction((tx) async {
        final userRef = _user.userRef(uid);

        // usernames reserve
        await _uname.reserveTx(tx: tx, usernameLower: unameLower, uid: uid);

        // users data
        final userData = _user.buildUserData(
          uid: uid,
          email: email,
          name: name,
          username: username,
          isCompany: isCompany,
          companyName: isCompany ? companyName?.trim() : null,
          taxNo: isCompany ? taxNo?.trim() : null,
          activity: isCompany ? activity?.trim() : null,
          acceptedTerms: acceptedTerms,
          acceptedPrivacy: acceptedPrivacy,
        );

        tx.set(userRef, userData);
      });

      // 3) (opsiyonel) notif init
      await inAppNotificationService.initForUser(uid);
    } on UsernameTakenException {
      // Transaction içinde username kapıldıysa: rollback + kullanıcıyı sil
      await _auth.deleteCurrentUserIfAny();
      await _auth.signOut();
      rethrow;
    } catch (e) {
      // Her türlü hata: auth user sil, signOut
      await _auth.deleteCurrentUserIfAny();
      await _auth.signOut();
      throw RegisterRollbackException('Kayıt tamamlanamadı: $e');
    }
  }
}
