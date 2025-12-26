// lib/screens/news_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class NewsDetailScreen extends StatelessWidget {
  final Map<String, dynamic> article;

  const NewsDetailScreen({
    super.key,
    required this.article,
  });

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) debugPrint('URL açılamadı: $url');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ui = NewsDetailUI.of(t);

    final String title = article['title']?.toString() ?? 'Başlıksız haber';

    final String? imageUrl = (article['image'] ?? article['urlToImage']) as String?;

    String source = 'Haber';
    final rawSource = article['source'];
    if (rawSource is Map) {
      source = rawSource['name']?.toString() ?? 'Haber';
    } else if (rawSource is String) {
      source = rawSource;
    }

    final String? description = article['description']?.toString();

    final String? rawContent = article['content']?.toString();
    String? content;
    if (rawContent != null && rawContent.isNotEmpty) {
      final bracketIndex = rawContent.indexOf('[');
      content = bracketIndex != -1
          ? rawContent.substring(0, bracketIndex).trim()
          : rawContent.trim();
    }

    final String? url = article['url']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(source),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: ui.imageFallbackBg,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image_outlined, color: ui.mutedText),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ui.primaryText,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    source,
                    style: t.textTheme.labelMedium?.copyWith(
                      color: ui.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (description != null && description.trim().isNotEmpty) ...[
                    Text(
                      description.trim(),
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: ui.primaryText,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (content != null && content.trim().isNotEmpty) ...[
                    Text(
                      content.trim(),
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: ui.secondaryText,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (url != null && url.trim().isNotEmpty) ...[
                    Divider(color: ui.divider),
                    const SizedBox(height: 8),

                    Text(
                      'Kaynak linki:',
                      style: t.textTheme.labelMedium?.copyWith(
                        color: ui.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),

                    InkWell(
                      onTap: () => _openUrl(url.trim()),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          url.trim(),
                          style: t.textTheme.bodySmall?.copyWith(
                            color: ui.link,
                            decoration: TextDecoration.underline,
                            decorationColor: ui.link,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      'Bağlantıya dokunarak haberi tarayıcıda açabilirsin.',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: ui.hintText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===========================================================
/// ✅ Tek yerden UI kararları (News Detail)
/// ===========================================================
class NewsDetailUI {
  final Color primaryText;
  final Color secondaryText;
  final Color mutedText;
  final Color hintText;
  final Color link;
  final Color divider;
  final Color imageFallbackBg;

  NewsDetailUI._({
    required this.primaryText,
    required this.secondaryText,
    required this.mutedText,
    required this.hintText,
    required this.link,
    required this.divider,
    required this.imageFallbackBg,
  });

  static NewsDetailUI of(ThemeData t) {
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final primary = t.textTheme.bodyLarge?.color ?? (isDark ? Colors.white : Colors.black87);
    final secondary = t.textTheme.bodyMedium?.color ?? (isDark ? Colors.white70 : Colors.black54);

    // Brand pembe (aynı interaction rengi)
    const brand = Color(0xFFE57AFF);

    return NewsDetailUI._(
      primaryText: primary,
      secondaryText: secondary,
      mutedText: secondary.withOpacity(0.85),
      hintText: secondary.withOpacity(isDark ? 0.75 : 0.80),
      link: cs.primary == brand ? cs.primary : brand, // primary farklıysa bile brand link kullan
      divider: isDark ? Colors.white12 : Colors.black12,
      imageFallbackBg: isDark ? const Color(0xFF1A1C22) : const Color(0xFFF2F3F5),
    );
  }
}
