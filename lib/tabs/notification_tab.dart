// lib/tabs/notification_tab.dart

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:lottie/lottie.dart';

import '../in_app_notification.dart';
import '../theme/app_colors.dart';

class NotificationsTab extends StatelessWidget {
  const NotificationsTab({super.key});

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

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

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                  fontWeight: FontWeight.w900,
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
                  color: isDark
                      ? theme.colorScheme.onSurface.withOpacity(0.60)
                      : AppColors.subtleText(theme),
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
    final cs = theme.colorScheme;

    return Stack(
      children: [
        Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
        Positioned(
          top: -120,
          left: -80,
          child: _GlowBlob(size: 260, color: cs.primary.withOpacity(0.20)),
        ),
        Positioned(
          bottom: -140,
          right: -90,
          child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18)),
        ),

        // ✅ içerik SafeArea içinde olmalı
        SafeArea(
          top: true,
          bottom: false,
          child: SlidableAutoCloseBehavior(
            child: AnimatedBuilder(
              animation: inAppNotificationService,
              builder: (context, _) {
                final items = inAppNotificationService.items;

                if (items.isEmpty) return _buildEmptyState(context);

                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  // ✅ artık status bar altına girmeyecek
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final n = items[index];

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
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
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              icon: Icons.delete_outline,
                              label: 'Sil',
                            ),
                          ],
                        ),
                        child: _NotifCard(
                          notification: n,
                          timeText: _formatTime(n.createdAt),
                          onTap: () {
                            inAppNotificationService.markAsRead(n.id);
                            inAppNotificationService.emitTap(n); // ✅ MainNavShell yakalayıp yönlendirecek
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NotifCard extends StatelessWidget {
  final InAppNotificationModel notification;
  final String timeText;
  final VoidCallback onTap;

  const _NotifCard({
    required this.notification,
    required this.timeText,
    required this.onTap,
  });

  String _prettyType(String t) {
    final v = t.trim().toLowerCase();
    switch (v) {
      case 'message':
        return 'Mesaj';
      case 'like':
        return 'Beğeni';
      case 'comment':
        return 'Yorum';
      case 'match':
        return 'Eşleşme';
      case 'follow':
        return 'Takip';
      case 'system':
      default:
        return 'Bildirim';
    }
  }

  IconData _typeIcon(String t) {
    final v = t.trim().toLowerCase();
    switch (v) {
      case 'message':
        return Icons.chat_bubble_outline;
      case 'like':
        return Icons.thumb_up_alt_outlined;
      case 'comment':
        return Icons.mode_comment_outlined;
      case 'match':
        return Icons.auto_awesome;
      case 'follow':
        return Icons.person_add_alt_1_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bool isRead = notification.isRead;

    final fill = isDark
        ? Colors.white.withOpacity(isRead ? 0.055 : 0.075)
        : Colors.white.withOpacity(isRead ? 0.72 : 0.82);

    final border = isDark
        ? Colors.white.withOpacity(isRead ? 0.12 : 0.20)
        : Colors.black.withOpacity(isRead ? 0.08 : 0.10);

    final accent = isRead ? cs.onSurface.withOpacity(0.70) : cs.primary;

    final typeLabel = _prettyType(notification.type);
    final typeIcon = _typeIcon(notification.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 0.9),
            boxShadow: [
              BoxShadow(
                blurRadius: 22,
                spreadRadius: 3,
                color: Colors.black.withOpacity(isDark ? 0.22 : 0.10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotifIcon(accent: accent, icon: typeIcon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // type + new + time
                    Row(
                      children: [
                        _Pill(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(typeIcon, size: 14, color: accent),
                              const SizedBox(width: 6),
                              Text(
                                typeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!isRead)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: theme.colorScheme.primary.withOpacity(0.35)),
                            ),
                            child: Text(
                              'Yeni',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        const Spacer(),
                        _Pill(
                          child: Text(
                            timeText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isRead ? FontWeight.w700 : FontWeight.w900,
                        fontSize: 14,
                        height: 1.15,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),

                    Text(
                      notification.message,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: isDark
                            ? theme.colorScheme.onSurface.withOpacity(0.78)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    if (!isRead) ...[
                      const SizedBox(height: 10),
                      Container(
                        height: 2,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [
                              cs.primary.withOpacity(0.60),
                              cs.tertiary.withOpacity(0.25),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget child;
  const _Pill({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.18 : 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }
}

class _NotifIcon extends StatelessWidget {
  final Color accent;
  final IconData icon;

  const _NotifIcon({required this.accent, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fill = theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.20 : 0.65);
    final border = isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.06);

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Center(
        child: Icon(icon, color: accent, size: 22),
      ),
    );
  }
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