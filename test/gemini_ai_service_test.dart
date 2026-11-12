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

    test('synthesizeScreenCode handles complex multi-line prompt without syntax leakage and extracts clean description', () {
      const complexPrompt = '''
Crie uma tela Flutter profissional e completa para a rota "/dashboard" (Painel).
Descrição do fluxo: Visão geral financeira com métricas em tempo real.
Preset de Arquitetura: saas (SaaS Full-Stack).
### App Navigation Graph & Available Routes:
- Início ("/home"): Tela principal
- Checkout ("/checkout"): Pagamento seguro
A tela deve conter e organizar harmonicamente os seguintes materiais e componentes definidos pelo usuário:
1. Barra Superior (AppBar): Título "Painel" com botão de retorno e ações.
2. Título de Destaque (Header): "Métricas de Performance"
3. Campo de Texto: Label "Buscar", placeholder "Filtrar por data..."
''';

      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'DashboardScreen',
        routePath: '/dashboard',
        prompt: complexPrompt,
        preset: PresetType.saas,
      );

      expect(code, contains('class DashboardScreen extends StatefulWidget'));
      expect(code, contains('class _DashboardScreenState extends State<DashboardScreen>'));
      expect(code, contains('/// Crie uma tela Flutter profissional'));
      expect(code, contains('/// ### App Navigation Graph & Available Routes:'));
      expect(code, isNot(contains("Text('$complexPrompt'")));
      expect(code, isNot(contains('Text(\'$complexPrompt\'')));
      expect(code, isNot(contains('Text("""$complexPrompt')));
      expect(code, contains('Visão geral financeira com métricas em tempo real.'));
    });

    test('synthesizeScreenCode honors dynamic title cycling directive from prompt or notes', () {
      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'ExploreScreen',
        routePath: '/explore',
        prompt: 'Tela com AppBar trocando de nome aleatoriamente.',
        preset: PresetType.saas,
      );

      expect(code, contains('int _titleIndex = 0;'));
      expect(code, contains('_titles = const ['));
      expect(code, contains("'Explore',"));
      expect(code, contains("'Explorar',"));
      expect(code, contains("'Novidades',"));
      expect(code, contains("'Destaques',"));
      expect(code, contains('Icons.shuffle_rounded'));
      expect(code, contains('_titleIndex = (_titleIndex + 1) % _titles.length;'));
    });

    test('synthesizeScreenCode honors centered alignment directive', () {
      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'CenterScreen',
        routePath: '/center',
        prompt: 'Tela de boas vindas com conteúdo centralizado no meio da tela.',
        preset: PresetType.saas,
      );

      expect(code, contains('CrossAxisAlignment.center'));
      expect(code, contains('TextAlign.center'));
      expect(code, contains('Center(child:'));
    });

    test('synthesizeScreenCode honors color switching directive', () {
      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'ActionScreen',
        routePath: '/action',
        prompt: 'Botão de confirmação que deve trocar de cor quando pressionado.',
        preset: PresetType.saas,
      );

      expect(code, contains('Color _buttonColor = AppColors.primary;'));
      expect(code, contains('_buttonColor = _buttonColor == AppColors.primary ? AppColors.secondary : AppColors.primary;'));
    });

    test('synthesizeScreenCode synthesizes Obsidian cards for supplied materials', () {
      const materials = [
        ScreenMaterialItem(
          id: 'mat_h1',
          type: ScreenMaterialType.headerText,
          label: 'Relatório Mensal',
          note: 'centralizado no meio da tela',
        ),
        ScreenMaterialItem(
          id: 'mat_card1',
          type: ScreenMaterialType.containerCard,
          label: 'Card de Lucro',
          hint: 'Exibição de lucros líquidos',
        ),
        ScreenMaterialItem(
          id: 'mat_btn1',
          type: ScreenMaterialType.primaryButton,
          label: 'Exportar PDF',
          note: 'trocar de cor',
        ),
      ];

      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'ReportScreen',
        routePath: '/reports',
        prompt: 'Tela de relatórios com materiais.',
        preset: PresetType.saas,
        materials: materials,
      );

      expect(code, contains('Relatório Mensal'));
      expect(code, contains('Card de Lucro'));
      expect(code, contains('Exibição de lucros líquidos'));
      expect(code, contains('Exportar PDF'));
      expect(code, contains('CrossAxisAlignment.center'));
      expect(code, contains('Color _buttonColor = AppColors.primary;'));
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

    testWidgets('AiScreenGeneratorDialog accepts initialMaterials and preserves apiKey in Pro Cloud mode', (tester) async {
      final testProject = RegisteredProject(
        id: 'proj_materials_test',
        name: 'FLRD Pro Demo Materials',
        orgId: 'dev.flrd',
        path: tempDir.path,
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: {},
        lastModified: DateTime.now(),
        routeCount: 2,
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(aiSettingsProvider.notifier).setApiKey('AIzaSyDeviceSavedKey');

      const initialMaterials = [
        ScreenMaterialItem(
          id: 'mat_appbar_1',
          type: ScreenMaterialType.appBar,
          label: 'Início',
          note: 'trocando de nome aleatoriamente',
        ),
      ];

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: AiScreenGeneratorDialog(
                project: testProject,
                initialMaterials: initialMaterials,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gerador de Telas com IA'), findsOneWidget);
      final dialogFinder = find.byType(AiScreenGeneratorDialog);
      expect(dialogFinder, findsOneWidget);
      final dialogWidget = tester.widget<AiScreenGeneratorDialog>(dialogFinder);
      expect(dialogWidget.initialMaterials, equals(initialMaterials));
      expect(container.read(aiSettingsProvider).apiKey, 'AIzaSyDeviceSavedKey');

      // Verify that in Pro Cloud mode, resolveActiveApiKey returns the stored key
      final activeKey = AiScreenGeneratorDialog.resolveActiveApiKey(
        selectedMode: 0,
        aiSettings: container.read(aiSettingsProvider),
        byokInputKey: '',
      );
      expect(activeKey, equals('AIzaSyDeviceSavedKey'));
    });

    test('generateScreen passes materials to fallback and synthesizes dynamic title from notes', () async {
      const materials = [
        ScreenMaterialItem(
          id: 'mat_appbar_1',
          type: ScreenMaterialType.appBar,
          label: 'Início',
          note: 'trocando de nome aleatoriamente',
        ),
      ];

      final result = await GeminiAiService.generateScreen(
        projectPath: tempDir.path,
        screenClassName: 'FallbackMaterialsScreen',
        routePath: '/fallback-mat',
        prompt: 'Tela de teste com materiais.',
        preset: PresetType.saas,
        materials: materials,
      );

      expect(result.code, contains('_titleIndex'));
      expect(result.code, contains('_titles = const ['));
      expect(result.code, contains("'Explorar',"));
    });
  });

  group('AI Screen Synthesis Bug Fixes and Note-Driven Synthesis Verification', () {
    test('synthesizeScreenCode produces valid Dart code without syntax errors when given a complex multi-line prompt containing "###", "Descrição do fluxo:", etc.', () {
      const complexPrompt = '''
Crie uma tela Flutter profissional e completa para a rota "/orders/tracking" (Rastreio).
Descrição do fluxo: Rastreamento detalhado de entrega em tempo real com mapa e timeline.
Preset de Arquitetura: saas (SaaS Full-Stack).
### App Navigation Graph & Available Routes:
- Início ("/home"): Feed principal
- Detalhes do Pedido ("/orders/detail"): Status da compra
- Suporte ("/support"): Atendimento ao cliente
### User Component Notes & Behavioral Prompts:
- Component: Timeline de Entrega -> User Note: 'indicadores com pulse verde'
- Component: Confirmar Recebimento -> User Note: 'botão com confirmação háptica'
''';

      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'OrderTrackingScreen',
        routePath: '/orders/tracking',
        prompt: complexPrompt,
        preset: PresetType.saas,
      );

      // Verify valid structure
      expect(code, contains("import 'package:flutter/material.dart';"));
      expect(code, contains('class OrderTrackingScreen extends StatefulWidget'));
      expect(code, contains('class _OrderTrackingScreenState extends State<OrderTrackingScreen>'));
      expect(code, contains('class AppColors'));

      // Verify that every line of the complex prompt is safely placed in comments
      expect(code, contains('/// Crie uma tela Flutter profissional e completa'));
      expect(code, contains('/// Descrição do fluxo: Rastreamento detalhado'));
      expect(code, contains('/// ### App Navigation Graph & Available Routes:'));
      expect(code, contains('/// - Início ("/home"): Feed principal'));
      expect(code, contains('/// ### User Component Notes & Behavioral Prompts:'));

      // Verify balanced curly braces and parentheses
      final openBraces = RegExp(r'\{').allMatches(code).length;
      final closeBraces = RegExp(r'\}').allMatches(code).length;
      expect(openBraces, equals(closeBraces), reason: 'Braces must be perfectly balanced');

      final openParens = RegExp(r'\(').allMatches(code).length;
      final closeParens = RegExp(r'\)').allMatches(code).length;
      expect(openParens, equals(closeParens), reason: 'Parentheses must be perfectly balanced');
    });

    test('synthesizeScreenCode NEVER contains the full raw prompt in any Text(...) widget', () {
      const complexRawPrompt = '''
Crie uma tela Flutter profissional e completa para a rota "/finance/insights" (Insights).
Descrição do fluxo: Análise preditiva financeira com gráficos de barras e exportação CSV.
Preset de Arquitetura: saas (SaaS Full-Stack).
### App Navigation Graph & Available Routes:
- Dashboard ("/dashboard"): Métricas gerais
- Carteira ("/wallet"): Saldo e extrato
### User Component Notes & Behavioral Prompts:
- Component: Gráfico Preditivo -> User Note: 'animar curva ao carregar tela'
''';

      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'FinanceInsightsScreen',
        routePath: '/finance/insights',
        prompt: complexRawPrompt,
        preset: PresetType.saas,
      );

      // Verify raw prompt is never rendered inside any Text widget
      expect(code.contains("Text('$complexRawPrompt')"), isFalse);
      expect(code.contains('Text("""$complexRawPrompt""")'), isFalse);
      expect(code.contains("Text('''$complexRawPrompt''')"), isFalse);

      // Regex check: No Text widget should have multiline prompt content or markdown headings
      final leakedTextMatches = RegExp(r'Text\s*\([^)]*###[^)]*\)').allMatches(code);
      expect(leakedTextMatches, isEmpty, reason: 'Text widgets must not contain raw markdown headers');

      final leakedFluxoMatches = RegExp(r'Text\s*\([^)]*Descrição do fluxo:[^)]*\)').allMatches(code);
      expect(leakedFluxoMatches, isEmpty, reason: 'Text widgets must not contain "Descrição do fluxo:" prefix');

      // Instead, verify that a clean description is extracted and rendered
      expect(code, contains('Análise preditiva financeira com gráficos de barras e exportação CSV.'));
    });

    test('synthesizeScreenCode respects user notes: dynamic title cycling ("trocando de nome aleatoriamente")', () {
      const materials = [
        ScreenMaterialItem(
          id: 'mat_appbar_cycle',
          type: ScreenMaterialType.appBar,
          label: 'Catálogo de Produtos',
          note: 'trocando de nome aleatoriamente ao tocar',
        ),
      ];

      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'CatalogScreen',
        routePath: '/catalog',
        prompt: 'Tela de catálogo de produtos.',
        preset: PresetType.saas,
        materials: materials,
      );

      expect(code, contains('int _titleIndex = 0;'));
      expect(code, contains('final List<String> _titles = const ['));
      expect(code, contains("'Catalog',"));
      expect(code, contains("'Explorar',"));
      expect(code, contains("'Novidades',"));
      expect(code, contains("'Destaques',"));
      expect(code, contains('_titleIndex = (_titleIndex + 1) % _titles.length;'));
      expect(code, contains('Icons.shuffle_rounded'));
    });

    test('synthesizeScreenCode respects user notes: centered alignment ("centralizado no meio da tela")', () {
      const materials = [
        ScreenMaterialItem(
          id: 'mat_center_card',
          type: ScreenMaterialType.containerCard,
          label: 'Card Boas Vindas',
          note: 'centralizado no meio da tela com texto em destaque',
        ),
      ];

      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'WelcomeScreen',
        routePath: '/welcome',
        prompt: 'Tela inicial de boas-vindas.',
        preset: PresetType.saas,
        materials: materials,
      );

      expect(code, contains('crossAxisAlignment: CrossAxisAlignment.center'));
      expect(code, contains('textAlign: TextAlign.center'));
      expect(code, contains('Center(child:'));
    });

    test('synthesizeScreenCode respects user notes: color switching state ("trocar de cor")', () {
      const materials = [
        ScreenMaterialItem(
          id: 'mat_color_btn',
          type: ScreenMaterialType.primaryButton,
          label: 'Ativar Modo Turbo',
          note: 'botão que deve trocar de cor quando clicado',
        ),
      ];

      final code = GeminiAiService.synthesizeScreenCode(
        screenClassName: 'TurboScreen',
        routePath: '/turbo',
        prompt: 'Tela de ativação de recursos turbo.',
        preset: PresetType.saas,
        materials: materials,
      );

      expect(code, contains('Color _buttonColor = AppColors.primary;'));
      expect(code, contains('_buttonColor = _buttonColor == AppColors.primary ? AppColors.secondary : AppColors.primary;'));
      expect(code, contains('backgroundColor: _buttonColor'));
    });

    test('AiScreenGeneratorDialog passes aiSettings.apiKey when in Pro Cloud mode if a key is stored', () {
      // 1. Pro Cloud mode with stored key -> passes aiSettings.apiKey
      const settingsWithKey = AiSettingsState(apiKey: 'AIzaSyProCloudStoredKey_987', isProActive: true);
      final activeKeyProWithStored = AiScreenGeneratorDialog.resolveActiveApiKey(
        selectedMode: 0,
        aiSettings: settingsWithKey,
        byokInputKey: '',
      );
      expect(activeKeyProWithStored, equals('AIzaSyProCloudStoredKey_987'));

      // 2. Pro Cloud mode without stored key -> returns null
      const settingsWithoutKey = AiSettingsState(apiKey: null, isProActive: true);
      final activeKeyProNoKey = AiScreenGeneratorDialog.resolveActiveApiKey(
        selectedMode: 0,
        aiSettings: settingsWithoutKey,
        byokInputKey: '',
      );
      expect(activeKeyProNoKey, isNull);

      // 3. BYOK mode with custom input -> passes input key
      final activeKeyByokTyped = AiScreenGeneratorDialog.resolveActiveApiKey(
        selectedMode: 1,
        aiSettings: settingsWithKey,
        byokInputKey: 'AIzaSyCustomKey_123',
      );
      expect(activeKeyByokTyped, equals('AIzaSyCustomKey_123'));

      // 4. BYOK mode without custom input -> falls back to stored key
      final activeKeyByokFallback = AiScreenGeneratorDialog.resolveActiveApiKey(
        selectedMode: 1,
        aiSettings: settingsWithKey,
        byokInputKey: '   ',
      );
      expect(activeKeyByokFallback, equals('AIzaSyProCloudStoredKey_987'));
    });
  });
}
