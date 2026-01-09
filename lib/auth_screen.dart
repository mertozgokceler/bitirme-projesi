// lib/auth_screen.dart

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'in_app_notification.dart';
import 'services/auth_flow.dart';
import 'services/auth/auth_facade.dart';
import 'services/auth/auth_types.dart';
import 'services/auth/auth_errors.dart';

const String kLogoPath = 'assets/images/techconnectlogo.png';
const String kIconGoogle = 'assets/icons/google.png';
const String kIconGithub = 'assets/icons/github.png';
const String kIconApple = 'assets/icons/apple.png';


const String kTermsAsset = 'assets/legal/terms_tr.md';
const String kPrivacyAsset = 'assets/legal/privacy_tr.md';

const String kLottieLogin = 'assets/lottie/login.json';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // ---- flow
  final AuthFlow _flow = AuthFlow(fs: FirebaseFirestore.instance);
  final AuthFacade _auth = AuthFacade();


  // ---- form
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  bool _rememberMe = true;
  bool _obscure = true;
  bool _loading = false;

  // ---- stage
  bool _showAuthCard = false;

  // ---- mode
  bool _isLogin = true;

  // ---- company mode
  bool _isCompany = false;
  final _taxCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _activityOtherCtrl = TextEditingController();
  final List<String> _activities = const [
    'Yazılım',
    'E-ticaret',
    'Eğitim',
    'Sağlık',
    'Finans',
    'Üretim',
    'Enerji',
    'Lojistik',
    'Medya',
    'Diğer',
  ];
  String? _selectedActivity;

  // ---- legal
  bool _agreeTerms = false;
  bool _agreePrivacy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();

    _taxCtrl.dispose();
    _companyCtrl.dispose();
    _activityOtherCtrl.dispose();
    super.dispose();
  }

  // =========================
  // Helpers
  // =========================
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _niceAuthError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'E-posta formatı hatalı.';
        case 'user-not-found':
          return 'Bu e-posta ile kayıtlı kullanıcı yok.';
        case 'wrong-password':
          return 'Şifre yanlış.';
        case 'invalid-credential':
          return 'E-posta/şifre hatalı.';
        case 'email-already-in-use':
          return 'Bu e-posta zaten kullanımda.';
        case 'weak-password':
          return 'Şifre çok zayıf (en az 8 karakter önerilir).';
        case 'network-request-failed':
          return 'Ağ hatası. İnternetini kontrol et.';
        default:
          return e.message ?? 'Kimlik doğrulama hatası';
      }
    }
    return e.toString();
  }

  Future<String> _loadAssetText(String path) async {
    return DefaultAssetBundle.of(context).loadString(path);
  }

  Future<void> _openTermsSheet() async {
    final text = await _loadAssetText(kTermsAsset);

    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LegalAcceptSheet(
        title: 'Kullanıcı Sözleşmesi',
        body: text,
      ),
    );

    if (accepted == true && mounted) {
      setState(() => _agreeTerms = true);
    }
  }

  Future<void> _openPrivacySheet() async {
    final text = await _loadAssetText(kPrivacyAsset);

    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LegalAcceptSheet(
        title: 'Gizlilik Politikası',
        body: text,
      ),
    );

    if (accepted == true && mounted) {
      setState(() => _agreePrivacy = true);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _snack('Şifre sıfırlama için e-posta gir.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack('Şifre sıfırlama bağlantısı e-postana gönderildi.');
    } catch (e) {
      _snack(_niceAuthError(e));
    }
  }

  void _switchMode(bool login) {
    setState(() => _isLogin = login);
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    // Register için legal zorunlu
    if (!_isLogin && (!(_agreeTerms && _agreePrivacy))) {
      if (!_agreeTerms && !_agreePrivacy) {
        _snack('Devam etmek için sözleşme ve gizlilik politikasını kabul et.');
      } else if (!_agreeTerms) {
        _snack('Devam etmek için Kullanıcı Sözleşmesini kabul et.');
      } else {
        _snack('Devam etmek için Gizlilik Politikasını kabul et.');
      }
      return;
    }

    // Company ekstra kontroller
    if (!_isLogin && _isCompany) {
      if (_selectedActivity == null || _selectedActivity!.isEmpty) {
        _snack('Faaliyet alanı seçin.');
        return;
      }
      if (_selectedActivity == 'Diğer' &&
          _activityOtherCtrl.text.trim().isEmpty) {
        _snack('Faaliyet alanını yazın.');
        return;
      }
    }

    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await _flow.login(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
          rememberMe: _rememberMe,
        );
      } else {
        final activity = !_isCompany
            ? null
            : (_selectedActivity == 'Diğer'
            ? _activityOtherCtrl.text.trim()
            : _selectedActivity);

        await _flow.register(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
          name: _nameCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          isCompany: _isCompany,
          companyName: _isCompany ? _companyCtrl.text.trim() : null,
          taxNo: _isCompany ? _taxCtrl.text.trim() : null,
          activity: _isCompany ? activity?.trim() : null,
          acceptedTerms: true,
          acceptedPrivacy: true,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rememberMe', _rememberMe);

      // notif
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await inAppNotificationService.initForUser(uid);

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (r) => false);
    } catch (e) {
      _snack(_niceAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _social(AuthProviderType type) async {
    if (_loading) return;

    setState(() => _loading = true);
    try {
      await _auth.signIn(type);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rememberMe', _rememberMe);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await inAppNotificationService.initForUser(uid);

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (r) => false);
    } on AuthFailure catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(_niceAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // background gradient (senin renkler)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF4B3CFF),
                  Color(0xFFB06CFF),
                ],
              ),
            ),
          ),

          // soft blobs
          const Positioned(
            top: -70,
            right: -60,
            child: _BlurBall(size: 220, opacity: 0.18),
          ),
          const Positioned(
            bottom: -70,
            left: -60,
            child: _BlurBall(size: 240, opacity: 0.14),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _CardFlipStage(
                    showAuth: _showAuthCard,
                    duration: const Duration(milliseconds: 820),
                    welcome: _buildWelcomeCard(t),
                    auth: _buildAuthCard(t),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard(ThemeData t) {
    final on = Colors.white;

    return _FrostedCard(
      key: const ValueKey('welcome'),
      surfaceColor: Colors.white.withOpacity(0.14),
      borderColor: Colors.white.withOpacity(0.20),
      shadowColor: Colors.black.withOpacity(0.18),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo + Title
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white.withOpacity(0.18),
                  child: ClipOval(
                    child: Image.asset(
                      kLogoPath,
                      width: 30,
                      height: 30,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.link_off,
                        color: on.withOpacity(0.85),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'TechConnect',
                  style: t.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: on,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Lottie ortada, arka planı “card gibi” değil
            SizedBox(
              height: 240,
              child: Center(
                child: IgnorePointer(
                  child: SizedBox(
                    width: 240,
                    height: 240,
                    child: Lottie.asset(
                      kLottieLogin,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.auto_awesome_rounded,
                        size: 92,
                        color: on.withOpacity(0.85),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Hesabına giriş yap veya hızlıca kayıt ol',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(
                color: on.withOpacity(0.88),
              ),
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => setState(() => _showAuthCard = true),
                style: ButtonStyle(
                  backgroundColor: const WidgetStatePropertyAll(Colors.white),
                  foregroundColor:
                  const WidgetStatePropertyAll(Color(0xFF4B3CFF)),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                child: const Text(
                  'Devam Et',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthCard(ThemeData t) {
    final on = Colors.white;

    return _FrostedCard(
      key: const ValueKey('auth'),
      surfaceColor: Colors.white.withOpacity(0.14),
      borderColor: Colors.white.withOpacity(0.20),
      shadowColor: Colors.black.withOpacity(0.18),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderMini(on: on),
            const SizedBox(height: 14),

            // segmented login/register
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Row(
                children: [
                  _segBtn(on, true, 'Giriş Yap'),
                  _segBtn(on, false, 'Kayıt Ol'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Form(
              key: _formKey,
              child: _FlipSwitcher(
                isLogin: _isLogin,
                duration: const Duration(milliseconds: 760),
                front: _buildLoginForm(t, on),
                back: _buildRegisterForm(t, on),
              ),
            ),

            const SizedBox(height: 14),

// socials: yuvarlak + yan yana + metinsiz (Google + GitHub + Apple + Facebook)
            const _DividerWithText(text: 'veya'),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 14,
              children: [
                _SocialRoundIcon(
                  asset: kIconGoogle,
                  tooltip: 'Google',
                  onTap: _loading ? () {} : () => _social(AuthProviderType.google),
                ),
                _SocialRoundIcon(
                  asset: kIconGithub,
                  tooltip: 'GitHub',
                  onTap: _loading ? () {} : () => _social(AuthProviderType.github),
                ),
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                  _SocialRoundIcon(
                    asset: kIconApple,
                    tooltip: 'Apple',
                    onTap: _loading ? () {} : () => _social(AuthProviderType.apple),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // back to welcome
            TextButton(
              onPressed: () => setState(() => _showAuthCard = false),
              child: Text(
                '← Geri',
                style: TextStyle(color: on.withOpacity(0.9)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segBtn(Color on, bool login, String text) {
    final active = _isLogin == login;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(login),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white.withOpacity(0.92) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                color: active ? const Color(0xFF4B3CFF) : on.withOpacity(0.85),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================
  // Forms
  // =========================
  Widget _buildLoginForm(ThemeData t, Color on) {
    return Column(
      key: const ValueKey('login'),
      children: [
        _field(
          t,
          controller: _emailCtrl,
          label: 'E-posta',
          prefix: Icons.alternate_email,
          validator: _emailValidator,
        ),
        const SizedBox(height: 12),
        _field(
          t,
          controller: _passwordCtrl,
          label: 'Şifre',
          prefix: Icons.lock_outline,
          obscure: _obscure,
          validator: _passwordValidator,
          suffix: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure ? Icons.visibility : Icons.visibility_off,
              color: on.withOpacity(0.85),
            ),
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Checkbox(
              value: _rememberMe,
              onChanged: (v) => setState(() => _rememberMe = v ?? true),
              activeColor: const Color(0xFFE57AFF),
              checkColor: Colors.white,
            ),
            Text(
              'Beni hatırla',
              style: TextStyle(color: on.withOpacity(0.92)),
            ),
            const Spacer(),
            TextButton(
              onPressed: _forgotPassword,
              child: Text(
                'Şifremi unuttum',
                style: TextStyle(
                  color: on.withOpacity(0.95),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),
        _primaryBtn(
          t,
          text: 'Giriş Yap',
          icon: Icons.login_rounded,
          onTap: _submit,
        ),
      ],
    );
  }

  Widget _buildRegisterForm(ThemeData t, Color on) {
    return Column(
      key: const ValueKey('register'),
      children: [
        // individual/company selector
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _isCompany = false;
                    _selectedActivity = null;
                    _taxCtrl.clear();
                    _companyCtrl.clear();
                    _activityOtherCtrl.clear();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !_isCompany
                          ? Colors.white.withOpacity(0.92)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Bireysel',
                        style: TextStyle(
                          color: !_isCompany
                              ? const Color(0xFF4B3CFF)
                              : on.withOpacity(0.85),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isCompany = true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _isCompany
                          ? Colors.white.withOpacity(0.92)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Şirket',
                        style: TextStyle(
                          color: _isCompany
                              ? const Color(0xFF4B3CFF)
                              : on.withOpacity(0.85),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        _field(
          t,
          controller: _nameCtrl,
          label: _isCompany ? 'Ad Soyad (isteğe bağlı)' : 'Ad Soyad',
          prefix: Icons.person_outline,
          validator: (v) {
            if (!_isCompany) {
              if (v == null || v.trim().length < 2) {
                return 'Lütfen adınızı girin';
              }
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        _field(
          t,
          controller: _usernameCtrl,
          label: 'Kullanıcı Adı',
          prefix: Icons.account_circle_outlined,
          validator: (v) =>
          (v == null || v.trim().length < 3) ? 'En az 3 karakter girin' : null,
        ),
        const SizedBox(height: 12),
        _field(
          t,
          controller: _emailCtrl,
          label: 'E-posta',
          prefix: Icons.alternate_email,
          validator: _emailValidator,
        ),
        const SizedBox(height: 12),
        _field(
          t,
          controller: _passwordCtrl,
          label: 'Şifre',
          prefix: Icons.lock_outline,
          obscure: _obscure,
          helperText: 'En az 8 karakter önerilir.',
          validator: _passwordValidator,
          suffix: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure ? Icons.visibility : Icons.visibility_off,
              color: on.withOpacity(0.85),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _field(
          t,
          controller: _confirmCtrl,
          label: 'Şifre (tekrar)',
          prefix: Icons.lock_person_outlined,
          obscure: _obscure,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Lütfen şifrenizi tekrar girin';
            if (v != _passwordCtrl.text) return 'Şifreler uyuşmuyor';
            return null;
          },
        ),

        if (_isCompany) ...[
          const SizedBox(height: 12),
          _field(
            t,
            controller: _companyCtrl,
            label: 'Şirket Adı',
            prefix: Icons.business_outlined,
            validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Şirket adı zorunlu' : null,
          ),
          const SizedBox(height: 12),
          _field(
            t,
            controller: _taxCtrl,
            label: 'Vergi Numarası (10 hane)',
            prefix: Icons.numbers,
            keyboardType: TextInputType.number,
            validator: (v) {
              if (!_isCompany) return null;
              if (v == null || v.trim().isEmpty) return 'Vergi numarası zorunlu';
              final ok = RegExp(r'^\d{10}$').hasMatch(v.trim());
              return ok ? null : 'Geçerli bir vergi no girin (10 hane)';
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedActivity,
            items: _activities
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _selectedActivity = v),
            dropdownColor: const Color(0xFF121317),
            iconEnabledColor: Colors.white.withOpacity(0.9),
            style: const TextStyle(color: Colors.white),
            decoration: _dec(t, 'Faaliyet Alanı', prefix: Icons.work_outline),
            validator: (v) {
              if (!_isCompany) return null;
              return (v == null || v.isEmpty) ? 'Faaliyet alanı seçin' : null;
            },
          ),
          if (_selectedActivity == 'Diğer') ...[
            const SizedBox(height: 12),
            _field(
              t,
              controller: _activityOtherCtrl,
              label: 'Faaliyet Alanı (Diğer)',
              prefix: Icons.edit_outlined,
              validator: (v) {
                if (_isCompany && _selectedActivity == 'Diğer') {
                  if (v == null || v.trim().isEmpty) return 'Lütfen alanı yazın';
                }
                return null;
              },
            ),
          ],
        ],

        const SizedBox(height: 12),
        _LegalRow(
          checked: _agreeTerms,
          onChanged: (v) async {
            if (v == true) {
              await _openTermsSheet();
            } else {
              setState(() => _agreeTerms = false);
            }
          },
          leadingText: 'Kullanıcı Sözleşmesini ',
          linkText: 'okudum ve kabul ediyorum',
          onLinkTap: _openTermsSheet,
          textColor: on.withOpacity(0.92),
          linkColor: on,
        ),
        const SizedBox(height: 6),
        _LegalRow(
          checked: _agreePrivacy,
          onChanged: (v) async {
            if (v == true) {
              await _openPrivacySheet();
            } else {
              setState(() => _agreePrivacy = false);
            }
          },
          leadingText: 'Gizlilik Politikasını ',
          linkText: 'okudum ve kabul ediyorum',
          onLinkTap: _openPrivacySheet,
          textColor: on.withOpacity(0.92),
          linkColor: on,
        ),

        const SizedBox(height: 10),
        _primaryBtn(
          t,
          text: 'Kayıt Ol',
          icon: Icons.app_registration_rounded,
          onTap: _submit,
        ),
      ],
    );
  }

  // =========================
  // Input helpers
  // =========================
  Widget _field(
      ThemeData t, {
        required TextEditingController controller,
        required String label,
        IconData? prefix,
        Widget? suffix,
        bool obscure = false,
        String? helperText,
        TextInputType? keyboardType,
        String? Function(String?)? validator,
      }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      cursorColor: const Color(0xFFE57AFF),
      style: const TextStyle(color: Colors.white),
      decoration:
      _dec(t, label, prefix: prefix, suffix: suffix, helperText: helperText),
      validator: validator,
    );
  }

  InputDecoration _dec(
      ThemeData t,
      String label, {
        IconData? prefix,
        Widget? suffix,
        String? helperText,
      }) {
    final onField = Colors.white.withOpacity(0.95);
    final border = Colors.white.withOpacity(0.22);
    final focused = Colors.white.withOpacity(0.82);

    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: border, width: 1),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: focused, width: 1.4),
    );

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: onField.withOpacity(0.85)),
      helperText: helperText,
      helperStyle: TextStyle(color: onField.withOpacity(0.65)),
      prefixIcon: prefix != null
          ? Icon(prefix, color: onField.withOpacity(0.85))
          : null,
      suffixIcon: suffix,
      enabledBorder: baseBorder,
      focusedBorder: focusedBorder,
      errorBorder: baseBorder.copyWith(
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
      focusedErrorBorder: focusedBorder.copyWith(
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _primaryBtn(
      ThemeData t, {
        required String text,
        required IconData icon,
        required VoidCallback onTap,
      }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: _loading ? null : onTap,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) {
              return Colors.white.withOpacity(0.35);
            }
            return Colors.white.withOpacity(0.92);
          }),
          foregroundColor: const WidgetStatePropertyAll(Color(0xFF4B3CFF)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        child: _loading
            ? const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF4B3CFF),
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  // validators
  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'E-posta zorunlu';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
    return ok ? null : 'Geçerli bir e-posta girin';
    // (evet, bu regex basit. İşini görür.)
  }

  String? _passwordValidator(String? v) {
    if (v == null || v.length < 8) return 'Şifre en az 8 karakter olmalı';
    return null;
  }
}

// ===========================================================
// ✅ 3D FLIP SWITCHER (login <-> register “takla”)
// ===========================================================
class _FlipSwitcher extends StatelessWidget {
  const _FlipSwitcher({
    required this.isLogin,
    required this.front,
    required this.back,
    required this.duration,
  });

  final bool isLogin;
  final Widget front;
  final Widget back;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final rotate = Tween<double>(begin: math.pi, end: 0).animate(anim);

        return AnimatedBuilder(
          animation: rotate,
          child: child,
          builder: (_, child) {
            final angle = rotate.value;

            // çocuk key’inden hangi yüz olduğunu anla
            final isUnder = child!.key != ValueKey(isLogin);

            final transform = Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(isUnder ? angle : -angle);

            // 90° sonrası child'ı gizle (ayna görüntüsü/ters yazı olmasın)
            return Transform(
              transform: transform,
              alignment: Alignment.center,
              child: angle > math.pi / 2 ? const SizedBox() : child,
            );
          },
        );
      },
      child: Container(
        key: ValueKey(isLogin),
        child: isLogin ? front : back,
      ),
    );
  }
}

// ===========================================================
// ✅ Stage flip (Welcome <-> Auth) 180°
// ===========================================================
class _CardFlipStage extends StatelessWidget {
  const _CardFlipStage({
    required this.showAuth,
    required this.welcome,
    required this.auth,
    this.duration = const Duration(milliseconds: 800),
  });

  final bool showAuth;
  final Widget welcome;
  final Widget auth;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: showAuth ? 1 : 0),
      duration: duration,
      curve: Curves.easeInOutCubic,
      builder: (context, t, _) {
        final angle = t * math.pi; // 0..pi (180°)
        final showBack = angle > (math.pi / 2);

        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..rotateY(angle);

        return Transform(
          transform: m,
          alignment: Alignment.center,
          child: RepaintBoundary(
            child: showBack
                ? Transform(
              // arka yüzü düz göstermek için +pi
              transform: Matrix4.identity()..rotateY(math.pi),
              alignment: Alignment.center,
              child: auth,
            )
                : welcome,
          ),
        );
      },
    );
  }
}

// ===========================================================
// UI pieces
// ===========================================================
class _HeaderMini extends StatelessWidget {
  const _HeaderMini({required this.on});
  final Color on;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white.withOpacity(0.18),
          child: ClipOval(
            child: Image.asset(
              kLogoPath,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.link_off, color: on.withOpacity(0.8)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'TechConnect',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: on,
          ),
        ),
      ],
    );
  }
}

class _FrostedCard extends StatelessWidget {
  const _FrostedCard({
    super.key,
    required this.child,
    required this.surfaceColor,
    required this.borderColor,
    required this.shadowColor,
  });

  final Widget child;
  final Color surfaceColor;
  final Color borderColor;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                blurRadius: 28,
                color: shadowColor,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DividerWithText extends StatelessWidget {
  const _DividerWithText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final on = Colors.white.withOpacity(0.9);
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: Colors.white.withOpacity(0.18),
            endIndent: 10,
          ),
        ),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: on),
        ),
        Expanded(
          child: Divider(
            color: Colors.white.withOpacity(0.18),
            indent: 10,
          ),
        ),
      ],
    );
  }
}

class _BlurBall extends StatelessWidget {
  const _BlurBall({required this.size, required this.opacity});

  final double size;
  final double opacity;

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

// ===========================================================
// Social: yuvarlak ikon
// ===========================================================
class _SocialRoundIcon extends StatelessWidget {
  const _SocialRoundIcon({
    required this.asset,
    required this.tooltip,
    required this.onTap,
  });

  final String asset;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final on = t.colorScheme.onPrimary;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(
              t.brightness == Brightness.dark ? 0.06 : 0.10,
            ),
            border: Border.all(color: on.withOpacity(0.28), width: 1),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 10),
                color: Colors.black.withOpacity(
                  t.brightness == Brightness.dark ? 0.22 : 0.10,
                ),
              ),
            ],
          ),
          child: Center(
            child: Image.asset(asset, width: 22, height: 22),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// Legal: checkbox row + bottom sheet
// ===========================================================
class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.checked,
    required this.onChanged,
    required this.leadingText,
    required this.linkText,
    required this.onLinkTap,
    required this.textColor,
    required this.linkColor,
  });

  final bool checked;
  final ValueChanged<bool?> onChanged;
  final String leadingText;
  final String linkText;
  final VoidCallback onLinkTap;
  final Color textColor;
  final Color linkColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: checked,
          onChanged: onChanged,
          activeColor: const Color(0xFFE57AFF),
          checkColor: Colors.white,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              children: [
                Text(leadingText, style: TextStyle(color: textColor)),
                InkWell(
                  onTap: onLinkTap,
                  child: Text(
                    linkText,
                    style: TextStyle(
                      color: linkColor,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegalAcceptSheet extends StatefulWidget {
  const _LegalAcceptSheet({required this.title, required this.body});
  final String title;
  final String body;

  @override
  State<_LegalAcceptSheet> createState() => _LegalAcceptSheetState();
}

class _LegalAcceptSheetState extends State<_LegalAcceptSheet> {
  final _scrollCtrl = ScrollController();
  bool _reachedBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final atBottom = pos.pixels >= (pos.maxScrollExtent - 24);
    if (atBottom != _reachedBottom) setState(() => _reachedBottom = atBottom);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                borderRadius: BorderRadius.circular(22),
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              style: t.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context, false),
                            icon: Icon(
                              Icons.close,
                              color: cs.onSurface.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: NotificationListener<
                          OverscrollIndicatorNotification>(
                        onNotification: (o) {
                          o.disallowIndicator();
                          return true;
                        },
                        child: Scrollbar(
                          controller: _scrollCtrl,
                          child: SingleChildScrollView(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                            child: Markdown(
                              data: widget.body,
                              selectable: true,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              styleSheet: MarkdownStyleSheet(
                                p: t.textTheme.bodyMedium?.copyWith(
                                  height: 1.45,
                                  color: Colors.white.withOpacity(0.92),
                                ),
                                h1: t.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                                h2: t.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                                h3: t.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                                listBullet:
                                t.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withOpacity(0.92),
                                ),
                                blockquoteDecoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border(
                                    left: BorderSide(
                                      color: cs.primary.withOpacity(0.6),
                                      width: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Column(
                        children: [
                          if (!_reachedBottom)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Devam etmek için lütfen metni sonuna kadar kaydır.',
                                style: t.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withOpacity(0.75),
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _reachedBottom
                                  ? () => Navigator.pop(context, true)
                                  : null,
                              child: Padding(
                                padding:
                                const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  _reachedBottom
                                      ? 'Okudum, Kabul Ediyorum'
                                      : 'Aşağı Kaydır',
                                ),
                              ),
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
      ),
    );
  }
}
