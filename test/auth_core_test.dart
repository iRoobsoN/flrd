import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flrd/features/ai/providers/ai_settings_provider.dart';
import 'package:flrd/features/auth/domain/user_account.dart';
import 'package:flrd/features/auth/providers/auth_provider.dart';
import 'package:flrd/features/auth/services/firebase_auth_service.dart';

void main() {
  group('SubscriptionTier Tests', () {
    test('SubscriptionTier labels and properties', () {
      expect(SubscriptionTier.community.label, equals('Community Free'));
      expect(SubscriptionTier.starter.label, equals('FLRD Starter'));
      expect(SubscriptionTier.studioPro.label, equals('FLRD Studio Pro'));

      expect(SubscriptionTier.community.isPro, isFalse);
      expect(SubscriptionTier.starter.isPro, isTrue);
      expect(SubscriptionTier.studioPro.isPro, isTrue);

      expect(SubscriptionTier.community.isSubscribed, isFalse);
      expect(SubscriptionTier.starter.isSubscribed, isTrue);
      expect(SubscriptionTier.studioPro.isSubscribed, isTrue);
    });

    test('SubscriptionTier.fromString handles variants', () {
      expect(SubscriptionTier.fromString('studioPro'), equals(SubscriptionTier.studioPro));
      expect(SubscriptionTier.fromString('pro'), equals(SubscriptionTier.studioPro));
      expect(SubscriptionTier.fromString('STUDIO_PRO'), equals(SubscriptionTier.studioPro));
      expect(SubscriptionTier.fromString('starter'), equals(SubscriptionTier.starter));
      expect(SubscriptionTier.fromString('community'), equals(SubscriptionTier.community));
      expect(SubscriptionTier.fromString(null), equals(SubscriptionTier.community));
      expect(SubscriptionTier.fromString('unknown'), equals(SubscriptionTier.community));
    });
  });

  group('UserAccount Tests', () {
    test('Constructs UserAccount with correct defaults', () {
      const user = UserAccount(
        uid: 'user_123',
        email: 'developer@example.com',
      );

      expect(user.uid, equals('user_123'));
      expect(user.email, equals('developer@example.com'));
      expect(user.displayName, isNull);
      expect(user.subscriptionTier, equals(SubscriptionTier.community));
      expect(user.isPro, isFalse);
      expect(user.isSubscribed, isFalse);
      expect(user.effectiveName, equals('developer'));
      expect(user.initials, equals('DE'));
      expect(user.aiCreditsRemaining, equals(10));
      expect(user.aiCreditsTotal, equals(10));
    });

    test('Effective name and initials with display name', () {
      const user = UserAccount(
        uid: 'user_456',
        email: 'robson@flrd.dev',
        displayName: 'Robson David',
        subscriptionTier: SubscriptionTier.studioPro,
      );

      expect(user.effectiveName, equals('Robson David'));
      expect(user.initials, equals('RD'));
      expect(user.isPro, isTrue);
      expect(user.isSubscribed, isTrue);
    });

    test('JSON serialization and deserialization roundtrip', () {
      final original = UserAccount.mockPro();
      final json = original.toJson();
      final restored = UserAccount.fromJson(json);

      expect(restored.uid, equals(original.uid));
      expect(restored.email, equals(original.email));
      expect(restored.displayName, equals(original.displayName));
      expect(restored.subscriptionTier, equals(SubscriptionTier.studioPro));
      expect(restored.isPro, isTrue);
      expect(restored.aiCreditsRemaining, equals(185));
      expect(restored.aiCreditsTotal, equals(200));
    });

    test('Mock factories instantiate valid tiers', () {
      final pro = UserAccount.mockPro();
      expect(pro.isPro, isTrue);
      expect(pro.subscriptionTier, equals(SubscriptionTier.studioPro));

      final starter = UserAccount.mockStarter();
      expect(starter.isPro, isTrue);
      expect(starter.subscriptionTier, equals(SubscriptionTier.starter));

      final comm = UserAccount.mockCommunity();
      expect(comm.isPro, isFalse);
      expect(comm.subscriptionTier, equals(SubscriptionTier.community));
    });
  });

  group('FirebaseAuthService Tests', () {
    late Directory tempDir;
    late String tempSessionFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flrd_auth_test_');
      tempSessionFile = '${tempDir.path}${Platform.pathSeparator}session.json';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Validation checks on email and password', () async {
      final service = FirebaseAuthService(
        sessionFilePath: tempSessionFile,
        mockMode: true,
      );

      expect(
        () => service.signInWithEmailAndPassword('', '123456'),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => service.signInWithEmailAndPassword('user@test.com', ''),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => service.signInWithEmailAndPassword('user@test.com', '123'),
        throwsA(isA<AuthException>()),
      );
    });

    test('Mock mode signInWithEmailAndPassword saves session file', () async {
      final service = FirebaseAuthService(
        sessionFilePath: tempSessionFile,
        mockMode: true,
      );

      final user = await service.signInWithEmailAndPassword('pro_dev@flrd.dev', 'password123');
      expect(user.email, equals('pro_dev@flrd.dev'));
      expect(user.isPro, isTrue);
      expect(user.subscriptionTier, equals(SubscriptionTier.studioPro));

      // Assert session file created
      final sessionFile = File(tempSessionFile);
      expect(await sessionFile.exists(), isTrue);

      // Assert restore session
      final restored = await service.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.email, equals('pro_dev@flrd.dev'));
      expect(restored.subscriptionTier, equals(SubscriptionTier.studioPro));

      // Sign out
      await service.signOut();
      expect(await sessionFile.exists(), isFalse);
      expect(await service.restoreSession(), isNull);
    });

    test('Mock mode signUpWithEmailAndPassword saves session with display name', () async {
      final service = FirebaseAuthService(
        sessionFilePath: tempSessionFile,
        mockMode: true,
      );

      final user = await service.signUpWithEmailAndPassword(
        'starter_user@flrd.dev',
        'securePass123',
        'Robson Starter',
      );
      expect(user.email, equals('starter_user@flrd.dev'));
      expect(user.displayName, equals('Robson Starter'));
      expect(user.subscriptionTier, equals(SubscriptionTier.starter));
      expect(user.isPro, isTrue);

      final restored = await service.restoreSession();
      expect(restored?.displayName, equals('Robson Starter'));
    });

    test('Mock mode signInWithOAuth creates OAuth session', () async {
      final service = FirebaseAuthService(
        sessionFilePath: tempSessionFile,
        mockMode: true,
      );

      final user = await service.signInWithOAuth('google.com', 'mock_google_token_123');
      expect(user.email, contains('google'));
      expect(user.isPro, isTrue);
      expect(user.subscriptionTier, equals(SubscriptionTier.studioPro));
    });

    test('Live HTTP simulation with MockClient', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('signInWithPassword')) {
          return http.Response(
            jsonEncode({
              'localId': 'live_uid_999',
              'email': 'studio_pro@flrd.dev',
              'displayName': 'Live Studio User',
              'idToken': 'mock_jwt_live',
              'refreshToken': 'mock_refresh_live',
              'expiresIn': '3600',
            }),
            200,
          );
        }
        return http.Response('{"error": {"message": "UNKNOWN"}}', 400);
      });

      final service = FirebaseAuthService(
        httpClient: mockClient,
        apiKey: 'AIzaFakeApiKeyForTest',
        sessionFilePath: tempSessionFile,
        mockMode: false,
      );

      final user = await service.signInWithEmailAndPassword('studio_pro@flrd.dev', 'password123');
      expect(user.uid, equals('live_uid_999'));
      expect(user.email, equals('studio_pro@flrd.dev'));
      expect(user.isPro, isTrue);
    });
  });

  group('AuthProvider & aiSettingsProvider Synchronization Tests', () {
    late Directory tempDir;
    late String tempSessionFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flrd_auth_provider_test_');
      tempSessionFile = '${tempDir.path}${Platform.pathSeparator}session.json';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Initial AuthState is unauthenticated', () {
      final container = ProviderContainer(
        overrides: [
          firebaseAuthServiceProvider.overrideWithValue(
            FirebaseAuthService(
              sessionFilePath: tempSessionFile,
              mockMode: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(authProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.user, isNull);
      expect(state.isPro, isFalse);
      expect(state.tier, equals(SubscriptionTier.community));
    });

    test('Signing in with Pro activates Pro in aiSettingsProvider and sets studioPro plan', () async {
      final container = ProviderContainer(
        overrides: [
          firebaseAuthServiceProvider.overrideWithValue(
            FirebaseAuthService(
              sessionFilePath: tempSessionFile,
              mockMode: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Verify initial AI settings
      expect(container.read(aiSettingsProvider).isProActive, isFalse);
      expect(container.read(aiSettingsProvider).selectedPlan, equals('community'));

      // Sign in with Pro account
      final success = await container.read(authProvider.notifier).signInWithEmailAndPassword(
            'pro_architect@flrd.dev',
            'password123',
          );

      expect(success, isTrue);
      expect(container.read(authProvider).isAuthenticated, isTrue);
      expect(container.read(authProvider).isPro, isTrue);
      expect(container.read(authProvider).tier, equals(SubscriptionTier.studioPro));

      // Assert automatic synchronization with aiSettingsProvider
      final aiSettings = container.read(aiSettingsProvider);
      expect(aiSettings.isProActive, isTrue);
      expect(aiSettings.selectedPlan, equals('studioPro'));

      // Now Sign Out
      await container.read(authProvider.notifier).signOut();
      expect(container.read(authProvider).isAuthenticated, isFalse);

      // Assert synchronization resets aiSettingsProvider to community
      final aiSettingsAfterLogout = container.read(aiSettingsProvider);
      expect(aiSettingsAfterLogout.isProActive, isFalse);
      expect(aiSettingsAfterLogout.selectedPlan, equals('community'));
    });

    test('Signing in with Starter activates Pro and sets starter plan in aiSettingsProvider', () async {
      final container = ProviderContainer(
        overrides: [
          firebaseAuthServiceProvider.overrideWithValue(
            FirebaseAuthService(
              sessionFilePath: tempSessionFile,
              mockMode: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final success = await container.read(authProvider.notifier).signInWithEmailAndPassword(
            'starter_dev@flrd.dev',
            'password123',
          );

      expect(success, isTrue);
      expect(container.read(authProvider).isPro, isTrue);
      expect(container.read(authProvider).tier, equals(SubscriptionTier.starter));

      final aiSettings = container.read(aiSettingsProvider);
      expect(aiSettings.isProActive, isTrue);
      expect(aiSettings.selectedPlan, equals('starter'));
    });

    test('Consume AI credit and update plan', () async {
      final container = ProviderContainer(
        overrides: [
          firebaseAuthServiceProvider.overrideWithValue(
            FirebaseAuthService(
              sessionFilePath: tempSessionFile,
              mockMode: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).signInWithEmailAndPassword(
            'pro@flrd.dev',
            'password123',
          );

      final initialCredits = container.read(authProvider).creditsRemaining;
      await container.read(authProvider.notifier).consumeAiCredit(1);
      expect(container.read(authProvider).creditsRemaining, equals(initialCredits - 1));

      // Update subscription to Community
      await container.read(authProvider.notifier).updateSubscription(SubscriptionTier.community);
      expect(container.read(authProvider).isPro, isFalse);
      expect(container.read(aiSettingsProvider).isProActive, isFalse);
      expect(container.read(aiSettingsProvider).selectedPlan, equals('community'));
    });
  });
}
