enum TemplateTier {
  microKit(
    label: 'Micro-Módulo / Componente',
    minimumPriceUsd: 15.0,
    description: 'Componentes avançados, dashboards pontuais ou widgets complexos isolados.',
  ),
  starterKit(
    label: 'Starter Kit / MVP Base',
    minimumPriceUsd: 29.0,
    description: 'Aplicações completas com autenticação, navegação e estrutura de dados pronta.',
  ),
  fullApp(
    label: 'Full App Comercial / Enterprise',
    minimumPriceUsd: 49.0,
    description: 'Sistemas robustos de nível comercial (Fintechs, Deliveries, E-commerce, Saúde).',
  );

  final String label;
  final double minimumPriceUsd;
  final String description;

  const TemplateTier({
    required this.label,
    required this.minimumPriceUsd,
    required this.description,
  });
}

class TemplateFingerprint {
  final String templateId;
  final Set<String> classDeclarations;
  final Set<String> widgetDeclarations;
  final Set<String> routePaths;
  final Set<String> relativeFilePaths;

  const TemplateFingerprint({
    required this.templateId,
    required this.classDeclarations,
    required this.widgetDeclarations,
    required this.routePaths,
    required this.relativeFilePaths,
  });

  /// Computes the Jaccard similarity index between this fingerprint and another.
  /// J(A, B) = |A ∩ B| / |A ∪ B|
  double computeSimilarity(TemplateFingerprint other) {
    final allDeclarationsA = {...classDeclarations, ...widgetDeclarations, ...routePaths};
    final allDeclarationsB = {...other.classDeclarations, ...other.widgetDeclarations, ...other.routePaths};

    if (allDeclarationsA.isEmpty && allDeclarationsB.isEmpty) return 1.0;
    if (allDeclarationsA.isEmpty || allDeclarationsB.isEmpty) return 0.0;

    final intersection = allDeclarationsA.intersection(allDeclarationsB).length;
    final union = allDeclarationsA.union(allDeclarationsB).length;

    return union == 0 ? 0.0 : (intersection / union);
  }
}

class SecurityAuditResult {
  final bool hasLeakedSecrets;
  final List<String> flaggedFiles;
  final List<String> findings;

  const SecurityAuditResult({
    required this.hasLeakedSecrets,
    required this.flaggedFiles,
    required this.findings,
  });

  bool get isClean => !hasLeakedSecrets && flaggedFiles.isEmpty;
}

class SubmissionValidationResult {
  final bool isValid;
  final bool priceFloorMet;
  final bool securityPassed;
  final bool originalityPassed;
  final double similarityScore;
  final String? matchedOriginalTemplateTitle;
  final List<String> errors;
  final List<String> warnings;

  const SubmissionValidationResult({
    required this.isValid,
    required this.priceFloorMet,
    required this.securityPassed,
    required this.originalityPassed,
    required this.similarityScore,
    this.matchedOriginalTemplateTitle,
    required this.errors,
    required this.warnings,
  });
}

class TemplateSubmissionData {
  final String title;
  final String authorName;
  final String githubHandle;
  final String payoutAccount; // Pix or PayPal
  final TemplateTier tier;
  final double priceUsd;
  final String description;
  final String projectPath;

  const TemplateSubmissionData({
    required this.title,
    required this.authorName,
    required this.githubHandle,
    required this.payoutAccount,
    required this.tier,
    required this.priceUsd,
    required this.description,
    required this.projectPath,
  });

  double get creatorEarningsUsd => priceUsd * 0.75;
  double get platformFeeUsd => priceUsd * 0.25;
}
