import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class AiCareerService {
  static const String _endpoint =
      'https://europe-west1-techconnectapp-e56d3.cloudfunctions.net/aiCareerAdvisor';

  Future<String> ask(String prompt) async {
    final uri = Uri.parse(_endpoint);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return 'Giriş yapılmamış. AI kullanmak için giriş yapmalısın.';
      }

      final idToken = await user.getIdToken();

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'message': prompt}),
      );

      // ✅ Hata ayıklama: status + body göster
      if (response.statusCode != 200) {
        return 'AI hata: ${response.statusCode} — ${response.body}';
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final reply = (data['reply'] ?? '').toString().trim();
      if (reply.isEmpty) {
        return 'AI boş cevap döndü. Tekrar dene.';
      }
      return reply;
    } catch (e) {
      return 'AI teknik hata: $e';
    }
  }
}
