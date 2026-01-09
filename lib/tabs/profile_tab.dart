import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';

import '../auth_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/saved_posts_screen.dart';
import '../screens/certificates_cv_screen.dart';
import '../screens/subscription_plans_screen.dart';
import '../screens/help_support_screen.dart';
import '../screens/connections_screen.dart';
import '../screens/company_my_jobs_screen.dart';
import '../screens/company_incoming_applications_screen.dart';
import '../screens/ai_cv_analysis_screen.dart';
import '../screens/my_applications_screen.dart';
import '../screens/job_test_hub_screen.dart';
import '../screens/profile_views_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _error;

  int _connectionCount = 0;

  // --------------------
  // SAFE PARSERS
  // --------------------
  String _s(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    final x = v.toString().trim();
    return x.isEmpty ? fallback : x;
  }

  bool _isCompanyFromData(Map<String, dynamic> d) {
    return (d['isCompany'] == true) || (d['type'] == 'company');
  }

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Giriş yapmış kullanıcı bulunamadı.';
      });
      return;
    }

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (!mounted) return;

      if (doc.exists) {
        setState(() {
          _userData = doc.data();
          _isLoading = false;
          _error = null;
        });
        _loadConnectionCount(user.uid);
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Kullanıcı veritabanında bulunamadı.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Veri alınırken bir hata oluştu: $e';
      });
    }
  }

  Future<void> _loadConnectionCount(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('connections')
          .doc(uid)
          .collection('list')
          .get();

      if (!mounted) return;

      setState(() {
        _connectionCount = snap.docs.length;
      });
    } catch (_) {}
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rememberMe', false);

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthScreen()),
            (route) => false,
      );
    } catch (_) {}
  }

  // --------------------
  // PREMIUM CHECK (same logic)
  // --------------------
  bool isPremiumActiveFromUserDoc(Map<String, dynamic> data) {
    final isPremiumFlag = data['isPremium'] == true;

    final until = data['premiumUntil'];
    DateTime? untilDt;

    if (until is Timestamp) {
      untilDt = until.toDate();
    }

    final now = DateTime.now();
    final validByDate = untilDt != null && untilDt.isAfter(now);

    if (untilDt != null) return validByDate;
    return isPremiumFlag;
  }

  // --------------------
  // BACKGROUND / PREMIUM FEEL
  // --------------------
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    if (_userData == null) {
      return const Center(child: Text('Kullanıcı verisi bulunamadı.'));
    }

    final isCompany = _isCompanyFromData(_userData!);

    return Stack(
      children: [
        Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
        Positioned(
          top: -140,
          left: -90,
          child: _GlowBlob(size: 300, color: theme.colorScheme.primary.withOpacity(0.18)),
        ),
        Positioned(
          bottom: -160,
          right: -110,
          child: _GlowBlob(size: 320, color: theme.colorScheme.tertiary.withOpacity(0.16)),
        ),
        SafeArea(
          child: RefreshIndicator(
            onRefresh: _fetchUserData,
            edgeOffset: 12,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                _buildProfileHeaderCard(),
                const SizedBox(height: 14),

                if (isCompany) ...[
                  _sectionTitle('İş İlanları'),
                  _sectionCard([
                    _menuRow(
                      icon: Icons.work_outline,
                      title: 'İlanlarım',
                      subtitle: 'Yayınlanan ilanlarını yönet',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CompanyMyJobsScreen()),
                      ),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.quiz_outlined,
                      title: 'İlan Testi Oluştur',
                      subtitle: 'Adaylara test hazırla',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JobTestHubScreen()),
                      ),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.bar_chart_outlined,
                      title: 'İlan Performansı',
                      subtitle: 'Görüntülenme ve dönüşüm (yakında)',
                      onTap: () {},
                      trailing: _soonPill(),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  _sectionTitle('Aday Yönetimi'),
                  _sectionCard([
                    _menuRow(
                      icon: Icons.inbox_outlined,
                      title: 'Gelen Başvurular',
                      subtitle: 'Başvuruları incele ve filtrele',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CompanyIncomingApplicationsScreen(),
                        ),
                      ),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.people_alt_outlined,
                      title: 'Aday Havuzum',
                      subtitle: 'Kaydettiğin adaylar (yakında)',
                      onTap: () {},
                      trailing: _soonPill(),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.auto_awesome_outlined,
                      title: 'AI Eşleşme Sonuçları',
                      subtitle: 'Premium ile gelişmiş eşleşme',
                      onTap: _showProfileViewsPremiumDialog,
                      trailing: _premiumPill(),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  _sectionTitle('İletişim ve Ağ'),
                  _sectionCard([
                    _menuRow(
                      icon: Icons.group_outlined,
                      title: 'Ağım / Bağlantılarım',
                      subtitle: 'Bağlantılarını yönet',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ConnectionsScreen()),
                      ),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.chat_bubble_outline,
                      title: 'Mesajlar',
                      subtitle: 'Sohbetler (yakında)',
                      onTap: () {},
                      trailing: _soonPill(),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.handshake_outlined,
                      title: 'İş Birliği Talepleri',
                      subtitle: 'Teklifler (yakında)',
                      onTap: () {},
                      trailing: _soonPill(),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  _sectionTitle('Şirket Sayfası'),
                  _sectionCard([
                    _menuRow(
                      icon: Icons.business_outlined,
                      title: 'Şirket Profili',
                      subtitle: 'Bilgilerini güncelle',
                      onTap: () async {
                        final result = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditProfileScreen(initialUserData: _userData!),
                          ),
                        );
                        if (result == true) _fetchUserData();
                      },
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.groups_2_outlined,
                      title: 'Ekip Üyeleri',
                      subtitle: 'Yetkilendirme (yakında)',
                      onTap: () {},
                      trailing: _soonPill(),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.info_outline,
                      title: 'Hakkımızda',
                      subtitle: 'Şirket açıklaması (yakında)',
                      onTap: () {},
                      trailing: _soonPill(),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  _sectionTitle('Planlar ve Faturalar'),
                  _sectionCard([
                    _menuRow(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Premium Paketler',
                      subtitle: 'Planını yükselt',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SubscriptionPlansScreen()),
                      ),
                      trailing: _sparkle(),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.receipt_long_outlined,
                      title: 'Fatura Geçmişi',
                      subtitle: 'Geçmiş ödemeler (yakında)',
                      onTap: () {},
                      trailing: _soonPill(),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Şirket Kredileri',
                      subtitle: 'Kredi bakiyesi (yakında)',
                      onTap: () {},
                      trailing: _soonPill(),
                    ),
                  ]),
                ] else ...[
                  _sectionTitle('Aktivite'),
                  _sectionCard([
                    _menuRow(
                      icon: Icons.article_outlined,
                      title: 'Başvurularım',
                      subtitle: 'Tüm başvurularını görüntüle',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
                      ),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.card_giftcard_outlined,
                      title: 'Aldığım Teklifler',
                      subtitle: 'Yakında',
                      onTap: () {},
                      trailing: _soonPill(),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.bookmark_border_outlined,
                      title: 'Kaydedilenler',
                      subtitle: 'Kaydettiğin gönderiler',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SavedPostsScreen()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  _sectionTitle('Sosyal'),
                  _sectionCard([
                    _menuRow(
                      icon: Icons.group_outlined,
                      title: 'Ağım / Bağlantılarım',
                      subtitle: 'Bağlantılarını yönet',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ConnectionsScreen()),
                      ),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.visibility_outlined,
                      title: 'Profilimi Görüntüleyenler',
                      subtitle: 'Premium ile açılır',
                      onTap: _handleProfileViewsTap,
                      trailing: _premiumPill(),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.school_outlined,
                      title: 'Sertifikalarım ve CV',
                      subtitle: 'CV ve sertifika dosyaları',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CertificatesCvScreen()),
                      ),
                    ),
                    _divider(),
                    _menuRow(
                      icon: Icons.auto_awesome_outlined,
                      title: 'AI CV Analiz',
                      subtitle: 'CV’ni yapay zekâ ile değerlendir',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CvAnalysisScreen()),
                      ),
                      trailing: _sparkle(),
                    ),
                  ]),
                ],

                const SizedBox(height: 14),

                _sectionTitle('Uygulama'),
                _sectionCard([
                  _menuRow(
                    icon: Icons.settings_outlined,
                    title: 'Ayarlar',
                    subtitle: 'Tema, bildirim, gizlilik',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                  _divider(),
                  _menuRow(
                    icon: Icons.help_outline,
                    title: 'Yardım ve Destek',
                    subtitle: 'Sık sorulanlar ve iletişim',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
                    ),
                  ),
                ]),

                const SizedBox(height: 12),

                _sectionCard([
                  _menuRow(
                    icon: Icons.logout,
                    title: 'Çıkış Yap',
                    subtitle: 'Hesabından güvenli çıkış yap',
                    onTap: () => _signOut(context),
                    danger: true,
                  ),
                ]),

                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --------------------
  // HEADER CARD
  // --------------------
  Widget _buildProfileHeaderCard() {
    final theme = Theme.of(context);
    final data = _userData!;
    final isDark = theme.brightness == Brightness.dark;

    final bool isPremium = isPremiumActiveFromUserDoc(data);
    final bool isCompany = _isCompanyFromData(data);

    final personName = _s(data['name'], fallback: '');
    final companyNameTop = _s(data['companyName'] ?? (data['company'] is Map ? (data['company']['name']) : null), fallback: '');

    final displayName = isCompany
        ? (companyNameTop.isNotEmpty ? companyNameTop : '(Şirket adı yok)')
        : (personName.isNotEmpty ? personName : '(İsimsiz)');

    final username = _s(data['username'], fallback: 'kullanici');
    final photoUrl = _s(data['photoUrl'], fallback: '');
    final location = _s(data['location'], fallback: '');
    final role = _s(data['role'], fallback: '');

    final hasConnections = _connectionCount > 0;

    final hasInfo = location.isNotEmpty || role.isNotEmpty || hasConnections;

    final avatar = _PremiumAvatar(
      isPremium: isPremium,
      photoUrl: photoUrl,
      radius: 46,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.white.withOpacity(0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.28 : 0.10),
                blurRadius: 22,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  avatar,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            if (isPremium)
                              SizedBox(
                                width: 34,
                                height: 34,
                                child: Lottie.asset(
                                  'assets/lottie/premium.json',
                                  repeat: true,
                                  animate: true,
                                  fit: BoxFit.contain,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface.withOpacity(0.65),
                          ),
                        ),
                        if (hasInfo) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (location.isNotEmpty)
                                _InfoPill(icon: Icons.location_on_outlined, text: location),
                              if (role.isNotEmpty)
                                _InfoPill(icon: Icons.work_outline, text: role),
                              if (hasConnections)
                                _InfoPill(
                                  icon: Icons.group_outlined,
                                  text: '$_connectionCount bağlantı',
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: isDark
                    ? DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.tertiary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.34),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () async {
                      final result = await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(initialUserData: _userData!),
                        ),
                      );
                      if (result == true) _fetchUserData();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit, size: 18, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          isCompany ? 'Şirket Profilini Düzenle' : 'Profili Düzenle',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                offset: Offset(0, 1),
                                blurRadius: 4,
                                color: Colors.black38,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                    : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: BorderSide(
                      color: theme.colorScheme.primary.withOpacity(0.55),
                      width: 1.2,
                    ),
                  ),
                  onPressed: () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(initialUserData: _userData!),
                      ),
                    );
                    if (result == true) _fetchUserData();
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        isCompany ? 'Şirket Profilini Düzenle' : 'Profili Düzenle',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              )

            ],
          ),
        ),
      ),
    );
  }

  // --------------------
  // SECTION UI
  // --------------------
  Widget _sectionTitle(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: theme.colorScheme.onSurface.withOpacity(0.55),
        ),
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.055) : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 1,
      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final titleColor = danger
        ? const Color(0xFFEF4444)
        : theme.colorScheme.onSurface;

    final subtitleColor = danger
        ? const Color(0xFFEF4444).withOpacity(0.85)
        : theme.colorScheme.onSurface.withOpacity(isDark ? 0.62 : 0.62);

    final iconBg = danger
        ? const Color(0xFFEF4444).withOpacity(0.12)
        : theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.18 : 0.65);

    final iconColor = danger
        ? const Color(0xFFEF4444)
        : theme.colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.05),
                  ),
                ),
                child: Center(
                  child: Icon(icon, color: iconColor, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 24,
                    color: theme.colorScheme.onSurface.withOpacity(0.55),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _premiumPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFBF04).withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFEFBF04).withOpacity(0.35)),
      ),
      child: const Text(
        'Premium',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _soonPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: const Text(
        'Yakında',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _sparkle() {
    return const Icon(Icons.auto_awesome, size: 20);
  }

  // --------------------
  // PREMIUM DIALOG
  // --------------------
  void _showProfileViewsPremiumDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          title: Row(
            children: [
              Icon(
                Icons.lock_outline,
                color: isDark ? Colors.amberAccent : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('Premium Özellik', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          content: const Text(
            'Bu özelliği kullanmak için TechConnect Premium üyeliğine geçmen gerekiyor.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SubscriptionPlansScreen()),
                );
              },
              child: const Text('Planları Gör'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleProfileViewsTap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snap.data() ?? {};
      final premiumActive = isPremiumActiveFromUserDoc(data);

      if (!mounted) return;

      if (premiumActive) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileViewsScreen()),
        );
      } else {
        _showProfileViewsPremiumDialog();
      }
    } catch (_) {
      _showProfileViewsPremiumDialog();
    }
  }
}

// --------------------
// SMALL WIDGETS
// --------------------
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

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.18 : 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.75)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface.withOpacity(0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumAvatar extends StatelessWidget {
  final bool isPremium;
  final String photoUrl;
  final double radius;

  const _PremiumAvatar({
    required this.isPremium,
    required this.photoUrl,
    this.radius = 45,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasPhoto = photoUrl.trim().isNotEmpty;

    // 🎯 Foto yokken kararmayı önleyen arka plan
    final Color avatarBg = isDark
        ? theme.colorScheme.surfaceVariant.withOpacity(0.85)
        : theme.colorScheme.primary.withOpacity(0.08);

    final Color avatarIconColor = isDark
        ? theme.colorScheme.onSurface
        : theme.colorScheme.primary;

    final Widget baseAvatar = CircleAvatar(
      radius: radius,
      backgroundColor: avatarBg,
      backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
      child: !hasPhoto
          ? Icon(
        Icons.person,
        size: radius,
        color: avatarIconColor,
      )
          : null,
    );

    // Premium değilse direkt dön
    if (!isPremium) return baseAvatar;

    // 🌟 Premium çerçeve
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFEFBF04),
      ),
      child: baseAvatar,
    );
  }

}
