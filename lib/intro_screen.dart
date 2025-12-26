import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pc = PageController();
  int _index = 0;

  final _items = const [
    _IntroItem(
      title: 'TechConnect’e Hoş Geldin',
      subtitle:
      'Yazılım dünyasının kalbine adım at. Kendi profilini oluştur, topluluğuna bağlan ve sana özel iş fırsatlarıyla kariyer yolculuğuna güçlü bir başlangıç yap.',
      image: 'assets/images/welcomeing.svg',
    ),
    _IntroItem(
      title: 'Profilini Güçlendir',
      subtitle: 'Rozetler, portföy ve beceri etiketleriyle öne çık.',
      image: 'assets/images/profile_rozet.svg',
    ),
    _IntroItem(
      title: 'AI Destekli Eşleşmeler',
      subtitle:
      'Yeteneklerin ve ilgi alanlarına göre sana uygun şirketler ve projelerle eşleş.',
      image: 'assets/images/ai_match.svg',
    ),
    _IntroItem(
      title: 'Güvenli İletişim',
      subtitle:
      'Gerçek zamanlı mesajlaşma ve sesli arama ile şirketlerle kolayca iletişim kur.',
      image: 'assets/images/video_call.svg',
    ),
    _IntroItem(
      title: 'Toplulukta Yerini Al',
      subtitle: 'Teknoloji forumları ve paylaşımlar ile kendini geliştir.',
      image: 'assets/images/community.svg',
    ),
    _IntroItem(
      title: 'Hemen Başla',
      subtitle: 'Dakikalar içinde hesabını oluştur ve keşfe çık.',
      image: 'assets/images/getting_started.svg',
    ),
  ];

  Future<void> _dontShowAgain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_dont_show', true);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/auth');
  }

  void _next() {
    if (_index < _items.length - 1) {
      _pc.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.pushReplacementNamed(context, '/auth');
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  // Arka plan gradient: aynı “brand vibe”, ama tema ile uyumlu.
  List<Color> _bgGradient(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isDark) {
      // Koyu: daha derin, göz yakmayan
      return [
        const Color(0xFF090979),
        cs.primary.withOpacity(0.85),
        cs.secondary.withOpacity(0.75),
      ];
    }

    // Açık: daha yumuşak
    return [
      cs.primary.withOpacity(0.92),
      cs.secondary.withOpacity(0.78),
      cs.primary.withOpacity(0.55),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // “Glass” kart için okunabilirlik: gradient üstünde açık yazı mantıklı.
    final onSplash = cs.onPrimary; // genelde açık ton verir
    final onSplashSoft = onSplash.withOpacity(0.75);
    final onSplashMid = onSplash.withOpacity(0.55);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight;
          final w = c.maxWidth;

          final indicatorBottom = h < 700 ? 72.0 : 96.0;

          double cardH = h * 0.52;
          if (cardH > 420) cardH = 420;
          if (cardH < 320) cardH = 320;

          final cardMaxW = w < 380 ? w - 32 : (w < 820 ? w - 80 : 720);

          double imgH = cardH * 0.35;
          if (imgH > 180) imgH = 180;
          if (imgH < 120) imgH = 120;

          final topGap = h < 700 ? 12.0 : 24.0;

          // Kart rengi: hardcode yok. Glass hissi sürsün.
          final cardFill = (isDark ? Colors.white : Colors.black).withOpacity(0.12);
          final cardBorder = (isDark ? Colors.white : Colors.black).withOpacity(0.18);
          final shadowColor = Colors.black.withOpacity(isDark ? 0.28 : 0.18);

          // “Bir daha gösterme” butonu: sabit blueGrey yerine tema üzerinden.
          final dontShowBg = cs.surface.withOpacity(isDark ? 0.22 : 0.18);
          final dontShowBorder = cs.outline.withOpacity(0.7);

          // FAB arka plan: saf siyah yerine tema primary (premium görünür, uyumlu olur)
          final fabBg = cs.primary;

          return Stack(
            children: [
              // Arka plan
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _bgGradient(context),
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    SizedBox(height: topGap),
                    Expanded(
                      child: PageView.builder(
                        controller: _pc,
                        itemCount: _items.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (_, i) => Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: cardMaxW.toDouble()),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                              child: SizedBox(
                                height: cardH,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: cardFill,
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: cardBorder),
                                    boxShadow: [
                                      BoxShadow(
                                        blurRadius: 28,
                                        color: shadowColor,
                                        offset: const Offset(0, 14),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      h < 700 ? 24 : 36,
                                      h < 700 ? 36 : 56,
                                      h < 700 ? 24 : 36,
                                      h < 700 ? 28 : 48,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.max,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: [
                                        // Görsel / ikon
                                        if (_items[i].image != null)
                                          (_items[i].image!.toLowerCase().endsWith('.svg'))
                                              ? SvgPicture.asset(
                                            _items[i].image!,
                                            height: h < 700 ? imgH * 0.85 : imgH,
                                            fit: BoxFit.contain,
                                          )
                                              : Image.asset(
                                            _items[i].image!,
                                            height: h < 700 ? imgH * 0.85 : imgH,
                                            fit: BoxFit.contain,
                                          )
                                        else
                                          Icon(
                                            Icons.auto_awesome,
                                            size: (h < 700 ? imgH * 0.4 : imgH * 0.5),
                                            color: onSplash.withOpacity(0.95),
                                          ),

                                        const SizedBox(height: 16),

                                        // Başlık
                                        Text(
                                          _items[i].title,
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                            color: onSplash,
                                            fontWeight: FontWeight.w800,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),

                                        const SizedBox(height: 12),

                                        // Alt yazı: tam boy + kaydırılabilir
                                        Expanded(
                                          child: SingleChildScrollView(
                                            physics: const BouncingScrollPhysics(),
                                            child: Text(
                                              _items[i].subtitle,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                color: onSplashSoft,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Sayfa göstergeleri
                    Padding(
                      padding: EdgeInsets.only(bottom: indicatorBottom, top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_items.length, (i) {
                          final active = i == _index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            height: 10,
                            width: active ? 28 : 10,
                            decoration: BoxDecoration(
                              color: active ? onSplash : onSplashMid,
                              borderRadius: BorderRadius.circular(14),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),

              // Sol alttaki buton
              Positioned(
                left: 20,
                bottom: 24,
                child: OutlinedButton.icon(
                  onPressed: _dontShowAgain,
                  icon: Icon(Icons.visibility_off, size: 18, color: onSplash),
                  label: Text('Bir daha gösterme', style: TextStyle(color: onSplash)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: dontShowBorder),
                    backgroundColor: dontShowBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),

              // Sağ alttaki Next FAB
              Positioned(
                right: 20,
                bottom: 24,
                child: FloatingActionButton(
                  onPressed: _next,
                  backgroundColor: fabBg,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: Icon(
                    _index < _items.length - 1 ? Icons.chevron_right : Icons.check,
                    color: cs.onPrimary,
                    size: 28,
                    weight: 900,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IntroItem {
  final String title;
  final String subtitle;
  final String? image;
  const _IntroItem({required this.title, required this.subtitle, this.image});
}
