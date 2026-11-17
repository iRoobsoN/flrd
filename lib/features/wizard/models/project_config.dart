import 'package:flutter/material.dart';
export 'project_name_validator.dart';

enum NavigationStyle {
  tabs(
    title: 'Modern Tabs (Bottom Bar)',
    description: 'Bottom navigation bar with animated floating pill indicators. Ideal for mobile-first MVPs.',
    icon: Icons.tab_rounded,
  ),
  drawer(
    title: 'Navigation Drawer & Dropdown',
    description: 'Collapsible side drawer menu with clean hierarchy. Perfect for multi-feature utilities.',
    icon: Icons.menu_open_rounded,
  ),
  adaptiveRail(
    title: 'Adaptive Shell (Tabs + Rail)',
    description: 'Auto-adapts: Bottom tabs on mobile screens, elegant Navigation Rail on Desktop & Tablets.',
    icon: Icons.splitscreen_rounded,
  );

  final String title;
  final String description;
  final IconData icon;

  const NavigationStyle({
    required this.title,
    required this.description,
    required this.icon,
  });

  String get ptLabel {
    switch (this) {
      case NavigationStyle.tabs:
        return 'Abas na Base (Bottom Bar)';
      case NavigationStyle.drawer:
        return 'Menu Lateral Retrátil (Drawer)';
      case NavigationStyle.adaptiveRail:
        return 'Shell Adaptativo (Celular + Desktop)';
    }
  }

  String get useCaseHint {
    switch (this) {
      case NavigationStyle.tabs:
        return 'Ideal para apps com 3 a 5 áreas principais usadas com o polegar (redes sociais, finanças, delivery).';
      case NavigationStyle.drawer:
        return 'Indicado para apps com muitas seções, cadastros ou ferramentas internas.';
      case NavigationStyle.adaptiveRail:
        return 'Indicado se o app vai rodar tanto no celular quanto no Windows, Web ou tablets.';
    }
  }
}

enum PresetType {
  saas(
    name: 'SaaS / Indie Hacker',
    tagline: 'Riverpod + GoRouter + Supabase + UI Moderna',
    friendlySubtitle: 'Apps Conectados na Nuvem, Login & Assinaturas',
    badgeLabel: 'Mais Popular • Nuvem & Auth',
    plainExplanation:
        'Estrutura pronta para aplicativos online com cadastro/login de usuários, banco de dados na nuvem (Supabase) e atualização reativa de telas.',
    idealFor:
        'Quem quer lançar um produto digital rápido sem precisar construir servidor próprio do zero.',
    appExamples: [
      'Delivery, loja ou marketplace local',
      'SaaS de gestão, CRM ou agendamentos',
      'Comunidade, cursos ou área de membros',
      'App por assinatura com perfil e painel online',
    ],
    generatedPackages: [
      'flutter_riverpod',
      'go_router',
      'supabase_flutter',
      'google_fonts',
    ],
    technicalHighlights: [
      'Gerenciamento reativo com Riverpod',
      'Rotas protegidas por login (Auth Guards)',
      'Integração pronta com Supabase Auth/DB',
      'Tema claro e escuro configurado',
    ],
    icon: Icons.rocket_launch_rounded,
  ),
  cleanLite(
    name: 'Clean-Lite Scalable',
    tagline: 'BLoC + Dio + GetIt + Pastas por Funcionalidade',
    friendlySubtitle: 'Apps Corporativos, Fintechs & APIs Próprias',
    badgeLabel: 'Escalável • API REST Própria',
    plainExplanation:
        'Arquitetura em camadas separadas (feature-first), cliente HTTP profissional (Dio) e BLoC. Ideal quando o app cresce em time ou consome um backend próprio.',
    idealFor:
        'Projetos médios/grandes ou empresas com API REST própria (Node, Java, Python, Go, .NET).',
    appExamples: [
      'Banco digital, fintech ou carteira Pix',
      'E-commerce ligado a sistema/API própria',
      'Portal corporativo, ERP móvel ou logística',
      'App médico, telemedicina ou atendimento',
    ],
    generatedPackages: [
      'flutter_bloc',
      'dio',
      'get_it',
      'go_router',
      'google_fonts',
    ],
    technicalHighlights: [
      'BLoC / Cubit para estados previsíveis',
      'Cliente HTTP Dio preparado para APIs',
      'Injeção de dependências com GetIt',
      'Organização limpa por funcionalidade',
    ],
    icon: Icons.layers_rounded,
  ),
  offline(
    name: 'Offline-First Utility',
    tagline: 'SQLite (sqflite) + Provider + SharedPreferences + Material 3',
    friendlySubtitle: 'Apps Locais, Rápidos & Sem Depender de Internet',
    badgeLabel: '100% Local • Zero Latência',
    plainExplanation:
        'Salva dados diretamente no aparelho em banco SQLite local e preferências nativas. Abre instantaneamente até no modo avião e sem custo de servidor.',
    idealFor:
        'Utilitários pessoais, ferramentas de produtividade e apps que precisam funcionar sem sinal.',
    appExamples: [
      'Controle de gastos ou finanças pessoais',
      'Notas, lista de compras, diário ou tarefas',
      'App de treinos, receitas, hábitos ou estudos',
      'Coletor de estoque / checklist em campo',
    ],
    generatedPackages: [
      'sqflite',
      'shared_preferences',
      'provider',
      'path',
      'go_router',
      'google_fonts',
    ],
    technicalHighlights: [
      'Banco relacional SQLite local (sqflite)',
      'Persistência simples de ajustes do usuário',
      'Estado leve com Provider',
      'Funciona integralmente offline',
    ],
    icon: Icons.wifi_off_rounded,
  );

