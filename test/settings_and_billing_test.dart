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
      expect(find.text('Configurações & Faturamento'), findsOneWidget);
      expect(
        find.text('Gerencie chaves de IA, licença FLRD Pro e apoios ao projeto'),
        findsOneWidget,
      );

      // Check Tabs exist
      expect(find.text('Inteligência Artificial (IA)'), findsOneWidget);
      expect(find.text('Plano & Faturamento'), findsOneWidget);
      expect(find.text('Apoiar Projeto'), findsOneWidget);
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
      expect(find.text('Chave de API do Gemini (Google AI Studio)'), findsOneWidget);
      expect(find.text('Obter Chave Gratuita no Google AI Studio'), findsOneWidget);
      expect(find.text('Salvar Chave de API'), findsOneWidget);

      // Enter a new API Key
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      await tester.enterText(textFieldFinder, 'AIzaSy_test_key_12345');
      await tester.pump();

      // Tap Save
      await tester.tap(find.text('Salvar Chave de API'));
      await tester.pumpAndSettle();

      // Verify that provider received the key
      expect(container.read(aiSettingsProvider).apiKey, equals('AIzaSy_test_key_12345'));
      expect(container.read(aiSettingsProvider).hasApiKey, isTrue);

      // Verify feedback SnackBar
      expect(find.text('Chave Gemini API salva com sucesso!'), findsOneWidget);
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
      expect(find.text(r'$149 / ano'), findsOneWidget);
      expect(find.text(r'$299 / ano'), findsOneWidget);

      // Verify benefits checklist
      expect(
        find.text('Scaffold ilimitado de apps (Riverpod SaaS, BLoC, SQLite)'),
        findsOneWidget,
      );
      expect(
        find.text('📂 Engenharia Reversa: importe e mapeie qualquer app legado no Studio'),
        findsOneWidget,
      );
      expect(
        find.text('🚀 BYOK Ilimitado: use sua própria chave de IA sem limites de telas'),
        findsOneWidget,
      );

      // Verify annual buttons
      expect(find.text('Assinar Starter Anual (\$149/ano)'), findsOneWidget);
      expect(find.text('Assinar Studio Pro Anual (\$299/ano)'), findsOneWidget);

      // Toggle to Monthly billing
      final monthlyToggle = find.text('Mensal');
      expect(monthlyToggle, findsOneWidget);
      await tester.tap(monthlyToggle);
      await tester.pumpAndSettle();

      expect(find.text(r'$15 / mês'), findsOneWidget);
      expect(find.text(r'$35 / mês'), findsOneWidget);
      expect(find.text('Assinar Starter Mensal (\$15/mês)'), findsOneWidget);
      expect(find.text('Assinar Studio Pro Mensal (\$35/mês)'), findsOneWidget);

      // Test Pro status toggle
      expect(container.read(aiSettingsProvider).isProActive, isFalse);
      final activateFinder = find.text('Ativar Licença');
      expect(activateFinder, findsOneWidget);

      await tester.ensureVisible(activateFinder);
      await tester.tap(activateFinder);
      await tester.pumpAndSettle();

      expect(container.read(aiSettingsProvider).isProActive, isTrue);
      expect(find.text('Status da Licença: FLRD Pro Ativo'), findsOneWidget);
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
      expect(find.text('Configurações & Faturamento'), findsOneWidget);

      // Close the dialog
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      // Verify dialog is dismissed
      expect(find.byType(SettingsAndBillingDialog), findsNothing);
    });
  });
}
