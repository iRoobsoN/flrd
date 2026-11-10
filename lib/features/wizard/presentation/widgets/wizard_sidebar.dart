import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../controllers/wizard_controller.dart';

class WizardSidebar extends ConsumerWidget {
  const WizardSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardProvider);
    final notifier = ref.read(wizardProvider.notifier);

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(right: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Sidebar Section Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'CONFIGURATION STEPS',
              style: TextStyle(
                color: AppColors.textMuted.withOpacity(0.8),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Steps List
          Expanded(
            child: ListView.builder(
              itemCount: WizardStep.values.length,
              itemBuilder: (context, index) {
                final step = WizardStep.values[index];
                final isSelected = state.currentStep == step;
                final isPast = state.currentStep.index > step.index;

                return _SidebarStepItem(
                  stepNumber: '0${index + 1}',
                  title: step.title,
                  subtitle: step.subtitle,
                  isSelected: isSelected,
                  isPast: isPast,
                  onTap: () => notifier.setStep(step),
                );
              },
            ),
          ),

          // Author / Branding & Sponsor Card
          const _AuthorSponsorCard(),
        ],
      ),
    );
  }
}

class _AuthorSponsorCard extends StatelessWidget {
  const _AuthorSponsorCard();

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível abrir o link: $url')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir link: $e')),
        );
      }
    }
  }

  void _showDonateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.pinkAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Apoiar o Projeto FLRD',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FLRD é um projeto open-source mantido por Robson David (@iRoobsoN). '
              'Se esta ferramenta está ajudando sua produtividade, deixe uma estrela no repositório ou envie um apoio!',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            // Pix Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PIX (Brasil)',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          Clipboard.setData(
                            const ClipboardData(text: 'robson.dv14@gmail.com'),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Chave Pix copiada: robson.dv14@gmail.com',
                              ),
                              backgroundColor: AppColors.success,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        label: const Text(
                          'Copiar Chave',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const SelectableText(
                    'robson.dv14@gmail.com',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // PayPal Card
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Navigator.of(ctx).pop();
                _openUrl(
                  context,
                  'https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=robson.dv14@gmail.com&currency_code=USD',
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.payment_rounded,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PayPal (Global)',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Doação segura via cartão de crédito',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Fechar',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _openUrl(context, 'https://github.com/iRoobsoN/flrd');
            },
            icon: const Icon(
              Icons.star_rounded,
              size: 16,
              color: Colors.amber,
            ),
            label: const Text('Deixar Estrela ⭐'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceCard,
            AppColors.surfaceHover.withOpacity(0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
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
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _openUrl(context, 'https://github.com/iRoobsoN'),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Robson David',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '@iRoobsoN',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Community / Support Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 12,
                  color: AppColors.secondary,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Gostou do FLRD? Apoie!',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Action Buttons: Star + Donate
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    backgroundColor: AppColors.surface,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () =>
                      _openUrl(context, 'https://github.com/iRoobsoN/flrd'),
                  icon: const Icon(
                    Icons.star_rounded,
                    size: 13,
                    color: Colors.amber,
                  ),
                  label: const Text(
                    'Star',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _showDonateDialog(context),
                  icon: const Icon(
                    Icons.favorite_rounded,
                    size: 12,
                    color: Colors.pinkAccent,
                  ),
                  label: const Text(
                    'Donate',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarStepItem extends StatefulWidget {
  final String stepNumber;
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isPast;
  final VoidCallback onTap;

  const _SidebarStepItem({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.isPast,
    required this.onTap,
  });

  @override
  State<_SidebarStepItem> createState() => _SidebarStepItemState();
}

class _SidebarStepItemState extends State<_SidebarStepItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.surfaceSelected
                : (_isHovered ? AppColors.surfaceHover : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primary.withOpacity(0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              // Step Indicator Pill
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? AppColors.primary
                      : (widget.isPast
                          ? AppColors.success.withOpacity(0.15)
                          : AppColors.surfaceCard),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.isSelected
                        ? AppColors.primary
                        : (widget.isPast
                            ? AppColors.success.withOpacity(0.5)
                            : AppColors.borderSubtle),
                  ),
                ),
                child: Center(
                  child: widget.isPast
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: AppColors.success,
                        )
                      : Text(
                          widget.stepNumber,
                          style: TextStyle(
                            color: widget.isSelected
                                ? Colors.white
                                : AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Titles
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.isSelected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight:
                            widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
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
