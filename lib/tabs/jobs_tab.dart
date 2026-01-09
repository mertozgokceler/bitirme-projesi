// lib/tabs/jobs_tab.dart
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/job_apply_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/job_details_sheet.dart';

class JobsTab extends StatelessWidget {
  const JobsTab({super.key});

  // ✅ workModel -> UI
  static String prettyWorkType(String raw) {
    final v = raw.toLowerCase().trim();

    if (v.isEmpty) return 'İş yerinde';
    if (v == 'remote' || v == 'uzaktan') return 'Uzaktan';
    if (v == 'hybrid' || v == 'hibrit') return 'Hibrit';
    if (v == 'onsite' ||
        v == 'on-site' ||
        v == 'iş yerinde' ||
        v == 'office') {
      return 'İş yerinde';
    }
    return raw;
  }

  static String _fmtDate(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year;
    return '$dd.$mm.$yy';
  }

  Future<void> _refresh() async {
    await FirebaseFirestore.instance
        .collection('jobs')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get(const GetOptions(source: Source.server));
  }

  void _openJobDetailsSheet(BuildContext context, String jobId, Map<String, dynamic> job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JobDetailsSheet(jobId: jobId, job: job),
    );
  }


  // ---- Premium background helpers ----
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
    final cs = theme.colorScheme;

    return Stack(
      children: [
        // Background
        Container(decoration: BoxDecoration(gradient: _bgGradient(context))),
        Positioned(
          top: -120,
          left: -80,
          child: _GlowBlob(size: 260, color: cs.primary.withOpacity(0.20)),
        ),
        Positioned(
          bottom: -140,
          right: -90,
          child: _GlowBlob(size: 280, color: cs.tertiary.withOpacity(0.18)),
        ),

        // ✅ FIX: İçeriği SafeArea içine al
        SafeArea(
          top: true,
          bottom: false,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  child: Text(
                    'İlanlar yüklenirken hata oluştu:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('Henüz yayınlanmış iş ilanı yok.'));
              }

              // ✅ Overflow fix: kartları biraz daha uzun yap.
              const spacing = 10.0;
              const aspect = 0.82;

              return RefreshIndicator(
                onRefresh: _refresh,
                edgeOffset: 12,
                child: GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    12 + MediaQuery.of(context).padding.bottom + 120, // ✅ navbar + safe area payı
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: aspect,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();

                    final title = (data['title'] ?? '').toString().trim();
                    final companyName =
                    (data['companyName'] ?? '').toString().trim();
                    final location = (data['location'] ?? '').toString().trim();
                    final workModel =
                    (data['workModel'] ?? '').toString().trim();

                    final logoUrl =
                    (data['companyLogoUrl'] ?? '').toString().trim();
                    final companyId =
                    (data['companyId'] ?? '').toString().trim();

                    final displayTitle =
                    title.isEmpty ? '(Pozisyon adı yok)' : title;
                    final displayCompany = companyName.isEmpty
                        ? 'Şirket adı belirtilmemiş'
                        : companyName;
                    final displayLocation = location.isEmpty
                        ? 'Konum belirtilmemiş'
                        : location;

                    // Logo: önce job içindeki companyLogoUrl, boşsa users/{id}.photoUrl
                    Widget logoWidget;
                    if (companyId.isEmpty) {
                      logoWidget = _CompanyLogoBox(
                        logoUrl: logoUrl,
                        fallbackText: displayCompany,
                      );
                    } else {
                      logoWidget =
                          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .doc(companyId)
                                .get(),
                            builder: (context, snap) {
                              String finalLogo = logoUrl;
                              if (snap.hasData && snap.data!.exists) {
                                final u = snap.data!.data()!;
                                final userLogo =
                                (u['photoUrl'] ?? '').toString().trim();
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

                    return _JobGridCard(
                      theme: theme,
                      title: displayTitle,
                      company: displayCompany,
                      location: displayLocation,
                      workModel: workModel,
                      logo: logoWidget,
                      onTap: () => _openJobDetailsSheet(context, doc.id, data),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _JobGridCard extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final String company;
  final String location;
  final String workModel;
  final Widget logo;
  final VoidCallback onTap;

  const _JobGridCard({
    required this.theme,
    required this.title,
    required this.company,
    required this.location,
    required this.workModel,
    required this.logo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    final fill = isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.white.withOpacity(0.72);
    final border =
    isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 0.9),
            boxShadow: [
              BoxShadow(
                blurRadius: 22,
                spreadRadius: 3,
                color: Colors.black.withOpacity(isDark ? 0.22 : 0.10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  logo,
                  const Spacer(),
                  _ActiveBadge(theme: theme),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      company,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.subtleText(theme),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.subtleText(theme),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$location • ${JobsTab.prettyWorkType(workModel)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.subtleText(theme),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 24,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: const [
                    _MiniTag(icon: Icons.flash_on, label: 'Kolay'),
                    SizedBox(width: 6),
                    _MiniTag(icon: Icons.fiber_new, label: 'Yeni'),
                    SizedBox(width: 6),
                    _MiniTag(icon: Icons.visibility, label: 'Görüntü'),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Container(
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withOpacity(0.55),
                      cs.tertiary.withOpacity(0.30),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  final ThemeData theme;
  const _ActiveBadge({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant
            .withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: AppColors.success(theme)),
          const SizedBox(width: 5),
          Text(
            'Aktif',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant
            .withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyLogoBox extends StatelessWidget {
  final String logoUrl;
  final String fallbackText;
  final double size;

  const _CompanyLogoBox({
    required this.logoUrl,
    required this.fallbackText,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant
            .withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.14)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl.isNotEmpty
          ? Image.network(
        logoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            _buildLogoFallback(context, fallbackText),
      )
          : _buildLogoFallback(context, fallbackText),
    );
  }
}

Widget _buildLogoFallback(BuildContext context, String companyName) {
  final theme = Theme.of(context);
  final initial =
  companyName.isNotEmpty ? companyName.characters.first.toUpperCase() : '?';

  return Container(
    color: theme.colorScheme.primary.withOpacity(0.35),
    child: Center(
      child: Text(
        initial,
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    ),
  );
}

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
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}
