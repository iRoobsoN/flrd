import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:flrd/features/ai/providers/ai_settings_provider.dart';
import 'package:flrd/features/ai/services/gemini_ai_service.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/presentation/widgets/ai_screen_generator_dialog.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/models/route_node.dart';

/// Lightweight custom MockHttpClient that extends [http.BaseClient]
class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final httpRequest = request as http.Request;
    final response = await handler(httpRequest);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

void main() {
  group('AiSettingsProvider Tests', () {
    test('Default values are initialized properly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(aiSettingsProvider);
      expect(state.apiKey, isNull);
      expect(state.isProActive, isFalse);
      expect(state.hasApiKey, isFalse);
    });

    test('setApiKey updates apiKey and hasApiKey status', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(aiSettingsProvider.notifier).setApiKey('AIzaSyTestKey123');
      expect(container.read(aiSettingsProvider).apiKey, 'AIzaSyTestKey123');
      expect(container.read(aiSettingsProvider).hasApiKey, isTrue);

      // Trims whitespace
      container.read(aiSettingsProvider.notifier).setApiKey('   AIzaTrimmed   ');
      expect(container.read(aiSettingsProvider).apiKey, 'AIzaTrimmed');

      // Empty string becomes null
      container.read(aiSettingsProvider.notifier).setApiKey('   ');
      expect(container.read(aiSettingsProvider).apiKey, isNull);
      expect(container.read(aiSettingsProvider).hasApiKey, isFalse);
    });

    test('clearApiKey removes current key', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(aiSettingsProvider.notifier).setApiKey('tempKey');
      expect(container.read(aiSettingsProvider).hasApiKey, isTrue);

      container.read(aiSettingsProvider.notifier).clearApiKey();
      expect(container.read(aiSettingsProvider).apiKey, isNull);
      expect(container.read(aiSettingsProvider).hasApiKey, isFalse);
    });

    test('setProActive and toggleProActive update Pro subscription state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(aiSettingsProvider.notifier).setProActive(true);
      expect(container.read(aiSettingsProvider).isProActive, isTrue);

      container.read(aiSettingsProvider.notifier).toggleProActive();
      expect(container.read(aiSettingsProvider).isProActive, isFalse);

      container.read(aiSettingsProvider.notifier).toggleProActive();
      expect(container.read(aiSettingsProvider).isProActive, isTrue);
    });

    test('AiSettingsState copyWith and equality work accurately', () {
      const state1 = AiSettingsState(apiKey: 'keyA', isProActive: true);
      final state2 = state1.copyWith(apiKey: 'keyB');

      expect(state2.apiKey, 'keyB');
      expect(state2.isProActive, isTrue);
      expect(state1 == const AiSettingsState(apiKey: 'keyA', isProActive: true), isTrue);
    });
  });

  group('GeminiAiService Extraction and Synthesis Tests', () {
    test('extractDartCode extracts code enclosed in ```dart ... ```', () {
      const markdown = '''
Here is the Flutter screen you requested:
```dart
import 'package:flutter/material.dart';

class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key});

  @override
  Widget build(BuildContext context) => const Placeholder();
}
```
You can now import it in your router!
''';

      final extracted = GeminiAiService.extractDartCode(markdown);
      expect(extracted, startsWith("import 'package:flutter/material.dart';"));
      expect(extracted, endsWith("Widget build(BuildContext context) => const Placeholder();\n}"));
      expect(extracted, isNot(contains('```')));
    });

    test('extractDartCode extracts code enclosed in generic ``` ... ``` fences', () {
      const raw = '''
```
class SimpleScreen extends StatelessWidget {}
```
''';
      final extracted = GeminiAiService.extractDartCode(raw);
      expect(extracted, 'class SimpleScreen extends StatelessWidget {}');
    });

    test('extractDartCode trims raw code without code fences', () {
      const raw = '   class RawScreen extends StatelessWidget {}   ';
      final extracted = GeminiAiService.extractDartCode(raw);
      expect(extracted, 'class RawScreen extends StatelessWidget {}');
    });

    test('synthesizeScreenCode produces clean, compilable Flutter code', () {
      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'AnalyticsScreen',
        routePath: '/analytics/overview',
        prompt: 'Tela de análise de vendas com gráficos e KPIs.',
        preset: PresetType.saas,
      );

      expect(code, contains('class AnalyticsScreen extends StatefulWidget'));
      expect(code, contains('class AppColors'));
      expect(code, contains('/analytics/overview'));
      expect(code, contains('Tela de análise de vendas com gráficos e KPIs.'));
      expect(code, contains("import 'package:flutter/material.dart';"));
    });
  });

  group('GeminiAiService generateScreen Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flrd_ai_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('generateScreen falls back to synthesis and creates file on disk when apiKey is null', () async {
      final result = await GeminiAiService.generateScreen(
        projectPath: tempDir.path,
        screenClassName: 'CheckoutScreen',
        routePath: '/checkout',
        prompt: 'Carrinho de compras e métodos de pagamento.',
        preset: PresetType.saas,
        apiKey: null,
      );

      expect(result.filePath, 'lib/features/checkout/presentation/checkoutscreen.dart');
      expect(result.code, contains('class CheckoutScreen extends StatefulWidget'));
      expect(result.code, contains('Carrinho de compras e métodos de pagamento.'));

      // Validate physical file creation on disk
      final expectedFile = File(p.join(tempDir.path, 'lib/features/checkout/presentation/checkoutscreen.dart'));
      expect(await expectedFile.exists(), isTrue);

      final diskContent = await expectedFile.readAsString();
      expect(diskContent, result.code);
      expect(result.absolutePath, expectedFile.absolute.path);
    });

    test('generateScreen calls Gemini API when apiKey is provided and extracts code', () async {
      final mockResponseDartCode = '''
import 'package:flutter/material.dart';

class OrderScreen extends StatelessWidget {
  const OrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('AI Generated Order Screen')));
  }
}
''';

      final mockClient = MockHttpClient((request) async {
        expect(request.url.toString(), contains('generativelanguage.googleapis.com'));
        expect(request.url.queryParameters['key'], 'test-gemini-key');
        expect(request.headers['content-type'], 'application/json');

        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['contents'], isNotEmpty);

        final jsonResponse = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': '```dart\n$mockResponseDartCode\n```',
                  }
                ]
              }
            }
          ]
        };

        return http.Response(jsonEncode(jsonResponse), 200);
      });

      final result = await GeminiAiService.generateScreen(
        projectPath: tempDir.path,
        screenClassName: 'OrderScreen',
        routePath: '/orders',
        prompt: 'Tela de pedidos do cliente.',
        preset: PresetType.saas,
        apiKey: 'test-gemini-key',
        httpClient: mockClient,
      );

      expect(result.filePath, 'lib/features/order/presentation/orderscreen.dart');
      expect(result.code, mockResponseDartCode.trim());

      final writtenFile = File(p.join(tempDir.path, 'lib/features/order/presentation/orderscreen.dart'));
      expect(await writtenFile.exists(), isTrue);
      expect(await writtenFile.readAsString(), mockResponseDartCode.trim());
    });

    test('generateScreen falls back cleanly when Gemini API responds with 500 or throws', () async {
      final mockFailingClient = MockHttpClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final result = await GeminiAiService.generateScreen(
        projectPath: tempDir.path,
        screenClassName: 'ProfileScreen',
        routePath: '/profile',
        prompt: 'Tela de perfil do usuário.',
        preset: PresetType.cleanLite,
        apiKey: 'invalid-or-offline-key',
        httpClient: mockFailingClient,
      );

      expect(result.filePath, 'lib/features/profile/presentation/profilescreen.dart');
      expect(result.code, contains('class ProfileScreen extends StatefulWidget'));

      final writtenFile = File(p.join(tempDir.path, 'lib/features/profile/presentation/profilescreen.dart'));
      expect(await writtenFile.exists(), isTrue);
    });

    test('generateScreen handles empty, whitespace, null strings, and network exceptions cleanly', () async {
      // 1. Whitespace / empty string / 'null'
      final emptyKeyResult = await GeminiAiService.generateScreen(
        projectPath: tempDir.path,
        screenClassName: 'FeedScreen',
        routePath: '/feed',
        prompt: 'Feed de novidades.',
        preset: PresetType.saas,
        apiKey: '   ',
      );
      expect(emptyKeyResult.code, contains('class FeedScreen extends StatefulWidget'));

      final literalNullResult = await GeminiAiService.generateScreen(
        projectPath: tempDir.path,
        screenClassName: 'FeedScreen',
        routePath: '/feed',
        prompt: 'Feed de novidades.',
        preset: PresetType.saas,
        apiKey: 'null',
      );
      expect(literalNullResult.code, contains('class FeedScreen extends StatefulWidget'));

      // 2. Client throwing SocketException / network disconnection
      final throwingClient = MockHttpClient((request) async {
        throw const SocketException('Failed host lookup: generativelanguage.googleapis.com');
      });

      final networkFailResult = await GeminiAiService.generateScreen(
        projectPath: tempDir.path,
        screenClassName: 'SearchScreen',
        routePath: '/search',
        prompt: 'Busca inteligente.',
        preset: PresetType.saas,
        apiKey: 'valid-format-key',
        httpClient: throwingClient,
      );
      expect(networkFailResult.code, contains('class SearchScreen extends StatefulWidget'));
    });

    test('generateScreen includes existingRoutes in system prompt and fallback comments', () async {
      final existingRoutes = [
        const RouteNode(
          id: 'home',
          path: '/home',
          title: 'Início',
          subtitle: 'Feed inicial',
          icon: Icons.home,
          position: Offset.zero,
          filePath: 'lib/screens/home.dart',
        ),
        const RouteNode(
          id: 'cart',
          path: '/cart',
          title: 'Carrinho',
          subtitle: 'Itens adicionados',
          icon: Icons.shopping_cart,
          position: Offset.zero,
          filePath: 'lib/screens/cart.dart',
        ),
      ];

      final result = await GeminiAiService.generateScreen(
        projectPath: tempDir.path,
        screenClassName: 'ProductListScreen',
        routePath: '/products',
        prompt: 'Lista de produtos com filtros.',
        preset: PresetType.saas,
        existingRoutes: existingRoutes,
      );

      expect(result.code, contains('App Navigation Routes: Início (/home), Carrinho (/cart)'));
    });

    test('generateWidgetSnippet generates standalone focused widget with fallback and API mock', () async {
      const material = ScreenMaterialItem(
        id: 'mat_counter_1',
        type: ScreenMaterialType.primaryButton,
        label: 'Contador Animado',
        note: 'Botão que incrementa contador com efeito haptics',
      );

      // 1. Offline fallback synthesis
      final fallbackSnippet = await GeminiAiService.generateWidgetSnippet(
        material: material,
        preset: PresetType.saas,
      );

      expect(fallbackSnippet, contains('class ContadorAnimadoWidget extends StatefulWidget'));
      expect(fallbackSnippet, contains('User Note: Botão que incrementa contador com efeito haptics'));
      expect(fallbackSnippet, contains('Obsidian Glass Focused Component'));

      // 2. Gemini API Mock
      const mockWidgetCode = '''
import 'package:flutter/material.dart';

class ContadorAnimadoWidget extends StatelessWidget {
  const ContadorAnimadoWidget({super.key});
  @override
  Widget build(BuildContext context) => const ElevatedButton(onPressed: null, child: Text('Mocked Widget'));
}
''';

      final mockClient = MockHttpClient((request) async {
        expect(request.url.toString(), contains('generativelanguage.googleapis.com'));
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['contents'], isNotEmpty);

        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '```dart\n$mockWidgetCode\n```'}
                  ]
                }
              }
            ]
          }),
          200,
        );
      });

      final apiSnippet = await GeminiAiService.generateWidgetSnippet(
        material: material,
        preset: PresetType.saas,
        apiKey: 'test-api-key',
        httpClient: mockClient,
      );

      expect(apiSnippet, contains('class ContadorAnimadoWidget extends StatelessWidget'));
      expect(apiSnippet, contains('Mocked Widget'));
    });
  });

  group('AiScreenGeneratorDialog Widget Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flrd_dialog_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('Renders AiScreenGeneratorDialog with all options and allows configuration', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testProject = RegisteredProject(
        id: 'test_proj',
        name: 'FLRD Pro Demo',
        orgId: 'dev.flrd',
        path: tempDir.path,
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: {},
        lastModified: DateTime.now(),
        routeCount: 4,
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: AiScreenGeneratorDialog(project: testProject),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Dialog header and inputs
      expect(find.text('Gerador de Telas com IA'), findsOneWidget);
      expect(find.textContaining('FLRD Pro Cloud', skipOffstage: false), findsWidgets);
      expect(find.textContaining('BYOK (Sua Chave)', skipOffstage: false), findsWidgets);
      expect(find.byType(TextField), findsNWidgets(3)); // path, title, prompt

      // Verify default values
      expect(find.text('/checkout/payment'), findsOneWidget);
      final initialFields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(initialFields[0].controller?.text, '/checkout/payment');
      expect(initialFields[1].controller?.text, 'PaymentScreen');

      // Switch to BYOK mode
      await tester.tap(find.textContaining('BYOK (Sua Chave)', skipOffstage: false).first);
      await tester.pumpAndSettle();

      // BYOK Gemini API Key field should now be visible
      expect(find.text('Chave de API Google Gemini (BYOK)'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(4));

      // Enter API key in BYOK input
      final keyFinder = find.widgetWithText(TextField, 'Cole sua Gemini API Key (ex: AIzaSy...)');
      expect(keyFinder, findsOneWidget);
      await tester.enterText(keyFinder, 'AIzaSyTestUserCustomKey');
      await tester.pumpAndSettle();

      // Verify aiSettingsProvider updated
      expect(container.read(aiSettingsProvider).apiKey, 'AIzaSyTestUserCustomKey');

      // Verify buttons
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Gerar e Injetar Tela'), findsOneWidget);
    });
  });
}
