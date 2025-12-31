// lib/tabs/jobs_tab.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/job_apply_screen.dart';
import '../theme/app_colors.dart';

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

  void _openJobDetailsSheet(
      BuildContext context,
      String jobId,
      Map<String, dynamic> job,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JobDetailsSheet(jobId: jobId, job: job),
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

        const spacing = 10.0;
        const aspect = 0.88;

        return RefreshIndicator(
          onRefresh: _refresh,
          edgeOffset: 12,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
              final companyName = (data['companyName'] ?? '').toString().trim();
              final location = (data['location'] ?? '').toString().trim();
              final workModel = (data['workModel'] ?? '').toString().trim();

              final logoUrl =
              (data['companyLogoUrl'] ?? '').toString().trim();
              final companyId = (data['companyId'] ?? '').toString().trim();

              final displayTitle = title.isEmpty ? '(Pozisyon adı yok)' : title;
              final displayCompany = companyName.isEmpty
                  ? 'Şirket adı belirtilmemiş'
                  : companyName;
              final displayLocation =
              location.isEmpty ? 'Konum belirtilmemiş' : location;

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
    );
  }
}

class _JobDetailsSheet extends StatelessWidget {
  final String jobId;
  final Map<String, dynamic> job;

  const _JobDetailsSheet({
    required this.jobId,
    required this.job,
  });

  Future<Map<String, dynamic>?> _loadCompany(String companyId) async {
    if (companyId.isEmpty) return null;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(companyId)
        .get();
    if (!snap.exists) return null;
    return snap.data();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Temel alanlar
    final title = (job['title'] ?? '(Pozisyon adı yok)').toString().trim();
    final companyName =
    (job['companyName'] ?? 'Şirket adı belirtilmemiş').toString().trim();
    final location =
    (job['location'] ?? 'Konum belirtilmemiş').toString().trim();
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
    final applyUrl = (job['applyUrl'] ?? '').toString().trim();
    final deadline = JobsTab._fmtDate(job['deadline']);
    final createdAt = JobsTab._fmtDate(job['createdAt']);

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
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Stack(
              children: [
                // CONTENT
                ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                      '$location • ${JobsTab.prettyWorkType(workModel)}',
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

                    if (contactEmail.isNotEmpty || applyUrl.isNotEmpty) ...[
                      dividerBlock(),
                      sectionTitle('Başvuru / İletişim'),
                      const SizedBox(height: 8),
                      if (contactEmail.isNotEmpty)
                        infoRow(Icons.mail_outline, contactEmail),
                      if (applyUrl.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        infoRow(Icons.link_outlined, applyUrl),
                      ],
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

                          final about = (cdata['about'] ?? cdata['bio'] ?? '')
                              .toString()
                              .trim();
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
                                  _CompanyLogoBox(
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

                    // ✅ bottom bar boşluğu (overlay button için)
                    const SizedBox(height: 86),
                  ],
                ),

                // BOTTOM CTA
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                          width: 1,
                        ),
                      ),
                    ),
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: isDark
                          ? DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF6D5DF6),
                              Color(0xFF4FC3F7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6D5DF6).withOpacity(0.45),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
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
                          child: const Text(
                            'Başvur',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 3,
                                  color: Colors.black38,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                          : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
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
                        child: const Text(
                          'Başvur',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    final bgColor = AppColors.cardBg(theme);
    final borderColor = AppColors.cardBorder(theme);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 0.7),
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
                        fontWeight: FontWeight.w800,
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
                        fontWeight: FontWeight.w600,
                        color: AppColors.subtleText(theme),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 14, color: AppColors.subtleText(theme)),
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
                height: 28,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: const [
                    _MiniTag(icon: Icons.flash_on, label: 'Kolay Başvuru'),
                    SizedBox(width: 6),
                    _MiniTag(icon: Icons.fiber_new, label: 'Yeni'),
                    SizedBox(width: 6),
                    _MiniTag(icon: Icons.visibility, label: 'Görüntülendi'),
                  ],
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
        color: theme.colorScheme.surfaceVariant.withOpacity(
          theme.brightness == Brightness.dark ? 0.18 : 0.65,
        ),
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
              fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(
          theme.brightness == Brightness.dark ? 0.18 : 0.65,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
        color: theme.colorScheme.surfaceVariant.withOpacity(
          theme.brightness == Brightness.dark ? 0.18 : 0.65,
        ),
        borderRadius: BorderRadius.circular(12),
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
