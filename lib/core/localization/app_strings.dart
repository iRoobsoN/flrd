enum AppLanguage {
  pt('Português (BR)', 'pt', '🇧🇷'),
  en('English (US)', 'en', '🇺🇸'),
  es('Español', 'es', '🇪🇸');

  final String label;
  final String code;
  final String flag;
  const AppLanguage(this.label, this.code, this.flag);
}

class AppStrings {
  final AppLanguage language;
  const AppStrings(this.language);

  // Hub Screen Strings
  String get hubTitle => switch (language) {
    AppLanguage.pt => 'FLRD Studio',
    AppLanguage.en => 'FLRD Studio',
    AppLanguage.es => 'FLRD Studio',
  };

  String get hubTagline => switch (language) {
    AppLanguage.pt => 'Acelerador e Gerenciador de Apps Flutter de Alta Performance',
    AppLanguage.en => 'High-Performance Flutter App Accelerator & Manager',
    AppLanguage.es => 'Acelerador y Gestor de Apps Flutter de Alto Rendimiento',
  };

  String get engineStatus => switch (language) {
    AppLanguage.pt => 'Engine Pronta',
    AppLanguage.en => 'Engine Ready',
    AppLanguage.es => 'Motor Listo',
  };

  String get newProjectTitle => switch (language) {
    AppLanguage.pt => 'Criar Novo Projeto',
    AppLanguage.en => 'Create New Project',
    AppLanguage.es => 'Crear Nuevo Proyecto',
  };

  String get newProjectDesc => switch (language) {
    AppLanguage.pt =>
      'Inicie um app do zero com arquitetura curada (SaaS, Clean-Lite ou Offline), injeção semântica e rotas blindadas.',
    AppLanguage.en =>
      'Start an app from scratch with curated architectures (SaaS, Clean-Lite, Offline), semantic AST injection, and robust routing.',
    AppLanguage.es =>
      'Inicie una app desde cero con arquitectura curada (SaaS, Clean-Lite u Offline), inyección semántica y rutas seguras.',
  };

  String get myProjectsTitle => switch (language) {
    AppLanguage.pt => 'Meus Projetos',
    AppLanguage.en => 'My Projects',
    AppLanguage.es => 'Mis Proyectos',
  };

  String get myProjectsDesc => switch (language) {
    AppLanguage.pt =>
      'Gerencie, inspecione e edite os aplicativos existentes reconhecidos no seu computador.',
    AppLanguage.en =>
      'Manage, inspect, and edit existing Flutter applications detected on your machine.',
    AppLanguage.es =>
      'Gestione, inspeccione y edite las aplicaciones Flutter existentes detectadas en su equipo.',
  };

  String get marketplaceTitle => switch (language) {
    AppLanguage.pt => 'Marketplace de Templates',
    AppLanguage.en => 'Template Marketplace',
    AppLanguage.es => 'Mercado de Plantillas',
  };

  String get marketplaceDesc => switch (language) {
    AppLanguage.pt =>
      'Explore templates prontos da comunidade ou venda os seus em USD com split de 75% via Stripe.',
    AppLanguage.en =>
      'Explore community templates or sell yours in USD with 75% automated split via Stripe.',
    AppLanguage.es =>
      'Explore plantillas de la comunidad o venda las suyas en USD con división del 75% vía Stripe.',
  };

  String get docsTitle => switch (language) {
    AppLanguage.pt => 'Documentação',
    AppLanguage.en => 'Architecture Docs',
    AppLanguage.es => 'Documentación',
  };

  String get docsDesc => switch (language) {
    AppLanguage.pt =>
      'Explore os 5 pilares anti-obsolescência, diagramas Mermaid e guias.',
    AppLanguage.en =>
      'Explore the 5 anti-obsolescence pillars, Mermaid diagrams, and guides.',
    AppLanguage.es =>
      'Explore los 5 pilares anti-obsolescencia, diagramas Mermaid y guías.',
  };

  String get recentProjects => switch (language) {
    AppLanguage.pt => 'Projetos Reconhecidos na Máquina',
    AppLanguage.en => 'Recognized Projects on Machine',
    AppLanguage.es => 'Proyectos Reconocidos en el Equipo',
  };

  String get scanProjects => switch (language) {
    AppLanguage.pt => 'Escanear Pastas',
    AppLanguage.en => 'Scan Directories',
    AppLanguage.es => 'Escanear Carpetas',
  };

  String get importProject => switch (language) {
    AppLanguage.pt => 'Importar Projeto',
    AppLanguage.en => 'Import Project',
    AppLanguage.es => 'Importar Proyecto',
  };

  String get noProjectsTitle => switch (language) {
    AppLanguage.pt => 'Nenhum projeto cadastrado no momento',
    AppLanguage.en => 'No registered projects yet',
    AppLanguage.es => 'Ningún proyecto registrado por el momento',
  };

