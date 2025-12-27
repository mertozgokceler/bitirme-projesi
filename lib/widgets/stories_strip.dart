import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/my_stories_screen.dart';
import '../screens/story_viewer_screen.dart';

class StoriesStrip extends StatelessWidget {
  const StoriesStrip({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _storiesStream() {
    final now = Timestamp.now();
    return FirebaseFirestore.instance
        .collection('stories')
        .where('expiresAt', isGreaterThan: now)
        .orderBy('expiresAt', descending: false)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .snapshots();
  }

  List<Map<String, dynamic>> _castItems(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  List<Map<String, dynamic>> _validItems(dynamic raw) {
    final items = _castItems(raw);
    return items
        .where((it) => (it['url'] ?? '').toString().trim().isNotEmpty)
        .where((it) {
      final t = (it['type'] ?? '').toString().trim();
      return t == 'image' || t == 'video';
    })
        .toList();
  }

  bool _isNotExpired(dynamic expiresAt) {
    try {
      final ts = expiresAt is Timestamp ? expiresAt : null;
      if (ts == null) return false;
      return ts.toDate().isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Future<void> _openMyStoryOrEditor({
    required BuildContext context,
    required String uid,
    required String ownerName,
    required String ownerPhotoUrl,
  }) async {
    final ref = FirebaseFirestore.instance.collection('stories').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      if (!context.mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyStoriesScreen()));
      return;
    }

    final data = snap.data() ?? {};
    final ok = _isNotExpired(data['expiresAt']);
    final items = _validItems(data['items']);

    if (!context.mounted) return;

    if (ok && items.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            ownerUid: uid,
            ownerName: ownerName.trim().isEmpty ? 'Ben' : ownerName.trim(),
            ownerPhotoUrl: ownerPhotoUrl.trim(),
            items: items,
          ),
        ),
      );
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyStoriesScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return const SizedBox.shrink();

    final myUid = me.uid;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outline.withOpacity(0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hikayeler',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _storiesStream(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];

                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 1 + docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
                        builder: (context, us) {
                          final u = us.data?.data() ?? {};
                          final myPhoto = (u['photoUrl'] ??
                              u['photoURL'] ??
                              u['profilePhotoUrl'] ??
                              u['userPhotoUrl'] ??
                              '')
                              .toString()
                              .trim();

                          final myName = (u['name'] ??
                              u['userName'] ??
                              u['username'] ??
                              u['companyName'] ??
                              'Ben')
                              .toString()
                              .trim();

                          return _AddStoryTile(
                            photoUrl: myPhoto.isEmpty ? null : myPhoto,
                            onTap: () {
                              _openMyStoryOrEditor(
                                context: context,
                                uid: myUid,
                                ownerName: myName,
                                ownerPhotoUrl: myPhoto,
                              );
                            },
                          );
                        },
                      );
                    }

                    final d = docs[i - 1];
                    final s = d.data();

                    final ownerUid = d.id;
                    final ownerName = (s['userName'] ?? 'Kullanıcı').toString().trim();
                    final ownerPhotoUrl = (s['userPhotoUrl'] ?? '').toString().trim();

                    final items = _validItems(s['items']);
                    final hasVideo = items.any((it) => (it['type'] ?? '').toString() == 'video');

                    return _StoryTile(
                      name: ownerName.isEmpty ? 'Kullanıcı' : ownerName,
                      photoUrl: ownerPhotoUrl.isEmpty ? null : ownerPhotoUrl,
                      hasVideo: hasVideo,
                      onTap: items.isEmpty
                          ? () {}
                          : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoryViewerScreen(
                              ownerUid: ownerUid,
                              ownerName: ownerName.isEmpty ? 'Kullanıcı' : ownerName,
                              ownerPhotoUrl: ownerPhotoUrl,
                              items: items,
                            ),
                          ),
                        );
                      },
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

class _AddStoryTile extends StatelessWidget {
  final VoidCallback onTap;
  final String? photoUrl;

  const _AddStoryTile({
    required this.onTap,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary.withOpacity(0.75), width: 2),
                    ),
                    child: CircleAvatar(
                      backgroundColor: cs.surface,
                      backgroundImage: hasPhoto ? NetworkImage(photoUrl!.trim()) : null,
                      child: !hasPhoto
                          ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.70))
                          : null,
                    ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 2),
                      ),
                      child: Icon(Icons.add_rounded, size: 14, color: cs.onPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Benim',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _StoryTile extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final bool hasVideo;
  final VoidCallback onTap;

  const _StoryTile({
    required this.name,
    required this.onTap,
    this.photoUrl,
    this.hasVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary.withOpacity(0.75), width: 2),
                    ),
                    child: CircleAvatar(
                      backgroundColor: cs.surface,
                      backgroundImage: hasPhoto ? NetworkImage(photoUrl!.trim()) : null,
                      child: !hasPhoto
                          ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.70))
                          : null,
                    ),
                  ),
                  if (hasVideo)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 2),
                        ),
                        child: Icon(Icons.videocam_rounded, size: 12, color: cs.onPrimary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
