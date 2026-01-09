import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'services/notification_service.dart';
import 'providers/theme_provider.dart';
import 'providers/cv_analysis_provider.dart';

import 'theme/light_theme.dart';
import 'theme/dark_theme.dart';

import 'welcome_screen.dart';
import 'intro_screen.dart';
import 'auth_screen.dart';
import 'shell/main_nav_shell.dart';
import 'email_verify_screen.dart';

// 🔔 In-app notification servisi (local cache)
import 'in_app_notification.dart';

// ----------------------------------------------------------
// 1) BACKGROUND HANDLER (SADECE MOBİL)
// ----------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  await Firebase.initializeApp();
  debugPrint("🔥 BACKGROUND mesaj alındı: ${message.notification?.title}");
}

// ----------------------------------------------------------
// 2) Local Notification Plugin
// ----------------------------------------------------------
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // 🔥 Firebase init
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBrMSZ3awbO8M1CV9o-lCJ2KoyRJeYgF8Q",
        authDomain: "techconnectapp-e56d3.firebaseapp.com",
        projectId: "techconnectapp-e56d3",
        storageBucket: "techconnectapp-e56d3.firebasestorage.app",
        messagingSenderId: "443319926125",
        appId: "1:443319926125:web:49e08540ad5ed0d166ee64",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // 🔔 Bildirimler – SADECE MOBİL
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await flutterLocalNotificationsPlugin.initialize(initSettings);

    final messaging = FirebaseMessaging.instance;

    // ✅ İzin iste (bu ok)
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // ✅ Servis init
    NotificationService().initialize();
    setupForegroundNotificationListener();
  } else {
    NotificationService().initialize();
  }

  // 🚨 In-app notification cache (local)
  await inAppNotificationService.loadFromPrefs();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CvAnalysisProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

// ----------------------------------------------------------
// 3) FOREGROUND LISTENER
// ----------------------------------------------------------
void setupForegroundNotificationListener() {
  if (kIsWeb) return;

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final notification = message.notification;

    if (notification != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'Genel Bildirimler',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  });
}

// ----------------------------------------------------------
// 4) APP ROOT
// ----------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TechConnect',
      themeMode: themeProvider.themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: const WelcomeScreen(),
      routes: {
        '/intro': (_) => const IntroScreen(),
        '/welcome': (_) => const WelcomeScreen(),
        '/auth': (_) => const AuthScreen(),
        '/main': (_) => const MainNavShell(),
        '/verify-email': (_) => const EmailVerifyScreen(),
      },
    );
  }
}
