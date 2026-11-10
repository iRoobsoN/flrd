import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/marketplace_provider.dart';
import 'widgets/publish_template_dialog.dart';
import 'widgets/template_card.dart';

class MarketplaceView extends ConsumerWidget {
  const MarketplaceView({super.key});

  static const List<String> _categories = [
    'Todos',
    'Fintech',
    'SaaS',
    'E-Commerce',
    'Offline',
    'Saúde & AI',
    'Gratuitos',
    'Premium',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(marketplaceProvider);
    final notifier = ref.read(marketplaceProvider.notifier);
    final templates = state.filteredTemplates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Marketplace Showcase Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.surfaceCard,
                AppColors.primary.withOpacity(0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Marketplace de Templates da Comunidade FLRD',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Templates prontos para produção. Qualquer criador pode publicar, vender em dólares e receber 75% via Lemon Squeezy / Stripe!',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => PublishTemplateDialog.show(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: const Text(
                  'Publicar Template',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Search Bar & Category Filter Chips
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  onChanged: notifier.setSearchQuery,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome, tag ou tecnologia (ex: Pix, Crypto, BLoC)...',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((category) {
              final isSelected = state.selectedCategory == category;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (_) => notifier.setCategory(category),
                  selectedColor: AppColors.primary.withOpacity(0.2),
                  backgroundColor: AppColors.surface,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : AppColors.borderSubtle,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),

        // Templates Grid
        if (templates.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: const Center(
              child: Text(
                'Nenhum template encontrado para os filtros selecionados.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          ),
        ] else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent: 250,
                ),
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  return TemplateCard(template: templates[index]);
                },
              );
            },
          ),
        ],
      ],
    );
  }
}
