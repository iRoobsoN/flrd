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
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stack Presets',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select the architectural blueprint best suited for your project goal.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),

          // Presets Grid
          ...PresetType.values.map((preset) {
            final isSelected = state.config.preset == preset;
            return _PresetCard(
              preset: preset,
              isSelected: isSelected,
              onSelect: () => notifier.updateConfig((c) => c.copyWith(preset: preset)),
            );
          }),
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

  List<String> _getFeatures(PresetType type) {
    switch (type) {
      case PresetType.saas:
        return ['Flutter Riverpod 2.x', 'GoRouter with Auth Guards', 'Supabase Auth & Database Ready', 'Persistent Light/Dark Theme'];
      case PresetType.cleanLite:
        return ['BLoC / Cubit Architecture', 'Dio + Pretty Logger', 'GetIt Dependency Injection', 'Feature-First Folder Layout'];
      case PresetType.offline:
        return ['Drift / SQLite Local DB', 'Provider / Riverpod Store', 'Dynamic Material 3 Color Seeds', 'Zero Remote Latency'];
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = _getFeatures(widget.preset);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
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
                width: 44,
                height: 44,
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
                  widget.preset.icon,
                  color: widget.isSelected ? AppColors.secondary : AppColors.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 18),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.preset.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.preset == PresetType.saas) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'MOST POPULAR',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.preset.tagline,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),

                    // Feature Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: features.map((feat) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.background.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_rounded, size: 12, color: AppColors.success),
                              const SizedBox(width: 5),
                              Text(
                                feat,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
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
