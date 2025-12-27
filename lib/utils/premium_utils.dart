import 'package:cloud_firestore/cloud_firestore.dart';

bool isPremiumActiveFromUserDoc(Map<String, dynamic> data) {
  final bool isPremium = data['isPremium'] == true;

  if (!isPremium) return false;

  final until = data['premiumUntil'];

  if (until is Timestamp) {
    return until.toDate().isAfter(DateTime.now());
  }

  return false;
}
