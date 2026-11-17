import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(find.text('Criar (6 etapas restantes)'), findsOneWidget);
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
}