  String get noProjectsSubtitle => switch (language) {
    AppLanguage.pt =>
      'Clique em "Criar Novo Projeto" para usar o assistente inteligente ou escaneie um diretório com projetos Flutter.',
    AppLanguage.en =>
      'Click "Create New Project" to launch the smart wizard, or scan a directory containing Flutter projects.',
    AppLanguage.es =>
      'Haga clic en "Crear Nuevo Proyecto" para usar el asistente inteligente o escanee un directorio con proyectos Flutter.',
  };

  String get quickActions => switch (language) {
    AppLanguage.pt => 'Ações Rápidas',
    AppLanguage.en => 'Quick Actions',
    AppLanguage.es => 'Acciones Rápidas',
  };

  String get openVsCode => switch (language) {
    AppLanguage.pt => 'Abrir no VS Code',
    AppLanguage.en => 'Open in VS Code',
    AppLanguage.es => 'Abrir en VS Code',
  };

  String get openFolder => switch (language) {
    AppLanguage.pt => 'Abrir Pasta',
    AppLanguage.en => 'Open Folder',
    AppLanguage.es => 'Abrir Carpeta',
  };

  String get editApp => switch (language) {
    AppLanguage.pt => 'Editar / Injetar',
    AppLanguage.en => 'Edit / Inject',
    AppLanguage.es => 'Editar / Inyectar',
  };

  String get runCliHelp => switch (language) {
    AppLanguage.pt => 'CLI Nativa Disponível',
    AppLanguage.en => 'Native CLI Available',
    AppLanguage.es => 'CLI Nativa Disponible',
  };

  String get runCliDesc => switch (language) {
    AppLanguage.pt => 'Você também pode executar diretamente no terminal: dart run bin/flrd.dart',
    AppLanguage.en => 'You can also run directly in your terminal: dart run bin/flrd.dart',
    AppLanguage.es => 'También puede ejecutar directamente en la terminal: dart run bin/flrd.dart',
  };

  String get backToHub => switch (language) {
    AppLanguage.pt => '← Voltar ao Hub',
    AppLanguage.en => '← Back to Hub',
    AppLanguage.es => '← Volver al Hub',
  };

  String get configurationSteps => switch (language) {
    AppLanguage.pt => 'ETAPAS DE CONFIGURAÇÃO',
    AppLanguage.en => 'CONFIGURATION STEPS',
    AppLanguage.es => 'PASOS DE CONFIGURACIÓN',
  };

  String get sponsorBannerText => switch (language) {
    AppLanguage.pt => 'Gostou do FLRD? Apoie!',
    AppLanguage.en => 'Love FLRD? Support it!',
    AppLanguage.es => '¿Te gusta FLRD? ¡Apóyalo!',
  };

  String get starButton => switch (language) {
    AppLanguage.pt => 'Star',
    AppLanguage.en => 'Star',
    AppLanguage.es => 'Star',
  };

  String get donateButton => switch (language) {
    AppLanguage.pt => 'Apoiar',
    AppLanguage.en => 'Donate',
    AppLanguage.es => 'Apoyar',
  };

  String get languageSelectorLabel => switch (language) {
    AppLanguage.pt => 'Idioma',
    AppLanguage.en => 'Language',
    AppLanguage.es => 'Idioma',
  };

  String get hubStatsPillar1 => switch (language) {
    AppLanguage.pt => '3 Pilares de Arquitetura',
    AppLanguage.en => '3 Curated Stacks',
    AppLanguage.es => '3 Pilares de Arquitectura',
  };

  String get hubStatsPillar2 => switch (language) {
    AppLanguage.pt => 'Injetor Semântico AST',
    AppLanguage.en => 'Semantic AST Injector',
    AppLanguage.es => 'Inyector Semántico AST',
  };

  String get hubStatsPillar3 => switch (language) {
    AppLanguage.pt => 'Anti-Obsolescência',
    AppLanguage.en => 'Zero Obsolescence',
    AppLanguage.es => 'Anti-Obsolescencia',
  };

  String get settingsAndBilling => switch (language) {
    AppLanguage.pt => 'Configurações & Faturamento',
    AppLanguage.en => 'Settings & Billing',
    AppLanguage.es => 'Configuración y Facturación',
  };

  String get flutterSdkChecking => switch (language) {
    AppLanguage.pt => 'Checando Flutter...',
    AppLanguage.en => 'Checking Flutter...',
    AppLanguage.es => 'Comprobando Flutter...',
  };

  String get flutterSdkMissing => switch (language) {
    AppLanguage.pt => 'Flutter Ausente',
    AppLanguage.en => 'Flutter Missing',
    AppLanguage.es => 'Flutter Ausente',
  };

