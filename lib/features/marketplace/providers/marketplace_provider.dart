import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../wizard/models/project_config.dart';
import '../models/marketplace_template.dart';
import '../models/template_submission.dart';

class MarketplaceState {
  final List<MarketplaceTemplate> templates;
  final String selectedCategory;
  final String searchQuery;
  final String? inspectingTemplateId;

  const MarketplaceState({
    required this.templates,
    this.selectedCategory = 'All',
    this.searchQuery = '',
    this.inspectingTemplateId,
  });

  List<MarketplaceTemplate> get filteredTemplates {
    return templates.where((template) {
      final matchesCategory = selectedCategory == 'All' ||
          selectedCategory == 'Todos' ||
          ((selectedCategory == 'Free' || selectedCategory == 'Gratuitos') && template.isFree) ||
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
                    'Complete banking application with hideable balance, QR code instant transfers, cryptocurrency portfolio with charts, biometric authentication, and detailed statements.',
                priceUsd: 49.0,
                rating: 4.9,
                reviewsCount: 184,
                downloadsCount: 2410,
                screensCount: 16,
                preset: PresetType.saas,
                navigationStyle: NavigationStyle.tabs,
                tags: ['Fintech', 'Crypto', 'Pix', 'Biometrics', 'Charts', 'Supabase'],
                features: [
                  '16 Complete production-ready screens',
                  'Native biometrics integration (Face ID / Fingerprint)',
                  'Instant transfers module with QR Code scanner',
                  'Real-time crypto portfolio tracker with charts',
                  'Obsidian Glass Dark Design System with centralized tokens',
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
                    'Official FLRD starter kit for modern SaaS platforms: Supabase Auth ready, multi-tenant workspace switcher, pricing tiers, and real-time analytical dashboard.',
                priceUsd: 0.0,
                rating: 5.0,
                reviewsCount: 310,
                downloadsCount: 5820,
                screensCount: 12,
                preset: PresetType.saas,
                navigationStyle: NavigationStyle.adaptiveRail,
                tags: ['SaaS', 'Supabase', 'Multi-tenant', 'Analytics', 'Official'],
                features: [
                  '100% Free & Open Source under MIT license',
                  'Full Supabase Auth integration (Email + Magic Link)',
                  'Multi-tenant support with dynamic organization switcher',
                  'Adaptive navigation: Bottom bar on mobile, Navigation Rail on Desktop',
                  'Stripe billing integration ready',
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
                    'On-demand food delivery marketplace with restaurant catalog, reactive cart, shipping calculation, Stripe/Card payments, and live GPS route tracking.',
                priceUsd: 39.0,
                rating: 4.8,
                reviewsCount: 97,
                downloadsCount: 1150,
                screensCount: 18,
                preset: PresetType.cleanLite,
                navigationStyle: NavigationStyle.tabs,
                tags: ['Delivery', 'GPS', 'Cart', 'BLoC', 'Orders'],
                features: [
                  '18 Modern screens with full checkout lifecycle',
                  'Reactive shopping cart with offline local persistence',
                  'Live real-time courier tracking on map',
                  'Clean-Lite architecture with BLoC 8.x & GetIt DI',
                  'Discount coupons and dynamic delivery fee calculation',
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
                    'Ultra-fast secure vault that works 100% offline without internet connection. AES-256 encrypted notes, password generator, and biometric unlock.',
                priceUsd: 0.0,
                rating: 4.9,
                reviewsCount: 125,
                downloadsCount: 3200,
                screensCount: 9,
                preset: PresetType.offline,
                navigationStyle: NavigationStyle.drawer,
                tags: ['Offline', 'SQLite', 'Encryption', 'Security', 'Free'],
                features: [
                  '100% Free community template for personal and commercial use',
                  'High-speed local database powered by SQLite / Drift',
                  'End-to-end zero-knowledge client encryption with no telemetry',
                  'Biometric fingerprint unlock or master PIN',
                  'Secure backup export and import in encrypted files',
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
                category: 'Health & AI',
                description:
                    'Workout routines and nutrition tracking app with integrated Gemini AI coach, interval resting timer, and interactive progress graphs.',
                priceUsd: 29.0,
                rating: 4.9,
                reviewsCount: 78,
                downloadsCount: 890,
                screensCount: 14,
                preset: PresetType.saas,
                navigationStyle: NavigationStyle.tabs,
                tags: ['Health', 'Fitness', 'Gemini AI', 'Charts', 'Timer'],
                features: [
                  '14 High-energy dark fitness screens',
                  'AI workout recommendations powered by Gemini API',
                  'Rest interval timer between sets with audio alerts',
                  'Body composition charts and macro nutrient tracking',
                  'Customizable workout plan split by muscle groups',
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

final marketplaceKnownFingerprintsProvider =
    Provider<List<TemplateFingerprint>>((ref) {
  return [
    const TemplateFingerprint(
      templateId: 'NovaBank - Fintech & Crypto MVP',
      classDeclarations: {
        'NovaBankApp',
        'HomeScreen',
        'TransactionDetailsScreen',
        'TransferPixScreen',
        'CryptoPortfolioScreen',
        'CardManagementScreen',
        'BiometricLockService',
      },
      widgetDeclarations: {
        'BalanceCardWidget',
        'QuickPixActionGrid',
        'TransactionListItem',
        'CryptoTickerPill',
      },
      routePaths: {'/home', '/pix', '/crypto', '/cards', '/statement'},
      relativeFilePaths: {
        'lib/main.dart',
        'lib/features/home/home_screen.dart',
        'lib/features/pix/pix_screen.dart',
        'lib/features/crypto/crypto_screen.dart',
      },
    ),
    const TemplateFingerprint(
      templateId: 'SaaSHero - B2B Subscription Boilerplate',
      classDeclarations: {
        'SaaSHeroApp',
        'AnalyticsDashboardScreen',
        'SubscriptionPlansScreen',
        'TeamMembersScreen',
        'BillingHistoryScreen',
        'StripeCheckoutBridge',
      },
      widgetDeclarations: {
        'MetricsKpiCard',
        'PricingPlanCard',
        'MemberRoleRow',
        'InvoiceDownloadPill',
      },
      routePaths: {'/dashboard', '/plans', '/team', '/billing', '/settings'},
      relativeFilePaths: {
        'lib/main.dart',
        'lib/features/dashboard/dashboard_screen.dart',
        'lib/features/billing/plans_screen.dart',
      },
    ),
    const TemplateFingerprint(
      templateId: 'FoodDelivery Pro - Multi-restaurant Logistics',
      classDeclarations: {
        'FoodApp',
        'RestaurantListScreen',
        'DishDetailsScreen',
        'CartCheckoutScreen',
        'LiveDriverTrackingScreen',
        'OrderNotifier',
      },
      widgetDeclarations: {
        'RestaurantHeroCard',
        'CartItemRow',
        'LiveGpsTrackerMap',
        'EstimatedDeliveryPill',
      },
      routePaths: {'/feed', '/restaurant', '/cart', '/tracking'},
      relativeFilePaths: {
        'lib/main.dart',
        'lib/features/feed/feed_screen.dart',
        'lib/features/checkout/cart_screen.dart',
      },
    ),
    const TemplateFingerprint(
      templateId: 'OfflineVault - Encrypted Local Storage',
      classDeclarations: {
        'OfflineVaultApp',
        'VaultHomeScreen',
        'SecureNoteEditorScreen',
        'CategoryManagerScreen',
        'BackupRestoreScreen',
        'SqlCipherDatabaseHelper',
      },
      widgetDeclarations: {
        'EncryptedNoteCard',
        'CategoryChipList',
        'PasswordStrengthMeter',
      },
      routePaths: {'/vault', '/editor', '/categories', '/backup'},
      relativeFilePaths: {
        'lib/main.dart',
        'lib/features/vault/vault_screen.dart',
        'lib/features/editor/editor_screen.dart',
      },
    ),
    const TemplateFingerprint(
      templateId: 'FitPulse - AI Fitness & Workout Tracker',
      classDeclarations: {
        'FitPulseApp',
        'WorkoutDashboardScreen',
        'ExerciseListScreen',
        'ActiveWorkoutScreen',
        'AiDietCoachScreen',
        'MacroTrackerScreen',
        'BodyProgressScreen',
      },
      widgetDeclarations: {
        'WorkoutTimerWidget',
        'MacroProgressBar',
        'ExerciseSetRow',
        'AiCoachInsightPill',
      },
      routePaths: {'/workout', '/exercises', '/coach', '/macros', '/progress'},
      relativeFilePaths: {
        'lib/main.dart',
        'lib/features/workout/dashboard_screen.dart',
        'lib/features/coach/ai_coach_screen.dart',
      },
    ),
  ];
});
