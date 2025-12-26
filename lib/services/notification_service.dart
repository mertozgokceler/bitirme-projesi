// lib/services/notification_service.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return; // ✅ tek sefer
    _initialized = true;

    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    _setupForegroundNotifications();

    // ✅ Token refresh listener'ı TEK kez kur
    _tokenRefreshSub ??= _fcm.onTokenRefresh.listen((newToken) async {
      await _saveTokenForCurrentUser(newToken: newToken);
    });

    // ✅ Auth listener'ı TEK kez kur (login olunca token kaydet)
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      await _saveTokenForCurrentUser(); // token'ı çekip kaydeder
    });

    // App açılışında user zaten login ise kaçırma:
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      await _saveTokenForCurrentUser();
    }
  }

  /// ✅ Kritik kural:
  /// - users/{uid} doc'u YOKSA yazma! (hayalet hesap üretme)
  /// - token aynıysa boşuna yazma
  Future<void> _saveTokenForCurrentUser({String? newToken}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final uid = user.uid;

      // 1) users doc var mı?
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await userRef.get();

      if (!snap.exists) {
        // 🔥 İşte hayalet hesapları kesen bıçak bu.
        debugPrint(
            'DEBUG[notif] users/$uid yok -> token yazılmadı (ghost doc engellendi)');
        return;
      }

      // 2) token al
      final token = newToken ?? await _fcm.getToken();
      if (token == null || token.isEmpty) return;

      // 3) aynı token mı? boşuna yazma
      final data = snap.data();
      final existing = (data?['fcmToken'] ?? '').toString();
      if (existing == token) return;

      await userRef.set(
        {
          'fcmToken': token,
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      debugPrint('DEBUG[notif] token saved for uid=$uid');
    } catch (e) {
      debugPrint("DEBUG[notif] token kaydetme hatası: $e");
    }
  }

  Future<void> _setupForegroundNotifications() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'Yüksek Önemli Bildirimler',
      description: 'Bu kanal, önemli bildirimler için kullanılır.',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final android = message.notification?.android;

      if (notification != null && android != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'Yüksek Önemli Bildirimler',
              channelDescription: 'Bu kanal, önemli bildirimler için kullanılır.',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });
  }

  /// İstersen uygulama kapanırken çağırırsın.
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _authSub = null;
    _tokenRefreshSub = null;
    _initialized = false;
  }
}
