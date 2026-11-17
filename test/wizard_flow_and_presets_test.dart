import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flrd/features/generator/pipeline/project_generator.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flrd/features/wizard/presentation/controllers/wizard_controller.dart';
import 'package:flrd/features/wizard/presentation/wizard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WizardController & PresetType Unit Tests', () {
    test('Every PresetType provides plain explanations, real packages, and concrete app examples', () {
      for (final preset in PresetType.values) {
        expect(preset.friendlySubtitle.trim(), isNotEmpty);
        expect(preset.plainExplanation.trim(), isNotEmpty);
        expect(preset.idealFor.trim(), isNotEmpty);
        expect(preset.appExamples.length, greaterThanOrEqualTo(3));
        expect(preset.generatedPackages, isNotEmpty);
        expect(preset.technicalHighlights, isNotEmpty);
      }
      expect(
        PresetType.offline.generatedPackages,
        contains('sqflite'),
      );
      expect(
        PresetType.saas.appExamples.any((e) => e.contains('Delivery')),
        isTrue,
      );
      expect(
        PresetType.cleanLite.appExamples.any((e) => e.contains('Fintech') || e.contains('fintech')),
        isTrue,
      );
    });

    test('WizardNotifier blocks skipping steps and forbids creation until all 6 steps pass', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(wizardProvider.notifier);

      expect(container.read(wizardProvider).currentStep, WizardStep.project);
      expect(container.read(wizardProvider).canGenerateProject, isFalse);

      // Cannot jump directly to Preset or Native step before completing Step 1
      expect(notifier.setStep(WizardStep.preset), isFalse);
      expect(notifier.setStep(WizardStep.native), isFalse);
      expect(container.read(wizardProvider).currentStep, WizardStep.project);

      // Cannot advance from Step 1 without destination directory
      final missingPathErr = notifier.nextStep();
      expect(missingPathErr, isNotNull);
      expect(container.read(wizardProvider).currentStep, WizardStep.project);

      // Set valid project info & destination folder
      notifier.updateConfig(
        (c) => c.copyWith(
          projectName: 'delivery_express',
          orgId: 'com.acme.delivery',
          outputPath: 'C:/Projects',
        ),
      );

      // Advance step by step 1 -> 2 -> 3 -> 4 -> 5 -> 6
      expect(notifier.nextStep(), isNull);
      expect(container.read(wizardProvider).currentStep, WizardStep.preset);
      expect(container.read(wizardProvider).canGenerateProject, isFalse);

      // Can revisit Step 1, still cannot jump to Step 4
      expect(notifier.setStep(WizardStep.project), isTrue);
      expect(notifier.setStep(WizardStep.theme), isFalse);
      expect(notifier.setStep(WizardStep.preset), isTrue);

      // Advance through preset -> navigation -> theme -> permissions -> native
      expect(notifier.nextStep(), isNull); // -> navigation
      expect(container.read(wizardProvider).canGenerateProject, isFalse);

      expect(notifier.nextStep(), isNull); // -> theme
      expect(container.read(wizardProvider).canGenerateProject, isFalse);

      expect(notifier.nextStep(), isNull); // -> permissions
      expect(container.read(wizardProvider).canGenerateProject, isFalse);

      expect(notifier.nextStep(), isNull); // -> native (all 6 steps traversed)
      expect(container.read(wizardProvider).currentStep, WizardStep.native);
      expect(container.read(wizardProvider).hasCompletedAllSteps, isTrue);
      expect(container.read(wizardProvider).canGenerateProject, isTrue);

      // Invalidating Step 1 (e.g. clearing outputPath) immediately re-blocks generation
      notifier.updateConfig((c) => c.copyWith(outputPath: ''));
      expect(container.read(wizardProvider).canGenerateProject, isFalse);

      notifier.resetWizard();
      expect(container.read(wizardProvider).currentStep, WizardStep.project);
      expect(container.read(wizardProvider).completedSteps, isEmpty);
    });
  });

  group('WizardScreen Widget Flow & Presets UX Tests', () {
    testWidgets('Enforces walking all 6 steps and displays clear app examples on Stack Presets', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: WizardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Creation button starts locked & clicking it does not open generation dialog
      expect(find.text('Faltam 6 etapas'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wizard_generate_button')));
      await tester.pumpAndSettle();
      expect(find.text('Generating Flutter Project...'), findsNothing);

      // Trying to click locked Step 2 on sidebar does NOT switch tabs
      await tester.tap(find.byKey(const ValueKey('wizard_sidebar_step_preset')));
      await tester.pumpAndSettle();
      expect(container.read(wizardProvider).currentStep, WizardStep.project);

      // Trying to Continue with empty outputPath keeps user on Step 1
      await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
      await tester.pumpAndSettle();
      expect(container.read(wizardProvider).currentStep, WizardStep.project);

      // Dismiss/let active toast settle cleanly before continuing
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Pick destination folder shortcut and fill project name
      await tester.enterText(
        find.byKey(const ValueKey('wizard_project_name_input')),
        'meu_app_teste',
      );
      final projectsChip = find.widgetWithText(ActionChip, 'C:/Projects');
      await tester.ensureVisible(projectsChip);
      await tester.tap(projectsChip);
      await tester.pumpAndSettle();

      // Step 1 -> Step 2 (Presets)
      await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
      await tester.pumpAndSettle();
      expect(container.read(wizardProvider).currentStep, WizardStep.preset);

      // Verify clear decision guide + concrete app examples are visible
      expect(
        find.text('Não sabe qual escolher? Guia rápido de 5 segundos:'),
        findsOneWidget,
      );
      expect(find.text('Delivery, loja ou marketplace local'), findsOneWidget);
      expect(find.text('Banco digital, fintech ou carteira Pix'), findsOneWidget);
      expect(find.text('Controle de gastos ou finanças pessoais'), findsOneWidget);

      // Select Clean-Lite preset
      await tester.ensureVisible(find.byKey(const ValueKey('preset_card_clean_lite')));
      await tester.tap(find.byKey(const ValueKey('preset_card_clean_lite')));
      await tester.pumpAndSettle();
      expect(container.read(wizardProvider).config.preset, PresetType.cleanLite);

      // Still blocked from creating on Step 2
      expect(container.read(wizardProvider).canGenerateProject, isFalse);

      // Step 2 -> Step 3 (Navigation)
      await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
      await tester.pumpAndSettle();
      expect(container.read(wizardProvider).currentStep, WizardStep.navigation);

      // Step 3 -> Step 4 (Theme)
      await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
      await tester.pumpAndSettle();
      expect(container.read(wizardProvider).currentStep, WizardStep.theme);

      // Step 4 -> Step 5 (Permissions)
      await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
      await tester.pumpAndSettle();
      expect(container.read(wizardProvider).currentStep, WizardStep.permissions);
      expect(container.read(wizardProvider).canGenerateProject, isFalse);

      // Step 5 -> Step 6 (Native & Review)
      await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
      await tester.pumpAndSettle();
      expect(container.read(wizardProvider).currentStep, WizardStep.native);

      // Now all 6 steps are completed -> Generate button unlocks and summary renders!
      expect(container.read(wizardProvider).canGenerateProject, isTrue);
      expect(find.text('Criar Projeto Flutter'), findsOneWidget);
      expect(find.text('RESUMO FINAL DO APP (PRONTO PARA CRIAR)'), findsOneWidget);

      // Can navigate back to already unlocked step via sidebar
      await tester.tap(find.byKey(const ValueKey('wizard_sidebar_step_theme')));
      await tester.pumpAndSettle();
      expect(container.read(wizardProvider).currentStep, WizardStep.theme);

      expect(tester.takeException(), isNull);
    });

    testWidgets('All 6 wizard steps render cleanly without overflow on compact desktop viewport', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: WizardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final projectsChip = find.widgetWithText(ActionChip, 'C:/Projects');
      await tester.ensureVisible(projectsChip);
      await tester.tap(projectsChip);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (var i = 0; i < WizardStep.values.length - 1; i++) {
        await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      expect(container.read(wizardProvider).currentStep, WizardStep.native);
      expect(container.read(wizardProvider).canGenerateProject, isTrue);
    });
  });

  group('Advanced Optional Dependencies Review Tests', () {
    test('ProjectConfig & ProjectGenerator adapt code safely when optional or template deps are excluded', () async {
      final tempDir = Directory.systemTemp.createTempSync('flrd_adv_deps_test_');
      try {
        // 1. Exclude optional deps: supabase_flutter, google_fonts, permission_handler
        const customSaas = ProjectConfig(
          projectName: 'lean_saas_app',
          orgId: 'com.lean.app',
          preset: PresetType.saas,
          permissions: {DevicePermission.camera},
          excludedPackages: {
            'supabase_flutter',
            'google_fonts',
            'permission_handler',
          },
          extraPackages: ['equatable'],
        );

        expect(customSaas.hasMissingTemplatePackages, isFalse);
        expect(customSaas.shouldSynthesizeMinimalApp, isFalse);
        expect(
          customSaas.resolvedPackagesToInstall,
          containsAll(['go_router', 'flutter_riverpod', 'equatable']),
        );
        expect(
          customSaas.resolvedPackagesToInstall,
          isNot(anyOf([
            contains('supabase_flutter'),
            contains('google_fonts'),
            contains('permission_handler'),
          ])),
        );

        final saasOut = Directory(p.join(tempDir.path, 'saas_custom'))
          ..createSync(recursive: true);
        await ProjectGenerator.synthesizeProjectCode(saasOut.path, customSaas);

        final themeCode = File(
          p.join(saasOut.path, 'lib', 'core', 'theme', 'app_theme.dart'),
        ).readAsStringSync();
        expect(themeCode, isNot(contains('package:google_fonts/google_fonts.dart')));
        expect(
          File(p.join(saasOut.path, 'lib', 'core', 'services', 'permission_service.dart'))
              .existsSync(),
          isFalse,
        );

        // 2. Excluding a template-used package (dio in cleanLite) triggers clean minimal scaffold
        const minimalClean = ProjectConfig(
          projectName: 'minimal_clean_app',
          orgId: 'com.clean.min',
          preset: PresetType.cleanLite,
          excludedPackages: {'dio', 'google_fonts'},
        );
        expect(minimalClean.hasMissingTemplatePackages, isTrue);
        expect(minimalClean.shouldSynthesizeMinimalApp, isTrue);

        final cleanOut = Directory(p.join(tempDir.path, 'clean_minimal'))
          ..createSync(recursive: true);
        await ProjectGenerator.synthesizeProjectCode(cleanOut.path, minimalClean);

        final mainCode =
            File(p.join(cleanOut.path, 'lib', 'main.dart')).readAsStringSync();
        expect(mainCode, contains('MaterialApp'));
        expect(mainCode, isNot(contains('package:dio/dio.dart')));
        expect(
          File(p.join(cleanOut.path, 'lib', 'core', 'network', 'dio_client.dart'))
              .existsSync(),
          isFalse,
        );
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    testWidgets('Step 6 offers optional dependencies review panel & dialog before creation', (tester) async {
      tester.view.physicalSize = const Size(1280, 920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: WizardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final projectsChip = find.widgetWithText(ActionChip, 'C:/Projects');
      await tester.ensureVisible(projectsChip);
      await tester.tap(projectsChip);
      await tester.pumpAndSettle();

      // Walk through all 6 mandatory steps -> lands on Step 6
      for (var i = 0; i < WizardStep.values.length - 1; i++) {
        await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
        await tester.pumpAndSettle();
      }
      expect(container.read(wizardProvider).canGenerateProject, isTrue);

      // Advanced panel is optional & collapsed by default (Create button already enabled)
      expect(
        find.byKey(const ValueKey('toggle_advanced_options_button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('review_dep_toggle_supabase_flutter')), findsNothing);

      // Open full dependencies review dialog before clicking Create
      final openReviewBtn =
          find.byKey(const ValueKey('open_dependencies_review_dialog_button'));
      await tester.ensureVisible(openReviewBtn);
      await tester.tap(openReviewBtn);
      await tester.pumpAndSettle();

      // Exclude unwanted default deps (supabase_flutter & google_fonts)
      final supabaseSwitch =
          find.byKey(const ValueKey('review_dep_toggle_supabase_flutter'));
      await tester.ensureVisible(supabaseSwitch);
      await tester.tap(supabaseSwitch);
      await tester.pumpAndSettle();

      final fontsSwitch =
          find.byKey(const ValueKey('review_dep_toggle_google_fonts'));
      await tester.ensureVisible(fontsSwitch);
      await tester.tap(fontsSwitch);
      await tester.pumpAndSettle();

      // Add extra dependency right before creating
      final extraInput = find.byKey(const ValueKey('advanced_extra_pkg_input'));
      await tester.ensureVisible(extraInput);
      await tester.enterText(extraInput, 'equatable');
      await tester.tap(
        find.byKey(const ValueKey('advanced_add_extra_pkg_button')),
      );
      await tester.pumpAndSettle();

      // Enable optional clean minimal scaffold mode
      final minimalSwitch =
          find.byKey(const ValueKey('advanced_minimal_scaffold_switch'));
      await tester.ensureVisible(minimalSwitch);
      await tester.tap(minimalSwitch);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('close_dependencies_review_dialog_button')),
      );
      await tester.pumpAndSettle();

      final customized = container.read(wizardProvider).config;
      expect(customized.hasCustomDependencies, isTrue);
      expect(customized.minimalScaffold, isTrue);
      expect(customized.resolvedPackagesToInstall, contains('equatable'));
      expect(
        customized.resolvedPackagesToInstall,
        isNot(contains('supabase_flutter')),
      );
      expect(
        customized.resolvedPackagesToInstall,
        isNot(contains('google_fonts')),
      );

      // Re-open via BottomActionBar Deps badge and restore defaults cleanly
      await tester.tap(find.byKey(const ValueKey('bottom_bar_deps_review_badge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reset_advanced_deps_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('close_dependencies_review_dialog_button')),
      );
      await tester.pumpAndSettle();

      final restored = container.read(wizardProvider).config;
      expect(restored.hasCustomDependencies, isFalse);
      expect(restored.resolvedPackagesToInstall, contains('supabase_flutter'));
      expect(tester.takeException(), isNull);
    });
  });
}
