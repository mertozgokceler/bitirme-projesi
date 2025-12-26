import 'package:flutter/material.dart';
import '../in_app_notification.dart';

class NotificationsTab extends StatelessWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: inAppNotificationService,
      builder: (context, _) {
        final items = inAppNotificationService.items;

        if (items.isEmpty) {
          return const Center(
            child: Text('Henüz bildirimin yok.'),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final n = items[index];

            return ListTile(
              leading: Icon(
                n.isRead
                    ? Icons.notifications_none
                    : Icons.notifications_active,
                color: n.isRead
                    ? Colors.grey
                    : Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                n.title,
                style: TextStyle(
                  fontWeight:
                  n.isRead ? FontWeight.w500 : FontWeight.bold,
                ),
              ),
              subtitle: Text(n.message),
              onTap: () {
                // Bildirimi okundu yap
                inAppNotificationService.markAsRead(n.id);

                // İleride detay ekran istersek buradan açarız
                // Navigator.push(...);
              },
            );
          },
        );
      },
    );
  }
}