  final String name;
  final String tagline;
  final String friendlySubtitle;
  final String badgeLabel;
  final String plainExplanation;
  final String idealFor;
  final List<String> appExamples;
  final List<String> generatedPackages;
  final List<String> technicalHighlights;
  final IconData icon;

  const PresetType({
    required this.name,
    required this.tagline,
    required this.friendlySubtitle,
    required this.badgeLabel,
    required this.plainExplanation,
    required this.idealFor,
    required this.appExamples,
    required this.generatedPackages,
    required this.technicalHighlights,
    required this.icon,
  });
}

enum DevicePermission {
  camera(
    name: 'Camera',
    description: 'Capturing photos, video recording, or scanning QR codes.',
    androidTag: 'android.permission.CAMERA',
    iosKey: 'NSCameraUsageDescription',
    iosDefaultReason: 'This app requires camera access to scan documents or take photos.',
    icon: Icons.camera_alt_rounded,
  ),
  location(
    name: 'Location (GPS)',
    description: 'Access precise device location in foreground.',
    androidTag: 'android.permission.ACCESS_FINE_LOCATION',
    iosKey: 'NSLocationWhenInUseUsageDescription',
    iosDefaultReason: 'This app needs access to your location to provide personalized local services.',
    icon: Icons.location_on_rounded,
  ),
  notifications(
    name: 'Push Notifications',
    description: 'Send engagement notifications and transaction alerts.',
    androidTag: 'android.permission.POST_NOTIFICATIONS',
    iosKey: 'NSPushNotificationUsageDescription',
    iosDefaultReason: 'We need permission to send you critical updates and reminders.',
    icon: Icons.notifications_active_rounded,
  ),
  photoLibrary(
    name: 'Photo Gallery',
    description: 'Select existing photos and media from the user device.',
    androidTag: 'android.permission.READ_MEDIA_IMAGES',
    iosKey: 'NSPhotoLibraryUsageDescription',
    iosDefaultReason: 'This app requires access to your photo library to upload profile pictures or media.',
    icon: Icons.photo_library_rounded,
  ),
  biometrics(
    name: 'Biometrics (Face ID / Touch ID)',
    description: 'Secure authentication using hardware fingerprint or Face ID.',
    androidTag: 'android.permission.USE_BIOMETRIC',
    iosKey: 'NSFaceIDUsageDescription',
    iosDefaultReason: 'We use Face ID / Touch ID to securely authenticate you without typing a password.',
    icon: Icons.fingerprint_rounded,
  );

