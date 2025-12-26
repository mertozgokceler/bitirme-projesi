// lib/auth_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'in_app_notification.dart';

const String kLogoPath = 'assets/images/techconnectlogo.png';
const String kIconGoogle = 'assets/icons/google.png';
const String kIconGithub = 'assets/icons/github.png';
const String kIconApple = 'assets/icons/apple.png';
const String kIconInstagram = 'assets/icons/instagram.png';

// Legal assets
const String kTermsAsset = 'assets/legal/terms_tr.md';
const String kPrivacyAsset = 'assets/legal/privacy_tr.md';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

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

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  bool _obscure = true;
  bool _rememberMe = true;

  // ✅ İKİ AYRI ONAY
  bool _agreeTerms = false;
  bool _agreePrivacy = false;

  bool _isLogin = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _confirmCtrl.dispose();

    _taxCtrl.dispose();
    _companyCtrl.dispose();
    _activityOtherCtrl.dispose();
    super.dispose();
  }

  void _toggleMode(bool login) {
    setState(() {
      _isLogin = login;
    });
  }

  String _trLower(String s) =>
      s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<String> _loadAssetText(String path) async {
    // DefaultAssetBundle ile hem prod hem testte düzgün çalışır
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

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    // ✅ Kayıtta iki onay da zorunlu
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

    // Şirket seçiliyse "Diğer" alanı kontrolü
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
        await _handleLogin();
      } else {
        await _handleRegister();
      }
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Kimlik doğrulama hatası');
    } catch (e) {
      if (e.toString().contains('username_taken')) {
        _snack('Bu kullanıcı adı az önce alındı, lütfen başka bir ad deneyin.');
      } else {
        _snack('Hata: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleLogin() async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rememberMe', _rememberMe);

    final user = cred.user!;
    final uid = user.uid;

    // ✅ “Hayalet hesap” kontrolü: users doc yoksa bu hesap uygulama için geçersiz
    final ref = _fs.collection('users').doc(uid);
    final doc = await ref.get();

    if (!doc.exists) {
      _snack('Profil bulunamadı. Bu hesap geçersiz/eksik. Tekrar kayıt ol.');
      await _auth.signOut();
      return;
    }

    final data = doc.data()!;
    final String name = (data['name'] ?? '').toString();
    final String username = (data['username'] ?? '').toString();

    // ✅ Patch: searchable + lower alanları yoksa tamamla
    final needPatch = (data['isSearchable'] != true) ||
        ((data['nameLower'] ?? '').toString().isEmpty && name.isNotEmpty) ||
        ((data['usernameLower'] ?? '').toString().isEmpty &&
            username.isNotEmpty);

    if (needPatch) {
      await ref.set({
        'isSearchable': true,
        if (name.isNotEmpty) 'nameLower': _trLower(name),
        if (username.isNotEmpty) 'usernameLower': _trLower(username),
      }, SetOptions(merge: true));
    }

    // ✅ In-app notif cache user’a bağla
    await inAppNotificationService.initForUser(uid);

    _snack(
        'Giriş başarılı — Hoş geldin ${data['username'] ?? data['name'] ?? ''}');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
  }

  Future<void> _handleRegister() async {
    final name = _nameCtrl.text.trim();
    final uname = _usernameCtrl.text.trim();
    final unameLower = _trLower(uname);

    final email = _emailCtrl.text.trim();
    final pass = _passwordCtrl.text;

    // ✅ username check (quick pre-check)
    final unameDoc = await _fs.collection('usernames').doc(unameLower).get();
    if (unameDoc.exists) {
      _snack('Bu kullanıcı adı alınmış.');
      return;
    }

    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: pass,
    );

    final user = cred.user!;
    final uid = user.uid;

    final bool isCompany = _isCompany;
    final String accountType = isCompany ? 'company' : 'individual';

    final String? taxNo = isCompany ? _taxCtrl.text.trim() : null;
    final String? companyName = isCompany ? _companyCtrl.text.trim() : null;

    String? activity;
    if (isCompany) {
      activity = (_selectedActivity == 'Diğer')
          ? _activityOtherCtrl.text.trim()
          : _selectedActivity;
    }

    await _fs.runTransaction((tx) async {
      final unameRef = _fs.collection('usernames').doc(unameLower);
      final userRef = _fs.collection('users').doc(uid);

      if ((await tx.get(unameRef)).exists) {
        throw Exception('username_taken');
      }

      tx.set(unameRef, {'uid': uid});

      final userData = <String, dynamic>{
        'name': name,
        'nameLower': name.isEmpty ? '' : _trLower(name),
        'username': uname,
        'usernameLower': unameLower,
        'isSearchable': true,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,
        'roles': ['user'],
        'type': accountType,
        'isCompany': isCompany,

        // ✅ Legal acceptance flags (istersen loglamayı da ekle)
        'acceptedTerms': true,
        'acceptedPrivacy': true,
        'acceptedTermsAt': FieldValue.serverTimestamp(),
        'acceptedPrivacyAt': FieldValue.serverTimestamp(),

        // ✅ SADECE individual için otomatik default alanlar
        if (!isCompany) ...{
          'cvParseStatus': 'idle',
          'cvTextHash': '',
          'profileStructured': <String, dynamic>{},
          'profileSummary': '',
          'cvParsedAt': null,
          'cvParseRequestId': '',
          'cvParseError': '',
        },

        // ✅ Şirket alanları
        if (isCompany) ...{
          'companyName': companyName,
          'companyTaxNo': taxNo,
          'companyActivity': activity,
          'company': {
            'name': companyName,
            'taxNo': taxNo,
            'activity': activity,
          },
        },
      };

      tx.set(userRef, userData);
    });

    _snack('Kayıt oluşturuldu.');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/main', (r) => false);
  }

  InputDecoration _dec(
      BuildContext context,
      String label, {
        IconData? prefix,
        Widget? suffix,
        String? helperText,
      }) {
    final t = Theme.of(context);
    final onField = AppColors.authFieldText(t);
    final hint = AppColors.authFieldHint(t);
    final border = AppColors.authFieldBorder(t);
    final borderFocused = AppColors.authFieldBorderFocused(t);
    final error = AppColors.authFieldError(t);

    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: border, width: 1),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: borderFocused, width: 1.4),
    );

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: onField.withOpacity(0.85)),
      hintText: ' ',
      hintStyle: TextStyle(color: hint),
      helperText: helperText,
      helperStyle: TextStyle(color: onField.withOpacity(0.70)),
      prefixIcon: prefix != null
          ? Icon(prefix, color: onField.withOpacity(0.85))
          : null,
      suffixIcon: suffix,
      enabledBorder: baseBorder,
      focusedBorder: focusedBorder,
      errorBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: error, width: 1),
      ),
      focusedErrorBorder: focusedBorder.copyWith(
        borderSide: BorderSide(color: error, width: 1.4),
      ),
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final onSplash = AppColors.authOnSplash(t);

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.authBackgroundGradient(t),
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: _BlurBall(
              size: 180,
              opacity: AppColors.authBlurBallOpacity(t, strong: true),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -50,
            child: _BlurBall(
              size: 200,
              opacity: AppColors.authBlurBallOpacity(t, strong: false),
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
                    surfaceColor: AppColors.authCardSurface(t),
                    borderColor: AppColors.authCardBorder(t),
                    shadowColor: AppColors.authCardShadow(t),
                    child: Padding(
                      padding: const EdgeInsets.all(22.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _AppHeader(),
                          const SizedBox(height: 16),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: true,
                                label: Text('Giriş Yap',
                                    style:
                                    TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              ButtonSegment(
                                value: false,
                                label: Text('Kayıt Ol',
                                    style:
                                    TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ],
                            selected: {_isLogin},
                            onSelectionChanged: (s) => _toggleMode(s.first),
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: WidgetStatePropertyAll(onSplash),
                              side: WidgetStatePropertyAll(
                                BorderSide(color: onSplash.withOpacity(0.25)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                ClipRect(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 400),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    transitionBuilder: (child, anim) =>
                                        FadeTransition(
                                          opacity: anim,
                                          child: SizeTransition(
                                            sizeFactor: anim,
                                            axisAlignment: 1.0,
                                            child: child,
                                          ),
                                        ),
                                    child: _isLogin
                                        ? _buildLoginFields(context,
                                        key: const ValueKey('login'))
                                        : _buildRegisterFields(context,
                                        key: const ValueKey('register')),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _loading ? null : _submit,
                                    style: ButtonStyle(
                                      backgroundColor:
                                      WidgetStateProperty.resolveWith(
                                              (states) {
                                            if (states
                                                .contains(WidgetState.pressed) ||
                                                states.contains(
                                                    WidgetState.hovered)) {
                                              return AppColors.interaction(t)
                                                  .withOpacity(0.85);
                                            }
                                            return t.colorScheme.primary;
                                          }),
                                      foregroundColor:
                                      const WidgetStatePropertyAll(
                                          Colors.white),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: _loading
                                          ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                          : Text(_isLogin
                                          ? 'Giriş Yap'
                                          : 'Kayıt Ol'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(
                                            () => _rememberMe = v ?? false),
                                    activeColor: AppColors.interaction(t),
                                    checkColor: Colors.white,
                                  ),
                                  Text(
                                    'Beni hatırla',
                                    style: TextStyle(
                                        color: onSplash.withOpacity(0.92)),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 1),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const _DividerWithText(text: 'veya'),
                          const SizedBox(height: 15),
                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _SocialButton(
                                      label: 'Google',
                                      icon: Image.asset(kIconGoogle,
                                          width: 20, height: 20),
                                      onTap: () =>
                                          _snack('Google ile giriş (demo)'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _SocialButton(
                                      label: 'Github',
                                      icon: Image.asset(kIconGithub,
                                          width: 20, height: 20),
                                      onTap: () =>
                                          _snack('Github ile giriş (demo)'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _SocialButton(
                                      label: 'Apple',
                                      icon: Image.asset(kIconApple,
                                          width: 20, height: 20),
                                      onTap: () =>
                                          _snack('Apple ile giriş (demo)'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _SocialButton(
                                      label: 'Instagram',
                                      icon: Image.asset(kIconInstagram,
                                          width: 20, height: 20),
                                      onTap: () =>
                                          _snack('Instagram ile giriş (demo)'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
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

  Widget _buildLoginFields(BuildContext context, {Key? key}) {
    final t = Theme.of(context);
    final onField = AppColors.authFieldText(t);

    return Column(
      key: key,
      children: [
        TextFormField(
          controller: _emailCtrl,
          cursorColor: AppColors.interaction(t),
          style: TextStyle(color: onField),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _dec(context, 'E-posta', prefix: Icons.alternate_email),
          validator: _emailValidator,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passwordCtrl,
          cursorColor: AppColors.interaction(t),
          style: TextStyle(color: onField),
          obscureText: _obscure,
          decoration: _dec(
            context,
            'Şifre',
            prefix: Icons.lock_outline,
            suffix: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure ? Icons.visibility : Icons.visibility_off,
                color: onField.withOpacity(0.8),
              ),
            ),
          ),
          validator: _passwordValidator,
        ),
      ],
    );
  }

  Widget _buildRegisterFields(BuildContext context, {Key? key}) {
    final t = Theme.of(context);
    final onField = AppColors.authFieldText(t);
    final onSplash = AppColors.authOnSplash(t);

    return Column(
      key: key,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Bireysel')),
              ButtonSegment(value: true, label: Text('Şirket')),
            ],
            selected: {_isCompany},
            onSelectionChanged: (s) => setState(() {
              _isCompany = s.first;
              if (!_isCompany) {
                _selectedActivity = null;
                _taxCtrl.clear();
                _companyCtrl.clear();
                _activityOtherCtrl.clear();
              }
            }),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor:
              WidgetStatePropertyAll(AppColors.authOnSplash(t)),
              side: WidgetStatePropertyAll(
                BorderSide(color: AppColors.authOnSplash(t).withOpacity(0.25)),
              ),
            ),
          ),
        ),
        TextFormField(
          controller: _nameCtrl,
          cursorColor: AppColors.interaction(t),
          style: TextStyle(color: onField),
          textInputAction: TextInputAction.next,
          decoration: _dec(
            context,
            _isCompany ? 'Ad Soyad (isteğe bağlı)' : 'Ad Soyad',
            prefix: Icons.person_outline,
          ),
          validator: (v) {
            if (!_isCompany) {
              if (v == null || v.trim().length < 2) return 'Lütfen adınızı girin';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _usernameCtrl,
          cursorColor: AppColors.interaction(t),
          style: TextStyle(color: onField),
          textInputAction: TextInputAction.next,
          decoration: _dec(context, 'Kullanıcı Adı',
              prefix: Icons.account_circle_outlined),
          validator: (v) =>
          (v == null || v.trim().length < 3) ? 'En az 3 karakter girin' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _emailCtrl,
          cursorColor: AppColors.interaction(t),
          style: TextStyle(color: onField),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _dec(context, 'E-posta', prefix: Icons.alternate_email),
          validator: _emailValidator,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passwordCtrl,
          cursorColor: AppColors.interaction(t),
          style: TextStyle(color: onField),
          obscureText: _obscure,
          textInputAction: TextInputAction.next,
          decoration: _dec(
            context,
            'Şifre',
            prefix: Icons.lock_outline,
            helperText: 'En az 8 karakter önerilir.',
            suffix: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure ? Icons.visibility : Icons.visibility_off,
                color: onField.withOpacity(0.8),
              ),
            ),
          ),
          validator: _passwordValidator,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _confirmCtrl,
          cursorColor: AppColors.interaction(t),
          style: TextStyle(color: onField),
          obscureText: _obscure,
          decoration:
          _dec(context, 'Şifre (tekrar)', prefix: Icons.lock_person_outlined),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Lütfen şifrenizi tekrar girin';
            if (v != _passwordCtrl.text) return 'Şifreler uyuşmuyor';
            return null;
          },
        ),
        if (_isCompany) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _companyCtrl,
            cursorColor: AppColors.interaction(t),
            style: TextStyle(color: onField),
            textInputAction: TextInputAction.next,
            decoration:
            _dec(context, 'Şirket Adı', prefix: Icons.business_outlined),
            validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Şirket adı zorunlu' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _taxCtrl,
            cursorColor: AppColors.interaction(t),
            style: TextStyle(color: onField),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration:
            _dec(context, 'Vergi Numarası (10 hane)', prefix: Icons.numbers),
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
            decoration:
            _dec(context, 'Faaliyet Alanı', prefix: Icons.work_outline),
            dropdownColor: AppColors.authDropdownBg(t),
            style: TextStyle(color: onField),
            iconEnabledColor: onField.withOpacity(0.85),
            validator: (v) {
              if (!_isCompany) return null;
              return (v == null || v.isEmpty) ? 'Faaliyet alanı seçin' : null;
            },
            onChanged: (v) => setState(() => _selectedActivity = v),
          ),
          if (_selectedActivity == 'Diğer') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _activityOtherCtrl,
              cursorColor: AppColors.interaction(t),
              style: TextStyle(color: onField),
              decoration: _dec(context, 'Faaliyet Alanı (Diğer)',
                  prefix: Icons.edit_outlined),
              validator: (v) {
                if (_isCompany && _selectedActivity == 'Diğer') {
                  if (v == null || v.trim().isEmpty) return 'Lütfen alanı yazın';
                }
                return null;
              },
            ),
          ],
        ],

        // ✅ İKİ AYRI ONAY SATIRI
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
          textColor: onSplash.withOpacity(0.92),
          linkColor: onSplash,
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
          textColor: onSplash.withOpacity(0.92),
          linkColor: onSplash,
        ),
      ],
    );
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'E-posta zorunlu';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
    return ok ? null : 'Geçerli bir e-posta girin';
  }

  String? _passwordValidator(String? v) {
    if (v == null || v.length < 8) return 'Şifre en az 8 karakter olmalı';
    return null;
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final onSplash = AppColors.authOnSplash(t);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 30),
        CircleAvatar(
          radius: 45,
          backgroundColor: AppColors.authLogoBg(t),
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: ClipOval(
              child: Image.asset(
                kLogoPath,
                width: 100,
                height: 100,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.link_off,
                    size: 52, color: onSplash.withOpacity(0.75)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'TechConnect',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: onSplash,
            shadows: const [Shadow(blurRadius: 12, color: Colors.black26)],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Hesabına giriş yap veya hızlıca kayıt ol',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: onSplash.withOpacity(0.75),
          ),
          textAlign: TextAlign.center,
        ),
      ],
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
  final String text;
  const _DividerWithText({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final onSplash = AppColors.authOnSplash(t);

    return Row(
      children: [
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            endIndent: 8,
            color: onSplash.withOpacity(0.18),
          ),
        ),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: onSplash.withOpacity(0.75),
          ),
        ),
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            indent: 8,
            color: onSplash.withOpacity(0.18),
          ),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  const _SocialButton({
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final onSplash = AppColors.authOnSplash(t);

    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon,
        label: Text(label, style: TextStyle(color: onSplash)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: onSplash.withOpacity(0.28)),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppColors.authSocialBtnBg(t),
        ).copyWith(
          overlayColor: WidgetStatePropertyAll(
            AppColors.interaction(t).withOpacity(0.12),
          ),
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

// ✅ Checkbox + link satırı (2 yerde tekrar yazma diye)
class _LegalRow extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool?> onChanged;

  final String leadingText;
  final String linkText;
  final VoidCallback onLinkTap;

  final Color textColor;
  final Color linkColor;

  const _LegalRow({
    required this.checked,
    required this.onChanged,
    required this.leadingText,
    required this.linkText,
    required this.onLinkTap,
    required this.textColor,
    required this.linkColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: checked,
          onChanged: onChanged,
          activeColor: AppColors.interaction(Theme.of(context)),
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
                      fontWeight: FontWeight.w800,
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

// ✅ Banka mantığı: en alta kaydırmadan kabul yok
class _LegalAcceptSheet extends StatefulWidget {
  final String title;
  final String body;

  const _LegalAcceptSheet({
    required this.title,
    required this.body,
  });

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

    // tolerans: 24px
    final atBottom = pos.pixels >= (pos.maxScrollExtent - 24);
    if (atBottom != _reachedBottom) {
      setState(() => _reachedBottom = atBottom);
    }
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
                color: (t.brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.55)
                    : Colors.white.withOpacity(0.72)),
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
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context, false),
                            icon: Icon(Icons.close,
                                color: cs.onSurface.withOpacity(0.8)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
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
                            padding:
                            const EdgeInsets.fromLTRB(16, 10, 16, 20),
                            child: Markdown(
                              data: widget.body,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                h1: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                                h2: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                h3: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                p: t.textTheme.bodyMedium?.copyWith(height: 1.45),
                                listBullet: t.textTheme.bodyMedium,
                                blockquote: t.textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                                horizontalRuleDecoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: cs.onSurface.withOpacity(0.18), width: 1),
                                  ),
                                ),
                              ).copyWith(
                                // Markdown widget kendi rengini theme’den alır; burada koyulaştırıyoruz
                                p: t.textTheme.bodyMedium?.copyWith(
                                  height: 1.45,
                                  color: cs.onSurface.withOpacity(0.92),
                                ),
                                h1: t.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface.withOpacity(0.96),
                                ),
                                h2: t.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface.withOpacity(0.96),
                                ),
                                h3: t.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface.withOpacity(0.96),
                                ),
                                listBullet: t.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface.withOpacity(0.92),
                                ),
                                blockquoteDecoration: BoxDecoration(
                                  color: cs.onSurface.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border(
                                    left: BorderSide(color: cs.primary.withOpacity(0.6), width: 4),
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(), // scroll'u dıştaki SingleChildScrollView kontrol etsin
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
                                  color: cs.onSurface.withOpacity(0.75),
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
                                child: Text(_reachedBottom
                                    ? 'Okudum, Kabul Ediyorum'
                                    : 'Aşağı Kaydır'),
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

/// ===========================================================
/// ✅ TEK YERDEN RENK KARARLARI
/// ===========================================================
class AppColors {
  static Color interaction(ThemeData t) => const Color(0xFFE57AFF);

  static List<Color> authBackgroundGradient(ThemeData t) {
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

  static Color authOnSplash(ThemeData t) => t.colorScheme.onPrimary;

  static double authBlurBallOpacity(ThemeData t, {required bool strong}) {
    final isDark = t.brightness == Brightness.dark;
    if (isDark) return strong ? 0.22 : 0.18;
    return strong ? 0.16 : 0.12;
  }

  static Color authCardSurface(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.white.withOpacity(0.14);
  }

  static Color authCardBorder(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark
        ? Colors.white.withOpacity(0.16)
        : Colors.white.withOpacity(0.20);
  }

  static Color authCardShadow(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark ? Colors.black.withOpacity(0.30) : Colors.black.withOpacity(0.18);
  }

  static Color authLogoBg(ThemeData t) {
    final cs = t.colorScheme;
    return cs.primaryContainer.withOpacity(0.80);
  }

  static Color authSocialBtnBg(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.10);
  }

  static Color authFieldText(ThemeData t) => authOnSplash(t).withOpacity(0.95);
  static Color authFieldHint(ThemeData t) => authOnSplash(t).withOpacity(0.35);
  static Color authFieldBorder(ThemeData t) => authOnSplash(t).withOpacity(0.28);
  static Color authFieldBorderFocused(ThemeData t) =>
      authOnSplash(t).withOpacity(0.85);
  static Color authFieldError(ThemeData t) => Colors.redAccent;

  static Color authDropdownBg(ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    return isDark ? const Color(0xFF121317) : Colors.white;
  }
}
