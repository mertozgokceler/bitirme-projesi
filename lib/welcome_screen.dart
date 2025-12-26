// lib/welcome_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String kVideoPath = 'assets/images/TechConnect.mp4';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const Duration kSplashDuration = Duration(seconds: 5);

  late final VideoPlayerController _controller;

  bool _showSubtitle = false;
  bool _videoReady = false;
  bool _navigated = false;

  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset(kVideoPath);
    _initVideo();

    // Subtitle animasyonu
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _showSubtitle = true);
    });

    // ✅ Splash süresi (tek otorite): 5 saniye sonra kesin geçiş
    _splashTimer = Timer(kSplashDuration, () {
      _navigateOnce();
    });
  }

  Future<void> _initVideo() async {
    try {
      await _controller.initialize();
      if (!mounted) return;

      setState(() => _videoReady = true);

      _controller
        ..setLooping(false)
        ..setVolume(0)
        ..play();
    } catch (_) {
      // Video yüklenemezse bile splash 5sn sonra geçecek.
    }
  }

  Future<void> _navigateOnce() async {
    if (!mounted || _navigated) return;
    _navigated = true;

    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('rememberMe') ?? false;
    final currentUser = FirebaseAuth.instance.currentUser;

    if (!mounted) return;

    if (rememberMe && currentUser != null) {
      Navigator.of(context).pushReplacementNamed('/main');
    } else {
      final dontShowIntro = prefs.getBool('intro_dont_show') ?? false;
      Navigator.of(context)
          .pushReplacementNamed(dontShowIntro ? '/auth' : '/intro');
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<Color> _backgroundGradient(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isDark) {
      return [
        const Color(0xFF090979),
        cs.primary.withOpacity(0.85),
        cs.secondary.withOpacity(0.75),
      ];
    }

    return [
      cs.primary.withOpacity(0.92),
      cs.secondary.withOpacity(0.78),
      cs.primary.withOpacity(0.55),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSplash = cs.onPrimary;

    final subtitleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: onSplash,
    );

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _backgroundGradient(context),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedOpacity(
                  opacity: _videoReady ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: _videoReady
                      ? SizedBox(
                    height: 120,
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  )
                      : SizedBox(
                    height: 120,
                    width: 120,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: onSplash,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                AnimatedSlide(
                  offset: _showSubtitle ? Offset.zero : const Offset(0, 1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: _showSubtitle ? 1 : 0,
                    duration: const Duration(milliseconds: 800),
                    child: Text(
                      'Tek Dokunuşla Geleceğine Adım At',
                      style: subtitleStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
