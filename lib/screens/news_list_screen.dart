// lib/screens/news_list_screen.dart

import 'package:flutter/material.dart';
import 'news_detail_screen.dart';

class NewsListScreen extends StatelessWidget {
  final List<dynamic> articles;
  final bool isLoading;

  const NewsListScreen({
    super.key,
    required this.articles,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    // API doluysa onu, boşsa fallback veriyi kullan
    final List<dynamic> data =
    (articles.isNotEmpty) ? articles : _fallbackNews;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final sourceColor =
    isDark ? Colors.blue.shade200 : Colors.blue; // Ensonhaber yazısı
    final titleColor = isDark ? Colors.white : Colors.black87;
    final descColor = isDark ? Colors.white70 : Colors.black87;
    final cardColor = isDark ? const Color(0xFF181820) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gündem'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: data.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final Map<String, dynamic> article =
          data[index] as Map<String, dynamic>;

          // ----- BAŞLIK -----
          final String title =
              article['title']?.toString() ?? 'Başlıksız haber';

          // ----- GÖRSEL -----
          // GNews: "image"  | Eski NewsAPI: "urlToImage"
          final String? imageUrl =
          (article['image'] ?? article['urlToImage']) as String?;

          // ----- KAYNAK (source) -----
          String source = 'Haber';
          final dynamic rawSource = article['source'];

          if (rawSource is Map) {
            // API'den gelen yapı
            source = rawSource['name']?.toString() ?? 'Haber';
          } else if (rawSource is String) {
            // Fallback listede direkt String
            source = rawSource;
          }

          // ----- AÇIKLAMA -----
          final String? description =
          article['description'] as String?;

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      NewsDetailScreen(article: article),
                ),
              );
            },
            child: Card(
              color: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imageUrl,
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (imageUrl != null) const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            source,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: sourceColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                            ),
                          ),
                          if (description != null &&
                              description.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: 13,
                                color: descColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// API boşsa kullanılacak örnek veri listesi
  List<Map<String, dynamic>> get _fallbackNews => [
    {
      'title': 'Flutter 4.0 Duyuruldu: Yenilikler Neler?',
      'source': 'Flutter Dev Blog',
      'description':
      'Yeni sürümle gelen performans iyileştirmeleri ve çoklu platform desteği detaylandırıldı.',
      'image': null,
    },
    {
      'title': 'Yapay Zeka Etik Kuralları Gündemde',
      'source': 'TechCrunch',
      'description':
      'Şirketler, yapay zeka modellerinin etik kullanımına yönelik yeni standartlar üzerinde çalışıyor.',
      'image': null,
    },
    {
      'title': 'Yeni Nesil Veritabanı Teknolojileri',
      'source': 'InfoWorld',
      'description':
      'Dağıtık veritabanı sistemleri ve bulut tabanlı çözümler yazılım dünyasını dönüştürüyor.',
      'image': null,
    },
  ];
}
