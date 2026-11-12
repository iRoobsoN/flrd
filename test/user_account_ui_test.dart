import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/core/window/custom_titlebar.dart';
import 'package:flrd/features/auth/domain/user_account.dart';
import 'package:flrd/features/auth/presentation/user_account_dialog.dart';
import 'package:flrd/features/auth/providers/auth_provider.dart';
import 'package:flrd/features/auth/services/firebase_auth_service.dart';
import 'package:flrd/features/settings/presentation/settings_and_billing_dialog.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flrd_ui_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ProviderContainer makeContainer() {
    final uniqueFile =
        '${tempDir.path}${Platform.pathSeparator}session_${DateTime.now().microsecondsSinceEpoch}.json';
    return ProviderContainer(
      overrides: [
        firebaseAuthServiceProvider.overrideWithValue(
          FirebaseAuthService(
            sessionFilePath: uniqueFile,
            mockMode: true,
          ),
        ),
      ],
    );
  }

  group('UserAccountDialog UI Tests', () {
    testWidgets('Renders unauthenticated state with Sign In and Sign Up tabs and social buttons',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: UserAccountDialog(initialTab: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header check
      expect(find.text('Autenticação FLRD'), findsOneWidget);
      expect(
        find.text('Acesse seus projetos e planos em qualquer dispositivo'),
        findsOneWidget,
      );

      // Tab check
      expect(find.text('🔑 Entrar / Sign In'), findsOneWidget);
      expect(find.text('✨ Criar Conta / Sign Up'), findsOneWidget);

      // Form inputs for Sign In
      expect(find.text('E-mail'), findsOneWidget);
      expect(find.text('Senha'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);

      // Social login buttons
      expect(find.text('🌐 Continuar com Google'), findsOneWidget);
      expect(find.text('🐱 Continuar com GitHub'), findsOneWidget);
    });

    testWidgets('Sign In validation warns when fields are empty',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: UserAccountDialog(initialTab: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Entrar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Por favor, informe seu email e senha.'), findsOneWidget);
    });

    testWidgets('Renders authenticated user profile card with badge, AI credits and actions',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = makeContainer();
      addTearDown(container.dispose);

      // Sign in with Pro account inside runAsync to handle Future.delayed and file I/O in FakeAsync zone
      await tester.runAsync(() async {
        final success = await container
            .read(authProvider.notifier)
            .signInWithEmailAndPassword('pro_robson@flrd.dev', 'password123');
        expect(success, isTrue);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: UserAccountDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header in logged in state
      expect(find.text('Perfil da Conta FLRD'), findsOneWidget);

      // Check User Card
      expect(find.text('pro_robson@flrd.dev'), findsOneWidget);
      expect(find.text('PR'), findsOneWidget); // Initials for pro_robson
      expect(find.textContaining('UID: flrd_mock_'), findsOneWidget);

      // Check Active Subscription Badge
      expect(find.text('⭐ FLRD Studio Pro'), findsOneWidget);

      // Check AI Credits counter
      expect(
        find.text('⚡ 185 / 200 Gerações de IA restantes neste mês'),
        findsOneWidget,
      );

      // Check Stripe and Sign out buttons
      expect(find.text('Gerenciar Assinatura (Stripe)'), findsOneWidget);
      expect(find.text('Desconectar / Sign Out'), findsOneWidget);

      // Tap Sign Out inside runAsync
      await tester.runAsync(() async {
        await container.read(authProvider.notifier).signOut();
      });
      await tester.pumpAndSettle();

      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(find.text('🔑 Entrar / Sign In'), findsOneWidget);
    });
  });

  group('CustomTitleBar User Account Pill Tests', () {
    testWidgets('Shows [👤 Entrar] pill when unauthenticated and opens UserAccountDialog',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CustomTitleBar(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify unauthenticated pill exists
      expect(find.text('Entrar'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

      // Tap the Entrar pill
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      // Verify dialog opened
      expect(find.byType(UserAccountDialog), findsOneWidget);
      expect(find.text('Autenticação FLRD'), findsOneWidget);
    });

    testWidgets('Shows Avatar + ⭐ PRO badge when logged in with Studio Pro',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = makeContainer();
      addTearDown(container.dispose);

      final mockProUser = UserAccount.mockPro(
        displayName: 'Alice Developer',
        email: 'alice@flutter.dev',
      );
      await tester.runAsync(() async {
        await container.read(authProvider.notifier).updateUser(mockProUser);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CustomTitleBar(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Avatar initials 'AD' and tier badge '⭐ PRO'
      expect(find.text('AD'), findsOneWidget);
      expect(find.text('⭐ PRO'), findsOneWidget);

      // Tap the pill to open UserAccountDialog
      await tester.tap(find.text('⭐ PRO'));
      await tester.pumpAndSettle();

      expect(find.byType(UserAccountDialog), findsOneWidget);
      expect(find.text('Perfil da Conta FLRD'), findsOneWidget);
      expect(find.text('Alice Developer'), findsOneWidget);
    });
  });

  group('SettingsAndBillingDialog Multi-Device Cloud Sync Tests', () {
    testWidgets('Reflects authenticated user email, plan badge, and cloud sync status in Tab 2',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = makeContainer();
      addTearDown(container.dispose);

      final mockProUser = UserAccount.mockPro(
        displayName: 'Robson Cloud',
        email: 'robson@flrd.dev',
      );
      await tester.runAsync(() async {
        await container.read(authProvider.notifier).updateUser(mockProUser);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsAndBillingDialog(initialTabIndex: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check user email & active subscription badge in sync card
      expect(find.text('robson@flrd.dev'), findsOneWidget);
      expect(find.text('⭐ FLRD Studio Pro'), findsWidgets);
      expect(
        find.text(
          'Sincronização em Nuvem Multi-Dispositivo Ativa • 185/200 créditos IA',
        ),
        findsOneWidget,
      );
      expect(find.text('Gerenciar Conta'), findsOneWidget);

      // Tap 'Gerenciar Conta' to open UserAccountDialog
      await tester.tap(find.text('Gerenciar Conta'));
      await tester.pumpAndSettle();

      expect(find.byType(UserAccountDialog), findsOneWidget);
    });

    testWidgets('Reflects offline/unauthenticated status when not logged in',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsAndBillingDialog(initialTabIndex: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Conta Não Conectada'), findsOneWidget);
      expect(find.text('Modo Offline'), findsOneWidget);
      expect(
        find.text(
          'Conecte sua conta FLRD para sincronizar licenças e projetos em múltiplos dispositivos.',
        ),
        findsOneWidget,
      );
      expect(find.text('Conectar Conta'), findsOneWidget);
    });
  });
}
