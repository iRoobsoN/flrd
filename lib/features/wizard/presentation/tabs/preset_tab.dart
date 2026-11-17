import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/project_config.dart';
import '../controllers/wizard_controller.dart';

class PresetTab extends ConsumerWidget {
  const PresetTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardProvider);
    final notifier = ref.read(wizardProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Etapa 2 • Preset de Arquitetura (Tipo de App)',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Escolha a base que mais combina com o tipo de aplicativo que você quer construir. Tudo já vem com telas iniciais, navegação e pacotes configurados.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),

          // Guia rápido de decisão para iniciantes e avançados
          const _PresetDecisionGuide(),
          const SizedBox(height: 22),

          // Cards detalhados com exemplos de apps reais
          ...PresetType.values.map((preset) {
            final isSelected = state.config.preset == preset;
            return _PresetCard(
              preset: preset,
              isSelected: isSelected,
              onSelect: () => notifier.updateConfig(
                (c) => c.copyWith(preset: preset),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PresetDecisionGuide extends StatelessWidget {
  const _PresetDecisionGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.28)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 16, color: AppColors.warning),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Não sabe qual escolher? Guia rápido de 5 segundos:',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _GuideItem(
                title: 'SaaS / Indie Hacker',
                hint: 'Seu app tem login e salva dados na nuvem (Supabase).',
              ),
              _GuideItem(
                title: 'Clean-Lite Scalable',
                hint: 'Vai conectar numa API própria ou crescer com equipe.',
              ),
              _GuideItem(
                title: 'Offline-First Utility',
                hint: 'Funciona direto no celular sem precisar de servidor.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  final String title;
  final String hint;

  const _GuideItem({required this.title, required this.hint});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.arrow_right_rounded, size: 14, color: AppColors.secondary),
          ),
          const SizedBox(width: 2),
          Flexible(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: hint),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatefulWidget {
  final PresetType preset;
  final bool isSelected;
  final VoidCallback onSelect;

  const _PresetCard({
    required this.preset,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  State<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends State<_PresetCard> {
  bool _isHovered = false;

  String _keySuffix(PresetType preset) {
    switch (preset) {
      case PresetType.saas:
        return 'saas';
      case PresetType.cleanLite:
        return 'clean_lite';
      case PresetType.offline:
        return 'offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preset;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        key: ValueKey('preset_card_${_keySuffix(p)}'),
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.surfaceSelected
                : (_isHovered ? AppColors.surfaceHover : AppColors.surfaceCard),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primary
                  : (_isHovered ? AppColors.borderHover : AppColors.border),
              width: widget.isSelected ? 1.5 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Badge
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? AppColors.primary.withOpacity(0.2)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.isSelected
                        ? AppColors.primary.withOpacity(0.6)
                        : AppColors.borderSubtle,
                  ),
                ),
                child: Icon(
                  p.icon,
                  color: widget.isSelected ? AppColors.secondary : AppColors.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: p == PresetType.saas
                                ? AppColors.primary.withOpacity(0.2)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: p == PresetType.saas
                                  ? AppColors.primary.withOpacity(0.45)
                                  : AppColors.borderSubtle,
                            ),
                          ),
                          child: Text(
                            p.badgeLabel,
                            style: TextStyle(
                              color: p == PresetType.saas
                                  ? AppColors.secondary
                                  : AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      p.friendlySubtitle,
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      p.plainExplanation,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Exemplos práticos de tipos de apps
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Exemplos de apps para criar com este preset:',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: p.appExamples.map((example) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceCard,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.secondary.withOpacity(0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.apps_rounded,
                                      size: 12,
                                      color: AppColors.secondary,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        example,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // O que já vem pronto + pacotes reais
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: p.technicalHighlights.map((feat) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.background.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_rounded, size: 12, color: AppColors.success),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  feat,
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Pacotes incluídos:',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        for (final pkg in p.generatedPackages)
                          Text(
                            pkg,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Radio Check
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.isSelected ? AppColors.primary : AppColors.textMuted,
                    width: 2,
                  ),
                  color: widget.isSelected ? AppColors.primary : Colors.transparent,
                ),
                child: widget.isSelected
                    ? const Center(
                        child: Icon(Icons.circle, size: 8, color: Colors.white),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
