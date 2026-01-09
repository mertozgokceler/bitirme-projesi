// lib/screens/saved_posts_screen.dart
// ✅ Paylaşımı yapanın PROFİL RESMİ gösterilir (post.userPhotoUrl varsa direkt,
// yoksa users/{userId}.photoUrl fallback ile çekilir)

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// =====================
// PREMIUM UI HELPERS (CvAnalysis look & feel)
// =====================

LinearGradient _bgGradient(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF0B1220),
        Color(0xFF0A1B2E),
        Color(0xFF081829),
      ],
    );
  }
  return const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF6FAFF),
      Color(0xFFEFF6FF),
      Color(0xFFF9FBFF),
    ],
  );
}

Widget _glassCard(
    BuildContext context, {
      required Widget child,
      EdgeInsets padding = const EdgeInsets.all(14),
      BorderRadius borderRadius = const BorderRadius.all(Radius.circular(18)),
    }) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  return ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(isDark ? 0.78 : 0.92),
          borderRadius: borderRadius,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.28 : 0.45),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 22,
              spreadRadius: 2,
              color: Colors.black.withOpacity(isDark ? 0.22 : 0.08),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

Widget _avatar(BuildContext context, String? photoUrl) {
  final theme = Theme.of(context);
  return CircleAvatar(
    radius: 22,
    backgroundColor: theme.colorScheme.surfaceVariant,
    backgroundImage:
    (photoUrl != null && photoUrl.trim().isNotEmpty) ? NetworkImage(photoUrl) : null,
    child: (photoUrl == null || photoUrl.trim().isEmpty)
        ? Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant)
        : null,
  );
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0.0)]),
        ),
      ),
    );
  }
}

// =====================
// SCREEN
// =====================

class SavedPostsScreen extends StatelessWidget {
  const SavedPostsScreen({super.key});

  Future<List<Map<String, dynamic>>> _loadSavedPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final savedSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedPosts')
        .orderBy('createdAt', descending: true)
        .get();

    if (savedSnap.docs.isEmpty) return [];

    final postIds = savedSnap.docs.map((d) => d.id).toList();

    final postFutures = postIds.map((postId) {
      return FirebaseFirestore.instance.collection('posts').doc(postId).get();
    }).toList();

    final postSnaps = await Future.wait(postFutures);

    final List<Map<String, dynamic>> posts = [];
    for (final snap in postSnaps) {
      if (!snap.exists) continue;

      final data = snap.data() as Map<String, dynamic>;
      data['id'] = snap.id;

      // 🔹 PROFİL RESMİ KAYNAĞI
      // 1) post.userPhotoUrl varsa kullan
      // 2) yoksa users/{userId}.photoUrl fallback
      String? photoUrl = (data['userPhotoUrl'] ?? '').toString().trim();
      final userId = (data['userId'] ?? '').toString().trim();

      if (photoUrl.isEmpty && userId.isNotEmpty) {
        try {
          final u = await FirebaseFirestore.instance.collection('users').doc(userId).get();
          final uData = u.data();
          photoUrl = (uData?['photoUrl'] ?? uData?['avatarUrl'] ?? '').toString().trim();
        } catch (_) {}
      }

      data['__resolvedUserPhotoUrl'] = photoUrl;
      posts.add(data);
    }

    return posts;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Kaydedilen Gönderiler'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
      ),
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
          Positioned(top: -120, left: -80, child: _GlowBlob(size: 260, color: cs.primary.withOpacity(0.20))),
          Positioned(bottom: -140, right: -90, child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18))),
          SafeArea(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadSavedPosts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _glassCard(
                        context,
                        child: Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  );
                }

                final posts = snapshot.data ?? [];

                if (posts.isEmpty) {
                  return Center(
                    child: _glassCard(
                      context,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bookmark_border, size: 34),
                          SizedBox(height: 10),
                          Text(
                            'Henüz kaydettiğin bir gönderi yok.',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                  itemCount: posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = posts[index];

                    final userName = (data['userName'] ?? 'Kullanıcı').toString();
                    final userTitle = (data['userTitle'] ?? '').toString();
                    final userPhotoUrl = (data['__resolvedUserPhotoUrl'] ?? '').toString();
                    final text = (data['text'] ?? '').toString();
                    final imageUrl = (data['imageUrl'] ?? '').toString();

                    return _glassCard(
                      context,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _avatar(context, userPhotoUrl),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      userName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (userTitle.isNotEmpty)
                                      Text(
                                        userTitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).hintColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(Icons.bookmark, color: cs.primary),
                            ],
                          ),

                          if (text.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              text,
                              style: const TextStyle(fontSize: 14, height: 1.3),
                            ),
                          ],

                          if (imageUrl.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(imageUrl, fit: BoxFit.cover),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
