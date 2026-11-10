import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

          // Author / Branding Footer Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
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
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
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
              ],
            ),
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
