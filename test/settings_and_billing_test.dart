import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/core/config/monetization_config.dart';
import 'package:flrd/core/window/custom_titlebar.dart';
import 'package:flrd/features/ai/providers/ai_settings_provider.dart';
import 'package:flrd/features/settings/presentation/settings_and_billing_dialog.dart';

void main() {
  group('MonetizationConfig Tests', () {
    test('Contains correct Lemon Squeezy, Pix, PayPal, and GitHub endpoints', () {
      expect(
        MonetizationConfig.lemonSqueezyProCheckoutUrl,
        equals('https://flrd.lemonsqueezy.com/buy/flrd-pro'),
      );
      expect(
        MonetizationConfig.lemonSqueezyStoreUrl,
        equals('https://flrd.lemonsqueezy.com'),
      );
      expect(
        MonetizationConfig.pixKey,
        equals('robson.dv14@gmail.com'),
      );
      expect(
        MonetizationConfig.payPalUrl,
        equals(
          'https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=robson.dv14@gmail.com&currency_code=USD',
        ),
      );
      expect(
        MonetizationConfig.githubSponsorsUrl,
        equals('https://github.com/sponsors/iRoobsoN'),
      );
      expect(
        MonetizationConfig.marketplaceSellerPortalUrl,
        equals('https://flrd.dev/sellers'),
      );
      expect(
        MonetizationConfig.googleAiStudioUrl,
        equals('https://aistudio.google.com/app/apikey'),
      );
    });
  });

  group('SettingsAndBillingDialog Widget Tests', () {
    testWidgets('Renders all 3 tabs and header correctly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SettingsAndBillingDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Header
      expect(find.text('Settings & Billing'), findsOneWidget);
      expect(
        find.text('Manage AI keys, FLRD subscriptions, and project sponsorships'),
        findsOneWidget,
      );

      // Check Tabs exist
      expect(find.text('Artificial Intelligence (AI)'), findsOneWidget);
      expect(find.text('Plan & Billing'), findsOneWidget);
      expect(find.text('Support Project'), findsOneWidget);
    });

    testWidgets('Tab 1 (IA): Saves Gemini API key into aiSettingsProvider',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsAndBillingDialog(initialTabIndex: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify BYOK section elements
      expect(find.text('Bring Your Own Key (BYOK) — Google Gemini'), findsOneWidget);
      expect(find.text('Gemini API Key (Google AI Studio)'), findsOneWidget);
      expect(find.text('Get Free Key at Google AI Studio'), findsOneWidget);
      expect(find.text('Save API Key'), findsOneWidget);

      // Enter a new API Key
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      await tester.enterText(textFieldFinder, 'AIzaSy_test_key_12345');
      await tester.pump();

      // Tap Save
      await tester.tap(find.text('Save API Key'));
      await tester.pumpAndSettle();

      // Verify that provider received the key
      expect(container.read(aiSettingsProvider).apiKey, equals('AIzaSy_test_key_12345'));
      expect(container.read(aiSettingsProvider).hasApiKey, isTrue);

      // Verify feedback SnackBar
      expect(find.text('Gemini API Key saved successfully!'), findsOneWidget);
    });

    testWidgets('Tab 2 (Plano & Faturamento): Displays FLRD Pro card, pricing, and benefits',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer();
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

      // Verify Tier cards
      expect(find.text('FLRD Starter'), findsOneWidget);
      expect(find.text('FLRD Studio Pro'), findsOneWidget);
      expect(find.text(r'$149 / year'), findsOneWidget);
      expect(find.text(r'$299 / year'), findsOneWidget);

      // Verify benefits checklist
      expect(
        find.text('Unlimited app scaffolding (Riverpod SaaS, BLoC, SQLite)'),
        findsOneWidget,
      );
      expect(
        find.text('📂 Reverse Engineering: import and map any legacy app in Studio'),
        findsOneWidget,
      );
      expect(
        find.text('🚀 Unlimited BYOK: use your own AI key with no screen limits'),
        findsOneWidget,
      );

      // Verify annual buttons
      expect(find.text('Subscribe Starter Annual (\$149/year)'), findsOneWidget);
      expect(find.text('Subscribe Studio Pro Annual (\$299/year)'), findsOneWidget);

      // Toggle to Monthly billing
      final monthlyToggle = find.text('Monthly');
      expect(monthlyToggle, findsOneWidget);
      await tester.tap(monthlyToggle);
      await tester.pumpAndSettle();

      expect(find.text(r'$15 / month'), findsOneWidget);
      expect(find.text(r'$35 / month'), findsOneWidget);
      expect(find.text('Subscribe Starter Monthly (\$15/month)'), findsOneWidget);
      expect(find.text('Subscribe Studio Pro Monthly (\$35/month)'), findsOneWidget);

      // Test Pro status toggle
      expect(container.read(aiSettingsProvider).isProActive, isFalse);
      final activateFinder = find.text('Activate License');
      expect(activateFinder, findsOneWidget);

      await tester.ensureVisible(activateFinder);
      await tester.tap(activateFinder);
      await tester.pumpAndSettle();

      expect(container.read(aiSettingsProvider).isProActive, isTrue);
      expect(find.text('License Status: FLRD Pro Active'), findsOneWidget);
    });

    testWidgets('Tab 3 (Apoiar Projeto): Shows Pix key and Copy button',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SettingsAndBillingDialog(initialTabIndex: 2),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify open source support section
      expect(find.text('Apoie o Desenvolvimento Independente'), findsOneWidget);
      expect(find.text('PIX (Brasil)'), findsOneWidget);
      expect(find.text('robson.dv14@gmail.com'), findsOneWidget);
      expect(find.text('Copiar Chave'), findsOneWidget);

      // Verify PayPal and GitHub cards
      expect(find.text('PayPal (Global)'), findsOneWidget);
      expect(find.text('GitHub Sponsors (@iRoobsoN)'), findsOneWidget);

      // Tap Copiar Chave
      await tester.tap(find.text('Copiar Chave'));
      await tester.pumpAndSettle();

      expect(
        find.text('Chave Pix copiada com sucesso: robson.dv14@gmail.com'),
        findsOneWidget,
      );
    });

    testWidgets('CustomTitleBar opens SettingsAndBillingDialog when Settings button is pressed',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
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

      // Locate the settings icon button
      final settingsButton = find.byIcon(Icons.settings_rounded);
      expect(settingsButton, findsOneWidget);

      // Tap settings button
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      // Verify dialog is opened
      expect(find.byType(SettingsAndBillingDialog), findsOneWidget);
      expect(find.text('Settings & Billing'), findsOneWidget);

      // Close the dialog
      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Verify dialog is dismissed
      expect(find.byType(SettingsAndBillingDialog), findsNothing);
    });
  });
}
