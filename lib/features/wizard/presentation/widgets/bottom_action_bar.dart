import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
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

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          // Live Config Tag Preview
          Expanded(
            child: Row(
              children: [
                _Badge(
                  label: 'Project',
                  value: state.config.projectName.isEmpty
                      ? 'unnamed'
                      : state.config.projectName,
                  icon: Icons.folder_zip_rounded,
                ),
                const SizedBox(width: 8),
                _Badge(
                  label: 'Stack',
                  value: state.config.preset.name,
                  icon: state.config.preset.icon,
                ),
                const SizedBox(width: 8),
                _Badge(
                  label: 'Nav',
                  value: state.config.navigationStyle.name,
                  icon: state.config.navigationStyle.icon,
                ),
              ],
            ),
          ),

          // Navigation Controls
          if (!isFirstStep) ...[
            TextButton.icon(
              onPressed: () => notifier.previousStep(),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(width: 12),
          ],

          if (!isLastStep)
            ElevatedButton.icon(
              onPressed: () => notifier.nextStep(),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Continue'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceHover,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

          const SizedBox(width: 12),

          // Primary Launch / Generate Button
          _GenerateHeroButton(onPressed: onGenerate),
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
  final VoidCallback onPressed;

  const _GenerateHeroButton({required this.onPressed});

  @override
  State<_GenerateHeroButton> createState() => _GenerateHeroButtonState();
}

class _GenerateHeroButtonState extends State<_GenerateHeroButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? AppColors.primaryGlow
                    : AppColors.primary.withOpacity(0.2),
                blurRadius: _isHovered ? 16 : 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.rocket_launch_rounded, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Generate & Launch',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
