// lib/tabs/add_post_tab.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../screens/create_post_screen.dart';

class AddPostTab extends StatefulWidget {
  const AddPostTab({super.key});

  @override
  State<AddPostTab> createState() => _AddPostTabState();
}

class _AddPostTabState extends State<AddPostTab> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> _postStream() {
    final user = _auth.currentUser;

    if (user == null) {
      return _firestore
          .collection('posts')
          .where('userId', isEqualTo: '__no_user__')
          .snapshots();
    }

    return _firestore
        .collection('posts')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ✅ EMPTY FEED (LOTTIE)
  Widget _buildEmptyFeed(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Transform.translate(
          offset: const Offset(0, -70), // 👈 tüm bloğu yukarı alır
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 240,
                height: 240,
                child: Lottie.asset(
                  'assets/lottie/empty_feed.json',
                  repeat: true,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Henüz bir gönderi paylaşmadın',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sağ alttaki + butonuna dokunarak\nilk gönderini paylaşabilirsin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return Stack(
        children: [
          Center(
            child: Text(
              'Gönderilerini görmek için giriş yapmalısın.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white70 : Colors.grey.shade700,
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF6E44FF),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Gönderi paylaşmak için önce giriş yap.'),
                  ),
                );
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _postStream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Gönderiler yüklenirken bir hata oluştu.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.red.shade300 : Colors.red,
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // ✅ EMPTY STATE (LOTTIE)
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyFeed(context);
            }

            final docs = snapshot.data!.docs;

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data();

                final userName =
                    data['userName'] as String? ?? 'Bilinmeyen Kullanıcı';
                final userTitle = data['userTitle'] as String? ?? '';
                final userAvatarUrl = data['userAvatarUrl'] as String?;
                final text = data['text'] as String? ?? '';
                final imageUrl = data['imageUrl'] as String?;
                final createdAt = data['createdAt'];

                String timeAgo = '';
                if (createdAt is Timestamp) {
                  final dt = createdAt.toDate();
                  final diff = DateTime.now().difference(dt);
                  if (diff.inMinutes < 1) {
                    timeAgo = 'Şimdi';
                  } else if (diff.inHours < 1) {
                    timeAgo = '${diff.inMinutes} dk önce';
                  } else if (diff.inDays < 1) {
                    timeAgo = '${diff.inHours} sa önce';
                  } else {
                    timeAgo = '${dt.day}.${dt.month}.${dt.year}';
                  }
                }

                return _PostCard(
                  userName: userName,
                  userTitle: userTitle,
                  userAvatarUrl: userAvatarUrl,
                  text: text,
                  imageUrl: imageUrl,
                  timeAgo: timeAgo,
                );
              },
            );
          },
        ),

        // Bu sayfada FAB kullanmıyorsun çünkü MainNavShell zaten _index==2 iken FAB basıyor.
        // İstersen burada da özel FAB koyarsın ama şu an çakışmasın diye dokunmadım.
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  final String userName;
  final String userTitle;
  final String? userAvatarUrl;
  final String text;
  final String? imageUrl;
  final String timeAgo;

  const _PostCard({
    required this.userName,
    required this.userTitle,
    required this.userAvatarUrl,
    required this.text,
    required this.imageUrl,
    required this.timeAgo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor =
    isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade300;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundImage:
                  (userAvatarUrl != null && userAvatarUrl!.isNotEmpty)
                      ? NetworkImage(userAvatarUrl!)
                      : null,
                  child: (userAvatarUrl == null || userAvatarUrl!.isEmpty)
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (userTitle.isNotEmpty)
                        Text(
                          userTitle,
                          style: TextStyle(
                            color:
                            isDark ? Colors.grey.shade400 : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  timeAgo,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (imageUrl != null && imageUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(imageUrl!),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _actionButton(Icons.thumb_up_alt_outlined, 'Beğen', () {}),
                _actionButton(Icons.comment_outlined, 'Yorum Yap', () {}),
                _actionButton(Icons.share_outlined, 'Paylaş', () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: Colors.grey.shade600),
      label: Text(
        label,
        style: TextStyle(color: Colors.grey.shade700),
      ),
      style: TextButton.styleFrom(
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
