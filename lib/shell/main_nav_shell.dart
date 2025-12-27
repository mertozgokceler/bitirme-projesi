// lib/shell/main_nav_shell.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:techconnect/screens/create_job_post_screen.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:lottie/lottie.dart';

import '../screens/chat_list_screen.dart';
import '../tabs/home_tab.dart';
import '../tabs/profile_tab.dart';
import '../tabs/add_post_tab.dart';
import '../screens/create_post_screen.dart';
import '../screens/subscription_plans_screen.dart';
import '../screens/user_profile_screen.dart';
import '../in_app_notification.dart';
import '../screens/connection_requests_screen.dart';
import '../screens/job_apply_screen.dart';
import '../screens/incoming_call_screen.dart';
import '../services/location_service.dart';
import '../widgets/city_picker_sheet.dart';


// ✅ CALL - Global Yakalama
import '../services/call_service.dart';

import '../services/incoming_call_service.dart';

const String kLogoPath = 'assets/images/techconnectlogo.png';
const String kLogoGoldPath = 'assets/images/techconnect_logo_gold.png';

class MainNavShell extends StatefulWidget {
  const MainNavShell({super.key});

  @override
  State<MainNavShell> createState() => _MainNavShellState();
}

class _MainNavShellState extends State<MainNavShell>
    with SingleTickerProviderStateMixin {
  // ✅ Call: tek instance — app-level
  late final CallService _callService;
  late final IncomingCallService _incomingCallService;

  int _index = 0;

  bool _showBars = true;
  bool _chatsWarmupDone = false;

  bool _isCompany = false;
  bool _accountLoaded = false;

  bool _isPremium = false;
  bool _premiumLoaded = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumSub;


  final _pages = const [
    HomeTab(),
    JobsTab(),
    AddPostTab(),
    NotificationsTab(),
    ProfileTab(),
  ];

  final _titles = const [
    '',
    'İş İlanları',
    'Gönderilerim',
    'Bildirimler',
    'Profilim',
  ];

  final _auth = FirebaseAuth.instance;

  StreamSubscription<QuerySnapshot>? _chatSub;
  StreamSubscription<QuerySnapshot>? _connReqSub;

  final Map<String, Timestamp?> _lastSeenChatTs = {};
  bool _incomingReqInitialized = false;
  final Map<String, String> _senderNameCache = {};

  late final AnimationController _aiPulseController;

  // ✅ auth değişince call listener refresh
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();

    // ✅ tek instance
    _callService = CallService();
    _incomingCallService = IncomingCallService();

    inAppNotificationService.loadFromPrefs();
    _initNotificationsForCurrentUser();
    _loadAccountType();
    _listenPremiumStatus();

    _aiPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _listenIncomingMessages();
    _listenIncomingConnectionRequests();
    _showPremiumPopupIfNeeded();

    // ✅ uygulama açıkken gelen aramayı her yerden yakala
    _startIncomingCallServiceListener();

    // ✅ login/logout olunca listener’ı tazele
    _authSub = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _incomingCallService.stop();
        return;
      }
      _startIncomingCallServiceListener();
    });
  }

  Future<void> _handleLocationAction() async {
    if (!mounted) return;

    try {
      // ✅ 1) Önce GPS dene
      await LocationService.requestAndSaveLiveLocation();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum güncellendi (GPS).')),
      );
    } catch (_) {
      // ✅ 2) GPS patladıysa → manuel şehir sheet aç
      final city = await showCityPickerSheet(context);

      if (city == null) return;
      final trimmed = city.trim();
      if (trimmed.isEmpty) return;

      try {
        await LocationService.saveManualCity(trimmed);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konum güncellendi: $trimmed')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konum kaydedilemedi: $e')),
        );
      }
    }
  }


  Future<void> _initNotificationsForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    await inAppNotificationService.initForUser(user?.uid);
  }

  Future<void> _loadAccountType() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = snap.data() as Map<String, dynamic>? ?? {};

      final rawAccountType =
      (data['accountType'] ?? data['userType'] ?? data['role'] ?? '')
          .toString()
          .toLowerCase();

      final bool flagIsCompany = (data['isCompany'] == true) ||
          (data['is_company'] == true) ||
          rawAccountType == 'company' ||
          rawAccountType == 'şirket' ||
          rawAccountType == 'employer';

      setState(() {
        _isCompany = flagIsCompany;
        _accountLoaded = true;
      });

      debugPrint(
        'DEBUG[accountType] uid=${user.uid} raw="$rawAccountType" '
            'isCompanyFlag=$flagIsCompany dataKeys=${data.keys}',
      );
    } catch (e) {
      debugPrint('DEBUG[accountType] hata: $e');
    }
  }

  bool _computeIsPremiumFromUser(Map<String, dynamic> data) {
    final isPremiumFlag = data['isPremium'] == true;

    final until = data['premiumUntil'];
    DateTime? untilDt;

    if (until is Timestamp) {
      untilDt = until.toDate();
    }

    final now = DateTime.now();
    final validByDate = untilDt != null && untilDt.isAfter(now);

    // Flag true olsa bile tarih geçmişse premium sayma.
    // Tarih varsa esas alınır.
    if (untilDt != null) return validByDate;

    return isPremiumFlag;
  }

  void _listenPremiumStatus() {
    final user = _auth.currentUser;
    if (user == null) return;

    _premiumSub?.cancel();

    _premiumSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) {
      final data = snap.data() ?? {};
      final p = _computeIsPremiumFromUser(data);

      if (!mounted) return;
      setState(() {
        _isPremium = p;
        _premiumLoaded = true;
      });
    }, onError: (e) {
      debugPrint('DEBUG[premium] listen error: $e');
      if (!mounted) return;
      setState(() {
        _isPremium = false;
        _premiumLoaded = true;
      });
    });
  }


  @override
  void dispose() {
    _chatSub?.cancel();
    _connReqSub?.cancel();
    _authSub?.cancel();
    _premiumSub?.cancel();

    _incomingCallService.dispose();
    _aiPulseController.dispose();

    super.dispose();
  }

  void _setBarsVisible(bool visible) {
    if (_showBars == visible) return;
    setState(() => _showBars = visible);
  }

  Future<String> _getSenderDisplayName(String uid) async {
    if (_senderNameCache.containsKey(uid)) {
      return _senderNameCache[uid]!;
    }

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

      String displayName = uid;
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final name = (data['name'] ?? '').toString().trim();
        final username = (data['username'] ?? '').toString().trim();

        if (name.isNotEmpty) {
          displayName = name;
        } else if (username.isNotEmpty) {
          displayName = '@$username';
        }
      }

      _senderNameCache[uid] = displayName;
      return displayName;
    } catch (e) {
      debugPrint('DEBUG[inapp] _getSenderDisplayName hata: $e');
      return uid;
    }
  }

  // ==========================================================
  // ✅ INCOMING CALL LISTENER (foreground) — SERVICE
  // ==========================================================
  void _startIncomingCallServiceListener() {
    _incomingCallService.start(
      onIncoming: (call) async {
        if (!mounted) return;

        try {
          // ✅ Root navigator kullan: modal/sheet vs araya girince sapıtmasın
          await Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => IncomingCallScreen(
                call: call,
                callService: _callService,
                onDone: () {
                  // ✅ UI kapandı bilgisi
                  _incomingCallService.markUiClosed();
                },
              ),
            ),
          );
        } catch (e, st) {
          debugPrint('DEBUG[call] incoming push error: $e');
          _incomingCallService.markUiClosed();
        } finally {
          // ✅ Her durumda kilidi bırak
          _incomingCallService.markUiClosed();
        }
      },
      onError: (e, st) {
        debugPrint('DEBUG[call] incomingCallService error: $e');
        _incomingCallService.markUiClosed();
      },
    );
  }


  void _listenIncomingMessages() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('DEBUG[inapp] currentUser null, listener başlamıyor.');
      return;
    }

    _chatSub?.cancel();

    debugPrint('DEBUG[inapp] Listener başlatılıyor. user=${currentUser.uid}');

    _chatSub = FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: currentUser.uid)
        .snapshots()
        .listen(
          (snapshot) async {
        debugPrint(
          'DEBUG[inapp] chats snapshot docs=${snapshot.docs.length} changes=${snapshot.docChanges.length}',
        );

        if (!_chatsWarmupDone) {
          debugPrint('DEBUG[inapp] chats warmup başlıyor.');
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = data['lastMessageTimestamp'] as Timestamp?;
            if (ts != null) _lastSeenChatTs[doc.id] = ts;
          }
          _chatsWarmupDone = true;
          debugPrint(
              'DEBUG[inapp] chats warmup bitti. stored=${_lastSeenChatTs.length}');
          return;
        }

        for (var change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added &&
              change.type != DocumentChangeType.modified) {
            continue;
          }

          final data = change.doc.data() as Map<String, dynamic>?;
          if (data == null) continue;

          final chatId = change.doc.id;
          final senderId = data['lastMessageSenderId'] as String?;
          final ts = data['lastMessageTimestamp'] as Timestamp?;
          final lastMessage =
          (data['lastMessage'] ?? 'Sana yeni bir mesaj geldi').toString();

          if (senderId == null) continue;
          if (senderId == currentUser.uid) continue;

          if (ts != null) {
            final oldTs = _lastSeenChatTs[chatId];
            if (oldTs != null && !ts.toDate().isAfter(oldTs.toDate())) {
              continue;
            }
            _lastSeenChatTs[chatId] = ts;
          }

          if (!mounted) return;

          final displayName = await _getSenderDisplayName(senderId);

          inAppNotificationService.show(
            displayName,
            lastMessage,
            context: context,
          );
        }
      },
      onError: (e, st) {
        debugPrint('DEBUG[inapp] chat listener error: $e');
      },
    );
  }

  void _listenIncomingConnectionRequests() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('DEBUG[inapp] currentUser null, connReq listener başlamıyor.');
      return;
    }

    _connReqSub?.cancel();

    _connReqSub = FirebaseFirestore.instance
        .collection('connectionRequests')
        .doc(currentUser.uid)
        .collection('incoming')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) async {
        if (!_incomingReqInitialized) {
          _incomingReqInitialized = true;
          return;
        }

        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) continue;

          final data = change.doc.data() as Map<String, dynamic>?;
          if (data == null) continue;

          final fromId = (data['from'] as String?) ?? change.doc.id;
          if (fromId == currentUser.uid) continue;

          final displayName = await _getSenderDisplayName(fromId);
          if (!mounted) return;

          inAppNotificationService.show(
            'Yeni bağlantı isteği',
            '$displayName sana bağlantı isteği gönderdi.',
            context: context,
          );
        }
      },
      onError: (e, st) {
        debugPrint('DEBUG[inapp] connReq listener error: $e');
      },
    );
  }

  Future<void> _showPremiumPopupIfNeeded() async {

    if (_premiumLoaded && _isPremium) return;

    final prefs = await SharedPreferences.getInstance();
    final hide = prefs.getBool('hidePremiumPopup') ?? false;
    if (hide) return;

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPremiumDialog();
    });
  }

  void _showPremiumDialog() {
    bool dontShowAgain = false;

    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_outline,
                    size: 36,
                    color: AppColors.premiumIcon(theme),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'TechConnect Premium',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daha yüksek profil görüntülenme oranı, '
                        'profilini kimlerin görüntülediğini görme ve '
                        'işe alım süreçlerinde öne çıkmanı sağlayan ek avantajlar.',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: dontShowAgain,
                    onChanged: (val) {
                      setState(() => dontShowAgain = val ?? false);
                    },
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Bir daha gösterme',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    if (dontShowAgain) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('hidePremiumPopup', true);
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Sonra'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (dontShowAgain) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('hidePremiumPopup', true);
                    }
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionPlansScreen(),
                      ),
                    );
                  },
                  child: const Text('Planları Gör'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAiFabIcon(BuildContext context) {
    final theme = Theme.of(context);
    final glowColor = AppColors.aiGlow(theme);

    return AnimatedBuilder(
      animation: _aiPulseController,
      builder: (context, child) {
        final t = _aiPulseController.value;
        final scale = 1.0 + 0.06 * t;
        final blur = 8.0 + 10.0 * t;
        final spread = 1.0 + 1.5 * t;

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: glowColor,
                  blurRadius: blur,
                  spreadRadius: spread,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Image.asset(
        'assets/icons/ai.png',
        width: 28,
        height: 28,
      ),
    );
  }

  Widget _buildSearchBubble(
      BuildContext context, {
        Widget? rightInside,
      }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bg = theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.18 : 0.75);
    final border = theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.30 : 0.55);
    final hint = theme.colorScheme.onSurfaceVariant.withOpacity(isDark ? 0.55 : 0.65);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchTab()),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.25 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 18, color: hint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kullanıcı veya şirket ara',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: hint,
                      ),
                    ),
                  ),
                  if (rightInside != null) ...[
                    const SizedBox(width: 8),
                    rightInside,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar(BuildContext context) {
    final theme = Theme.of(context);

    // AddPost tab: hiç AppBar istemiyorsan
    if (_index == 2) return null;

    // Notifications: basit başlık
    if (_index == 3) {
      return AppBar(
        automaticallyImplyLeading: false,
      );
    }

    // Profile: basit başlık
    if (_index == 4) {
      return AppBar(
        automaticallyImplyLeading: false,
      );
    }

    // Jobs: istersen search bubble KALABİLİR veya SADECE title olabilir.
    // Ben senin mevcut UX'ine uygun: search bubble kalsın + sağda ilan ekle (şirketse) diyorum.
    if (_index == 1) {
      return AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _buildSearchBubble(
            context,
            rightInside: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleLocationAction, // ✅ TEK DOĞRU ÇAĞRI
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: InkResponse(
                  onTap: _handleLocationAction,
                  radius: 22,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Image.asset(
                      'assets/icons/gps.png',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      color: const Color(0xFFFC7CFF),
                    ),
                  ),
                ),

              ),
            ),
          ),
        ),
      );
    }
    // Home: senin mevcut "logo + search + chat" AppBar
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      leadingWidth: 64,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: Image.asset(
            (_premiumLoaded && _isPremium) ? kLogoGoldPath : kLogoPath,
            height: 42,
            fit: BoxFit.contain,
          ),
        ),
      ),
      title: Padding(
        padding: const EdgeInsets.only(left: 8, right: 12),
        child: _buildSearchBubble(context),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton(
            icon: Image.asset(
              'assets/icons/chat_arrow.png',
              width: 32,
              height: 32,
            ),
            tooltip: 'Sohbetler',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatListScreen()),
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildFloatingNavBar(BuildContext context) {
    return AnimatedBuilder(
      animation: inAppNotificationService,
      builder: (context, _) {
        final unread = inAppNotificationService.unreadCount;
        final theme = Theme.of(context);

        final barColor = AppColors.floatingBarBg(theme);
        final shadowColor = AppColors.floatingBarShadow(theme);
        final borderColor = AppColors.floatingBarBorder(theme);

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 32,
                spreadRadius: 4,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildNavItem(
                index: 0,
                label: 'Anasayfa',
                icon: _navIcon(
                  theme.brightness == Brightness.dark
                      ? 'assets/icons/home_light.png'
                      : 'assets/icons/home2.png',
                  0,
                  context,
                ),
              ),
              _buildNavItem(
                index: 1,
                label: 'İş İlanları',
                icon: _navIcon(
                  theme.brightness == Brightness.dark
                      ? 'assets/icons/job_light.png'
                      : 'assets/icons/job.png',
                  1,
                  context,
                ),
              ),
              _buildNavItem(
                index: 2,
                label: 'Gönderi',
                icon: _navIcon(
                  theme.brightness == Brightness.dark
                      ? 'assets/icons/more_light.png'
                      : 'assets/icons/more.png',
                  2,
                  context,
                ),
              ),
              _buildNavItem(
                index: 3,
                label: 'Bildirimler',
                icon: _navIconWithBadge(
                  theme.brightness == Brightness.dark
                      ? 'assets/icons/notification_light.png'
                      : 'assets/icons/notification.png',
                  3,
                  context,
                  unread,
                ),
              ),
              _buildNavItem(
                index: 4,
                label: 'Profilim',
                icon: _navIcon(
                  theme.brightness == Brightness.dark
                      ? 'assets/icons/user_light.png'
                      : 'assets/icons/user.png',
                  4,
                  context,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    FloatingActionButton? fab;
    if (_showBars) {
      if (_index == 2) {
        fab = FloatingActionButton(
          tooltip: 'Yeni Gönderi',
          backgroundColor: AppColors.brand(theme),
          foregroundColor: AppColors.onBrand(theme),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreatePostScreen()),
            );
          },
          child: Icon(Icons.add, color: AppColors.onBrand(theme)),
        );
      } else if (_index == 1 && _isCompany) {
        fab = FloatingActionButton(
          tooltip: 'İlan Ekle',
          backgroundColor: AppColors.brand(theme),
          foregroundColor: AppColors.onBrand(theme),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateJobPostScreen()),
            );
          },
          child: Icon(Icons.post_add, color: AppColors.onBrand(theme)),
        );
      } else {
        fab = FloatingActionButton(
          tooltip: 'AI Career Advisor',
          backgroundColor: AppColors.brand(theme),
          foregroundColor: AppColors.onBrand(theme),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: theme.colorScheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const AiCareerAdvisorSheet(),
            );
          },
          child: _buildAiFabIcon(context),
        );
      }
    }

    return Scaffold(
      appBar: _buildAppBar(context),
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis != Axis.vertical) return false;
          if (notification.depth != 0) return false;

          final metrics = notification.metrics;

          if (metrics.maxScrollExtent <= 0) {
            _setBarsVisible(true);
            return false;
          }

          final bool atBottom = metrics.pixels >= (metrics.maxScrollExtent - 16);

          _setBarsVisible(!atBottom);
          return false;
        },
        child: Stack(
          children: [
            SafeArea(
              child: IndexedStack(index: _index, children: _pages),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 35,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                offset: _showBars ? Offset.zero : const Offset(0, 1.0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeOutCubic,
                  opacity: _showBars ? 1 : 0,
                  child: _buildFloatingNavBar(context),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: fab,
      floatingActionButtonLocation: const _UpFABLocation(offset: 85),
    );
  }

  // ======================= ICON HELPERS =======================

  Widget _navIcon(String path, int i, BuildContext context) {
    final theme = Theme.of(context);
    final bool isSelected = _index == i;
    final Color color =
    isSelected ? AppColors.navSelected(theme) : AppColors.navUnselected(theme);

    return SizedBox(
      width: 24,
      height: 24,
      child: Image.asset(
        path,
        width: 24,
        height: 24,
        fit: BoxFit.contain,
        color: color,
      ),
    );
  }

  Widget _navIconWithBadge(
      String path,
      int i,
      BuildContext context,
      int unreadCount,
      ) {
    final theme = Theme.of(context);
    final base = _navIcon(path, i, context);

    if (unreadCount <= 0) return base;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppColors.badge(theme),
              shape: BoxShape.circle,
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Center(
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: TextStyle(
                  color: AppColors.onBadge(theme),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required Widget icon,
  }) {
    final theme = Theme.of(context);
    final bool isSelected = _index == index;

    final Color color =
    isSelected ? AppColors.navSelected(theme) : AppColors.navUnselected(theme);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => setState(() => _index = index),
          splashColor: AppColors.navSplash(theme),
          highlightColor: AppColors.navHighlight(theme),
          child: SizedBox(
            height: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ======================= SEARCH TAB =======================
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();

  static Future<void> devSeedOneUser(BuildContext context) async {
    final fs = FirebaseFirestore.instance;
    final doc = fs.collection('users').doc('dev_seed_mert');
    final exists = await doc.get();
    if (exists.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seed zaten var: dev_seed_mert')),
      );
      return;
    }
    String trLower(String s) =>
        s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
    const name = 'Mert Özgökçeler';
    const username = 'mertozgokceler';
    await doc.set({
      'name': name,
      'username': username,
      'nameLower': trLower(name),
      'usernameLower': trLower(username),
      'photoUrl': null,
      'role': 'Developer',
      'isSearchable': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seed eklendi: mertozgokceler')),
    );
  }

  static Future<void> devBackfillLower(BuildContext context) async {
    final fs = FirebaseFirestore.instance;
    String trLower(String s) =>
        s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
    final snap = await fs.collection('users').limit(500).get();
    int toUpdate = 0;
    final batch = fs.batch();
    for (final d in snap.docs) {
      final m = d.data();
      final name = (m['name'] ?? '').toString();
      final username = (m['username'] ?? '').toString();
      final upd = <String, dynamic>{};
      if (m['isSearchable'] != true) upd['isSearchable'] = true;
      if ((m['nameLower'] ?? '').toString().isEmpty && name.isNotEmpty) {
        upd['nameLower'] = trLower(name);
      }
      if ((m['usernameLower'] ?? '').toString().isEmpty && username.isNotEmpty) {
        upd['usernameLower'] = trLower(username);
      }
      if (upd.isNotEmpty) {
        batch.update(d.reference, upd);
        toUpdate++;
      }
    }
    if (toUpdate > 0) {
      await batch.commit();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backfill tamam: $toUpdate doküman güncellendi')),
    );
  }
}

class _SearchTabState extends State<SearchTab> {
  static const String kRecentViewedKey = 'recent_viewed_users_v1';

  final _qCtrl = TextEditingController();
  final _fs = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  DateTime _lastType = DateTime.now();
  List<String> _history = [];
  SharedPreferences? _prefs;

  List<Map<String, dynamic>> _recentViewed = [];
  bool _recentLoading = false;

  @override
  void initState() {
    super.initState();
    _qCtrl.addListener(_onChanged);
    _initPrefs();
  }

  @override
  void dispose() {
    _qCtrl.removeListener(_onChanged);
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _history = _prefs?.getStringList('search_history') ?? [];
    });
    await _loadRecentViewed();
  }

  String _formatRelativeTime(int tsMs) {
    if (tsMs <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 10) return 'Şimdi';
    if (diff.inSeconds < 60) return '${diff.inSeconds} sn önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';

    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    return '$d.$m.$y';
  }

  Future<void> _addRecentViewed(String uid) async {
    if (uid.trim().isEmpty) return;

    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kRecentViewedKey) ?? [];

    raw.removeWhere((x) => x.startsWith('$uid|') || x == uid);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    raw.insert(0, '$uid|$nowMs');

    if (raw.length > 30) raw.removeRange(30, raw.length);

    await prefs.setStringList(kRecentViewedKey, raw);
    await _loadRecentViewed();
  }

  Future<void> _removeRecentViewed(String uid) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kRecentViewedKey) ?? [];

    raw.removeWhere((x) => x.startsWith('$uid|') || x == uid);

    await prefs.setStringList(kRecentViewedKey, raw);
    await _loadRecentViewed();
  }

  Future<void> _clearRecentViewed() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove(kRecentViewedKey);
    if (!mounted) return;
    setState(() => _recentViewed.clear());
  }

  Future<void> _loadRecentViewed() async {
    if (!mounted) return;
    setState(() => _recentLoading = true);

    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      final raw = prefs.getStringList(kRecentViewedKey) ?? [];

      final List<Map<String, dynamic>> parsed = [];
      final seen = <String>{};

      for (final s in raw) {
        final parts = s.split('|');
        if (parts.isEmpty) continue;
        final uid = parts[0].trim();
        if (uid.isEmpty) continue;
        if (seen.contains(uid)) continue;
        seen.add(uid);

        int ts = 0;
        if (parts.length >= 2) {
          ts = int.tryParse(parts[1]) ?? 0;
        }
        parsed.add({'uid': uid, 'ts': ts});
      }

      final List<Map<String, dynamic>> enriched = [];
      for (final it in parsed) {
        final uid = it['uid'] as String;
        final ts = it['ts'] as int;

        try {
          final doc = await _fs.collection('users').doc(uid).get();
          if (!doc.exists) continue;
          final data = doc.data() as Map<String, dynamic>? ?? {};
          enriched.add({
            'uid': uid,
            'ts': ts,
            'name': (data['name'] ?? '').toString(),
            'username': (data['username'] ?? '').toString(),
            'photoUrl': data['photoUrl'],
            'role': data['role'],
          });
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _recentViewed = enriched;
        _recentLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _recentLoading = false);
      debugPrint('DEBUG[recent] load error: $e');
    }
  }

  Future<void> _saveHistory() async {
    await _prefs?.setStringList('search_history', _history);
  }

  String trLower(String s) =>
      s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  void _addToHistory(String q) {
    final key = trLower(q);
    if (key.isEmpty) return;
    _history.removeWhere((e) => e == key);
    _history.insert(0, key);
    if (_history.length > 20) _history = _history.sublist(0, 20);
    _saveHistory();
  }

  Future<void> _clearHistory() async {
    await _prefs?.remove('search_history');
    if (!mounted) return;

    setState(() {
      _history.clear();
      _qCtrl.clear();
      _results.clear();
      _loading = false;
    });

    FocusScope.of(context).unfocus();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Arama geçmişi temizlendi')),
    );
  }

  void _onChanged() async {
    _lastType = DateTime.now();
    final captured = _lastType;

    await Future.delayed(const Duration(milliseconds: 350));
    if (captured != _lastType) return;

    _search(_qCtrl.text.trim());
  }

  String _endBound(String s) => '$s\uf8ff';

  Future<void> _search(String q) async {
    if (!mounted) return;

    if (q.isEmpty) {
      setState(() {
        _results.clear();
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      _addToHistory(q);

      final key = trLower(q);
      final end = _endBound(key);

      Future<QuerySnapshot<Map<String, dynamic>>> q1() => _fs
          .collection('users')
          .where('isSearchable', isEqualTo: true)
          .orderBy('usernameLower')
          .startAt([key])
          .endAt([end])
          .limit(20)
          .get();

      Future<QuerySnapshot<Map<String, dynamic>>> q2() => _fs
          .collection('users')
          .where('isSearchable', isEqualTo: true)
          .orderBy('nameLower')
          .startAt([key])
          .endAt([end])
          .limit(20)
          .get();

      var snaps = await Future.wait([q1(), q2()]);

      if (snaps[0].docs.isEmpty && snaps[1].docs.isEmpty) {
        final f1 = _fs
            .collection('users')
            .where('isSearchable', isEqualTo: true)
            .orderBy('username')
            .startAt([q])
            .endAt([_endBound(q)])
            .limit(20)
            .get();

        final f2 = _fs
            .collection('users')
            .where('isSearchable', isEqualTo: true)
            .orderBy('name')
            .startAt([q])
            .endAt([_endBound(q)])
            .limit(20)
            .get();

        snaps = await Future.wait([f1, f2]);
      }

      final Map<String, Map<String, dynamic>> uniq = {};
      for (final s in snaps) {
        for (final d in s.docs) {
          final data = d.data();
          uniq[d.id] = {
            'uid': d.id,
            'name': (data['name'] ?? '').toString(),
            'username': (data['username'] ?? '').toString(),
            'photoUrl': data['photoUrl'],
            'role': data['role'],
          };
        }
      }

      final list = uniq.values.toList()
        ..sort((a, b) {
          final aExact = a['username'].toString().toLowerCase() == key ||
              a['name'].toString().toLowerCase().startsWith(key);
          final bExact = b['username'].toString().toLowerCase() == key ||
              b['name'].toString().toLowerCase().startsWith(key);
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;
          return a['name']
              .toString()
              .toLowerCase()
              .compareTo(b['name'].toString().toLowerCase());
        });

      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arama hatası: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showHistory = _qCtrl.text.isEmpty && _history.isNotEmpty;

    final usernameStyle = TextStyle(
      color: AppColors.subtleText(theme),
    );

    final isQueryEmpty = _qCtrl.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanıcı Ara'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Bağlantı istekleri',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ConnectionRequestsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _qCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Kullanıcı adı veya Ad Soyad',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Arama geçmişini sil',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _clearHistory,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _search(_qCtrl.text.trim()),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (showHistory)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: -6,
                  children: _history
                      .map(
                        (h) => InputChip(
                      label: Text(h),
                      onPressed: () {
                        _qCtrl.text = h;
                        _search(h);
                      },
                    ),
                  )
                      .toList(),
                ),
              ),
            ),
          if (isQueryEmpty)
            Expanded(
              child: _recentLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_recentViewed.isEmpty
                  ? Center(
                child: Text(
                  'Henüz herhangi bir kullanıcı aramadın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.subtleText(theme)),
                ),
              )
                  : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      children: [
                        const Text(
                          'Son Baktığın Hesaplar',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _clearRecentViewed,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Temizle'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _recentViewed.length,
                      separatorBuilder: (_, __) =>
                      const Divider(height: 1, thickness: 0.5),
                      itemBuilder: (context, i) {
                        final u = _recentViewed[i];
                        final name = (u['name'] ?? '').toString().trim();
                        final username =
                        (u['username'] ?? '').toString().trim();
                        final role = (u['role'] ?? '').toString().trim();
                        final uid = (u['uid'] ?? '').toString();
                        final ts = (u['ts'] ?? 0) as int;

                        final when = _formatRelativeTime(ts);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: u['photoUrl'] != null
                                ? NetworkImage(u['photoUrl'])
                                : null,
                            child: u['photoUrl'] == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(
                            name.isEmpty ? '(İsimsiz)' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@$username',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: usernameStyle,
                              ),
                              if (role.isNotEmpty)
                                Text(
                                  role,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (when.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    when,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.subtleText(theme),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: 'Listeden kaldır',
                            icon: Icon(
                              Icons.close,
                              color: AppColors.subtleText(theme),
                            ),
                            onPressed: () => _removeRecentViewed(uid),
                          ),
                          onTap: () async {
                            await _addRecentViewed(uid);
                            final currentUserId =
                                FirebaseAuth.instance.currentUser!.uid;

                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(
                                  userId: uid,
                                  currentUserId: currentUserId,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              )),
            )
          else
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('Sonuç yok'))
                  : ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, __) =>
                const Divider(height: 1, thickness: 0.5),
                itemBuilder: (context, i) {
                  final u = _results[i];
                  final name = (u['name'] ?? '').toString().trim();
                  final username = (u['username'] ?? '').toString().trim();
                  final role = (u['role'] ?? '').toString().trim();

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: u['photoUrl'] != null
                          ? NetworkImage(u['photoUrl'])
                          : null,
                      child: u['photoUrl'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(
                      name.isEmpty ? '(İsimsiz)' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: role.isNotEmpty
                        ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: usernameStyle,
                        ),
                        Text(
                          role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                        : Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: usernameStyle,
                    ),
                    onTap: () async {
                      final currentUserId =
                          FirebaseAuth.instance.currentUser!.uid;

                      final uid = (u['uid'] ?? '').toString();
                      await _addRecentViewed(uid);

                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            userId: uid,
                            currentUserId: currentUserId,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// ======================= JOBS TAB =======================
class JobsTab extends StatelessWidget {
  const JobsTab({super.key});

  void _openJobDetailsSheet(
      BuildContext context,
      String jobId,
      Map<String, dynamic> job,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final theme = Theme.of(context);

        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.40,
          maxChildSize: 1.00,
          expand: false,
          builder: (context, scrollController) {
            final title = (job['title'] ?? '(Pozisyon adı yok)').toString().trim();
            final companyName =
            (job['companyName'] ?? 'Şirket adı belirtilmemiş').toString().trim();
            final location =
            (job['location'] ?? 'Konum belirtilmemiş').toString().trim();
            final description = (job['description'] ?? '').toString().trim();
            final workType = (job['workType'] ?? 'İş yerinde').toString().trim();

            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.sheetHandle(theme),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          companyName,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.subtleText(theme),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: AppColors.subtleText(theme),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$location • $workType',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.subtleText(theme),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        Text(
                          'İlan Açıklaması',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description.isEmpty ? 'Açıklama eklenmemiş.' : description,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => JobApplyScreen(
                                    jobId: jobId,
                                    job: job,
                                  ),
                                ),
                              );
                            },
                            child: const Text('Başvur'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('İlanlar yüklenirken hata oluştu:\n${snapshot.error}'),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('Henüz yayınlanmış iş ilanı yok.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();

            final title = (data['title'] ?? '').toString().trim();
            final companyName = (data['companyName'] ?? '').toString().trim();
            final location = (data['location'] ?? '').toString().trim();
            final logoUrl = (data['companyLogoUrl'] ?? '').toString().trim();
            final companyId = (data['companyId'] ?? '').toString().trim();

            final displayTitle = title.isEmpty ? '(Pozisyon adı yok)' : title;
            final displayCompany =
            companyName.isEmpty ? 'Şirket adı belirtilmemiş' : companyName;
            final displayLocation =
            location.isEmpty ? 'Konum belirtilmemiş' : location;

            final bgColor = AppColors.cardBg(theme);
            final borderColor = AppColors.cardBorder(theme);

            Widget logoWidget;
            if (companyId.isEmpty) {
              logoWidget = _CompanyLogoBox(
                logoUrl: logoUrl,
                fallbackText: displayCompany,
              );
            } else {
              logoWidget = FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(companyId)
                    .get(),
                builder: (context, snap) {
                  String finalLogo = logoUrl;

                  if (snap.hasData && snap.data!.exists) {
                    final userData = snap.data!.data()!;
                    final userLogo = (userData['photoUrl'] ?? '').toString().trim();
                    if (finalLogo.isEmpty && userLogo.isNotEmpty) {
                      finalLogo = userLogo;
                    }
                  }

                  return _CompanyLogoBox(
                    logoUrl: finalLogo,
                    fallbackText: displayCompany,
                  );
                },
              );
            }

            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openJobDetailsSheet(context, doc.id, data),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 0.6),
                ),
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        logoWidget,
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                displayCompany,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '$displayLocation (İş yerinde)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.subtleText(theme),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: AppColors.success(theme),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Başvurular aktif olarak inceleniyor',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: -4,
                      children: [
                        _buildTag(context, 'Görüntülendi'),
                        _buildTag(context, 'Tanıtılan içerik'),
                        _buildTag(
                          context,
                          'Kolay Başvuru',
                          leadingIcon: Icons.linked_camera,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CompanyLogoBox extends StatelessWidget {
  final String logoUrl;
  final String fallbackText;

  const _CompanyLogoBox({
    required this.logoUrl,
    required this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.logoBoxBg(theme),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl.isNotEmpty
          ? Image.network(
        logoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return _buildLogoFallback(fallbackText);
        },
      )
          : _buildLogoFallback(fallbackText),
    );
  }
}

Widget _buildTag(BuildContext context, String label, {IconData? leadingIcon}) {
  final theme = Theme.of(context);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.chipBg(theme),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingIcon != null) ...[
          Icon(
            leadingIcon,
            size: 13,
            color: AppColors.subtleText(theme),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    ),
  );
}

Widget _buildLogoFallback(String companyName) {
  final initial =
  companyName.isNotEmpty ? companyName.characters.first.toUpperCase() : '?';

  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      return Container(
        color: AppColors.fallbackAvatarBg(theme),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              color: AppColors.onFallbackAvatar(theme),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    },
  );
}

/// ======================= NOTIFICATIONS TAB =======================
class NotificationsTab extends StatelessWidget {
  const NotificationsTab({super.key});

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  // ================= EMPTY STATE =================
  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Transform.translate(
          offset: const Offset(0, -90), // 👈 HER ŞEYİ yukarı alır
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: Lottie.asset(
                  'assets/lottie/no_item_found.json',
                  repeat: true,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Henüz herhangi bir bildirim almadın',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Bildirim almaya başladıkça burada göreceksin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.subtleText(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SlidableAutoCloseBehavior(
      child: AnimatedBuilder(
        animation: inAppNotificationService,
        builder: (context, _) {
          final items = inAppNotificationService.items;

          // 👇 EMPTY STATE
          if (items.isEmpty) {
            return _buildEmptyState(context);
          }

          // 👇 NORMAL LIST
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final n = items[index];

              final bg = n.isRead
                  ? theme.colorScheme.surface
                  : theme.colorScheme.primary.withOpacity(0.12);

              final border = n.isRead
                  ? AppColors.listBorder(theme)
                  : theme.colorScheme.primary.withOpacity(0.5);

              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Slidable(
                  key: ValueKey('notif_${n.id}'),
                  closeOnScroll: true,
                  endActionPane: ActionPane(
                    motion: const BehindMotion(),
                    extentRatio: 0.30,
                    children: [
                      SlidableAction(
                        onPressed: (_) {
                          inAppNotificationService.removeById(n.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bildirim silindi'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        icon: Icons.delete,
                        label: 'Sil',
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        inAppNotificationService.markAsRead(n.id);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              n.isRead
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              color: theme.colorScheme.onSurface,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.title,
                                    style: TextStyle(
                                      fontWeight: n.isRead
                                          ? FontWeight.w500
                                          : FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    n.message,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTime(n.createdAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.subtleText(theme),
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
              );
            },
          );
        },
      ),
    );
  }
}


/// ======================= AI CAREER ADVISOR SHEET =======================
class AiCareerAdvisorSheet extends StatefulWidget {
  const AiCareerAdvisorSheet({super.key});

  @override
  State<AiCareerAdvisorSheet> createState() => _AiCareerAdvisorSheetState();
}

class _AiCareerAdvisorSheetState extends State<AiCareerAdvisorSheet> {
  final TextEditingController _controller = TextEditingController();
  final List<_AiMessage> _messages = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _AiMessage(
        fromUser: false,
        text: 'Merhaba, ben TechConnect AI Career Advisor.\n'
            'Bana şunları sorabilirsin:\n'
            '- Hangi pozisyon bana uygun?\n'
            '- CV’mi nasıl iyileştiririm?\n'
            '- Hangi skill’leri öğrenmeliyim?\n'
            '- Bugün hangi şirkete başvurayım?',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String> _callAiBackend(String prompt) async {
    final uri = Uri.parse('https://aicareeradvisor-kb3kwlqefq-ew.a.run.app');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': prompt}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final reply = (data['reply'] ?? '').toString().trim();
        if (reply.isEmpty) {
          return 'AI şu an boş bir cevap döndü. Lütfen tekrar dene.';
        }
        return reply;
      } else {
        return 'Şu anda AI servisine bağlanırken bir hata oluştu. Lütfen daha sonra tekrar dene.';
      }
    } catch (e) {
      return 'Şu anda AI servisine bağlanırken teknik bir hata oluştu.';
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _messages.add(_AiMessage(fromUser: true, text: text));
      _controller.clear();
    });

    try {
      final reply = await _callAiBackend(text);
      if (!mounted) return;
      setState(() {
        _messages.add(_AiMessage(fromUser: false, text: reply));
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.sheetHandle(theme),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'AI Career Advisor',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final m = _messages[index];

                  final align =
                  m.fromUser ? Alignment.centerRight : Alignment.centerLeft;

                  final bubble = m.fromUser
                      ? AppBubbleStyle.user(theme)
                      : AppBubbleStyle.ai(theme);

                  return Align(
                    alignment: align,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: bubble.decoration,
                      child: Text(
                        m.text,
                        style: TextStyle(color: bubble.textColor),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Kariyerinle ilgili bir soru yaz...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiMessage {
  final bool fromUser;
  final String text;

  const _AiMessage({required this.fromUser, required this.text});
}

class _UpFABLocation extends FloatingActionButtonLocation {
  final double offset;
  const _UpFABLocation({this.offset = 60});

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry layout) {
    final original = FloatingActionButtonLocation.endFloat.getOffset(layout);
    return Offset(original.dx, original.dy - offset);
  }
}

/// ======================= TOKENS (SEMANTIC COLORS) =======================
class AppColors {
  static Color brand(ThemeData t) => t.colorScheme.primary;
  static Color onBrand(ThemeData t) => t.colorScheme.onPrimary;

  static Color navSelected(ThemeData t) => t.colorScheme.primary;
  static Color navUnselected(ThemeData t) => t.colorScheme.onSurfaceVariant;

  static Color navSplash(ThemeData t) => t.colorScheme.primary.withOpacity(0.14);
  static Color navHighlight(ThemeData t) =>
      t.colorScheme.primary.withOpacity(0.08);

  static Color badge(ThemeData t) => t.colorScheme.error;
  static Color onBadge(ThemeData t) => t.colorScheme.onError;

  static Color subtleText(ThemeData t) => t.colorScheme.onSurfaceVariant;

  static Color floatingBarBg(ThemeData t) => t.colorScheme.surface.withOpacity(
      t.brightness == Brightness.dark ? 0.92 : 0.96);

  static Color floatingBarBorder(ThemeData t) =>
      t.colorScheme.outlineVariant.withOpacity(
          t.brightness == Brightness.dark ? 0.22 : 0.35);

  static Color floatingBarShadow(ThemeData t) => Colors.black.withOpacity(
      t.brightness == Brightness.dark ? 0.55 : 0.12);

  static Color searchBubbleBg(ThemeData t) =>
      t.colorScheme.surfaceVariant.withOpacity(
          t.brightness == Brightness.dark ? 0.22 : 0.75);

  static Color searchBubbleBorder(ThemeData t) =>
      t.colorScheme.outlineVariant.withOpacity(
          t.brightness == Brightness.dark ? 0.35 : 0.55);

  static Color searchBubbleIcon(ThemeData t) => t.colorScheme.onSurfaceVariant;
  static Color searchBubbleText(ThemeData t) => t.colorScheme.onSurfaceVariant;

  static Color aiGlow(ThemeData t) =>
      (t.brightness == Brightness.dark
          ? t.colorScheme.secondary
          : t.colorScheme.primary)
          .withOpacity(0.55);

  static Color premiumIcon(ThemeData t) => (t.brightness == Brightness.dark
      ? t.colorScheme.tertiary
      : t.colorScheme.primary);

  static Color sheetHandle(ThemeData t) =>
      t.colorScheme.onSurfaceVariant.withOpacity(0.35);

  static Color cardBg(ThemeData t) => t.colorScheme.surface;
  static Color cardBorder(ThemeData t) =>
      t.colorScheme.outlineVariant.withOpacity(0.35);

  static Color chipBg(ThemeData t) => t.colorScheme.surfaceVariant.withOpacity(
      t.brightness == Brightness.dark ? 0.18 : 0.65);

  static Color logoBoxBg(ThemeData t) =>
      t.colorScheme.surfaceVariant.withOpacity(
          t.brightness == Brightness.dark ? 0.18 : 0.65);

  static Color fallbackAvatarBg(ThemeData t) =>
      t.colorScheme.primary.withOpacity(0.35);
  static Color onFallbackAvatar(ThemeData t) => t.colorScheme.onPrimary;

  static Color listBorder(ThemeData t) =>
      t.colorScheme.outlineVariant.withOpacity(0.45);

  static Color success(ThemeData t) => (t.brightness == Brightness.dark
      ? t.colorScheme.tertiary
      : t.colorScheme.secondary);
}

class AppGradients {
  static LinearGradient aiUserBubble(ThemeData t) => LinearGradient(
    colors: [
      t.colorScheme.primary.withOpacity(0.95),
      t.colorScheme.secondary.withOpacity(0.90),
      t.colorScheme.tertiary.withOpacity(0.85),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppBubbleStyle {
  final BoxDecoration decoration;
  final Color textColor;

  const AppBubbleStyle({
    required this.decoration,
    required this.textColor,
  });

  static AppBubbleStyle user(ThemeData t) => AppBubbleStyle(
    decoration: BoxDecoration(
      gradient: AppGradients.aiUserBubble(t),
      borderRadius: BorderRadius.circular(12),
    ),
    textColor: t.colorScheme.onPrimary,
  );

  static AppBubbleStyle ai(ThemeData t) => AppBubbleStyle(
    decoration: BoxDecoration(
      color: t.colorScheme.surfaceVariant
          .withOpacity(t.brightness == Brightness.dark ? 0.25 : 0.8),
      borderRadius: BorderRadius.circular(12),
    ),
    textColor: t.colorScheme.onSurface,
  );
}
