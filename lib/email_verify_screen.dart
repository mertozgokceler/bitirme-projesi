// lib/email_verify_screen.dart

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EmailVerifyScreen extends StatefulWidget {
  const EmailVerifyScreen({super.key});

  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  final _auth = FirebaseAuth.instance;
  bool _sending = false;

  String get _emailText =>
      _auth.currentUser?.email ?? 'Kayıt olurken kullandığın e-posta adresi';

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _resendEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      _snack('Oturum bulunamadı. Lütfen tekrar giriş yap.');
      return;
    }

    setState(() => _sending = true);
    try {
      await user.sendEmailVerification();
      _snack('Doğrulama e-postasını tekrar gönderdik. Gelen kutunu kontrol et.');
    } catch (e) {
      _snack('Mail gönderilemedi: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final onSplash = EmailVerifyColors.onSplash(t);
    final interaction = EmailVerifyColors.interaction(t);

    return Scaffold(
      body: Stack(
        children: [
          // ✅ Theme + brand uyumlu gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: EmailVerifyColors.backgroundGradient(t),
              ),
            ),
          ),

          Positioned(
            top: -60,
            right: -40,
            child: _BlurBall(
              size: 180,
              opacity: EmailVerifyColors.blurBallOpacity(t, strong: true),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -50,
            child: _BlurBall(
              size: 200,
              opacity: EmailVerifyColors.blurBallOpacity(t, strong: false),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _FrostedCard(
                    surfaceColor: EmailVerifyColors.cardSurface(t),
                    borderColor: EmailVerifyColors.cardBorder(t),
                    shadowColor: EmailVerifyColors.cardShadow(t),
                    child: Padding(
                      padding: const EdgeInsets.all(22.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 180,
                            child: SvgPicture.asset(
                              'assets/images/mailbox.svg',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 20),

                          Text(
                            'E-postanı Kontrol Et ✉️',
                            style: t.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: onSplash,
                              shadows: const [
                                Shadow(
                                  blurRadius: 12,
                                  color: Colors.black26,
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),

                          Text(
                            'TechConnect hesabını aktifleştirmek için sana bir '
                                'doğrulama e-postası gönderdik.',
                            style: t.textTheme.bodyMedium?.copyWith(
                              color: onSplash.withOpacity(0.75),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),

                          Text(
                            'Lütfen gelen kutunu (ve gerekirse spam / gereksiz '
                                'kutusunu) kontrol etmeyi unutma.',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: onSplash.withOpacity(0.60),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),

                          // ✅ mail kutusu chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: EmailVerifyColors.mailChipBg(t),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: EmailVerifyColors.mailChipBorder(t),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.alternate_email,
                                  color: interaction,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _emailText,
                                    style: TextStyle(
                                      color: onSplash,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ✅ resend button (hover/pressed -> pembe)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _sending ? null : _resendEmail,
                              icon: _sending
                                  ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                                  : const Icon(Icons.refresh_rounded),
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Doğrulama mailini tekrar gönder'),
                              ),
                              style: ButtonStyle(
                                backgroundColor:
                                WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.disabled)) {
                                    return EmailVerifyColors.disabledBtnBg(t);
                                  }
                                  if (states.contains(WidgetState.pressed) ||
                                      states.contains(WidgetState.hovered)) {
                                    return interaction.withOpacity(0.85);
                                  }
                                  return t.colorScheme.primary;
                                }),
                                foregroundColor: WidgetStatePropertyAll(
                                  EmailVerifyColors.onPrimary(t),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ✅ back to auth
                          TextButton.icon(
                            onPressed: () async {
                              await _auth.signOut();
                              if (!mounted) return;
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/auth',
                                    (route) => false,
                              );
                            },
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            label: const Text('Giriş ekranına dön'),
                            style: ButtonStyle(
                              foregroundColor: WidgetStatePropertyAll(
                                onSplash.withOpacity(0.80),
                              ),
                              overlayColor: WidgetStatePropertyAll(
                                interaction.withOpacity(0.12),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Hesabını doğruladıktan sonra giriş ekranına dönüp '
                                'mail adresin ve şifrenle tekrar giriş yapabilirsin.',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: onSplash.withOpacity(0.60),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrostedCard extends StatelessWidget {
  final Widget child;
  final Color surfaceColor;
  final Color borderColor;
  final Color shadowColor;

  const _FrostedCard({
    required this.child,
    required this.surfaceColor,
    required this.borderColor,
    required this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                blurRadius: 24,
                color: shadowColor,
                offset: const Offset(0, 12),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BlurBall extends StatelessWidget {
  final double size;
  final double opacity;
  const _BlurBall({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                Color(0xFFFFFFFF),
                Color(0x66FFFFFF),
                Color(0x11FFFFFF),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===========================================================
/// ✅ EMAIL VERIFY RENK TOKENLARI (tek yer)
/// Not: Auth'taki AppColors ile birleştirmen lazım.
/// ===========================================================
class EmailVerifyColors {
  // Brand interaction (pembe)
  static Color interaction(ThemeData t) => const Color(0xFFE57AFF);

  static List<Color> backgroundGradient(ThemeData t) {
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    if (isDark) {
      return [
        const Color(0xFF090979),
        cs.primary.withOpacity(0.90),
        cs.secondary.withOpacity(0.75),
      ];
    }
    return [
      cs.primary.withOpacity(0.92),
      cs.secondary.withOpacity(0.78),
      cs.primary.withOpacity(0.55),
    ];
  }

  static Color onSplash(ThemeData t) => t.colorScheme.onPrimary;
  static Color onPrimary(ThemeData t) => t.colorScheme.onPrimary;

  static double blurBallOpacity(ThemeData t, {required bool strong}) {
    final isDark = t.brightness == Brightness.dark;
    if (isDark) return strong ? 0.22 : 0.18;
    return strong ? 0.16 : 0.12;
  }

  static Color cardSurface(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.white.withOpacity(0.14);
  }

  static Color cardBorder(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark
        ? Colors.white.withOpacity(0.16)
        : Colors.white.withOpacity(0.20);
  }

  static Color cardShadow(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark ? Colors.black.withOpacity(0.30) : Colors.black.withOpacity(0.18);
  }

  static Color mailChipBg(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.10);
  }

  static Color mailChipBorder(ThemeData t) => onSplash(t).withOpacity(0.25);

  static Color disabledBtnBg(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.10);
  }
}
