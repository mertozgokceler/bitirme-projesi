// lib/in_app_notification.dart

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tek bir bildirim modeli
class InAppNotificationModel {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  bool isRead;

  InAppNotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
  });

  factory InAppNotificationModel.fromJson(Map<String, dynamic> json) {
    return InAppNotificationModel(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isRead': isRead,
    };
  }
}

/// Uygulama içi bildirim servisi
class InAppNotificationService extends ChangeNotifier {
  String? _currentUserId;

  String get _prefsKey => 'inapp_notifications_v1_${_currentUserId ?? 'guest'}';

  final List<InAppNotificationModel> _items = [];

  List<InAppNotificationModel> get items => List.unmodifiable(_items);

  int get unreadCount => _items.where((n) => !n.isRead).length;

  bool _loaded = false;

  Future<void> initForUser(String? uid) async {
    _currentUserId = uid;
    _loaded = false;
    _items.clear();
    await loadFromPrefs();
  }

  Future<void> loadFromPrefs() async {
    if (_loaded) return;
    _loaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;

      final List decoded = jsonDecode(raw) as List;
      _items.clear();
      for (final e in decoded) {
        final map = Map<String, dynamic>.from(e as Map);
        _items.add(InAppNotificationModel.fromJson(map));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('DEBUG[inapp] loadFromPrefs error: $e');
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _items.take(100).map((n) => n.toJson()).toList();
      await prefs.setString(_prefsKey, jsonEncode(list));
    } catch (e) {
      debugPrint('DEBUG[inapp] _saveToPrefs error: $e');
    }
  }

  String _generateId() {
    final rand = Random();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'n_${ts}_${rand.nextInt(1 << 32)}';
  }

  void show(
      String title,
      String message, {
        BuildContext? context,
        bool showOverlay = true,
      }) {
    final model = InAppNotificationModel(
      id: _generateId(),
      title: title,
      message: message,
      createdAt: DateTime.now(),
      isRead: false,
    );

    _items.insert(0, model);

    notifyListeners();
    _saveToPrefs();

    if (showOverlay && context != null) {
      _showOverlayBanner(context, model);
    }
  }

  void markAsRead(String id) {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    if (_items[idx].isRead) return;

    _items[idx].isRead = true;
    notifyListeners();
    _saveToPrefs();
  }

  void markAllAsRead() {
    var changed = false;
    for (final n in _items) {
      if (!n.isRead) {
        n.isRead = true;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _saveToPrefs();
    }
  }

  void removeById(String id) {
    _items.removeWhere((n) => n.id == id);
    notifyListeners();
    _saveToPrefs();
  }

  void _showOverlayBanner(BuildContext context, InAppNotificationModel n) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final t = Theme.of(context);
    final ui = InAppNotifUI.of(t);

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 40,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: -80, end: 0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value),
                  child: child,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ui.bannerBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ui.bannerBorder),
                  boxShadow: [
                    BoxShadow(
                      color: ui.bannerShadow,
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_active,
                      color: ui.icon,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            style: TextStyle(
                              color: ui.title,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            n.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ui.message,
                              fontSize: 13,
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
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(const Duration(seconds: 3)).then((_) {
      entry.remove();
    });
  }
}

/// Global instance
final inAppNotificationService = InAppNotificationService();

/// ===========================================================
/// ✅ Tek yerden UI renk kararları (In-app notif banner)
/// ===========================================================
class InAppNotifUI {
  final Color bannerBg;
  final Color bannerBorder;
  final Color bannerShadow;

  final Color icon;
  final Color title;
  final Color message;

  InAppNotifUI._({
    required this.bannerBg,
    required this.bannerBorder,
    required this.bannerShadow,
    required this.icon,
    required this.title,
    required this.message,
  });

  static InAppNotifUI of(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;

    // Brand pembe: aynı “interaction” rengi
    const brand = Color(0xFFE57AFF);

    // Banner arka planı: koyu/aydınlık temaya göre ayarla
    final bg = isDark
        ? const Color(0xFF1A1C22)
        : const Color(0xFFFFFFFF);

    final border = isDark ? Colors.white10 : Colors.black12;

    final shadow = Colors.black.withOpacity(isDark ? 0.25 : 0.12);

    final icon = isDark ? brand : brand;

    final title = isDark ? Colors.white : Colors.black87;
    final message = isDark ? Colors.white70 : Colors.black54;

    return InAppNotifUI._(
      bannerBg: bg.withOpacity(isDark ? 0.92 : 0.90),
      bannerBorder: border,
      bannerShadow: shadow,
      icon: icon,
      title: title,
      message: message,
    );
  }
}
