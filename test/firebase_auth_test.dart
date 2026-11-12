import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flrd/core/window/custom_titlebar.dart';
import 'package:flrd/features/ai/providers/ai_settings_provider.dart';
import 'package:flrd/features/auth/domain/user_account.dart';
import 'package:flrd/features/auth/presentation/user_account_dialog.dart';
import 'package:flrd/features/auth/providers/auth_provider.dart';
import 'package:flrd/features/auth/services/firebase_auth_service.dart';
import 'package:flrd/features/settings/presentation/settings_and_billing_dialog.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flrd_firebase_auth_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  String getUniqueSessionFile() {
    return '${tempDir.path}${Platform.pathSeparator}session_${DateTime.now().microsecondsSinceEpoch}.json';
  }

  ProviderContainer createTestContainer({FirebaseAuthService? customService}) {
    final sessionFile = getUniqueSessionFile();
    final service = customService ??
        FirebaseAuthService(
          sessionFilePath: sessionFile,
          mockMode: true,
        );
    return ProviderContainer(
      overrides: [
        firebaseAuthServiceProvider.overrideWithValue(service),
      ],
    );
  }

  // ===========================================================================
  // 1. UNIT TESTS: SubscriptionTier
  // ===========================================================================
  group('1. SubscriptionTier Unit Tests', () {
    test('Verifies tier labels and badge labels', () {
      expect(SubscriptionTier.community.label, equals('Community Free'));
      expect(SubscriptionTier.starter.label, equals('FLRD Starter'));
      expect(SubscriptionTier.studioPro.label, equals('FLRD Studio Pro'));

      expect(SubscriptionTier.community.badgeLabel, equals('🌱 Community Free'));
      expect(SubscriptionTier.starter.badgeLabel, equals('⚡ FLRD Starter'));
      expect(SubscriptionTier.studioPro.badgeLabel, equals('⭐ FLRD Studio Pro'));
    });

    test('Verifies tier isPro and isSubscribed boolean flags', () {
      expect(SubscriptionTier.community.isPro, isFalse);
      expect(SubscriptionTier.starter.isPro, isTrue);
      expect(SubscriptionTier.studioPro.isPro, isTrue);

      expect(SubscriptionTier.community.isSubscribed, isFalse);
      expect(SubscriptionTier.starter.isSubscribed, isTrue);
      expect(SubscriptionTier.studioPro.isSubscribed, isTrue);
    });

    test('Parses subscription tier strings safely via fromString', () {
      expect(SubscriptionTier.fromString('studioPro'), equals(SubscriptionTier.studioPro));
      expect(SubscriptionTier.fromString('pro'), equals(SubscriptionTier.studioPro));
      expect(SubscriptionTier.fromString('STUDIO_PRO'), equals(SubscriptionTier.studioPro));
      expect(SubscriptionTier.fromString('starter'), equals(SubscriptionTier.starter));
      expect(SubscriptionTier.fromString('FLRD_STARTER'), equals(SubscriptionTier.starter));
      expect(SubscriptionTier.fromString('community'), equals(SubscriptionTier.community));
      expect(SubscriptionTier.fromString(null), equals(SubscriptionTier.community));
      expect(SubscriptionTier.fromString(''), equals(SubscriptionTier.community));
      expect(SubscriptionTier.fromString('enterprise'), equals(SubscriptionTier.community));
    });
  });

  // ===========================================================================
  // 2. UNIT TESTS: UserAccount
  // ===========================================================================
  group('2. UserAccount Unit Tests', () {
    test('Constructs UserAccount with default values', () {
      const user = UserAccount(
        uid: 'usr_abc_123',
        email: 'developer@flrd.dev',
      );

      expect(user.uid, equals('usr_abc_123'));
      expect(user.email, equals('developer@flrd.dev'));
      expect(user.displayName, isNull);
      expect(user.photoUrl, isNull);
      expect(user.idToken, isNull);
      expect(user.refreshToken, isNull);
      expect(user.subscriptionTier, equals(SubscriptionTier.community));
      expect(user.isPro, isFalse);
      expect(user.isSubscribed, isFalse);
      expect(user.aiCreditsRemaining, equals(10));
      expect(user.aiCreditsTotal, equals(10));
      expect(user.effectiveName, equals('developer'));
      expect(user.initials, equals('DE'));
    });

    test('Computes effectiveName and initials correctly for various names', () {
      const userWithFull = UserAccount(
        uid: 'u1',
        email: 'robson@flrd.dev',
        displayName: 'Robson David',
      );
      expect(userWithFull.effectiveName, equals('Robson David'));
      expect(userWithFull.initials, equals('RD'));

      const userSingleName = UserAccount(
        uid: 'u2',
        email: 'ada@flrd.dev',
        displayName: 'Ada',
      );
      expect(userSingleName.effectiveName, equals('Ada'));
      expect(userSingleName.initials, equals('AD'));

      const userEmailFallback = UserAccount(
        uid: 'u3',
        email: 'samuel@flrd.dev',
      );
      expect(userEmailFallback.effectiveName, equals('samuel'));
      expect(userEmailFallback.initials, equals('SA'));

      const userEmptyFallback = UserAccount(
        uid: 'u4',
        email: 'invalid-email',
      );
      expect(userEmptyFallback.effectiveName, equals('FLRD Developer'));
      expect(userEmptyFallback.initials, equals('FD'));
    });

    test('Supports explicit isPro and isSubscribed overrides', () {
      const overriddenUser = UserAccount(
        uid: 'u5',
        email: 'comm_pro@flrd.dev',
        subscriptionTier: SubscriptionTier.community,
        isPro: true,
        isSubscribed: true,
      );
      expect(overriddenUser.isPro, isTrue);
      expect(overriddenUser.isSubscribed, isTrue);
    });

    test('Implements immutable copyWith properly', () {
      final original = UserAccount.mockCommunity();
      final updated = original.copyWith(
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
        displayName: 'Upgraded Dev',
      );

      expect(original.subscriptionTier, equals(SubscriptionTier.community));
      expect(original.aiCreditsRemaining, equals(5));

      expect(updated.subscriptionTier, equals(SubscriptionTier.studioPro));
      expect(updated.aiCreditsRemaining, equals(185));
      expect(updated.aiCreditsTotal, equals(200));
      expect(updated.displayName, equals('Upgraded Dev'));
      expect(updated.uid, equals(original.uid));
      expect(updated.email, equals(original.email));
    });

    test('Serializes to and deserializes from JSON preserving all fields', () {
      final original = UserAccount.mockPro();
      final map = original.toJson();
      final restored = UserAccount.fromJson(map);

      expect(restored.uid, equals(original.uid));
      expect(restored.email, equals(original.email));
      expect(restored.displayName, equals(original.displayName));
      expect(restored.subscriptionTier, equals(SubscriptionTier.studioPro));
      expect(restored.isPro, isTrue);
      expect(restored.aiCreditsRemaining, equals(original.aiCreditsRemaining));
      expect(restored.aiCreditsTotal, equals(original.aiCreditsTotal));
      expect(restored.idToken, equals(original.idToken));
      expect(restored.refreshToken, equals(original.refreshToken));
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
    });

    test('Mock factories generate valid accounts', () {
      final pro = UserAccount.mockPro();
      expect(pro.isPro, isTrue);
      expect(pro.subscriptionTier, equals(SubscriptionTier.studioPro));
      expect(pro.aiCreditsTotal, equals(200));

      final starter = UserAccount.mockStarter();
      expect(starter.isPro, isTrue);
      expect(starter.subscriptionTier, equals(SubscriptionTier.starter));
      expect(starter.aiCreditsTotal, equals(50));

      final comm = UserAccount.mockCommunity();
      expect(comm.isPro, isFalse);
      expect(comm.subscriptionTier, equals(SubscriptionTier.community));
      expect(comm.aiCreditsTotal, equals(10));
    });
  });

  // ===========================================================================
  // 3. UNIT TESTS: FirebaseAuthService
  // ===========================================================================
  group('3. FirebaseAuthService Unit Tests', () {
    test('Throws AuthException on invalid input arguments', () async {
      final service = FirebaseAuthService(
        sessionFilePath: getUniqueSessionFile(),
        mockMode: true,
      );

      expect(
        () => service.signInWithEmailAndPassword('', 'password123'),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => service.signInWithEmailAndPassword('user@flrd.dev', ''),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => service.signInWithEmailAndPassword('user@flrd.dev', '123'),
        throwsA(isA<AuthException>()),
      );

      expect(
        () => service.signUpWithEmailAndPassword('', 'password123'),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => service.signUpWithEmailAndPassword('user@flrd.dev', ''),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => service.signUpWithEmailAndPassword('user@flrd.dev', '123'),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => service.signInWithOAuth('', 'token123'),
        throwsA(isA<AuthException>()),
      );
    });

    test('Signs in successfully in mock mode and infers tier from email', () async {
      final sessionFile = getUniqueSessionFile();
      final service = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      // Pro tier inference
      final proUser = await service.signInWithEmailAndPassword('pro_dev@flrd.dev', 'secret123');
      expect(proUser.email, equals('pro_dev@flrd.dev'));
      expect(proUser.subscriptionTier, equals(SubscriptionTier.studioPro));
      expect(proUser.isPro, isTrue);
      expect(proUser.aiCreditsRemaining, equals(185));

      // Starter tier inference
      final starterUser =
          await service.signInWithEmailAndPassword('starter_dev@flrd.dev', 'secret123');
      expect(starterUser.email, equals('starter_dev@flrd.dev'));
      expect(starterUser.subscriptionTier, equals(SubscriptionTier.starter));
      expect(starterUser.isPro, isTrue);
      expect(starterUser.aiCreditsRemaining, equals(45));

      // Community tier inference
      final commUser =
          await service.signInWithEmailAndPassword('regular_dev@flrd.dev', 'secret123');
      expect(commUser.email, equals('regular_dev@flrd.dev'));
      expect(commUser.subscriptionTier, equals(SubscriptionTier.community));
      expect(commUser.isPro, isFalse);
      expect(commUser.aiCreditsRemaining, equals(10));
    });

    test('Signs up new account with displayName in mock mode', () async {
      final sessionFile = getUniqueSessionFile();
      final service = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      final user = await service.signUpWithEmailAndPassword(
        'new_pro_dev@flrd.dev',
        'password123',
        'Novo Robson',
      );
      expect(user.email, equals('new_pro_dev@flrd.dev'));
      expect(user.displayName, equals('Novo Robson'));
      expect(user.effectiveName, equals('Novo Robson'));
      expect(user.subscriptionTier, equals(SubscriptionTier.studioPro));
    });

    test('Signs in with OAuth Google and GitHub in mock mode', () async {
      final sessionFile = getUniqueSessionFile();
      final service = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      final googleUser = await service.signInWithOAuth('Google', 'token_google_abc');
      expect(googleUser.email, equals('google.dev@flrd.dev'));
      expect(googleUser.displayName, equals('Google Developer'));
      expect(googleUser.subscriptionTier, equals(SubscriptionTier.studioPro));

      final githubUser = await service.signInWithOAuth('GitHub', 'token_github_xyz');
      expect(githubUser.email, equals('github.dev@flrd.dev'));
      expect(githubUser.displayName, equals('GitHub Developer'));
      expect(githubUser.subscriptionTier, equals(SubscriptionTier.studioPro));
    });

    test('Session lifecycle: saveSession, restoreSession, clearSession, and signOut', () async {
      final sessionFile = getUniqueSessionFile();
      final service = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      // Initially no session exists
      expect(await service.restoreSession(), isNull);

      final user = UserAccount.mockPro(email: 'saved_pro@flrd.dev');
      await service.saveSession(user);

      // Verify file exists and restore yields user
      expect(File(sessionFile).existsSync(), isTrue);
      final restored = await service.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.email, equals('saved_pro@flrd.dev'));
      expect(restored.subscriptionTier, equals(SubscriptionTier.studioPro));

      // Clear session via signOut
      await service.signOut();
      expect(await service.restoreSession(), isNull);
      expect(File(sessionFile).existsSync(), isFalse);
    });

    test('Real REST API client integration via MockClient (HTTP 200 and Error handling)', () async {
      final sessionFile = getUniqueSessionFile();

      final mockHttpClient = MockClient((request) async {
        final uri = request.url.toString();
        if (uri.contains('signInWithPassword')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['email'] == 'error@flrd.dev') {
            return http.Response(
              jsonEncode({
                'error': {'message': 'EMAIL_NOT_FOUND', 'code': 400}
              }),
              400,
            );
          }
          if (body['password'] == 'wrong_pass') {
            return http.Response(
              jsonEncode({
                'error': {'message': 'INVALID_PASSWORD', 'code': 400}
              }),
              400,
            );
          }
          return http.Response(
            jsonEncode({
              'localId': 'firebase_uid_123',
              'email': body['email'],
              'displayName': 'Firebase User',
              'idToken': 'firebase_mock_id_token',
              'refreshToken': 'firebase_mock_refresh_token',
            }),
            200,
          );
        } else if (uri.contains('lookup')) {
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'localId': 'firebase_uid_123',
                  'email': 'lookup_pro@flrd.dev',
                  'displayName': 'Lookup Pro User',
                }
              ]
            }),
            200,
          );
        }
        return http.Response('{"error":"Not Found"}', 404);
      });

      final service = FirebaseAuthService(
        httpClient: mockHttpClient,
        apiKey: 'test_firebase_api_key_123',
        sessionFilePath: sessionFile,
        mockMode: false,
      );

      // Successful HTTP 200 sign in
      final signedIn =
          await service.signInWithEmailAndPassword('pro_real@flrd.dev', 'password123');
      expect(signedIn.uid, equals('firebase_uid_123'));
      expect(signedIn.email, equals('pro_real@flrd.dev'));
      expect(signedIn.subscriptionTier, equals(SubscriptionTier.studioPro));
      expect(signedIn.isPro, isTrue);

      // Lookup user data HTTP 200
      final lookedUp = await service.lookupUserData('firebase_mock_id_token');
      expect(lookedUp, isNotNull);
      expect(lookedUp!.email, equals('lookup_pro@flrd.dev'));
      expect(lookedUp.subscriptionTier, equals(SubscriptionTier.studioPro));

      // Error: EMAIL_NOT_FOUND
      expect(
        () => service.signInWithEmailAndPassword('error@flrd.dev', 'password123'),
        throwsA(
          predicate<AuthException>(
            (e) => e.message.contains('Nenhum usuário encontrado com este e-mail'),
          ),
        ),
      );

      // Error: INVALID_PASSWORD
      expect(
        () => service.signInWithEmailAndPassword('pro_real@flrd.dev', 'wrong_pass'),
        throwsA(
          predicate<AuthException>(
            (e) => e.message.contains('Senha incorreta'),
          ),
        ),
      );
    });
  });

  // ===========================================================================
  // 4. INTEGRATION TESTS: authProvider <-> aiSettingsProvider
  // ===========================================================================
  group('4. Integration Tests: authProvider and aiSettingsProvider', () {
    test('Signing in with Pro activates Pro in AiSettingsState', () async {
      final container = createTestContainer();
      addTearDown(container.dispose);

      // Initial state
      expect(container.read(aiSettingsProvider).isProActive, isFalse);
      expect(container.read(aiSettingsProvider).selectedPlan, equals('community'));
      expect(container.read(authProvider).isAuthenticated, isFalse);

      // Sign in with Pro
      final success = await container
          .read(authProvider.notifier)
          .signInWithEmailAndPassword('pro_architect@flrd.dev', 'password123');

      expect(success, isTrue);
      expect(container.read(authProvider).isAuthenticated, isTrue);
      expect(container.read(authProvider).isPro, isTrue);
      expect(container.read(authProvider).tier, equals(SubscriptionTier.studioPro));

      // AiSettingsState synchronization assertion
      final aiState = container.read(aiSettingsProvider);
      expect(aiState.isProActive, isTrue);
      expect(aiState.selectedPlan, equals('studioPro'));
    });

    test('Signing in with Starter activates Pro with starter plan in AiSettingsState', () async {
      final container = createTestContainer();
      addTearDown(container.dispose);

      final success = await container
          .read(authProvider.notifier)
          .signInWithEmailAndPassword('starter_dev@flrd.dev', 'password123');

      expect(success, isTrue);
      expect(container.read(authProvider).isAuthenticated, isTrue);
      expect(container.read(authProvider).tier, equals(SubscriptionTier.starter));
      expect(container.read(authProvider).isPro, isTrue);

      final aiState = container.read(aiSettingsProvider);
      expect(aiState.isProActive, isTrue);
      expect(aiState.selectedPlan, equals('starter'));
    });

    test('Signing out resets AiSettingsState to community and deactivates Pro', () async {
      final container = createTestContainer();
      addTearDown(container.dispose);

      // Sign in first
      await container
          .read(authProvider.notifier)
          .signInWithEmailAndPassword('pro_lead@flrd.dev', 'password123');
      expect(container.read(aiSettingsProvider).isProActive, isTrue);

      // Sign out
      await container.read(authProvider.notifier).signOut();

      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).user, isNull);

      final aiState = container.read(aiSettingsProvider);
      expect(aiState.isProActive, isFalse);
      expect(aiState.selectedPlan, equals('community'));
    });

    test('Dynamic subscription update syncs with AiSettingsState', () async {
      final container = createTestContainer();
      addTearDown(container.dispose);

      // Sign in with community tier
      await container
          .read(authProvider.notifier)
          .signInWithEmailAndPassword('community_user@flrd.dev', 'password123');
      expect(container.read(aiSettingsProvider).isProActive, isFalse);

      // Upgrade to Studio Pro
      await container.read(authProvider.notifier).updateSubscription(SubscriptionTier.studioPro);
      expect(container.read(authProvider).tier, equals(SubscriptionTier.studioPro));
      expect(container.read(aiSettingsProvider).isProActive, isTrue);
      expect(container.read(aiSettingsProvider).selectedPlan, equals('studioPro'));

      // Downgrade to Community
      await container.read(authProvider.notifier).updateSubscription(SubscriptionTier.community);
      expect(container.read(authProvider).tier, equals(SubscriptionTier.community));
      expect(container.read(aiSettingsProvider).isProActive, isFalse);
      expect(container.read(aiSettingsProvider).selectedPlan, equals('community'));
    });

    test('Consuming AI credit decrements remaining credits safely', () async {
      final container = createTestContainer();
      addTearDown(container.dispose);

      await container
          .read(authProvider.notifier)
          .signInWithEmailAndPassword('pro_user@flrd.dev', 'password123');

      final initialRemaining = container.read(authProvider).creditsRemaining;
      expect(initialRemaining, equals(185));

      await container.read(authProvider.notifier).consumeAiCredit(5);
      expect(container.read(authProvider).creditsRemaining, equals(180));

      // Consuming beyond total clamps to 0
      await container.read(authProvider.notifier).consumeAiCredit(300);
      expect(container.read(authProvider).creditsRemaining, equals(0));
    });
  });

  // ===========================================================================
  // 5. WIDGET TESTS: UserAccountDialog & CustomTitleBar
  // ===========================================================================
  group('5. Widget Tests: UserAccountDialog & CustomTitleBar', () {
    testWidgets('Renders sign-in and sign-up tabs, inputs, and social buttons',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = createTestContainer();
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

      // Check Header in unauthenticated state
      expect(find.text('Autenticação FLRD'), findsOneWidget);
      expect(
        find.text('Acesse seus projetos e planos em qualquer dispositivo'),
        findsOneWidget,
      );

      // Check Tabs
      expect(find.text('🔑 Entrar / Sign In'), findsOneWidget);
      expect(find.text('✨ Criar Conta / Sign Up'), findsOneWidget);

      // Check Sign-in form inputs
      expect(find.text('E-mail'), findsOneWidget);
      expect(find.text('Senha'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);

      // Check Social login buttons
      expect(find.text('🌐 Continuar com Google'), findsOneWidget);
      expect(find.text('🐱 Continuar com GitHub'), findsOneWidget);

      // Switch to Sign-Up tab
      await tester.tap(find.text('✨ Criar Conta / Sign Up'));
      await tester.pumpAndSettle();

      // Check registration fields
      expect(find.text('Nome de Exibição (Opcional)'), findsOneWidget);
      expect(find.text('Senha (mínimo 6 caracteres)'), findsOneWidget);
      expect(find.text('Criar Conta'), findsOneWidget);
    });

    testWidgets(
        'Successful login updates the UI and displays the user profile card with subscription badge and AI credits',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = createTestContainer();
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

      // Enter valid login credentials
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2)); // Email and Password fields on tab 0

      await tester.enterText(textFields.at(0), 'pro_developer@flrd.dev');
      await tester.enterText(textFields.at(1), 'password123');
      await tester.pump();

      // Tap Entrar button inside runAsync to handle disk I/O and wait for completion
      await tester.runAsync(() async {
        await tester.tap(find.text('Entrar'));
        for (int i = 0; i < 30; i++) {
          if (container.read(authProvider).isAuthenticated) break;
          await Future.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();

      // Assert transition to Authenticated View
      expect(find.text('Perfil da Conta FLRD'), findsOneWidget);
      expect(
        find.text('Sincronização em nuvem & Gerenciamento de Assinatura'),
        findsOneWidget,
      );

      // User details
      expect(find.text('pro_developer@flrd.dev'), findsOneWidget);
      expect(find.text('PR'), findsOneWidget); // Computed initials for pro_developer
      expect(find.textContaining('UID: flrd_mock_'), findsOneWidget);

      // Subscription badge
      expect(find.text('⭐ FLRD Studio Pro'), findsOneWidget);
      expect(
        find.text('Sincronização em nuvem ativa em todos os seus computadores.'),
        findsOneWidget,
      );

      // AI credits counter
      expect(find.text('Cota de IA'), findsOneWidget);
      expect(
        find.text('⚡ 185 / 200 Gerações de IA restantes neste mês'),
        findsOneWidget,
      );

      // Actions
      expect(find.text('Gerenciar Assinatura (Stripe)'), findsOneWidget);
      expect(find.text('Desconectar / Sign Out'), findsOneWidget);

      // Test Sign Out inside runAsync
      await tester.runAsync(() async {
        await tester.tap(find.text('Desconectar / Sign Out'));
        for (int i = 0; i < 30; i++) {
          if (!container.read(authProvider).isAuthenticated) break;
          await Future.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();

      // Verify returned to unauthenticated view
      expect(find.text('Autenticação FLRD'), findsOneWidget);
      expect(find.text('🔑 Entrar / Sign In'), findsOneWidget);
    });

    testWidgets('Titlebar user button renders in CustomTitleBar and opens UserAccountDialog',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = createTestContainer();
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

      // Verify unauthenticated pill [👤 Entrar] exists in titlebar
      final unauthPill = find.text('Entrar');
      expect(unauthPill, findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

      // Tap the pill to open UserAccountDialog
      await tester.tap(unauthPill);
      await tester.pumpAndSettle();

      // Verify UserAccountDialog opened
      expect(find.byType(UserAccountDialog), findsOneWidget);
      expect(find.text('Autenticação FLRD'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountDialog), findsNothing);

      // Log in with Pro account
      await tester.runAsync(() async {
        await container
            .read(authProvider.notifier)
            .signInWithEmailAndPassword('pro_titlebar@flrd.dev', 'password123');
      });
      await tester.pumpAndSettle();

      // Verify titlebar now renders user initials and ⭐ PRO badge
      expect(find.text('PR'), findsOneWidget); // Initials
      expect(find.text('⭐ PRO'), findsOneWidget);

      // Clicking the user profile pill opens UserAccountDialog with authenticated profile
      await tester.tap(find.text('⭐ PRO'));
      await tester.pumpAndSettle();

      expect(find.byType(UserAccountDialog), findsOneWidget);
      expect(find.text('Perfil da Conta FLRD'), findsOneWidget);
      expect(find.text('pro_titlebar@flrd.dev'), findsOneWidget);
    });

    testWidgets(
        'SettingsAndBillingDialog reflects multi-device cloud sync and opens UserAccountDialog',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = createTestContainer();
      addTearDown(container.dispose);

      // Pre-authenticate with Studio Pro account
      await tester.runAsync(() async {
        await container
            .read(authProvider.notifier)
            .signInWithEmailAndPassword('pro_cloud_sync@flrd.dev', 'password123');
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

      // Verify Cloud Sync status card
      expect(find.text('pro_cloud_sync@flrd.dev'), findsOneWidget);
      expect(find.text('⭐ FLRD Studio Pro'), findsOneWidget);
      expect(
        find.textContaining('Sincronização em Nuvem Multi-Dispositivo Ativa'),
        findsOneWidget,
      );
      expect(find.text('Gerenciar Conta'), findsOneWidget);

      // Tap Gerenciar Conta
      await tester.tap(find.text('Gerenciar Conta'));
      await tester.pumpAndSettle();

      // Verify UserAccountDialog opened
      expect(find.byType(UserAccountDialog), findsOneWidget);
      expect(find.text('Perfil da Conta FLRD'), findsOneWidget);
    });
  });
}
