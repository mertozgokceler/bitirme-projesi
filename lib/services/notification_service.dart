// lib/services/notification_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../in_app_notification.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;

  bool _initialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Yüksek Önemli Bildirimler',
    description: 'Bu kanal, önemli bildirimler için kullanılır.',
    importance: Importance.max,
  );

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    await _initLocalNotifications();
    await _setupForegroundNotifications();

    // ✅ background -> tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap);

    // ✅ terminated -> tap
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleFcmTap(initial);

    _tokenRefreshSub ??= _fcm.onTokenRefresh.listen((newToken) async {
      await _saveTokenForCurrentUser(newToken: newToken);
    });

    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      await _saveTokenForCurrentUser();
    });

    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      await _saveTokenForCurrentUser();
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;

        try {
          final decoded = jsonDecode(payload);
          if (decoded is! Map) return;

          final map = Map<String, dynamic>.from(decoded);
          final model = InAppNotificationModel.fromJson(map);

          // ✅ sadece tap event (listeye ekleme yok)
          inAppNotificationService.emitTap(model);
        } catch (e) {
          debugPrint('DEBUG[notif] payload parse error: $e');
        }
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  Future<void> _saveTokenForCurrentUser({String? newToken}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final uid = user.uid;

      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await userRef.get();

      if (!snap.exists) {
        debugPrint(
            'DEBUG[notif] users/$uid yok -> token yazılmadı (ghost doc engellendi)');
        return;
      }

      final token = newToken ?? await _fcm.getToken();
      if (token == null || token.isEmpty) return;

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
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final android = message.notification?.android;

      final data = message.data;
      final type = (data['type'] ?? data['notifType'] ?? 'system').toString();

      final title =
      (notification?.title ?? data['title'] ?? 'Bildirim').toString();
      final body = (notification?.body ?? data['message'] ?? '').toString();

      // ✅ ÖNEMLİ: In-app listeye ASLA yazma.
      // inAppNotificationService.show(...)  -> SİLİNDİ

      // ✅ Sadece telefon bildirimi göster (foreground)
      if (notification != null && android != null) {
        final modelForPayload = InAppNotificationModel(
          id: 'push_${DateTime.now().millisecondsSinceEpoch}',
          type: type,
          title: title,
          message: body,
          createdAt: DateTime.now(),
          isRead: false,
          data: Map<String, dynamic>.from(data),
        );

        _localNotifications.show(
          notification.hashCode,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
          payload: jsonEncode(modelForPayload.toJson()),
        );
      }
    });
  }

  void _handleFcmTap(RemoteMessage message) {
    try {
      final data = message.data;

      final type = (data['type'] ?? data['notifType'] ?? 'system').toString();
      final title =
      (message.notification?.title ?? data['title'] ?? 'Bildirim').toString();
      final body =
      (message.notification?.body ?? data['message'] ?? '').toString();

      final model = InAppNotificationModel(
        id: 'push_tap_${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        title: title,
        message: body,
        createdAt: DateTime.now(),
        isRead: false,
        data: Map<String, dynamic>.from(data),
      );

      // ✅ sadece yönlendirme için tap event
      inAppNotificationService.emitTap(model);
    } catch (e) {
      debugPrint('DEBUG[notif] _handleFcmTap error: $e');
    }
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _authSub = null;
    _tokenRefreshSub = null;
    _initialized = false;
  }
}
