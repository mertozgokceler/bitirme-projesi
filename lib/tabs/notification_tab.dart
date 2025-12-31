// lib/tabs/notification_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:lottie/lottie.dart';

import '../in_app_notification.dart';
import '../theme/app_colors.dart'; // ✅ senin semantic layer'ın

class NotificationsTab extends StatelessWidget {
  const NotificationsTab({super.key});

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Transform.translate(
          offset: const Offset(0, -90),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: Lottie.asset(
                  'assets/lottie/no_item_found.json',
                  repeat: true,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Henüz herhangi bir bildirim almadın',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Bildirim almaya başladıkça burada göreceksin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.subtleText(theme),
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

    return SlidableAutoCloseBehavior(
      child: AnimatedBuilder(
        animation: inAppNotificationService,
        builder: (context, _) {
          final items = inAppNotificationService.items;

          if (items.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final n = items[index];

              final bg = n.isRead
                  ? theme.colorScheme.surface
                  : theme.colorScheme.primary.withOpacity(0.12);

              final border = n.isRead
                  ? AppColors.listBorder(theme)
                  : theme.colorScheme.primary.withOpacity(0.5);

              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Slidable(
                  key: ValueKey('notif_${n.id}'),
                  closeOnScroll: true,
                  endActionPane: ActionPane(
                    motion: const BehindMotion(),
                    extentRatio: 0.30,
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
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              n.isRead
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              color: theme.colorScheme.onSurface,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.title,
                                    style: TextStyle(
                                      fontWeight: n.isRead
                                          ? FontWeight.w500
                                          : FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    n.message,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTime(n.createdAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.subtleText(theme),
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
