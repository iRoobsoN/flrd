import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../wizard/models/project_config.dart';
import '../models/marketplace_template.dart';

class MarketplaceState {
  final List<MarketplaceTemplate> templates;
  final String selectedCategory;
  final String searchQuery;
  final String? inspectingTemplateId;

  const MarketplaceState({
    required this.templates,
    this.selectedCategory = 'Todos',
    this.searchQuery = '',
    this.inspectingTemplateId,
  });

  List<MarketplaceTemplate> get filteredTemplates {
    return templates.where((template) {
      final matchesCategory = selectedCategory == 'Todos' ||
          (selectedCategory == 'Gratuitos' && template.isFree) ||
          (selectedCategory == 'Premium' && !template.isFree) ||
          template.category == selectedCategory;

      final matchesSearch = searchQuery.isEmpty ||
          template.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
          template.description.toLowerCase().contains(searchQuery.toLowerCase()) ||
          template.tags.any((t) => t.toLowerCase().contains(searchQuery.toLowerCase()));

      return matchesCategory && matchesSearch;
    }).toList();
  }

  MarketplaceTemplate? get inspectingTemplate {
    if (inspectingTemplateId == null) return null;
    try {
      return templates.firstWhere((t) => t.id == inspectingTemplateId);
    } catch (_) {
      return null;
    }
  }

  MarketplaceState copyWith({
    List<MarketplaceTemplate>? templates,
    String? selectedCategory,
    String? searchQuery,
    String? inspectingTemplateId,
  }) {
    return MarketplaceState(
      templates: templates ?? this.templates,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      inspectingTemplateId: inspectingTemplateId ?? this.inspectingTemplateId,
    );
  }
}

