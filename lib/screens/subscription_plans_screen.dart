import 'package:flutter/material.dart';
import '../screens/demo_payment_screen.dart'; // ✅ kendi dosya yoluna göre düzelt

class SubscriptionPlansScreen extends StatelessWidget {
  const SubscriptionPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Üyelik Planları'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'TechConnect Premium',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Profilinin daha fazla kişi tarafından görülmesini, '
                'profilini kimlerin görüntülediğini takip etmeyi ve '
                'işe alım süreçlerinde öne çıkmanı sağlayan ek avantajlar.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 24),

          // ✅ AYLIK
          _buildPlanCard(
            context,
            planId: 'premium_monthly',
            title: 'Aylık Premium',
            price: '₺59,90 / ay',
            features: const [
              'Profilini kimlerin görüntülediğini gör',
              'Daha yüksek profil görüntülenme oranı',
              'Öne çıkarılmış profil rozeti',
              'Daha fazla mesaj hakkı',
            ],
            isRecommended: true,
          ),
          const SizedBox(height: 16),

          // ✅ YILLIK
          _buildPlanCard(
            context,
            planId: 'premium_yearly',
            title: 'Yıllık Premium',
            price: '₺499,90 / yıl',
            features: const [
              'Tüm Premium özellikler',
              'Daha yüksek profil görüntülenme oranı',
              'Yaklaşık %30 daha avantajlı',
              'Öne çıkarılmış profil rozeti',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(
      BuildContext context, {
        required String planId,
        required String title,
        required String price,
        required List<String> features,
        bool isRecommended = false,
      }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isRecommended
            ? BorderSide(
          color: theme.colorScheme.primary,
          width: 1.4,
        )
            : BorderSide.none,
      ),
      elevation: isDark ? 0 : 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isRecommended)
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Önerilen',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (isRecommended) const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...features.map(
                  (f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  // ✅ Demo ödeme ekranına planId ile git
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DemoPaymentScreen(
                        planId: planId,
                        planTitle: title,
                        planPrice: price,
                      ),
                    ),
                  );
                },
                child: const Text('Bu Planı Seç'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
