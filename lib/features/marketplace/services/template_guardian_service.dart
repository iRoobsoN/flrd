import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/template_submission.dart';

class TemplateGuardianService {
  static const double maxAllowedSimilarity = 0.70; // 70% max similarity to prevent clones

  /// Validates that the requested price meets or exceeds the mandatory category floor
  bool isPriceFloorValid({required TemplateTier tier, required double priceUsd}) {
    if (priceUsd == 0.0) return true; // Free community templates are permitted
    return priceUsd >= tier.minimumPriceUsd;
  }

  /// Audits project files for leaked secrets, .env files, private keys and tokens
  Future<SecurityAuditResult> auditSecurity(Directory projectDir) async {
    final flaggedFiles = <String>[];
    final findings = <String>[];

    if (!await projectDir.exists()) {
      return const SecurityAuditResult(
        hasLeakedSecrets: false,
        flaggedFiles: [],
        findings: ['Diretório do projeto não encontrado.'],
      );
    }

    final forbiddenFilenames = [
      '.env',
      '.env.local',
      '.env.production',
      '.env.development',
      'id_rsa',
      'id_rsa.pub',
      'key.properties',
    ];

    final forbiddenExtensions = ['.pem', '.keystore', '.jks', '.p12'];

    final secretRegexes = [
      RegExp(r'AIza[0-9A-Za-z\-_]{30,45}'), // Google API Key
      RegExp(r'sk_live_[0-9a-zA-Z]{20,}'), // Stripe Live Key
      RegExp(r'ghp_[0-9a-zA-Z]{30,}'), // GitHub Personal Access Token
      RegExp(r'-----BEGIN (RSA )?PRIVATE KEY-----'), // Private Key Block
    ];

    try {
      await for (final entity in projectDir.list(recursive: true, followLinks: false)) {
        final path = entity.path;
        if (path.contains('.dart_tool') ||
            path.contains('.git') ||
            path.contains('build') ||
            path.contains('.idea')) {
          continue;
        }

        if (entity is File) {
          final filename = p.basename(entity.path).toLowerCase();
          final ext = p.extension(entity.path).toLowerCase();

          if (forbiddenFilenames.contains(filename) || forbiddenExtensions.contains(ext)) {
            flaggedFiles.add(p.relative(entity.path, from: projectDir.path));
            findings.add('Arquivo sensível não permitido encontrado: $filename');
          }

          // Scan Dart and Yaml files for hardcoded secrets
          if (ext == '.dart' || ext == '.yaml' || ext == '.json') {
            try {
              final content = await entity.readAsString();
              for (final regex in secretRegexes) {
                if (regex.hasMatch(content)) {
                  final rel = p.relative(entity.path, from: projectDir.path);
                  if (!flaggedFiles.contains(rel)) {
                    flaggedFiles.add(rel);
                  }
                  findings.add('Potencial chave privada ou token detectado em: $rel');
                  break;
                }
              }
            } catch (_) {
              // Ignore binary or unreadable files
            }
          }
        }
      }
    } catch (e) {
      findings.add('Erro ao escanear diretório: $e');
    }

    return SecurityAuditResult(
      hasLeakedSecrets: flaggedFiles.isNotEmpty,
      flaggedFiles: flaggedFiles,
      findings: findings,
    );
  }

  /// Extracts structural AST declarations from Dart files to form a fingerprint
  Future<TemplateFingerprint> generateFingerprint(
    Directory projectDir, {
    String templateId = 'candidate',
  }) async {
    final classes = <String>{};
    final widgets = <String>{};
    final routes = <String>{};
    final relativePaths = <String>{};

    final libDir = Directory(p.join(projectDir.path, 'lib'));
    if (!await libDir.exists()) {
      return TemplateFingerprint(
        templateId: templateId,
        classDeclarations: classes,
        widgetDeclarations: widgets,
        routePaths: routes,
        relativeFilePaths: relativePaths,
      );
    }

    final classRegex = RegExp(r'class\s+([A-Za-z0-9_]+)\s*(?:extends|implements|with)?');
    final widgetRegex = RegExp(r'class\s+([A-Za-z0-9_]+)\s+extends\s+(?:StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget)');
    final routeRegex = RegExp(r"path:\s*['\x22](/[A-Za-z0-9_\-/]*)['\x22]");

    try {
      await for (final entity in libDir.list(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final relPath = p.relative(entity.path, from: projectDir.path);
          relativePaths.add(relPath);

          try {
            final content = await entity.readAsString();

            for (final match in classRegex.allMatches(content)) {
              if (match.group(1) != null) classes.add(match.group(1)!);
            }

            for (final match in widgetRegex.allMatches(content)) {
              if (match.group(1) != null) widgets.add(match.group(1)!);
            }

            for (final match in routeRegex.allMatches(content)) {
              if (match.group(1) != null) routes.add(match.group(1)!);
            }
          } catch (_) {
            // Ignore unreadable files
          }
        }
      }
    } catch (_) {}

    return TemplateFingerprint(
      templateId: templateId,
      classDeclarations: classes,
      widgetDeclarations: widgets,
      routePaths: routes,
      relativeFilePaths: relativePaths,
    );
  }

