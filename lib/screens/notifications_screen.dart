// lib/screens/notifications_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../in_app_notification.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 60) return 'Şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          AnimatedBuilder(
            animation: inAppNotificationService,
            builder: (context, _) {
              if (inAppNotificationService.unreadCount == 0) {
                return const SizedBox.shrink();
              }
              return TextButton(
                onPressed: inAppNotificationService.markAllAsRead,
                child: const Text(
                  'Tümünü okundu işaretle',
                  style: TextStyle(color: Colors.white),
                ),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: inAppNotificationService,
        builder: (context, _) {
          final items = inAppNotificationService.items;

          if (items.isEmpty) {
            return const Center(child: Text('Henüz bildirimin yok.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final n = items[index];

              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Slidable(
                  key: ValueKey(n.id),

                  // sola kaydırınca sağdaki aksiyonlar açılır (endActionPane)
                  endActionPane: ActionPane(
                    motion: const ScrollMotion(),
                    extentRatio: 0.32, // kırmızı alan genişliği
                    children: [
                      SlidableAction(
                        onPressed: (_) {
                          inAppNotificationService.removeById(n.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bildirim silindi'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        icon: Icons.delete,
                        label: 'Sil',
                      ),
                    ],
                  ),

                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => inAppNotificationService.markAsRead(n.id),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: n.isRead
                              ? cs.surface
                              : cs.primary.withOpacity(0.12),
                          border: Border.all(
                            color: n.isRead
                                ? Colors.grey.withOpacity(0.30)
                                : cs.primary.withOpacity(0.50),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              n.isRead
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              color: cs.onSurface.withOpacity(0.85),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: n.isRead
                                          ? FontWeight.w600
                                          : FontWeight.w900,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    n.message,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withOpacity(0.85),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _formatTime(n.createdAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurface.withOpacity(0.55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
