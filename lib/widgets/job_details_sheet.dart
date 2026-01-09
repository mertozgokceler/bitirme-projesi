// lib/widgets/job_details_sheet.dart

import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../screens/job_apply_screen.dart';

class JobDetailsSheet extends StatelessWidget {
  final String jobId;
  final Map<String, dynamic> job;

  const JobDetailsSheet({
    super.key,
    required this.jobId,
    required this.job,
  });

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

  static String fmtDate(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year;
    return '$dd.$mm.$yy';
  }

  Future<Map<String, dynamic>?> _loadCompany(String companyId) async {
    if (companyId.isEmpty) return null;
    final snap =
    await FirebaseFirestore.instance.collection('users').doc(companyId).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  void _goToApply(BuildContext context) {
    Navigator.of(context).pop(); // sheet kapanmadan push yapma -> bug üretir
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobApplyScreen(
          jobId: jobId,
          job: job,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Temel alanlar
    final title = (job['title'] ?? '(Pozisyon adı yok)').toString().trim();
    final companyName =
    (job['companyName'] ?? 'Şirket adı belirtilmemiş').toString().trim();
    final location = (job['location'] ?? 'Konum belirtilmemiş').toString().trim();
    final description = (job['description'] ?? '').toString().trim();
    final workModel = (job['workModel'] ?? '').toString().trim();

    // opsiyonel alanlar
    final level = (job['level'] ?? '').toString().trim();
    final salary = (job['salary'] ?? '').toString().trim();
    final employmentType = (job['employmentType'] ?? '').toString().trim();
    final requirements = (job['requirements'] ?? '').toString().trim();
    final benefits = (job['benefits'] ?? '').toString().trim();
    final techStack = (job['techStack'] ?? '').toString().trim();
    final experienceYears = (job['experienceYears'] ?? '').toString().trim();
    final contactEmail = (job['contactEmail'] ?? '').toString().trim();
    final deadline = fmtDate(job['deadline']);
    final createdAt = fmtDate(job['createdAt']);

    final companyId = (job['companyId'] ?? '').toString().trim();
    final logoUrl = (job['companyLogoUrl'] ?? '').toString().trim();

    Widget infoRow(IconData icon, String text) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.subtleText(theme)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.subtleText(theme),
              ),
            ),
          ),
        ],
      );
    }

    Widget sectionTitle(String t) {
      return Text(
        t,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    Widget sectionBody(String t) {
      return Text(
        t,
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    Widget dividerBlock() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 1.00,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(isDark ? 0.86 : 0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.25),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Stack(
                  children: [
                    // CONTENT
                    ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 104),
                      children: [
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppColors.sheetHandle(theme),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),

                        Text(
                          companyName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.subtleText(theme),
                          ),
                        ),
                        const SizedBox(height: 10),

                        infoRow(
                          Icons.location_on_outlined,
                          '$location • ${prettyWorkType(workModel)}',
                        ),
                        const SizedBox(height: 10),

                        if (employmentType.isNotEmpty)
                          infoRow(Icons.badge_outlined, 'Çalışma tipi: $employmentType'),

                        if (level.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          infoRow(Icons.trending_up, 'Seviye: $level'),
                        ],
                        if (salary.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          infoRow(Icons.payments_outlined, 'Maaş: $salary'),
                        ],
                        if (experienceYears.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          infoRow(Icons.timelapse_outlined, 'Deneyim: $experienceYears'),
                        ],
                        if (createdAt.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          infoRow(Icons.calendar_today_outlined, 'Yayın tarihi: $createdAt'),
                        ],
                        if (deadline.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          infoRow(Icons.event_busy_outlined, 'Son başvuru: $deadline'),
                        ],

                        dividerBlock(),
                        sectionTitle('İlan Açıklaması'),
                        const SizedBox(height: 8),
                        sectionBody(description.isEmpty ? 'Açıklama eklenmemiş.' : description),

                        if (requirements.isNotEmpty) ...[
                          dividerBlock(),
                          sectionTitle('Aranan Nitelikler'),
                          const SizedBox(height: 8),
                          sectionBody(requirements),
                        ],

                        if (techStack.isNotEmpty) ...[
                          dividerBlock(),
                          sectionTitle('Teknolojiler'),
                          const SizedBox(height: 8),
                          sectionBody(techStack),
                        ],

                        if (benefits.isNotEmpty) ...[
                          dividerBlock(),
                          sectionTitle('Yan Haklar / Avantajlar'),
                          const SizedBox(height: 8),
                          sectionBody(benefits),
                        ],

                        if (contactEmail.isNotEmpty) ...[
                          dividerBlock(),
                          sectionTitle('İletişim'),
                          const SizedBox(height: 8),
                          infoRow(Icons.mail_outline, contactEmail),
                        ],

                        if (companyId.isNotEmpty) ...[
                          dividerBlock(),
                          FutureBuilder<Map<String, dynamic>?>(
                            future: _loadCompany(companyId),
                            builder: (context, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final cdata = snap.data;
                              if (cdata == null) {
                                return Text(
                                  'Şirket bilgisi bulunamadı.',
                                  style: TextStyle(
                                    color: AppColors.subtleText(theme),
                                    fontSize: 13,
                                  ),
                                );
                              }

                              final about =
                              (cdata['about'] ?? cdata['bio'] ?? '').toString().trim();
                              final website = (cdata['website'] ?? '').toString().trim();
                              final photo = (cdata['photoUrl'] ?? '').toString().trim();
                              final finalLogo = logoUrl.isNotEmpty ? logoUrl : photo;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  sectionTitle('Şirket Hakkında'),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      CompanyLogoBox(
                                        logoUrl: finalLogo,
                                        fallbackText: companyName,
                                        size: 48,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              companyName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            if (website.isNotEmpty)
                                              Text(
                                                website,
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
                                  if (about.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    sectionBody(about),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],

                        const SizedBox(height: 24),
                      ],
                    ),

                    // ✅ bottom actions: Kapat + Başvur
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withOpacity(isDark ? 0.86 : 0.95),
                                border: Border(
                                  top: BorderSide(
                                    color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 52,
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: theme.colorScheme.onSurface,
                                          side: BorderSide(
                                            color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: const Text(
                                          'Kapat',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: SizedBox(
                                      height: 52,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          gradient: const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFF6E44FF), // mor
                                              Color(0xFF00C4FF), // mavi
                                            ],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Color(0xFF6E44FF).withOpacity(0.35),
                                              blurRadius: 16,
                                              offset: Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(14),
                                            onTap: () => _goToApply(context),
                                            child: const Center(
                                              child: Text(
                                                'Başvur',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ),
                                          ),
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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CompanyLogoBox extends StatelessWidget {
  final String logoUrl;
  final String fallbackText;
  final double size;

  const CompanyLogoBox({
    super.key,
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
        errorBuilder: (_, __, ___) => _fallback(context),
      )
          : _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    final theme = Theme.of(context);
    final initial = fallbackText.trim().isNotEmpty
        ? fallbackText.trim().characters.first.toUpperCase()
        : '?';

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
}