  final String name;
  final String description;
  final String androidTag;
  final String iosKey;
  final String iosDefaultReason;
  final IconData icon;

  const DevicePermission({
    required this.name,
    required this.description,
    required this.androidTag,
    required this.iosKey,
    required this.iosDefaultReason,
    required this.icon,
  });
}

class PlannedDependency {
  final String name;
  final String originLabel;
  final String reason;
  final bool requiredByFullTemplate;
  final bool isIncluded;
  final bool isExtra;

  const PlannedDependency({
    required this.name,
    required this.originLabel,
    required this.reason,
    required this.requiredByFullTemplate,
    required this.isIncluded,
    this.isExtra = false,
  });
}

class ProjectConfig {
  final String projectName;
  final String orgId;
  final String outputPath;
  final PresetType preset;
  final NavigationStyle navigationStyle;
  final Set<DevicePermission> permissions;
  final Color seedColor;
  final bool enableDarkTheme;
  final int androidMinSdk;
  final bool enableMultiDex;
  final String iosTarget;
  final Set<String> targetPlatforms;

  /// Advanced optional overrides configured before creation.
  final Set<String> excludedPackages;
  final List<String> extraPackages;
  final bool minimalScaffold;

  const ProjectConfig({
    this.projectName = 'my_awesome_app',
    this.orgId = 'com.example',
    this.outputPath = '',
    this.preset = PresetType.saas,
    this.navigationStyle = NavigationStyle.tabs,
    this.permissions = const {DevicePermission.notifications},
    this.seedColor = const Color(0xFF6366F1),
    this.enableDarkTheme = true,
    this.androidMinSdk = 24,
    this.enableMultiDex = true,
    this.iosTarget = '15.0',
    this.targetPlatforms = const {'android', 'ios', 'web'},
    this.excludedPackages = const {},
    this.extraPackages = const [],
    this.minimalScaffold = false,
  });

  static const Map<String, ({String reason, bool requiredByFullTemplate})>
      _packageCatalog = {
    'flutter_riverpod': (
      reason: 'Estado reativo e AuthNotifier nos arquivos iniciais do SaaS.',
      requiredByFullTemplate: true,
    ),
    'go_router': (
      reason: 'Rotas declarativas e proteção de páginas geradas em app_router.dart.',
      requiredByFullTemplate: true,
    ),
    'supabase_flutter': (
      reason: 'SDK Supabase Auth/Database (opcional se preferir Firebase ou API própria).',
      requiredByFullTemplate: false,
    ),
    'google_fonts': (
      reason: 'Tipografia PlusJakartaSans no AppTheme (se removida, usa fonte nativa M3).',
      requiredByFullTemplate: false,
    ),
    'flutter_bloc': (
      reason: 'Cubits/BLoCs gerados para autenticação no preset Clean-Lite.',
      requiredByFullTemplate: true,
    ),
    'dio': (
      reason: 'Cliente HTTP pré-configurado em core/network/dio_client.dart.',
      requiredByFullTemplate: true,
    ),
    'get_it': (
      reason: 'Localizador de serviços / DI em core/di/injection.dart.',
      requiredByFullTemplate: true,
    ),
    'sqflite': (
      reason: 'Banco SQLite local em core/database/database_helper.dart.',
      requiredByFullTemplate: true,
    ),
    'path': (
      reason: 'Resolução segura do arquivo .db no armazenamento do aparelho.',
      requiredByFullTemplate: true,
    ),
    'provider': (
      reason: 'ChangeNotifier para gerenciar lista local e tema no preset Offline.',
      requiredByFullTemplate: true,
    ),
    'shared_preferences': (
      reason: 'Armazenamento chave-valor para preferências do usuário no Offline.',
      requiredByFullTemplate: true,
    ),
    'permission_handler': (
      reason: 'Wrapper PermissionService em Dart (AndroidManifest e Info.plist continuam injetados).',
      requiredByFullTemplate: false,
    ),
  };

