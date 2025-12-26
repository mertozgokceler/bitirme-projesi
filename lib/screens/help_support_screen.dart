import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  // Konum
  static const double _lat = 41.549537;
  static const double _lng = 32.291844;

  static const String _email = 'techconnect7430@gmail.com';
  static const String _phone = '0552 281 71 89';
  static const String _addressLine =
      'Yeni, 74110 Kutlubeyyazıcılar/Bartın Merkez/Bartın';

  Future<void> _openMap() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$_lat,$_lng',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callPhone() async {
    final uri = Uri.parse('tel:$_phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendMail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _email,
      query: 'subject=TechConnect%20Destek',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final officeLatLng = LatLng(_lat, _lng);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yardım ve Destek'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- KONUM / MAP ---
            Text(
              'Konumumuz',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    // ⚡ GERÇEK GOOGLE MAPS WIDGET’I
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: officeLatLng,
                        zoom: 15,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('office'),
                          position: officeLatLng,
                          infoWindow: const InfoWindow(title: 'TechConnect Ofis'),
                        ),
                      },
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                    ),


                    // Üstte chip
                    Positioned(
                      left: 16,
                      top: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.location_on,
                                color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'TechConnect Ofis',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: ElevatedButton.icon(
                        onPressed: _openMap,
                        icon: const Icon(Icons.directions),
                        label: const Text('Haritalarda Aç'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // --- İLETİŞİM ---
            Text(
              'İletişim',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone),
                    title: const Text('Telefon'),
                    subtitle: const Text(_phone),
                    onTap: _callPhone,
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('E-posta'),
                    subtitle: const Text(_email),
                    onTap: _sendMail,
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('Adres'),
                    subtitle: Text(_addressLine),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Text(
              'Çalışma saatlerimiz: Hafta içi 09.00 – 18.00\n'
                  'Mesajlarınıza en kısa sürede dönüş yapmaya çalışıyoruz.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
