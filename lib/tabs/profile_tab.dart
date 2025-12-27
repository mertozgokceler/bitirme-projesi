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

  int _connectionCount = 0; // 🔹 bağlantı sayısı

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Giriş yapmış kullanıcı bulunamadı.';
        });
      }
      return;
    }
    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted) {
        if (doc.exists) {
          setState(() {
            _userData = doc.data();
            _isLoading = false;
            _error = null;
          });

          // 🔹 Kullanıcının bağlantı sayısını çek
          _loadConnectionCount(user.uid);
        } else {
          setState(() {
            _isLoading = false;
            _error = 'Kullanıcı veritabanında bulunamadı.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Veri alınırken bir hata oluştu: $e';
        });
      }
    }
  }

  Future<void> _loadConnectionCount(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('connections')
          .doc(uid)
          .collection('list')
      // .where('status', isEqualTo: 'accepted')
          .get();

      if (!mounted) return;

      setState(() {
        _connectionCount = snap.docs.length;
      });
    } catch (e) {
      // print('Bağlantı sayısı okunamadı: $e');
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rememberMe', false);

      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthScreen()),
              (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      // Hata yönetimi
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_userData == null) {
      return const Center(child: Text('Kullanıcı verisi bulunamadı.'));
    }

    // 🔹 Kullanıcının şirket hesabı olup olmadığını burada çözüyoruz
    final bool isCompany =
        (_userData!['isCompany'] == true) || (_userData!['type'] == 'company');

    // 🔹 Şirket hesabı ise ayrı bir layout, değilse mevcut bireysel layout
    if (isCompany) {
      return _buildCompanyProfilePage();
    } else {
      return _buildIndividualProfilePage();
    }
  }

  // ------------------------------------------------------------
  // 🔵 BİREYSEL PROFİL SAYFASI (MEVCUT YAPI)
  // ------------------------------------------------------------
  Widget _buildIndividualProfilePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, left: 16, right: 16, bottom: 16),
      child: Column(
        children: [
          _buildProfileHeader(),
          const SizedBox(height: 24),

          // --- AKTİVİTE ---
          _buildMenuSectionTitle('Aktivite'),
          _buildProfileMenuItem(
            icon: Icons.article_outlined,
            title: 'Başvurularım',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
              );
            },
          ),

          _buildProfileMenuItem(
            icon: Icons.card_giftcard_outlined,
            title: 'Aldığım Teklifler',
            onTap: () {},
          ),
          _buildProfileMenuItem(
            icon: Icons.bookmark_border_outlined,
            title: 'Kaydedilenler',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SavedPostsScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // --- SOSYAL ---
          _buildMenuSectionTitle('Sosyal'),
          _buildProfileMenuItem(
            icon: Icons.group_outlined,
            title: 'Ağım / Bağlantılarım',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ConnectionsScreen(),
                ),
              );
            },
          ),
          _buildProfileMenuItem(
            icon: Icons.visibility_outlined,
            title: 'Profilimi Görüntüleyenler',
            onTap: _handleProfileViewsTap,
          ),
          _buildProfileMenuItem(
            icon: Icons.school_outlined,
            title: 'Sertifikalarım ve CV',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CertificatesCvScreen(),
                ),
              );
            },
          ),

          // ✅ AI CV Analiz (Yeni)
          _buildProfileMenuItem(
            icon: Icons.auto_awesome_outlined,
            title: 'AI CV Analiz',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CvAnalysisScreen()),
              );
            },
          ),

          const SizedBox(height: 16),

          // --- UYGULAMA ---
          _buildMenuSectionTitle('Uygulama'),
          _buildProfileMenuItem(
            icon: Icons.settings_outlined,
            title: 'Ayarlar',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
          _buildProfileMenuItem(
            icon: Icons.help_outline,
            title: 'Yardım ve Destek',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const HelpSupportScreen(),
                ),
              );
            },
          ),

          const Divider(height: 24),
          _buildProfileMenuItem(
            icon: Icons.logout,
            title: 'Çıkış Yap',
            color: Colors.red,
            onTap: () => _signOut(context),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // 🟣 ŞİRKET PROFİL SAYFASI (YENİ YAPI)
  // ------------------------------------------------------------
  Widget _buildCompanyProfilePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          _buildProfileHeader(),
          const SizedBox(height: 24),

          // --- İŞ İLANLARI ---
          _buildMenuSectionTitle('İş İlanları'),
          _buildProfileMenuItem(
            icon: Icons.work_outline,
            title: 'İlanlarım',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CompanyMyJobsScreen()),
              );
            },
          ),
          _buildProfileMenuItem(
            icon: Icons.quiz_outlined,
            title: 'İlan Testi Oluştur',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const JobTestHubScreen()),
              );
            },
          ),

          _buildProfileMenuItem(
            icon: Icons.bar_chart_outlined,
            title: 'İlan Performansı',
            onTap: () {
              // TODO: Analitik / performans ekranı
            },
          ),

          const SizedBox(height: 16),

          // --- ADAY YÖNETİMİ ---
          _buildMenuSectionTitle('Aday Yönetimi'),
          _buildProfileMenuItem(
            icon: Icons.inbox_outlined,
            title: 'Gelen Başvurular',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const CompanyIncomingApplicationsScreen()),
              );
            },
          ),
          _buildProfileMenuItem(
            icon: Icons.people_alt_outlined,
            title: 'Aday Havuzum',
            onTap: () {
              // TODO
            },
          ),
          _buildProfileMenuItem(
            icon: Icons.auto_awesome_outlined,
            title: 'AI Eşleşme Sonuçları',
            onTap: () {
              _showProfileViewsPremiumDialog();
            },
          ),

          const SizedBox(height: 16),

          // --- İLETİŞİM ---
          _buildMenuSectionTitle('İletişim ve Ağ'),
          _buildProfileMenuItem(
            icon: Icons.group_outlined,
            title: 'Ağım / Bağlantılarım',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ConnectionsScreen(),
                ),
              );
            },
          ),
          _buildProfileMenuItem(
            icon: Icons.chat_bubble_outline,
            title: 'Mesajlar',
            onTap: () {},
          ),
          _buildProfileMenuItem(
            icon: Icons.handshake_outlined,
            title: 'İş Birliği Talepleri',
            onTap: () {},
          ),

          const SizedBox(height: 16),

          // --- ŞİRKET SAYFASI ---
          _buildMenuSectionTitle('Şirket Sayfası'),
          _buildProfileMenuItem(
            icon: Icons.business_outlined,
            title: 'Şirket Profili',
            onTap: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => EditProfileScreen(initialUserData: _userData!),
                ),
              );
              if (result == true) {
                _fetchUserData();
              }
            },
          ),
          _buildProfileMenuItem(
            icon: Icons.groups_2_outlined,
            title: 'Ekip Üyeleri',
            onTap: () {},
          ),
          _buildProfileMenuItem(
            icon: Icons.info_outline,
            title: 'Hakkımızda',
            onTap: () {},
          ),

          const SizedBox(height: 16),

          // --- PLANLAR & FATURALAR ---
          _buildMenuSectionTitle('Planlar ve Faturalar'),
          _buildProfileMenuItem(
            icon: Icons.workspace_premium_outlined,
            title: 'Premium Paketler',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SubscriptionPlansScreen(),
                ),
              );
            },
          ),
          _buildProfileMenuItem(
            icon: Icons.receipt_long_outlined,
            title: 'Fatura Geçmişi',
            onTap: () {},
          ),
          _buildProfileMenuItem(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Şirket Kredileri',
            onTap: () {},
          ),

          const SizedBox(height: 16),

          // --- UYGULAMA ---
          _buildMenuSectionTitle('Uygulama'),
          _buildProfileMenuItem(
            icon: Icons.settings_outlined,
            title: 'Ayarlar',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
          _buildProfileMenuItem(
            icon: Icons.help_outline,
            title: 'Yardım ve Destek',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const HelpSupportScreen(),
                ),
              );
            },
          ),

          const Divider(height: 24),
          _buildProfileMenuItem(
            icon: Icons.logout,
            title: 'Çıkış Yap',
            color: Colors.red,
            onTap: () => _signOut(context),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // Profil başlığı (hem bireysel hem şirket için ortak)
  // ------------------------------------------------------------
  Widget _buildProfileHeader() {
    final data = _userData!;
    final bool isPremium = isPremiumActiveFromUserDoc(data);

    // 🔹 Hesap tipi & şirket bilgileri
    final bool isCompany =
        (data['isCompany'] == true) || (data['type'] == 'company');

    final String? personName = data['name'] as String?;
    final String? companyNameTop =
    (data['companyName'] ?? data['company']?['name']) as String?;

    final String displayName = isCompany
        ? (companyNameTop != null && companyNameTop.isNotEmpty
        ? companyNameTop
        : '(Şirket adı yok)')
        : (personName != null && personName.isNotEmpty ? personName : '(İsimsiz)');

    final String username = (data['username'] ?? 'Kullanıcı adı yok') as String;
    final String? photoUrl = data['photoUrl'] as String?;
    final String? location = data['location'] as String?;
    final String? role = data['role'] as String?;

    final bool hasConnections = _connectionCount > 0;

    final bool hasInfo =
        (location != null && location.isNotEmpty) ||
            (role != null && role.isNotEmpty) ||
            hasConnections;

    // ✅ Premium kontrollü avatar
    final Widget avatar = isPremium
        ? Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFEFBF04),
      ),
      child: CircleAvatar(
        radius: 45,
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: photoUrl == null ? const Icon(Icons.person, size: 45) : null,
      ),
    )
        : CircleAvatar(
      radius: 45,
      backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
      child: photoUrl == null ? const Icon(Icons.person, size: 45) : null,
    );


    return Stack(
      children: [
        Column(
          children: [
            avatar,
            const SizedBox(height: 12),

            // ✅ İsim + Premium Lottie (premiumsa)
            SizedBox(
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isPremium)
                    Positioned(
                      right: 0,
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: Lottie.asset(
                          'assets/lottie/premium.json',
                          repeat: true,
                          animate: true,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            Text(
              '@$username',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),

            if (hasInfo) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (location != null && location.isNotEmpty)
                    _buildInfoChip(Icons.location_on_outlined, location),
                  if ((location != null && location.isNotEmpty) &&
                      (role != null && role.isNotEmpty))
                    _buildDotSeparator(),
                  if (role != null && role.isNotEmpty)
                    _buildInfoChip(Icons.work_outline, role),
                  if (((location != null && location.isNotEmpty) ||
                      (role != null && role.isNotEmpty)) &&
                      hasConnections)
                    _buildDotSeparator(),
                  if (hasConnections)
                    _buildInfoChip(
                      Icons.group_outlined,
                      '$_connectionCount bağlantı',
                    ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            OutlinedButton(
              onPressed: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        EditProfileScreen(initialUserData: _userData!),
                  ),
                );
                if (result == true) {
                  _fetchUserData();
                }
              },
              child:
              Text(isCompany ? 'Şirket Profilini Düzenle' : 'Profili Düzenle'),
            ),
          ],
        ),
      ],
    );
  }

  // Konum / rol / bağlantı chip
  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildDotSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6.0),
      child: Text(
        '•',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _buildProfileMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    final itemColor = color ?? Theme.of(context).textTheme.bodyLarge?.color;
    return ListTile(
      leading: Icon(icon, color: itemColor),
      title: Text(
        title,
        style: TextStyle(
          color: itemColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: color == null ? const Icon(Icons.arrow_forward_ios, size: 16) : null,
      onTap: onTap,
    );
  }

  Widget _buildMenuSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade600,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // 🔒 Premium bilgilendirme dialog'u
  void _showProfileViewsPremiumDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          title: Row(
            children: [
              Icon(
                Icons.lock_outline,
                color: isDark ? Colors.amberAccent : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Premium Özellik',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: const Text(
            'Profilini kimlerin görüntülediğini görmek için '
                'TechConnect Premium üyeliğine geçmen gerekiyor.',
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
                  MaterialPageRoute(
                    builder: (context) => const SubscriptionPlansScreen(),
                  ),
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
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snap.data() ?? {};
      final premiumActive = isPremiumActiveFromUserDoc(data);

      if (premiumActive) {
        if (!mounted) return;
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

  bool isPremiumActiveFromUserDoc(Map<String, dynamic> data) {
    final isPremiumFlag = data['isPremium'] == true;

    final until = data['premiumUntil'];
    DateTime? untilDt;

    if (until is Timestamp) {
      untilDt = until.toDate();
    }

    final now = DateTime.now();
    final validByDate = untilDt != null && untilDt.isAfter(now);

    // Tarih varsa onu esas al: geçmişse premium değil.
    if (untilDt != null) return validByDate;

    // Tarih yoksa flag’e bak.
    return isPremiumFlag;
  }
}
