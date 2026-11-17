import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../controllers/wizard_controller.dart';

class BottomActionBar extends ConsumerWidget {
  final VoidCallback onGenerate;

  const BottomActionBar({
    super.key,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardProvider);
    final notifier = ref.read(wizardProvider.notifier);
    final isFirstStep = state.currentStep.index == 0;
    final isLastStep = state.currentStep.index == WizardStep.values.length - 1;
    final canGenerate = state.canGenerateProject;

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          // Live Config Tag Preview (horizontally scrollable to avoid overflow on narrower screens)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Badge(
                    label: 'Etapa',
                    value:
                        '${state.currentStep.index + 1}/${WizardStep.values.length}',
                    icon: canGenerate
                        ? Icons.verified_rounded
                        : Icons.route_rounded,
                  ),
                  const SizedBox(width: 8),
                  _Badge(
                    label: 'Projeto',
                    value: state.config.projectName.isEmpty
                        ? 'sem_nome'
                        : state.config.projectName,
                    icon: Icons.folder_zip_rounded,
                  ),
                  const SizedBox(width: 8),
                  _Badge(
                    label: 'Preset',
                    value: state.config.preset.name,
                    icon: state.config.preset.icon,
                  ),
                  const SizedBox(width: 8),
                  _Badge(
                    label: 'Nav',
                    value: state.config.navigationStyle.ptLabel,
                    icon: state.config.navigationStyle.icon,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Navigation Controls
          if (!isFirstStep) ...[
            TextButton.icon(
              key: const ValueKey('wizard_back_button'),
              onPressed: () => notifier.previousStep(),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Voltar'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(width: 8),
          ],

          if (!isLastStep)
            ElevatedButton.icon(
              key: const ValueKey('wizard_next_button'),
              onPressed: () {
                final err = notifier.nextStep();
                if (err != null) {
                  AppToast.error(context, err);
                }
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Continuar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceHover,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

          const SizedBox(width: 10),

          // Primary Launch / Generate Button (blocked until all 6 steps completed)
          _GenerateHeroButton(
            enabled: canGenerate,
            remainingSteps: WizardStep.values.length - state.completedCount,
            onPressed: () {
              if (!canGenerate) {
                final pending = state.firstIncompleteStep;
                AppToast.info(
                  context,
                  'Passe por todas as 6 etapas antes de criar o projeto (pendente: ${pending.title}).',
                );
                return;
              }
              onGenerate();
            },
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Badge({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.secondary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GenerateHeroButton extends StatefulWidget {
  final bool enabled;
  final int remainingSteps;
  final VoidCallback onPressed;

  const _GenerateHeroButton({
    required this.enabled,
    required this.remainingSteps,
    required this.onPressed,
  });

  @override
  State<_GenerateHeroButton> createState() => _GenerateHeroButtonState();
}

class _GenerateHeroButtonState extends State<_GenerateHeroButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.enabled
        ? 'Criar Projeto Flutter'
        : 'Criar (${widget.remainingSteps} etapas restantes)';

    return Tooltip(
      message: widget.enabled
          ? 'Todas as etapas concluídas. Clique para gerar o app!'
          : 'Passe por todas as 6 etapas para liberar a criação.',
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          key: const ValueKey('wizard_generate_button'),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              gradient: widget.enabled ? AppColors.primaryGradient : null,
              color: widget.enabled ? null : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(8),
              border: widget.enabled
                  ? null
                  : Border.all(color: AppColors.border),
              boxShadow: widget.enabled
                  ? [
                      BoxShadow(
                        color: _isHovered
                            ? AppColors.primaryGlow
                            : AppColors.primary.withOpacity(0.2),
                        blurRadius: _isHovered ? 16 : 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.enabled
                      ? Icons.rocket_launch_rounded
                      : Icons.lock_outline_rounded,
                  size: 16,
                  color: widget.enabled ? Colors.white : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: widget.enabled ? Colors.white : AppColors.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
