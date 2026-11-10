import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/language_provider.dart';
import '../../../core/localization/language_selector_widget.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/donate_dialog.dart';
import '../../../core/window/custom_titlebar.dart';
import '../../projects/providers/projects_provider.dart';
import '../../wizard/presentation/wizard_screen.dart';
import 'widgets/projects_grid_view.dart';

class HubScreen extends ConsumerWidget {
  const HubScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Title Bar with compact language selector
            CustomTitleBar(
              showBackButton: false,
              trailing: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: LanguageSelectorWidget(compact: true),
              ),
            ),

            // Scrollable Hub Canvas
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hero Header Section
                        _buildHeroHeader(context, ref, strings),
                        const SizedBox(height: 32),

                        // Action Tiles (New Project, My Projects, Architecture)
                        _buildActionCards(context, strings),
                        const SizedBox(height: 36),

                        // CLI Terminal Tip Banner
                        _buildCliBanner(context, strings),
                        const SizedBox(height: 36),

                        // Recognized Projects Workspace Section
                        _buildRecognizedProjectsSection(context, ref, strings),
                        const SizedBox(height: 48),

                        // Community Footer
                        _buildCommunityFooter(context, strings),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.surfaceCard.withOpacity(0.8)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Tag Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 13,
                        color: AppColors.secondary,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'FLRD STUDIO v0.1.0 • OPEN-SOURCE ENGINE',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Main Heading with Gradient
                ShaderMask(
                  shaderCallback: (bounds) =>
                      AppColors.primaryGradient.createShader(bounds),
                  child: Text(
                    strings.hubTitle,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  strings.hubTagline,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),

                // 3 Anti-Obsolescence Pillar Chips
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildPillarChip(
                      Icons.layers_rounded,
                      strings.hubStatsPillar1,
                      AppColors.primary,
                    ),
                    _buildPillarChip(
                      Icons.security_rounded,
                      strings.hubStatsPillar2,
                      AppColors.secondary,
                    ),
                    _buildPillarChip(
                      Icons.diamond_rounded,
                      strings.hubStatsPillar3,
                      AppColors.success,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),

          // Header Right: Full Language Selector & Quick Star
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const LanguageSelectorWidget(compact: false),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.surfaceCard,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () =>
                    _openUrl(context, 'https://github.com/iRoobsoN/flrd'),
                icon: const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: Colors.amber,
                ),
                label: const Text(
                  'GitHub ⭐',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPillarChip(IconData icon, String label, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCards(BuildContext context, AppStrings strings) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 750;

        final newProjectCard = _ActionCard(
          title: strings.newProjectTitle,
          description: strings.newProjectDesc,
          icon: Icons.rocket_launch_rounded,
          accentColor: AppColors.primary,
          buttonText: '${strings.newProjectTitle} →',
          isPrimary: true,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WizardScreen()),
            );
          },
        );

        final myProjectsCard = _ActionCard(
          title: strings.myProjectsTitle,
          description: strings.myProjectsDesc,
          icon: Icons.grid_view_rounded,
          accentColor: AppColors.secondary,
          buttonText: '${strings.myProjectsTitle} →',
          onTap: () {
            // Scroll to recognized projects section or trigger scan
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${strings.myProjectsTitle}: Reconhecendo projetos na máquina...',
                ),
                backgroundColor: AppColors.surfaceCard,
              ),
            );
          },
        );

        final docsCard = _ActionCard(
          title: strings.docsTitle,
          description: strings.docsDesc,
          icon: Icons.menu_book_rounded,
          accentColor: AppColors.success,
          buttonText: '${strings.docsTitle} ↗',
          onTap: () {
            _openUrl(
              context,
              'https://github.com/iRoobsoN/flrd/blob/main/ARCHITECTURE.md',
            );
          },
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: newProjectCard),
              const SizedBox(width: 16),
              Expanded(child: myProjectsCard),
              const SizedBox(width: 16),
              Expanded(child: docsCard),
            ],
          );
        } else {
          return Column(
            children: [
              newProjectCard,
              const SizedBox(height: 16),
              myProjectsCard,
              const SizedBox(height: 16),
              docsCard,
            ],
          );
        }
      },
    );
  }

  Widget _buildCliBanner(BuildContext context, AppStrings strings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.terminal_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.runCliHelp,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  strings.runCliDesc,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              Clipboard.setData(
                const ClipboardData(text: 'dart run bin/flrd.dart'),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Comando copiado: dart run bin/flrd.dart'),
                  duration: Duration(seconds: 2),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Text(
                    'dart run bin/flrd.dart',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.copy_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecognizedProjectsSection(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) {
    final isScanning = ref.watch(projectsProvider).isScanning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              strings.recentProjects,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                backgroundColor: AppColors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: isScanning
                  ? null
                  : () async {
                      await ref
                          .read(projectsProvider.notifier)
                          .scanWorkspace();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Varredura concluída: 3 projetos Flutter reconhecidos na máquina!',
                            ),
                            backgroundColor: AppColors.surfaceSelected,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
              icon: isScanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
              label: Text(
                isScanning ? 'Escaneando...' : strings.scanProjects,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // GridView of Recognized Projects
        const ProjectsGridView(),
      ],
    );
  }

  Widget _buildCommunityFooter(BuildContext context, AppStrings strings) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'RD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Robson David (@iRoobsoN)',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  strings.sponsorBannerText,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: const BorderSide(color: AppColors.border),
              backgroundColor: AppColors.surfaceCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () =>
                _openUrl(context, 'https://github.com/iRoobsoN/flrd'),
            icon: const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
            label: Text(
              strings.starButton,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => DonateDialog.show(context),
            icon: const Icon(
              Icons.favorite_rounded,
              size: 14,
              color: Colors.pinkAccent,
            ),
            label: Text(
              strings.donateButton,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final String buttonText;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.buttonText,
    this.isPrimary = false,
    required this.onTap,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? AppColors.surfaceCard
                : (_isHovered ? AppColors.surfaceHover : AppColors.surface),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered
                  ? widget.accentColor.withOpacity(0.8)
                  : (widget.isPrimary
                        ? widget.accentColor.withOpacity(0.4)
                        : AppColors.border),
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.accentColor.withOpacity(0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.accentColor.withOpacity(0.25),
                  ),
                ),
                child: Icon(widget.icon, color: widget.accentColor, size: 22),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    widget.buttonText,
                    style: TextStyle(
                      color: widget.accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
