import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../models/project_config.dart';
import '../controllers/wizard_controller.dart';

/// Regex validating standard Dart/Flutter package names (`snake_case`).
final RegExp _validExtraPackageRegex = RegExp(r'^[a-z][a-z0-9_]*$');

/// Optional collapsible panel placed at the end of Step 6 (`NativeConfigTab`)
/// allowing advanced Flutter developers to inspect, exclude, or add dependencies
/// before creating the project without slowing down beginners.
class AdvancedDependenciesSection extends ConsumerStatefulWidget {
  const AdvancedDependenciesSection({super.key});

  @override
  ConsumerState<AdvancedDependenciesSection> createState() =>
      _AdvancedDependenciesSectionState();
}

class _AdvancedDependenciesSectionState
    extends ConsumerState<AdvancedDependenciesSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(wizardProvider).config;
    final selectedCount = config.resolvedPackagesToInstall.length;
    final totalPlanned = config.plannedDependencies.length;
    final isCustomized = config.hasCustomDependencies;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCustomized
              ? AppColors.secondary.withOpacity(0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('toggle_advanced_options_button'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Opções Avançadas (Opcional) • Revisão de Dependências',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isCustomized
                                    ? AppColors.secondary.withOpacity(0.16)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: isCustomized
                                      ? AppColors.secondary.withOpacity(0.45)
                                      : AppColors.borderSubtle,
                                ),
                              ),
                              child: Text(
                                isCustomized
                                    ? 'Personalizado ($selectedCount/$totalPlanned)'
                                    : '$selectedCount pacotes incluídos',
                                style: TextStyle(
                                  color: isCustomized
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
                        const Text(
                          'Para devs avançados: revise o que será importado no pubspec.yaml, desmarque pacotes indesejados ou inclua extras antes de gerar.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('open_dependencies_review_dialog_button'),
                    onPressed: () => DependenciesReviewDialog.show(context),
                    icon: const Icon(Icons.fact_check_outlined, size: 14),
                    label: const Text(
                      'Abrir Revisão',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondary,
                      side: BorderSide(
                        color: AppColors.secondary.withOpacity(0.45),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1, color: AppColors.borderSubtle),
            const Padding(
              padding: EdgeInsets.all(18),
              child: DependenciesReviewBody(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dedicated modal screen for reviewing and customizing planned `pubspec.yaml`
/// dependencies right before triggering project generation.
class DependenciesReviewDialog extends ConsumerWidget {
  const DependenciesReviewDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const DependenciesReviewDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(wizardProvider).config;
    final selectedCount = config.resolvedPackagesToInstall.length;

    return Dialog(
      backgroundColor: AppColors.backgroundSecondary,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.inventory_2_rounded,
                      size: 18,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Revisão de Dependências — ${config.projectName}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Preset ativo: ${config.preset.name} • $selectedCount pacote(s) serão adicionados ao pubspec.yaml',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.borderSubtle),
              const SizedBox(height: 16),
              const Expanded(
                child: SingleChildScrollView(
                  child: DependenciesReviewBody(),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.borderSubtle),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    key: const ValueKey('close_dependencies_review_dialog_button'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Concluir Revisão'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
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

/// Shared dependency review editor used both inline in [AdvancedDependenciesSection]
/// and inside [DependenciesReviewDialog].
class DependenciesReviewBody extends ConsumerStatefulWidget {
  const DependenciesReviewBody({super.key});

  @override
  ConsumerState<DependenciesReviewBody> createState() =>
      _DependenciesReviewBodyState();
}

class _DependenciesReviewBodyState
    extends ConsumerState<DependenciesReviewBody> {
  final TextEditingController _extraPkgController = TextEditingController();

  @override
  void dispose() {
    _extraPkgController.dispose();
    super.dispose();
  }

  void _togglePackage(PlannedDependency dep, bool include) {
    ref.read(wizardProvider.notifier).updateConfig((config) {
      if (dep.isExtra && !include) {
        final nextExtras = config.extraPackages
            .where((p) => p.trim().toLowerCase() != dep.name)
            .toList();
        return config.copyWith(extraPackages: nextExtras);
      }
      final nextExcluded = Set<String>.from(config.excludedPackages);
      if (include) {
        nextExcluded.remove(dep.name);
      } else {
        nextExcluded.add(dep.name);
      }
      return config.copyWith(excludedPackages: nextExcluded);
    });
  }

  void _addExtraPackage() {
    final pkgName = _extraPkgController.text.trim().toLowerCase();
    if (!_validExtraPackageRegex.hasMatch(pkgName)) {
      AppToast.error(
        context,
        'Nome de pacote inválido. Use snake_case (ex.: equatable, intl).',
      );
      return;
    }

    final notifier = ref.read(wizardProvider.notifier);
    final config = ref.read(wizardProvider).config;
    final alreadyInCatalog =
        config.plannedDependencies.any((d) => d.name == pkgName);

    if (alreadyInCatalog) {
      // Ensure it is enabled if it was previously excluded
      final nextExcluded = Set<String>.from(config.excludedPackages)
        ..remove(pkgName);
      notifier.updateConfig((c) => c.copyWith(excludedPackages: nextExcluded));
      _extraPkgController.clear();
      return;
    }

    notifier.updateConfig(
      (c) => c.copyWith(extraPackages: [...c.extraPackages, pkgName]),
    );
    _extraPkgController.clear();
  }

  void _restoreDefaults() {
    ref.read(wizardProvider.notifier).updateConfig(
          (c) => c.copyWith(
            excludedPackages: const {},
            extraPackages: const [],
            minimalScaffold: false,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(wizardProvider).config;
    final planned = config.plannedDependencies;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Optional clean-minimal scaffold switch
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: config.minimalScaffold
                  ? AppColors.secondary.withOpacity(0.45)
                  : AppColors.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.cleaning_services_rounded,
                size: 16,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Modo Estrutura Mínima Limpa (sem arquivos de exemplo do preset)',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Gera apenas pubspec customizado, AppTheme, main.dart enxuto e permissões nativas.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                key: const ValueKey('advanced_minimal_scaffold_switch'),
                value: config.minimalScaffold,
                activeColor: AppColors.secondary,
                onChanged: (val) => ref
                    .read(wizardProvider.notifier)
                    .updateConfig((c) => c.copyWith(minimalScaffold: val)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (config.hasMissingTemplatePackages) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withOpacity(0.4)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Você desmarcou pacotes usados pelos arquivos de exemplo do preset. Para evitar erros de compilação, o FLRD gerará automaticamente uma estrutura mínima limpa com os pacotes mantidos.',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Row(
          children: [
            const Expanded(
              child: Text(
                'DEPENDÊNCIAS QUE SERÃO IMPORTADAS NO PUBSPEC.YAML',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            if (config.hasCustomDependencies)
              TextButton.icon(
                key: const ValueKey('reset_advanced_deps_button'),
                onPressed: _restoreDefaults,
                icon: const Icon(Icons.restart_alt_rounded, size: 14),
                label: const Text(
                  'Restaurar padrão',
                  style: TextStyle(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        for (final dep in planned)
          _PlannedDependencyTile(
            dependency: dep,
            onChanged: (val) => _togglePackage(dep, val),
          ),

        const SizedBox(height: 10),
        // Extra package quick inclusion bar
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('advanced_extra_pkg_input'),
                controller: _extraPkgController,
                onSubmitted: (_) => _addExtraPackage(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Incluir pacote extra já na criação (ex.: intl, equatable)',
                  hintStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              key: const ValueKey('advanced_add_extra_pkg_button'),
              onPressed: _addExtraPackage,
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text('Incluir', style: TextStyle(fontSize: 11.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlannedDependencyTile extends StatelessWidget {
  final PlannedDependency dependency;
  final ValueChanged<bool> onChanged;

  const _PlannedDependencyTile({
    required this.dependency,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final included = dependency.isIncluded;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: included
              ? AppColors.borderSubtle
              : AppColors.textMuted.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: included ? 1.0 : 0.52,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        dependency.name,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          decoration:
                              included ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      _PillBadge(
                        label: dependency.originLabel,
                        color: AppColors.primary,
                      ),
                      _PillBadge(
                        label: dependency.isExtra
                            ? 'Extra'
                            : (dependency.requiredByFullTemplate
                                ? 'Usado no template'
                                : 'Opcional'),
                        color: dependency.requiredByFullTemplate
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dependency.reason,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            key: ValueKey('review_dep_toggle_${dependency.name}'),
            value: included,
            activeColor: AppColors.success,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _PillBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
