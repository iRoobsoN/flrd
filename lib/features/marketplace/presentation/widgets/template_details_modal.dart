import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../projects/providers/projects_provider.dart';
import '../../models/marketplace_template.dart';

class TemplateDetailsModal extends ConsumerWidget {
  final MarketplaceTemplate template;

  const TemplateDetailsModal({super.key, required this.template});

  static void show(BuildContext context, MarketplaceTemplate template) {
    showDialog(
      context: context,
      builder: (_) => TemplateDetailsModal(template: template),
    );
  }

  void _installTemplate(BuildContext context, WidgetRef ref) {
    // Add to recognized projects
    ref.read(projectsProvider.notifier).addProject(
          name: template.id.replaceAll('-', '_'),
          orgId: 'com.marketplace.${template.id.replaceAll('-', '')}',
          path: 'C:/Projects/${template.id.replaceAll('-', '_')}',
          preset: template.preset,
          navigationStyle: template.navigationStyle,
          permissions: {},
          routeCount: template.screensCount,
        );

    Navigator.of(context).pop();

    AppToast.success(
      context,
      'Template "${template.title}" instalado e adicionado aos Meus Projetos!',
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = template;
    final m = template.manifest;

    return AlertDialog(
      backgroundColor: AppColors.backgroundSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      contentPadding: const EdgeInsets.all(24),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header: Icon + Title + Price
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: t.accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: t.accentColor.withOpacity(0.4),
                      ),
                    ),
                    child: Icon(t.icon, color: t.accentColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Criado por ${t.author} • Categoria: ${t.category}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: t.isFree
                          ? AppColors.success.withOpacity(0.15)
                          : AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: t.isFree
                            ? AppColors.success.withOpacity(0.4)
                            : AppColors.primary.withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      t.formattedPrice,
                      style: TextStyle(
                        color: t.isFree ? AppColors.success : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Rating & Community Stats Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${t.rating} (${t.reviewsCount} avaliações)',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.download_rounded,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${t.downloadsCount} downloads',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.layers_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${t.screensCount} telas inclusas',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Description
              Text(
                t.description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),

              // FLRD Architecture & Consistency Blueprint (Answering user's question!)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.accentColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: t.accentColor,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Contrato de Consistência & Contexto do Template',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildBlueprintRow(
                      '🎨 Design System:',
                      m.designSystem,
                    ),
                    const SizedBox(height: 6),
                    _buildBlueprintRow(
                      '🏗️ Gerenciamento de Estado:',
                      m.stateManagement,
                    ),
                    const SizedBox(height: 6),
                    _buildBlueprintRow(
                      '🗺️ Padrão de Rotas:',
                      m.routingPattern,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            size: 14,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Garantia Anti-Quebra: Toda nova tela criada ou gerada via IA consumirá este manifesto (.flrd/manifest.json) para manter 100% da identidade do template.',
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Included Screens
              const Text(
                'Telas e Módulos Inclusos no Template:',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: m.screenNames.map((screen) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 12,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          screen,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: AppColors.textPrimary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Features
              const Text(
                'Principais Recursos do Pacote:',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...t.features.map((feature) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.done_all_rounded,
                        size: 14,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Fechar',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        if (t.isFree) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _installTemplate(context, ref),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text(
              'Instalar Template no Meu PC (Grátis)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ] else ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              AppToast.info(
                context,
                'Checkout Seguro Stripe simulado: \$${t.priceUsd.toStringAsFixed(0)} USD (75% ao criador ${t.author} / 25% FLRD Platform Fee).',
                duration: const Duration(seconds: 4),
              );
            },
            icon: const Icon(Icons.shopping_bag_rounded, size: 16),
            label: Text(
              'Comprar Template (${t.formattedPrice})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBlueprintRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 170,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