class MarketplaceNotifier extends StateNotifier<MarketplaceState> {
  MarketplaceNotifier()
      : super(
          MarketplaceState(
            templates: [
              const MarketplaceTemplate(
                id: 'novabank-fintech',
                title: 'NovaBank - Fintech & Crypto MVP',
                author: 'Lucas Silva (@lucas_flutter)',
                category: 'Fintech',
                description:
                    'App bancário completo com saldo ocultável, transferências Pix com QR Code, carteira de criptomoedas com gráficos, autenticação biométrica e extrato detalhado.',
                priceUsd: 49.0,
                rating: 4.9,
                reviewsCount: 184,
                downloadsCount: 2410,
                screensCount: 16,
                preset: PresetType.saas,
                navigationStyle: NavigationStyle.tabs,
                tags: ['Pix', 'Crypto', 'Biometrics', 'Charts', 'Supabase'],
                features: [
                  '16 Telas completas prontas para produção',
                  'Integração nativa com Biometria (Face ID / Fingerprint)',
                  'Módulo Pix com leitor de QR Code e chave aleatória',
                  'Carteira Crypto com cotações em tempo real',
                  'Design System Obsidian Glass com tokens centralizados',
                ],
                accentColor: Color(0xFF10B981),
                icon: Icons.account_balance_wallet_rounded,
                manifest: TemplateManifestContext(
                  designSystem: 'Obsidian Glass Dark • Emerald Accent (#10B981)',
                  stateManagement: 'Riverpod 2.5 + AsyncNotifier',
                  routingPattern: 'GoRouter 14 com Biometric Guard e ShellRoute',
                  screenNames: [
                    'SplashScreen',
                    'BiometricLockScreen',
                    'HomeScreen',
                    'PixTransferScreen',
                    'PixQrScannerScreen',
                    'CryptoPortfolioScreen',
                    'TransactionsScreen',
                    'CardSettingsScreen',
                    'ProfileScreen'
                  ],
                  aiPromptRules:
                      'Todas as novas telas devem consumir AppColors.surfaceCard, usar Riverpod com AsyncValue para estados de carregamento, e manter formulários com validação estrita.',
                ),
              ),
              const MarketplaceTemplate(
                id: 'saas-hero',
                title: 'SaaSHero - Multi-Tenant B2B Kit',
                author: 'Robson David (@iRoobsoN)',
                category: 'SaaS',
                description:
                    'Starter oficial do FLRD para plataformas SaaS modernas: autenticação Supabase pronta, alternador de workspaces, tabela de planos/preços e dashboard analítico.',
                priceUsd: 0.0,
                rating: 5.0,
                reviewsCount: 310,
                downloadsCount: 5820,
                screensCount: 12,
                preset: PresetType.saas,
                navigationStyle: NavigationStyle.adaptiveRail,
                tags: ['SaaS', 'Supabase', 'Multi-tenant', 'Analytics', 'Oficial'],
                features: [
                  '100% Gratuito & Open Source sob licença MIT',
                  'Autenticação completa com Supabase Auth (Email + Magic Link)',
                  'Suporte Multi-tenant com troca dinâmica de organização',
                  'Navegação adaptativa: Bottom Bar no mobile, Navigation Rail no Desktop',
                  'Pronto para faturamento Stripe / Lemon Squeezy',
                ],
                accentColor: AppColors.primary,
                icon: Icons.rocket_launch_rounded,
                manifest: TemplateManifestContext(
                  designSystem: 'Obsidian Glass Dark • Electric Indigo (#6366F1)',
                  stateManagement: 'Riverpod 2.5 + Repository Pattern',
                  routingPattern: 'GoRouter com AuthGuard inquebrável',
                  screenNames: [
                    'AuthScreen',
                    'WorkspaceSelectScreen',
                    'DashboardOverviewScreen',
                    'PricingPlansScreen',
                    'TeamMembersScreen',
                    'BillingScreen',
                    'AccountSettingsScreen'
                  ],
                  aiPromptRules:
                      'Use a arquitetura Riverpod padrão do SaaSHero. Telas administrativas devem respeitar papéis de permissão (admin/member) e herdar o AppTheme.',
                ),
              ),
              const MarketplaceTemplate(
                id: 'food-delivery-pro',
                title: 'FoodDelivery Pro - On-Demand Tracking',
                author: 'Elena Rostova (@elena_codes)',
                category: 'E-Commerce',
                description:
                    'Marketplace de delivery com catálogo de restaurantes, carrinho interativo, cálculo de frete, pagamento Pix/Cartão e acompanhamento de rota via GPS.',
                priceUsd: 39.0,
                rating: 4.8,
                reviewsCount: 97,
                downloadsCount: 1150,
                screensCount: 18,
                preset: PresetType.cleanLite,
                navigationStyle: NavigationStyle.tabs,
                tags: ['Delivery', 'GPS', 'Cart', 'BLoC', 'Orders'],
                features: [
                  '18 Telas modernas com fluxo de compra completo',
                  'Carrinho de compras reativo com persistência local',
                  'Rastreamento em tempo real do entregador no mapa',
                  'Arquitetura Clean-Lite com BLoC 8.x e injeção GetIt',
                  'Suporte a cupons de desconto e taxa de entrega dinâmica',
                ],
                accentColor: Color(0xFFF59E0B),
                icon: Icons.delivery_dining_rounded,
                manifest: TemplateManifestContext(
                  designSystem: 'Obsidian Warm Dark • Amber Accent (#F59E0B)',
                  stateManagement: 'BLoC 8.x + Dio HTTP + GetIt DI',
                  routingPattern: 'GoRouter com rotas aninhadas de pedido',
                  screenNames: [
                    'RestaurantCatalogScreen',
                    'DishDetailsScreen',
                    'CartCheckoutScreen',
                    'OrderTrackingScreen',
                    'PaymentSelectionScreen',
                    'OrderHistoryScreen'
                  ],
                  aiPromptRules:
                      'Novas telas de delivery devem seguir o padrão BLoC (Event/State), tratando estados de Loading, Success e Error com snackbars Obsidian.',
                ),
              ),
              const MarketplaceTemplate(
                id: 'offline-vault',
                title: 'OfflineVault - Encrypted Notes & Passwords',
                author: 'Marco Rossi (@marco_dev)',
                category: 'Offline',
                description:
                    'Cofre seguro e ultrarrápido que funciona 100% offline sem conexão à internet. Notas com criptografia AES-256, gerador de senhas e biometria.',
                priceUsd: 0.0,
                rating: 4.9,
                reviewsCount: 125,
                downloadsCount: 3200,
                screensCount: 9,
                preset: PresetType.offline,
                navigationStyle: NavigationStyle.drawer,
                tags: ['Offline', 'SQLite', 'Encryption', 'Security', 'Free'],
                features: [
                  '100% Gratuito da comunidade para uso pessoal ou comercial',
                  'Banco de dados local ultrarrápido com SQLite / Drift',
                  'Criptografia de ponta a ponta sem tráfego de rede',
                  'Desbloqueio com impressão digital ou PIN mestre',
                  'Exportação e importação de backup seguro em arquivo',
                ],
                accentColor: Color(0xFF38BDF8),
                icon: Icons.shield_rounded,
                manifest: TemplateManifestContext(
                  designSystem: 'Obsidian Minimalist • Cyber Cyan (#38BDF8)',
                  stateManagement: 'Provider + DatabaseHelper SQLite',
                  routingPattern: 'Rotas declarativas com autenticação offline',
                  screenNames: [
                    'PinLockScreen',
                    'NotesListScreen',
                    'NoteEditorScreen',
                    'PasswordVaultScreen',
                    'PasswordGeneratorScreen',
                    'BackupExportScreen'
                  ],
                  aiPromptRules:
                      'Mantenha a filosofia offline-first: nunca adicione dependências de rede sem consentimento. O armazenamento deve ser estritamente no SQLite local.',
                ),
              ),
              const MarketplaceTemplate(
                id: 'fitpulse-ai',
                title: 'FitPulse - Workout & Diet AI Coach',
                author: 'Juliana Mendes (@ju_flutter)',
                category: 'Saúde & AI',
                description:
                    'Aplicativo de treino físico e acompanhamento nutricional com coach integrado via Gemini AI, cronômetro de descanso e gráficos de performance.',
                priceUsd: 29.0,
                rating: 4.9,
                reviewsCount: 78,
                downloadsCount: 890,
                screensCount: 14,
                preset: PresetType.saas,
                navigationStyle: NavigationStyle.tabs,
                tags: ['Health', 'Fitness', 'Gemini AI', 'Charts', 'Timer'],
                features: [
                  '14 Telas com visual fitness escuro de alta energia',
                  'Coach de treinos alimentado por Gemini AI integrada',
                  'Cronômetro de descanso entre séries com avisos sonoros',
                  'Gráficos de evolução corporal e contagem de macros',
                  'Planilhas de treino customizáveis por grupo muscular',
                ],
                accentColor: Color(0xFFEC4899),
                icon: Icons.fitness_center_rounded,
                manifest: TemplateManifestContext(
                  designSystem: 'Obsidian Sport Dark • Pink Neon Accent (#EC4899)',
                  stateManagement: 'Riverpod 2.5 + StateNotifier',
                  routingPattern: 'GoRouter com Bottom Navigation Tabs',
                  screenNames: [
                    'WorkoutDashboardScreen',
                    'ExerciseListScreen',
                    'ActiveWorkoutScreen',
                    'AiDietCoachScreen',
                    'MacroTrackerScreen',
                    'BodyProgressScreen'
                  ],
                  aiPromptRules:
                      'Telas fitness devem incluir feedback tátil/haptic em ações de treino e gráficos bem destacados com kaTex ou bibliotecas declarativas.',
                ),
              ),
            ],
          ),
        );

  void setCategory(String category) {
    state = state.copyWith(selectedCategory: category);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setInspectingTemplate(String? id) {
    state = state.copyWith(inspectingTemplateId: id);
  }
}

final marketplaceProvider =
    StateNotifierProvider<MarketplaceNotifier, MarketplaceState>((ref) {
  return MarketplaceNotifier();
});