  /// Checks candidate fingerprint against known catalog templates for unauthorized clone attempts
  ({bool isOriginal, double highestSimilarity, String? matchedTemplateId}) checkOriginality({
    required TemplateFingerprint candidate,
    required List<TemplateFingerprint> knownTemplates,
    double threshold = maxAllowedSimilarity,
  }) {
    double highestSim = 0.0;
    String? matchedId;

    for (final known in knownTemplates) {
      if (known.templateId == candidate.templateId) continue;
      final sim = candidate.computeSimilarity(known);
      if (sim > highestSim) {
        highestSim = sim;
        matchedId = known.templateId;
      }
    }

    final isOriginal = highestSim <= threshold;
    return (
      isOriginal: isOriginal,
      highestSimilarity: highestSim,
      matchedTemplateId: matchedId,
    );
  }

  /// Comprehensive submission validation pipeline
  Future<SubmissionValidationResult> validateSubmission({
    required TemplateSubmissionData submission,
    required List<TemplateFingerprint> knownTemplates,
    Directory? projectDir,
  }) async {
    final errors = <String>[];
    final warnings = <String>[];

    // 1. Price Floor Check
    final isPriceFloorMet = isPriceFloorValid(
      tier: submission.tier,
      priceUsd: submission.priceUsd,
    );

    if (!isPriceFloorMet) {
      errors.add(
        'O preço (\$${submission.priceUsd.toStringAsFixed(2)}) é inferior ao piso mínimo da categoria "${submission.tier.label}" (\$${submission.tier.minimumPriceUsd.toStringAsFixed(2)}). Para manter a integridade e evitar prostituição de mercado, ajuste o valor.',
      );
    }

    // 2. Security Audit
    bool securityPassed = true;
    if (projectDir != null && await projectDir.exists()) {
      final security = await auditSecurity(projectDir);
      if (!security.isClean) {
        securityPassed = false;
        errors.add('Foram encontrados arquivos ou segredos sensíveis no projeto:');
        for (final finding in security.findings) {
          errors.add(' • $finding');
        }
      }
    } else {
      warnings.add('Diretório do projeto não informado para auditoria de arquivos sensíveis.');
    }

    // 3. Originality & Anti-Plagiarism AST Check
    bool originalityPassed = true;
    double highestSimilarity = 0.0;
    String? matchedTitle;

    if (projectDir != null && await projectDir.exists()) {
      final fingerprint = await generateFingerprint(projectDir, templateId: submission.title);
      final check = checkOriginality(
        candidate: fingerprint,
        knownTemplates: knownTemplates,
      );

      highestSimilarity = check.highestSimilarity;
      matchedTitle = check.matchedTemplateId;

      if (!check.isOriginal) {
        originalityPassed = false;
        final simPercent = (highestSimilarity * 100).toStringAsFixed(1);
        errors.add(
          'Rejeitado por similaridade estrutural: O código possui $simPercent% de similaridade com o template catalogado "$matchedTitle" (limite máximo permitido: ${(maxAllowedSimilarity * 100).toInt()}%). Obras derivadas sem alteração substancial não são permitidas.',
        );
      }
    }

    final isValid = isPriceFloorMet && securityPassed && originalityPassed;

    return SubmissionValidationResult(
      isValid: isValid,
      priceFloorMet: isPriceFloorMet,
      securityPassed: securityPassed,
      originalityPassed: originalityPassed,
      similarityScore: highestSimilarity,
      matchedOriginalTemplateTitle: matchedTitle,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Synthesizes the signed .flrd/manifest.json containing ownership and commercial terms
  Map<String, dynamic> generateSignedManifest({
    required TemplateSubmissionData submission,
    required TemplateFingerprint fingerprint,
    String? checksumSha256,
  }) {
    return {
      'format_version': '1.0',
      'template_id': submission.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_'),
      'name': submission.title,
      'tier': submission.tier.name,
      'tier_label': submission.tier.label,
      'author': {
        'name': submission.authorName,
        'github_handle': submission.githubHandle,
        'payout_account': submission.payoutAccount,
        'creator_split': 0.75,
        'platform_split': 0.25,
      },
      'commercial': {
        'price_usd': submission.priceUsd,
        'currency': 'USD',
        'creator_earnings_usd': submission.creatorEarningsUsd,
        'license_type': 'FLRD_COMMERCIAL_LICENSE_V1',
        'no_resale_clause': true,
      },
      'security': {
        'checksum_sha256': checksumSha256 ?? 'sha256_placeholder',
        'registered_at': DateTime.now().toUtc().toIso8601String(),
        'fingerprint': {
          'classes_count': fingerprint.classDeclarations.length,
          'widgets_count': fingerprint.widgetDeclarations.length,
          'routes_count': fingerprint.routePaths.length,
        },
      },
    };
  }
}
