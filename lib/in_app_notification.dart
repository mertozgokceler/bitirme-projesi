// lib/in_app_notification.dart

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tek bir bildirim modeli
class InAppNotificationModel {
  final String id;

  /// type (message, like, comment, match, follow, system...)
  final String type;

  final String title;
  final String message;
  final DateTime createdAt;
  bool isRead;

  /// Payload: ilgili sayfaya yönlendirmek için hedef id'ler burada taşınır
  /// Örn:
  ///  - message: {chatId, peerId}
  ///  - like/comment: {postId}
  ///  - follow: {userId}
  ///  - match: {jobId}
  final Map<String, dynamic> data;

  InAppNotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
    Map<String, dynamic>? data,
  }) : data = data ?? const {};

  static String _s(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    final x = v.toString().trim();
    return x.isEmpty ? fallback : x;
  }

  static bool _b(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return fallback;
  }

  static DateTime _dt(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    final s = v.toString().trim();
    final parsed = int.tryParse(s);
    if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
    final iso = DateTime.tryParse(s);
    return iso ?? DateTime.now();
  }

  static Map<String, dynamic> _map(dynamic v) {
    if (v == null) return <String, dynamic>{};
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  factory InAppNotificationModel.fromJson(Map<String, dynamic> json) {
    final id = _s(json['id'], fallback: 'n_${DateTime.now().millisecondsSinceEpoch}');
    final type = _s(json['type'], fallback: 'system');
    final title = _s(json['title'], fallback: 'Bildirim');
    final message = _s(json['message'], fallback: '');
    final createdAt = _dt(json['createdAt']);
    final isRead = _b(json['isRead'], fallback: false);
    final data = _map(json['data']);

    return InAppNotificationModel(
      id: id,
      type: type,
      title: title,
      message: message,
      createdAt: createdAt,
      isRead: isRead,
      data: data,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'message': message,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isRead': isRead,
      'data': data,
    };
  }
}

class InAppNotificationService extends ChangeNotifier {
  String? _currentUserId;

  String get _prefsKey => 'inapp_notifications_v1_${_currentUserId ?? 'guest'}';

  final List<InAppNotificationModel> _items = [];
  List<InAppNotificationModel> get items => List.unmodifiable(_items);

  int get unreadCount => _items.where((n) => !n.isRead).length;

  bool _loaded = false;

  /// Bildirime tıklama olayı
  final ValueNotifier<InAppNotificationModel?> tappedNotification = ValueNotifier(null);

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

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      _items.clear();
      for (final e in decoded) {
        if (e is Map) {
          final map = Map<String, dynamic>.from(e);
          _items.add(InAppNotificationModel.fromJson(map));
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('DEBUG[inapp] loadFromPrefs error: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey);
      } catch (_) {}
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

  Future<void> clearAll() async {
    _items.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
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
        String type = 'system',
        Map<String, dynamic>? data,
        VoidCallback? onOverlayTap,
      }) {
    final model = InAppNotificationModel(
      id: _generateId(),
      type: type.trim().isEmpty ? 'system' : type.trim(),
      title: title.trim().isEmpty ? 'Bildirim' : title.trim(),
      message: message.trim(),
      createdAt: DateTime.now(),
      isRead: false,
      data: data,
    );

    _items.insert(0, model);
    notifyListeners();
    _saveToPrefs();

    if (showOverlay && context != null) {
      _showOverlayBanner(context, model, onTap: onOverlayTap);
    }
  }

  void emitTap(InAppNotificationModel n) {
    tappedNotification.value = n;
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

  void _showOverlayBanner(
      BuildContext context,
      InAppNotificationModel n, {
        VoidCallback? onTap,
      }) {
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
                return Transform.translate(offset: Offset(0, value), child: child);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  try {
                    entry.remove();
                  } catch (_) {}
                  onTap?.call();
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
                      Icon(Icons.notifications_active, color: ui.icon, size: 24),
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
                              style: TextStyle(color: ui.message, fontSize: 13),
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

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3)).then((_) {
      try {
        entry.remove();
      } catch (_) {}
    });
  }
}

final inAppNotificationService = InAppNotificationService();

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

    const brand = Color(0xFFE57AFF);

    final bg = isDark ? const Color(0xFF1A1C22) : const Color(0xFFFFFFFF);
    final border = isDark ? Colors.white10 : Colors.black12;
    final shadow = Colors.black.withOpacity(isDark ? 0.25 : 0.12);

    final title = isDark ? Colors.white : Colors.black87;
    final message = isDark ? Colors.white70 : Colors.black54;

    return InAppNotifUI._(
      bannerBg: bg.withOpacity(isDark ? 0.92 : 0.90),
      bannerBorder: border,
      bannerShadow: shadow,
      icon: brand,
      title: title,
      message: message,
    );
  }
}
