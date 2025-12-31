import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/tr_lower.dart';

class UserService {
  UserService({FirebaseFirestore? fs}) : _fs = fs ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;

  DocumentReference<Map<String, dynamic>> userRef(String uid) =>
      _fs.collection('users').doc(uid);

  Map<String, dynamic> buildUserData({
    required String uid,
    required String email,
    required String name,
    required String username,
    required bool isCompany,
    String? companyName,
    String? taxNo,
    String? activity,
    required bool acceptedTerms,
    required bool acceptedPrivacy,
  }) {
    final unameLower = trLower(username.trim());
    final nameTrim = name.trim();

    final data = <String, dynamic>{
      'name': nameTrim,
      'nameLower': nameTrim.isEmpty ? '' : trLower(nameTrim),
      'username': username.trim(),
      'usernameLower': unameLower,
      'isSearchable': true,
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'active': true,
      'roles': ['user'],
      'type': isCompany ? 'company' : 'individual',
      'isCompany': isCompany,

      // Legal
      'acceptedTerms': acceptedTerms,
      'acceptedPrivacy': acceptedPrivacy,
      'acceptedTermsAt': FieldValue.serverTimestamp(),
      'acceptedPrivacyAt': FieldValue.serverTimestamp(),
    };

    if (!isCompany) {
      data.addAll({
        'cvParseStatus': 'idle',
        'cvTextHash': '',
        'profileStructured': <String, dynamic>{},
        'profileSummary': '',
        'cvParsedAt': null,
        'cvParseRequestId': '',
        'cvParseError': '',
      });
    } else {
      data.addAll({
        'companyName': companyName,
        'companyTaxNo': taxNo,
        'companyActivity': activity,
        'company': {
          'name': companyName,
          'taxNo': taxNo,
          'activity': activity,
        },
      });
    }

    return data;
  }

  /// Login sonrası “patch” (senin mevcut mantık)
  Future<void> patchSearchableIfMissing({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    final ref = userRef(uid);

    final name = (data['name'] ?? '').toString();
    final username = (data['username'] ?? '').toString();

    final needPatch = (data['isSearchable'] != true) ||
        ((data['nameLower'] ?? '').toString().isEmpty && name.isNotEmpty) ||
        ((data['usernameLower'] ?? '').toString().isEmpty &&
            username.isNotEmpty);

    if (!needPatch) return;

    await ref.set({
      'isSearchable': true,
      if (name.isNotEmpty) 'nameLower': trLower(name),
      if (username.isNotEmpty) 'usernameLower': trLower(username),
    }, SetOptions(merge: true));
  }
}
