import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/features/auth/domain/user_account.dart';
import 'package:flrd/features/auth/providers/auth_provider.dart';
import 'package:flrd/features/auth/services/firebase_auth_service.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/settings/presentation/settings_and_billing_dialog.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/presentation/widgets/ai_screen_generator_dialog.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  late Directory tempDir;
  late RegisteredProject testProject;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flrd_billing_ui_test_');
    testProject = RegisteredProject(
      id: 'proj_test',
      name: 'FlrdTestApp',
      orgId: 'org_test',
      path: tempDir.path,
      preset: PresetType.saas,
      navigationStyle: NavigationStyle.tabs,
      permissions: const {},
      lastModified: DateTime.now(),
      routeCount: 1,
    );
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildTestApp({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  group('AiScreenGeneratorDialog - Plan Status & AI Credits Header', () {
    testWidgets('Displays ⭐ FLRD Studio Pro and credits counter for Pro user',
        (tester) async {
      const proUser = UserAccount(
        uid: 'user_pro_123',
        email: 'pro@flrd.dev',
        displayName: 'Pro Developer',
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
      );

      final sessionFile =
          '${tempDir.path}${Platform.pathSeparator}session_${DateTime.now().microsecondsSinceEpoch}.json';
      final mockAuthService = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(context, testProject);
              },
              child: const Text('Open Dialog'),
            ),
          ),
          overrides: [
            firebaseAuthServiceProvider.overrideWithValue(mockAuthService),
            authProvider.overrideWith((ref) {
              final notifier = AuthNotifier(
                authService: mockAuthService,
                ref: ref,
                autoRestore: false,
              );
              notifier.updateUser(proUser);
              return notifier;
            }),
          ],
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Assert Plan Badge
      expect(find.text('⭐ FLRD Studio Pro'), findsOneWidget);

      // Assert Credits Counter
      expect(
        find.text('⚡ 185 / 200 Créditos Disponíveis'),
        findsOneWidget,
      );

      // Assert Manage Plan action button
      expect(
        find.text('⚡ Gerenciar Plano / Inscrição'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping [⚡ Gerenciar Plano / Inscrição] opens SettingsAndBillingDialog',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(context, testProject);
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final manageBtn = find.text('⚡ Gerenciar Plano / Inscrição');
      expect(manageBtn, findsOneWidget);
      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsAndBillingDialog), findsOneWidget);
    });

    testWidgets('Displays ⚡ FLRD Starter badge for starter subscriber',
        (tester) async {
      const starterUser = UserAccount(
        uid: 'user_starter_456',
        email: 'starter@flrd.dev',
        subscriptionTier: SubscriptionTier.starter,
        aiCreditsRemaining: 45,
        aiCreditsTotal: 50,
      );

      final sessionFile =
          '${tempDir.path}${Platform.pathSeparator}session_${DateTime.now().microsecondsSinceEpoch}.json';
      final mockAuthService = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(context, testProject);
              },
              child: const Text('Open Dialog'),
            ),
          ),
          overrides: [
            firebaseAuthServiceProvider.overrideWithValue(mockAuthService),
            authProvider.overrideWith((ref) {
              final notifier = AuthNotifier(
                authService: mockAuthService,
                ref: ref,
                autoRestore: false,
              );
              notifier.updateUser(starterUser);
              return notifier;
            }),
          ],
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('⚡ FLRD Starter'), findsOneWidget);
      expect(find.text('⚡ 45 / 50 Créditos Disponíveis'), findsOneWidget);
    });

    testWidgets('Displays Cota Ilimitada / BYOK Livre when BYOK mode is selected',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(context, testProject);
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Switch to BYOK mode
      final byokFinder = find.text('🔑 BYOK (Sua Chave)');
      await tester.ensureVisible(byokFinder);
      await tester.tap(byokFinder);
      await tester.pumpAndSettle();

      expect(find.text('Cota Ilimitada / BYOK Livre'), findsOneWidget);
    });
  });

  group('AiScreenGeneratorDialog - Focused Widget-Only Generation Mode', () {
    testWidgets('Switches to widget refinement title, prompt, and button',
        (tester) async {
      const material = ScreenMaterialItem(
        id: 'mat_test_input',
        type: ScreenMaterialType.textInput,
        label: 'E-mail Corporativo',
        hint: 'seu.nome@empresa.com',
        note: 'Validar formato de e-mail e aplicar borda neon ao focar',
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(
                  context,
                  testProject,
                  targetMaterial: material,
                );
              },
              child: const Text('Refine Material'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Refine Material'));
      await tester.pumpAndSettle();

      // Title switches to target material name
      expect(
        find.text('Refinar Widget com IA: E-mail Corporativo'),
        findsOneWidget,
      );

      // Button reads [✨ Refinar e Injetar Widget]
      expect(find.text('✨ Refinar e Injetar Widget'), findsOneWidget);

      // Prompt field contains widget specific instructions including note
      final textField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && (w.maxLines == 4),
        ),
      );
      expect(textField.controller?.text, contains('E-mail Corporativo'));
      expect(textField.controller?.text, contains('Validar formato de e-mail'));
    });
  });

  group('AiScreenGeneratorDialog - Credit Deduction', () {
    testWidgets('Consumes 1 AI credit when generating with Pro Cloud',
        (tester) async {
      const proUser = UserAccount(
        uid: 'user_pro_credit',
        email: 'credit@flrd.dev',
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
      );

      final sessionFile =
          '${tempDir.path}${Platform.pathSeparator}session_${DateTime.now().microsecondsSinceEpoch}.json';
      final mockAuthService = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      late AuthNotifier authNotifier;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(context, testProject);
              },
              child: const Text('Open Dialog'),
            ),
          ),
          overrides: [
            firebaseAuthServiceProvider.overrideWithValue(mockAuthService),
            authProvider.overrideWith((ref) {
              authNotifier = AuthNotifier(
                authService: mockAuthService,
                ref: ref,
                autoRestore: false,
              );
              authNotifier.updateUser(proUser);
              return authNotifier;
            }),
          ],
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(authNotifier.state.creditsRemaining, equals(185));

      // Tap Generate Screen button
      final generateBtn = find.text('Gerar e Injetar Tela');
      await tester.ensureVisible(generateBtn);
      await tester.tap(generateBtn);
      await tester.pump();

      // Verify that consumeAiCredit was called and credits decremented to 184
      expect(authNotifier.state.creditsRemaining, equals(184));
    });
  });
}