  String get flutterSdkReady => switch (language) {
    AppLanguage.pt => 'Flutter Pronto',
    AppLanguage.en => 'Flutter Ready',
    AppLanguage.es => 'Flutter Listo',
  };

  String get flutterSdkDialogTitle => switch (language) {
    AppLanguage.pt => 'Ambiente do Flutter SDK',
    AppLanguage.en => 'Flutter SDK Environment',
    AppLanguage.es => 'Entorno del Flutter SDK',
  };

  String get downloadFlutter => switch (language) {
    AppLanguage.pt => 'Baixar Flutter SDK (Oficial)',
    AppLanguage.en => 'Download Flutter SDK (Official)',
    AppLanguage.es => 'Descargar Flutter SDK (Oficial)',
  };

  String get recheckSdk => switch (language) {
    AppLanguage.pt => 'Verificar Novamente',
    AppLanguage.en => 'Re-check System',
    AppLanguage.es => 'Verificar Nuevamente',
  };

  String get missingSdkBannerTitle => switch (language) {
    AppLanguage.pt => 'Flutter SDK não detectado no sistema',
    AppLanguage.en => 'Flutter SDK not found on system',
    AppLanguage.es => 'Flutter SDK no encontrado en el sistema',
  };

  String get missingSdkBannerDesc => switch (language) {
    AppLanguage.pt =>
      'O FLRD requer o Flutter SDK instalado no PATH para compilar e gerar projetos reais no disco. Você pode explorar os templates e o estúdio, mas precisará do SDK para construir novos apps.',
    AppLanguage.en =>
      'FLRD requires the Flutter SDK in your system PATH to generate and compile real projects on disk. You can explore templates and the studio, but will need the SDK to build new apps.',
    AppLanguage.es =>
      'FLRD requiere el Flutter SDK en el PATH para compilar y generar proyectos reales en el disco. Puedes explorar plantillas y el estudio, pero necesitarás el SDK para crear nuevas apps.',
  };

  String get missingSdkBannerCta => switch (language) {
    AppLanguage.pt => 'Configurar Flutter SDK',
    AppLanguage.en => 'Setup Flutter SDK',
    AppLanguage.es => 'Configurar Flutter SDK',
  };

  // FLRD Doctor Strings
  String get doctorTitle => switch (language) {
    AppLanguage.pt => 'FLRD Doctor - Diagnóstico do Sistema',
    AppLanguage.en => 'FLRD Doctor - System Diagnostics',
    AppLanguage.es => 'FLRD Doctor - Diagnóstico del Sistema',
  };

  String get doctorHealthScore => switch (language) {
    AppLanguage.pt => 'Saúde do Ambiente',
    AppLanguage.en => 'Environment Health',
    AppLanguage.es => 'Salud del Entorno',
  };

  String get doctorRescan => switch (language) {
    AppLanguage.pt => 'Re-escanear Agora',
    AppLanguage.en => 'Rescan Now',
    AppLanguage.es => 'Reescanear Ahora',
  };

  String get doctorCopyCommand => switch (language) {
    AppLanguage.pt => 'Copiar Comando',
    AppLanguage.en => 'Copy Command',
    AppLanguage.es => 'Copiar Comando',
  };

  String get doctorCopied => switch (language) {
    AppLanguage.pt => 'Comando copiado para a área de transferência!',
    AppLanguage.en => 'Command copied to clipboard!',
    AppLanguage.es => '¡Comando copiado al portapapeles!',
  };

  String get doctorDownload => switch (language) {
    AppLanguage.pt => 'Baixar / Documentação',
    AppLanguage.en => 'Download / Docs',
    AppLanguage.es => 'Descargar / Documentación',
  };

  String get doctorAllGreen => switch (language) {
    AppLanguage.pt => 'Todos os componentes estão prontos e saudáveis!',
    AppLanguage.en => 'All components are ready and healthy!',
    AppLanguage.es => '¡Todos los componentes están listos y saludables!',
  };

  String get doctorIssuesFound => switch (language) {
    AppLanguage.pt => 'Atenção necessária em alguns componentes do sistema.',
    AppLanguage.en => 'Action required on some system components.',
    AppLanguage.es => 'Atención requerida en algunos componentes del sistema.',
  };

  // Studio Inspector Tabs
  String get routeDetailsTab => switch (language) {
    AppLanguage.pt => 'Detalhes',
    AppLanguage.en => 'Details',
    AppLanguage.es => 'Detalles',
  };

  String get viewCodeTab => switch (language) {
    AppLanguage.pt => 'Código',
    AppLanguage.en => 'Code',
    AppLanguage.es => 'Código',
  };

  String get emulateScreenTab => switch (language) {
    AppLanguage.pt => 'Emular',
    AppLanguage.en => 'Emulate',
    AppLanguage.es => 'Emular',
  };
}
