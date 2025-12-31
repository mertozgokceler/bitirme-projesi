import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/my_stories_screen.dart';
import '../screens/story_viewer_screen.dart';

class StoriesStrip extends StatelessWidget {
  const StoriesStrip({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _connectionsStream(String myUid) {
    return FirebaseFirestore.instance
        .collection('connections')
        .doc(myUid)
        .collection('list')
        .limit(50)
        .snapshots();
  }

  // ✅ latest active item: expiresAt > now
  Stream<QuerySnapshot<Map<String, dynamic>>> _latestActiveItemStream(String ownerUid) {
    final now = Timestamp.now();
    return FirebaseFirestore.instance
        .collection('stories')
        .doc(ownerUid)
        .collection('items')
        .where('expiresAt', isGreaterThan: now)
        .orderBy('expiresAt', descending: true)
        .limit(1)
        .snapshots();
  }

  // ✅ seen doc: stories/{ownerUid}/seen/{viewerUid}
  Stream<DocumentSnapshot<Map<String, dynamic>>> _seenDocStream({
    required String ownerUid,
    required String viewerUid,
  }) {
    return FirebaseFirestore.instance
        .collection('stories')
        .doc(ownerUid)
        .collection('seen')
        .doc(viewerUid)
        .snapshots();
  }

  Future<void> _openMyStoryOrEditor({
    required BuildContext context,
    required String myUid,
    required String myName,
    required String myPhotoUrl,
  }) async {
    final now = Timestamp.now();

    try {
      final q = await FirebaseFirestore.instance
          .collection('stories')
          .doc(myUid)
          .collection('items')
          .where('expiresAt', isGreaterThan: now)
          .orderBy('expiresAt', descending: true)
          .limit(1)
          .get();

      if (!context.mounted) return;

      final has = q.docs.isNotEmpty;

      if (!has) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyStoriesScreen()),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            ownerUid: myUid,
            ownerName: myName.trim().isEmpty ? 'Ben' : myName.trim(),
            ownerPhotoUrl: myPhotoUrl.trim(),
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyStoriesScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return const SizedBox.shrink();
    final myUid = me.uid;

    return SizedBox(
      height: 96,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _connectionsStream(myUid),
        builder: (context, connSnap) {
          final connDocs = connSnap.data?.docs ?? const [];
          final otherUids = connDocs.map((d) => d.id).toList();

          return ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // -----------------------
              // 0) MY TILE
              // -----------------------
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _latestActiveItemStream(myUid),
                    builder: (context, myItemSnap) {
                      final hasMyStory = (myItemSnap.data?.docs ?? const []).isNotEmpty;

                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _AddStoryTile(
                          photoUrl: myPhoto.isEmpty ? null : myPhoto,
                          showActiveRing: hasMyStory,
                          onTap: () => _openMyStoryOrEditor(
                            context: context,
                            myUid: myUid,
                            myName: myName,
                            myPhotoUrl: myPhoto,
                          ),
                          onLongPress: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const MyStoriesScreen()),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),

              // -----------------------
              // 1) OTHERS (NO HOLES)
              // -----------------------
              for (final otherUid in otherUids)
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _latestActiveItemStream(otherUid),
                  builder: (context, itemSnap) {
                    final docs = itemSnap.data?.docs ?? const [];
                    if (docs.isEmpty) return const SizedBox.shrink();

                    final item = docs.first.data();
                    final type = (item['type'] ?? '').toString().trim().toLowerCase();
                    final hasVideo = type == 'video';

                    // ✅ kıyas için stabil alan: expiresAt
                    final latestExpiresAt = item['expiresAt'];

                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection('users').doc(otherUid).snapshots(),
                      builder: (context, uSnap) {
                        final u = uSnap.data?.data() ?? {};
                        final name = (u['name'] ?? u['username'] ?? u['userName'] ?? 'Kullanıcı')
                            .toString()
                            .trim();
                        final photo = (u['photoUrl'] ?? '').toString().trim();

                        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: _seenDocStream(ownerUid: otherUid, viewerUid: myUid),
                          builder: (context, seenSnap) {
                            final seenData = seenSnap.data?.data() ?? {};

                            // ✅ viewer yazacağı alan:
                            // lastSeenExpiresAt
                            final lastSeenExpiresAt = seenData['lastSeenExpiresAt'];

                            bool isSeen = false;
                            if (lastSeenExpiresAt is Timestamp && latestExpiresAt is Timestamp) {
                              isSeen = lastSeenExpiresAt.compareTo(latestExpiresAt) >= 0;
                            }

                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _StoryTile(
                                name: name.isEmpty ? 'Kullanıcı' : name,
                                photoUrl: photo.isEmpty ? null : photo,
                                hasVideo: hasVideo,
                                isSeen: isSeen,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StoryViewerScreen(
                                        ownerUid: otherUid,
                                        ownerName: name.isEmpty ? 'Kullanıcı' : name,
                                        ownerPhotoUrl: photo,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------
// Tiles
// ---------------------------
class _AddStoryTile extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? photoUrl;
  final bool showActiveRing;

  const _AddStoryTile({
    required this.onTap,
    this.onLongPress,
    required this.photoUrl,
    required this.showActiveRing,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;

    final ringColor = showActiveRing
        ? cs.primary.withOpacity(isDark ? 0.80 : 0.85)
        : cs.outline.withOpacity(isDark ? 0.55 : 0.65);

    final innerBg = cs.surface;
    final labelColor = cs.onSurface.withOpacity(0.85);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    padding: const EdgeInsets.all(2.4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [ringColor, ringColor.withOpacity(0.45)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(1.6),
                      decoration: BoxDecoration(
                        color: innerBg,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        backgroundColor: innerBg,
                        backgroundImage: hasPhoto ? NetworkImage(photoUrl!.trim()) : null,
                        child: !hasPhoto
                            ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.70))
                            : null,
                      ),
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
                        border: Border.all(color: innerBg, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.25 : 0.10),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(Icons.add_rounded, size: 14, color: cs.onPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                'Hikayen',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: labelColor,
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
  final bool isSeen;
  final VoidCallback onTap;

  const _StoryTile({
    required this.name,
    required this.onTap,
    this.photoUrl,
    this.hasVideo = false,
    this.isSeen = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;

    // ✅ izlendiyse gri, izlenmediyse primary
    final ring = isSeen
        ? cs.outline.withOpacity(isDark ? 0.55 : 0.65)
        : cs.primary.withOpacity(isDark ? 0.72 : 0.78);

    final innerBg = cs.surface;
    final labelColor = cs.onSurface.withOpacity(0.85);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    padding: const EdgeInsets.all(2.4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [ring, ring.withOpacity(0.45)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(1.6),
                      decoration: BoxDecoration(
                        color: innerBg,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        backgroundColor: innerBg,
                        backgroundImage: hasPhoto ? NetworkImage(photoUrl!.trim()) : null,
                        child: !hasPhoto
                            ? Icon(Icons.person, color: cs.onSurface.withOpacity(0.70))
                            : null,
                      ),
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
                          border: Border.all(color: innerBg, width: 2),
                        ),
                        child: Icon(Icons.videocam_rounded, size: 12, color: cs.onPrimary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