  /// Complete list of dependencies planned for `pubspec.yaml`, annotated with
  /// their origin, role, and whether the user opted to include/exclude each one.
  List<PlannedDependency> get plannedDependencies {
    final baseNames = <String>[
      'go_router',
      'google_fonts',
      ...switch (preset) {
        PresetType.saas => ['flutter_riverpod', 'supabase_flutter'],
        PresetType.cleanLite => ['flutter_bloc', 'dio', 'get_it'],
        PresetType.offline => ['sqflite', 'path', 'provider', 'shared_preferences'],
      },
    ];

    final seen = <String>{};
    final items = <PlannedDependency>[];

    void addEntry(String name, String originLabel, {bool isExtra = false}) {
      if (!seen.add(name)) return;
      final meta = _packageCatalog[name];
      items.add(
        PlannedDependency(
          name: name,
          originLabel: originLabel,
          reason: meta?.reason ??
              'Dependência adicional solicitada manualmente antes da criação.',
          requiredByFullTemplate: meta?.requiredByFullTemplate ?? false,
          isIncluded: isExtra || !excludedPackages.contains(name),
          isExtra: isExtra,
        ),
      );
    }

    for (final pkg in baseNames) {
      addEntry(pkg, 'Preset ${preset.name}');
    }
    if (permissions.isNotEmpty) {
      addEntry('permission_handler', 'Permissões Nativas');
    }
    for (final extra in extraPackages) {
      final clean = extra.trim().toLowerCase();
      if (clean.isNotEmpty) {
        addEntry(clean, 'Extra Avançada', isExtra: true);
      }
    }
    return items;
  }

  /// Final ordered list of external packages that `ProjectGenerator` will install.
  List<String> get resolvedPackagesToInstall => plannedDependencies
      .where((dep) => dep.isIncluded)
      .map((dep) => dep.name)
      .toList();

  /// True if the user excluded any package directly imported by the preset's
  /// full template boilerplate files.
  bool get hasMissingTemplatePackages => plannedDependencies
      .any((dep) => dep.requiredByFullTemplate && !dep.isIncluded);

  bool get shouldSynthesizeMinimalApp =>
      minimalScaffold || hasMissingTemplatePackages;

  bool get hasCustomDependencies =>
      excludedPackages.isNotEmpty || extraPackages.isNotEmpty || minimalScaffold;

  ProjectConfig copyWith({
    String? projectName,
    String? orgId,
    String? outputPath,
    PresetType? preset,
    NavigationStyle? navigationStyle,
    Set<DevicePermission>? permissions,
    Color? seedColor,
    bool? enableDarkTheme,
    int? androidMinSdk,
    bool? enableMultiDex,
    String? iosTarget,
    Set<String>? targetPlatforms,
    Set<String>? excludedPackages,
    List<String>? extraPackages,
    bool? minimalScaffold,
  }) {
    return ProjectConfig(
      projectName: projectName ?? this.projectName,
      orgId: orgId ?? this.orgId,
      outputPath: outputPath ?? this.outputPath,
      preset: preset ?? this.preset,
      navigationStyle: navigationStyle ?? this.navigationStyle,
      permissions: permissions ?? this.permissions,
      seedColor: seedColor ?? this.seedColor,
      enableDarkTheme: enableDarkTheme ?? this.enableDarkTheme,
      androidMinSdk: androidMinSdk ?? this.androidMinSdk,
      enableMultiDex: enableMultiDex ?? this.enableMultiDex,
      iosTarget: iosTarget ?? this.iosTarget,
      targetPlatforms: targetPlatforms ?? this.targetPlatforms,
      excludedPackages: excludedPackages ?? this.excludedPackages,
      extraPackages: extraPackages ?? this.extraPackages,
      minimalScaffold: minimalScaffold ?? this.minimalScaffold,
    );
  }
}
