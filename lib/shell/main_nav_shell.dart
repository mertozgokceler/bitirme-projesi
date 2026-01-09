// lib/shell/main_nav_shell.dart

import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../in_app_notification.dart';

// tabs
import '../tabs/home_tab.dart';
import '../tabs/jobs_tab.dart';
import '../tabs/add_post_tab.dart';
import '../tabs/notification_tab.dart';
import '../tabs/profile_tab.dart';

// screens
import '../screens/chat_list_screen.dart';
import '../screens/create_post_screen.dart';
import '../screens/create_job_post_screen.dart';
import '../screens/subscription_plans_screen.dart';
import '../screens/chat_detail_screen.dart';

// separated widgets/sheets/screens
import '../tabs/search_tab.dart';
import '../widgets/ai_career_advisor_sheet.dart';

// location
import '../services/location_service.dart';
import '../widgets/city_picker_sheet.dart';

// calls
import '../services/call_service.dart';
import '../services/incoming_call_service.dart';
import '../screens/incoming_call_screen.dart';

// theme tokens
import '../theme/app_colors.dart';

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

  final _auth = FirebaseAuth.instance;

  int _index = 0;
  bool _showBars = true;

  // account
  bool _isCompany = false;

  // premium
  bool _isPremium = false;
  bool _premiumLoaded = false;
  bool _premiumPopupChecked = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumSub;

  // notifications listeners
  StreamSubscription<QuerySnapshot>? _chatSub;
  StreamSubscription<QuerySnapshot>? _connReqSub;

  bool _chatsWarmupDone = false;
  final Map<String, Timestamp?> _lastSeenChatTs = {};
  bool _incomingReqInitialized = false;
  final Map<String, String> _senderNameCache = {};

  // ai pulse
  late final AnimationController _aiPulseController;

  // auth changes
  StreamSubscription<User?>? _authSub;

  // ✅ artık const değil
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _callService = CallService();
    _incomingCallService = IncomingCallService();

    inAppNotificationService.loadFromPrefs();
    _initNotificationsForCurrentUser();

    // ✅ NOTIFICATION TAP ROUTER (tek yer)
    inAppNotificationService.tappedNotification.addListener(_onTappedNotification);

    _aiPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // ✅ HomeTab callback’leri burada bağlandı
    _pages = [
      HomeTab(
        callService: _callService,
        onGoToSearchTab: () {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchTab()),
          );
        },
        onGoToMessages: () {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ChatListScreen(callService: _callService)),
          );
        },
      ),
      const JobsTab(),
      const AddPostTab(),
      const NotificationsTab(),
      const ProfileTab(),
    ];

    _loadAccountType();
    _listenPremiumStatus();

    _listenIncomingMessages();
    _listenIncomingConnectionRequests();

    // ✅ foreground incoming call yakala
    _startIncomingCallServiceListener();

    // ✅ login/logout olunca listener tazele
    _authSub = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _incomingCallService.stop();
        return;
      }
      _startIncomingCallServiceListener();

      _chatsWarmupDone = false;
      _lastSeenChatTs.clear();
      _incomingReqInitialized = false;
      _senderNameCache.clear();

      _initNotificationsForCurrentUser();
      _loadAccountType();
      _listenPremiumStatus();
      _listenIncomingMessages();
      _listenIncomingConnectionRequests();
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _connReqSub?.cancel();
    _authSub?.cancel();
    _premiumSub?.cancel();

    inAppNotificationService.tappedNotification.removeListener(_onTappedNotification);

    _incomingCallService.dispose();
    _aiPulseController.dispose();

    super.dispose();
  }

  Future<void> _initNotificationsForCurrentUser() async {
    final user = _auth.currentUser;
    await inAppNotificationService.initForUser(user?.uid);
  }

  void _onTappedNotification() {
    final n = inAppNotificationService.tappedNotification.value;
    if (n == null) return;

    // consume first (double-trigger engelle)
    inAppNotificationService.tappedNotification.value = null;

    if (!mounted) return;

    // okundu
    inAppNotificationService.markAsRead(n.id);

    final type = n.type.trim().toLowerCase();
    final data = n.data;

    switch (type) {
      case 'message':
        {
          final chatId = (data['chatId'] ?? '').toString();
          final otherUserId =
          (data['peerId'] ?? data['senderId'] ?? data['otherUserId'] ?? '').toString();
          final otherUserName =
          (data['peerName'] ?? data['senderName'] ?? n.title).toString();
          final otherUserPhoto =
          (data['peerPhotoUrl'] ?? data['senderPhotoUrl'] ?? '').toString();

          if (chatId.isEmpty || otherUserId.isEmpty) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ChatListScreen(callService: _callService)),
            );
            break;
          }

          final otherUser = <String, dynamic>{
            'id': otherUserId,
            'uid': otherUserId,
            'userId': otherUserId,
            'name': otherUserName,
            'username': otherUserName.startsWith('@')
                ? otherUserName.substring(1)
                : otherUserName,
            'photoUrl': otherUserPhoto,
            'profilePhotoUrl': otherUserPhoto,
          };

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatDetailScreen(
                chatId: chatId,
                otherUser: otherUser,
                callService: _callService,
              ),
            ),
          );
          break;
        }

      case 'match':
        setState(() => _index = 1);
        break;

      case 'follow':
        setState(() => _index = 4);
        break;

      case 'like':
      case 'comment':
        setState(() => _index = 0);
        break;

      default:
        setState(() => _index = 3);
        break;
    }

    debugPrint('DEBUG[notifTap] type=$type data=$data');
  }

  // ===================== LOCATION =====================

  Future<void> _handleLocationAction() async {
    if (!mounted) return;

    try {
      await LocationService.requestAndSaveLiveLocation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum güncellendi (GPS).')),
      );
    } catch (_) {
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

  // ===================== ACCOUNT TYPE =====================

  Future<void> _loadAccountType() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

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

      if (!mounted) return;
      setState(() => _isCompany = flagIsCompany);
    } catch (e) {
      debugPrint('DEBUG[accountType] hata: $e');
    }
  }

  // ===================== PREMIUM =====================

  bool _computeIsPremiumFromUser(Map<String, dynamic> data) {
    final isPremiumFlag = data['isPremium'] == true;

    final until = data['premiumUntil'];
    DateTime? untilDt;
    if (until is Timestamp) untilDt = until.toDate();

    final now = DateTime.now();
    final validByDate = untilDt != null && untilDt.isAfter(now);

    if (untilDt != null) return validByDate;
    return isPremiumFlag;
  }

  void _listenPremiumStatus() {
    final user = _auth.currentUser;
    if (user == null) return;

    _premiumSub?.cancel();
    _premiumLoaded = false;
    _premiumPopupChecked = false;

    _premiumSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) async {
      final data = snap.data() ?? {};
      final p = _computeIsPremiumFromUser(data);

      if (!mounted) return;
      setState(() {
        _isPremium = p;
        _premiumLoaded = true;
      });

      if (!_premiumPopupChecked) {
        _premiumPopupChecked = true;
        if (!_isPremium) {
          await _showPremiumPopupIfNeeded();
        }
      }
    }, onError: (e) {
      debugPrint('DEBUG[premium] listen error: $e');
      if (!mounted) return;
      setState(() {
        _isPremium = false;
        _premiumLoaded = true;
      });

      if (!_premiumPopupChecked) {
        _premiumPopupChecked = true;
        _showPremiumPopupIfNeeded();
      }
    });
  }

  Future<void> _showPremiumPopupIfNeeded() async {
    if (!_premiumLoaded) return;
    if (_isPremium) return;

    final prefs = await SharedPreferences.getInstance();
    final hide = prefs.getBool('hidePremiumPopup') ?? false;
    if (hide) return;
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
          builder: (context, setStateSB) {
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
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
                    onChanged: (val) => setStateSB(() => dontShowAgain = val ?? false),
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
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Sonra'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (dontShowAgain) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('hidePremiumPopup', true);
                    }
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                    if (!mounted) return;
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

  // ===================== HELPERS =====================

  void _setBarsVisible(bool visible) {
    if (_showBars == visible) return;
    if (!mounted) return;
    setState(() => _showBars = visible);
  }

  Future<String> _getSenderDisplayName(String uid) async {
    final cached = _senderNameCache[uid];
    if (cached != null) return cached;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

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

  // ===================== CALL (FOREGROUND) =====================

  void _startIncomingCallServiceListener() {
    _incomingCallService.start(
      onIncoming: (call) async {
        if (!mounted) return;

        try {
          await Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => IncomingCallScreen(
                call: call,
                callService: _callService,
                onDone: () => _incomingCallService.markUiClosed(),
              ),
            ),
          );
        } catch (e) {
          debugPrint('DEBUG[call] incoming push error: $e');
        } finally {
          _incomingCallService.markUiClosed();
        }
      },
      onError: (e, st) {
        debugPrint('DEBUG[call] incomingCallService error: $e');
        _incomingCallService.markUiClosed();
      },
    );
  }

  // ===================== IN-APP NOTIFICATIONS =====================

  void _listenIncomingMessages() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _chatSub?.cancel();

    _chatSub = FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: currentUser.uid)
        .snapshots()
        .listen((snapshot) async {
      if (!_chatsWarmupDone) {
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final ts = data['lastMessageTimestamp'] as Timestamp?;
          if (ts != null) _lastSeenChatTs[doc.id] = ts;
        }
        _chatsWarmupDone = true;
        return;
      }

      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added &&
            change.type != DocumentChangeType.modified) continue;

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
          if (oldTs != null && !ts.toDate().isAfter(oldTs.toDate())) continue;
          _lastSeenChatTs[chatId] = ts;
        }

        if (!mounted) return;
        final displayName = await _getSenderDisplayName(senderId);

        inAppNotificationService.show(
          displayName,
          lastMessage,
          context: context,
          type: 'message',
          data: {
            'chatId': chatId,
            'peerId': senderId,
            'peerName': displayName,
          },
        );
      }
    }, onError: (e) {
      debugPrint('DEBUG[inapp] chat listener error: $e');
    });
  }

  void _listenIncomingConnectionRequests() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _connReqSub?.cancel();

    _connReqSub = FirebaseFirestore.instance
        .collection('connectionRequests')
        .doc(currentUser.uid)
        .collection('incoming')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) async {
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

        if (!mounted) return;
        final displayName = await _getSenderDisplayName(fromId);

        inAppNotificationService.show(
          'Yeni bağlantı isteği',
          '$displayName sana bağlantı isteği gönderdi.',
          context: context,
          type: 'follow',
          data: {'userId': fromId},
        );
      }
    }, onError: (e) {
      debugPrint('DEBUG[inapp] connReq listener error: $e');
    });
  }

  // ===================== UI =====================

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
    final border =
    theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.30 : 0.55);
    final hint =
    theme.colorScheme.onSurfaceVariant.withOpacity(isDark ? 0.55 : 0.65);

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
    // ✅ Home kendi header'ını çiziyor → AppBar KAPALI
    if (_index == 0) return null;

    if (_index == 2) return null;

    if (_index == 3 || _index == 4) {
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      );
    }

    if (_index == 1) {
      return AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _buildSearchBubble(
            context,
            rightInside: InkResponse(
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
      );
    }

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      leadingWidth: 64,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
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
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: Image.asset(
              'assets/icons/send_light.png',
              width: 32,
              height: 32,
            ),
            tooltip: 'Sohbetler',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ChatListScreen(callService: _callService)),
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
      extendBodyBehindAppBar: true,
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

          final atBottom = metrics.pixels >= (metrics.maxScrollExtent - 16);
          _setBarsVisible(!atBottom);
          return false;
        },
        child: Stack(
          children: [
            IndexedStack(index: _index, children: _pages),
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
    final isSelected = _index == i;
    final color =
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
    final isSelected = _index == index;

    final color =
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

class _UpFABLocation extends FloatingActionButtonLocation {
  final double offset;
  const _UpFABLocation({this.offset = 60});

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry layout) {
    final original = FloatingActionButtonLocation.endFloat.getOffset(layout);
    return Offset(original.dx, original.dy - offset);
  }
}
