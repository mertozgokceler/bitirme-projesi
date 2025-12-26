import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedPostsScreen extends StatelessWidget {
  const SavedPostsScreen({super.key});

  Future<List<Map<String, dynamic>>> _loadSavedPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      // 1) Kullanıcının kendi altındaki savedPosts koleksiyonunu çek
      final savedSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('savedPosts')
          .orderBy('createdAt', descending: true)
          .get();

      if (savedSnap.docs.isEmpty) return [];

      // 2) postId'leri al (doc id = postId)
      final postIds = savedSnap.docs.map((d) => d.id).toList();

      // 3) Tüm postları paralel çek
      final futures = postIds.map((postId) {
        return FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .get();
      }).toList();

      final postSnaps = await Future.wait(futures);

      // 4) Var olan postları listeye at
      final List<Map<String, dynamic>> posts = [];
      for (final snap in postSnaps) {
        if (snap.exists) {
          final data = snap.data() as Map<String, dynamic>;
          data['id'] = snap.id; // postId
          posts.add(data);
        }
      }

      return posts;
    } catch (e) {
      throw Exception('Kaydedilenler alınırken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kaydedilen Gönderiler'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadSavedPosts(),
        builder: (context, snapshot) {
          // Yükleniyor
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Hata
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final posts = snapshot.data ?? [];

          // Hiç kayıt yok
          if (posts.isEmpty) {
            return const Center(
              child: Text(
                'Henüz kaydettiğin bir gönderi yok.',
                style: TextStyle(fontSize: 15),
              ),
            );
          }

          // Liste
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final data = posts[index];

              final userName = (data['userName'] ?? 'Kullanıcı').toString();
              final userTitle = (data['userTitle'] ?? '').toString();
              final text = (data['text'] ?? '').toString();
              final imageUrl = (data['imageUrl'] ?? '').toString();

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Kullanıcı bilgisi
                      Row(
                        children: [
                          const CircleAvatar(
                            child: Icon(Icons.person, size: 18),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                if (userTitle.isNotEmpty)
                                  Text(
                                    userTitle,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Metin
                      if (text.isNotEmpty)
                        Text(
                          text,
                          style: const TextStyle(fontSize: 14),
                        ),

                      // Görsel
                      if (imageUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
