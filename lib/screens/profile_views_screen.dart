import 'package:flutter/material.dart';

class ProfileViewsScreen extends StatelessWidget {
  const ProfileViewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profilimi Görüntüleyenler')),
      body: const Center(
        child: Text('Buraya profil görüntüleyenler listesi gelecek.'),
      ),
    );
  }
}
