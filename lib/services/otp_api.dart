import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class OtpApi {
  // 🔽 Render URL'in
  static const String baseUrl = 'https://techconnect-otp.onrender.com';

  static Future<void> requestEmailOtp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user');
    final idToken = await user.getIdToken();
    final resp = await http.post(
      Uri.parse('$baseUrl/otp/request'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('OTP request failed: ${resp.statusCode} ${resp.body}');
    }
  }

  static Future<bool> verifyEmailOtp(String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final idToken = await user.getIdToken();
    final resp = await http.post(
      Uri.parse('$baseUrl/otp/verify'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'code': code}),
    );
    if (resp.statusCode != 200) return false;
    final data = jsonDecode(resp.body);
    return data['ok'] == true;
  }
}
