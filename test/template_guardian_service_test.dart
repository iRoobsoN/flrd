import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/features/marketplace/models/template_submission.dart';
import 'package:flrd/features/marketplace/presentation/widgets/publish_template_dialog.dart';
import 'package:flrd/features/marketplace/services/template_guardian_service.dart';

void main() {
  group('TemplateGuardianService Unit Tests', () {
    late TemplateGuardianService guardian;

    setUp(() {
      guardian = TemplateGuardianService();
    });

    test('isPriceFloorValid correctly enforces category minimums', () {
      // Free templates
      expect(guardian.isPriceFloorValid(tier: TemplateTier.microKit, priceUsd: 0.0), isTrue);
      expect(guardian.isPriceFloorValid(tier: TemplateTier.starterKit, priceUsd: 0.0), isTrue);

      // MicroKit (piso: $15)
      expect(guardian.isPriceFloorValid(tier: TemplateTier.microKit, priceUsd: 14.99), isFalse);
      expect(guardian.isPriceFloorValid(tier: TemplateTier.microKit, priceUsd: 15.0), isTrue);
      expect(guardian.isPriceFloorValid(tier: TemplateTier.microKit, priceUsd: 25.0), isTrue);

      // StarterKit (piso: $29)
      expect(guardian.isPriceFloorValid(tier: TemplateTier.starterKit, priceUsd: 20.0), isFalse);
      expect(guardian.isPriceFloorValid(tier: TemplateTier.starterKit, priceUsd: 28.99), isFalse);
      expect(guardian.isPriceFloorValid(tier: TemplateTier.starterKit, priceUsd: 29.0), isTrue);
      expect(guardian.isPriceFloorValid(tier: TemplateTier.starterKit, priceUsd: 39.0), isTrue);

      // FullApp (piso: $49)
      expect(guardian.isPriceFloorValid(tier: TemplateTier.fullApp, priceUsd: 2.0), isFalse);
      expect(guardian.isPriceFloorValid(tier: TemplateTier.fullApp, priceUsd: 48.0), isFalse);
      expect(guardian.isPriceFloorValid(tier: TemplateTier.fullApp, priceUsd: 49.0), isTrue);
      expect(guardian.isPriceFloorValid(tier: TemplateTier.fullApp, priceUsd: 99.0), isTrue);
    });

    test('auditSecurity catches .env files and hardcoded API keys', () async {
      final tempDir = await Directory.systemTemp.createTemp('flrd_sec_test_');

      try {
        // Create an unauthorized .env file
        final envFile = File('${tempDir.path}/.env');
        await envFile.writeAsString('DATABASE_URL=postgres://user:pass@localhost:5432/db');

        // Create a fake dart file with a leaked Google API key
        final libDir = Directory('${tempDir.path}/lib');
        await libDir.create(recursive: true);
        final dartFile = File('${libDir.path}/config.dart');
        await dartFile.writeAsString("const apiKey = 'AIzaSyD-1234567890abcdefghijklmnopqrst';");

        final result = await guardian.auditSecurity(tempDir);

        expect(result.isClean, isFalse);
        expect(result.hasLeakedSecrets, isTrue);
        expect(result.flaggedFiles.any((f) => f.contains('.env')), isTrue);
        expect(result.flaggedFiles.any((f) => f.contains('config.dart')), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('auditSecurity passes on clean projects', () async {
      final tempDir = await Directory.systemTemp.createTemp('flrd_clean_test_');

      try {
        final libDir = Directory('${tempDir.path}/lib');
        await libDir.create(recursive: true);
        final dartFile = File('${libDir.path}/main.dart');
        await dartFile.writeAsString('void main() { print("Clean App"); }');

        final result = await guardian.auditSecurity(tempDir);

        expect(result.isClean, isTrue);
        expect(result.flaggedFiles, isEmpty);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('TemplateFingerprint computes Jaccard similarity and catches clone attempts', () {
      const original = TemplateFingerprint(
        templateId: 'OriginalFintech',
        classDeclarations: {'App', 'HomeScreen', 'PixScreen', 'CardScreen', 'SecurityHelper'},
        widgetDeclarations: {'BalanceCard', 'PixGrid', 'CardCarousel'},
        routePaths: {'/home', '/pix', '/cards'},
        relativeFilePaths: {'lib/main.dart', 'lib/home.dart'},
      );

      // Clone with only 1 class renamed (high similarity > 80%)
      const clone = TemplateFingerprint(
        templateId: 'CloneFintech',
        classDeclarations: {'App', 'HomeScreen', 'PixScreen', 'CardScreen', 'OtherHelper'},
        widgetDeclarations: {'BalanceCard', 'PixGrid', 'CardCarousel'},
        routePaths: {'/home', '/pix', '/cards'},
        relativeFilePaths: {'lib/main.dart', 'lib/home.dart'},
      );

      final similarity = clone.computeSimilarity(original);
      expect(similarity, greaterThan(0.75));

      final check = guardian.checkOriginality(
        candidate: clone,
        knownTemplates: [original],
        threshold: 0.70,
      );

      expect(check.isOriginal, isFalse);
      expect(check.matchedTemplateId, equals('OriginalFintech'));
    });

    test('generateSignedManifest outputs compliant commercial terms with 75/25 split', () {
      const submission = TemplateSubmissionData(
        title: 'NovaBank Pro',
        authorName: 'Robson David',
        githubHandle: 'iRoobsoN',
        payoutAccount: 'robson.dv14@gmail.com',
        tier: TemplateTier.fullApp,
        priceUsd: 49.0,
        description: 'Complete FinTech App',
        projectPath: '/test/path',
      );

      const fingerprint = TemplateFingerprint(
        templateId: 'NovaBank Pro',
        classDeclarations: {'App', 'Home'},
        widgetDeclarations: {'Card'},
        routePaths: {'/home'},
        relativeFilePaths: {'lib/main.dart'},
      );

      final manifest = guardian.generateSignedManifest(
        submission: submission,
        fingerprint: fingerprint,
        checksumSha256: 'abc123sha256',
      );

      expect(manifest['name'], equals('NovaBank Pro'));
      expect(manifest['commercial']['price_usd'], equals(49.0));
      expect(manifest['commercial']['creator_earnings_usd'], equals(36.75)); // 75%
      expect(manifest['author']['creator_split'], equals(0.75));
      expect(manifest['author']['platform_split'], equals(0.25));
      expect(manifest['commercial']['no_resale_clause'], isTrue);
      expect(manifest['security']['checksum_sha256'], equals('abc123sha256'));
    });
  });

  group('PublishTemplateDialog Widget Tests', () {
    late Directory tempCleanDir;

    setUp(() async {
      tempCleanDir = await Directory.systemTemp.createTemp('flrd_widget_test_');
      final lib = Directory('${tempCleanDir.path}/lib');
      await lib.create(recursive: true);
      final mainFile = File('${lib.path}/main.dart');
      await mainFile.writeAsString('void main() {}');
    });

    tearDown(() async {
      if (await tempCleanDir.exists()) {
        await tempCleanDir.delete(recursive: true);
      }
    });

    testWidgets('Renders PublishTemplateDialog with pricing and floor calculations', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: PublishTemplateDialog(initialProjectPath: tempCleanDir.path),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Publicar Template no Marketplace FLRD'), findsOneWidget);
      expect(find.text('Categoria & Regra de Piso de Preço'), findsOneWidget);
      expect(find.text('Seu Repasse (75%)'), findsOneWidget);
      expect(find.text('Piso Exigido'), findsOneWidget);
      expect(find.text('Executar Auditoria'), findsOneWidget);
    });

    testWidgets('Triggers audit and shows results checklist on click', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: PublishTemplateDialog(initialProjectPath: tempCleanDir.path),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final auditButton = find.text('Executar Auditoria');
      expect(auditButton, findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(auditButton);
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      expect(find.text('Piso de Preço Respeitado'), findsOneWidget);
      expect(find.text('Segurança & Ausência de Chaves Privadas'), findsOneWidget);
      expect(find.textContaining('Originalidade & Anti-Plágio'), findsOneWidget);
    });
  });
}
