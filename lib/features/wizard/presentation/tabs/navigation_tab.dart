import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/project_config.dart';
import '../controllers/wizard_controller.dart';

class NavigationTab extends ConsumerWidget {
  const NavigationTab({super.key});

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
            'Navigation Architecture',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select how users navigate across major sections of your application.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),

          ...NavigationStyle.values.map((nav) {
            final isSelected = state.config.navigationStyle == nav;
            return _NavigationOptionCard(
              navStyle: nav,
              isSelected: isSelected,
              onSelect: () => notifier.updateConfig((c) => c.copyWith(navigationStyle: nav)),
            );
          }),
        ],
      ),
    );
  }
}

class _NavigationOptionCard extends StatefulWidget {
  final NavigationStyle navStyle;
  final bool isSelected;
  final VoidCallback onSelect;

  const _NavigationOptionCard({
    required this.navStyle,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  State<_NavigationOptionCard> createState() => _NavigationOptionCardState();
}

class _NavigationOptionCardState extends State<_NavigationOptionCard> {
  bool _isHovered = false;

  Widget _buildMiniMockup(NavigationStyle style) {
    switch (style) {
      case NavigationStyle.tabs:
        return Container(
          width: 80,
          height: 52,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(height: 6, decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(2))),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  3,
                  (i) => Container(
                    width: 14,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i == 0 ? AppColors.secondary : AppColors.surfaceHover,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

      case NavigationStyle.drawer:
        return Container(
          width: 80,
          height: 52,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSelected,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    3,
                    (i) => Container(width: 10, height: 3, color: i == 0 ? AppColors.secondary : AppColors.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ),
        );

      case NavigationStyle.adaptiveRail:
        return Container(
          width: 80,
          height: 52,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                decoration: BoxDecoration(color: AppColors.surfaceSelected, borderRadius: BorderRadius.circular(2)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(3, (i) => Container(width: 6, height: 4, color: i == 0 ? AppColors.secondary : AppColors.textMuted)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Container(color: AppColors.surfaceHover)),
                    Container(height: 4, color: AppColors.surfaceCard),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
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
          ),
          child: Row(
            children: [
              _buildMiniMockup(widget.navStyle),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.navStyle.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.navStyle.description,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
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
                    ? const Center(child: Icon(Icons.circle, size: 8, color: Colors.white))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
