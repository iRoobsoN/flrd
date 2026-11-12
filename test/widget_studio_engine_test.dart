import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flrd/features/ai/providers/ai_settings_provider.dart';
import 'package:flrd/features/ai/services/gemini_ai_service.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/domain/widget_variation.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/widgets/device_screen_emulator.dart';
import 'package:flrd/features/studio/presentation/widgets/screen_materials_builder.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

class _MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  _MockHttpClient(this.handler);

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
  TestWidgetsFlutterBinding.ensureInitialized();

  final testProject = RegisteredProject(
    id: 'studio_test_proj',
    name: 'Studio Test Proj',
    orgId: 'com.studio.test',
    path: Directory.systemTemp.path,
    preset: PresetType.cleanLite,
    navigationStyle: NavigationStyle.tabs,
    permissions: const {},
    lastModified: DateTime.now(),
    routeCount: 2,
  );

  const testNode = RouteNode(
    id: 'dashboard',
    title: 'DashboardScreen',
    subtitle: 'Painel Principal',
    path: '/dashboard',
    filePath: 'lib/features/dashboard/dashboard_screen.dart',
    position: Offset(100, 100),
    isProtected: false,
    icon: Icons.dashboard_rounded,
  );

  const sampleScreenCode = '''import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Bem-vindo ao painel'),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
''';

  group('WidgetVariation Domain Model', () {
    test('instantiates with all fields and supports copyWith and serialization', () {
      const variation = WidgetVariation(
        id: 'var_test_1',
        title: 'Glass Card',
        styleTag: 'Glassmorphism Oval',
        description: 'Card translúcido com avatar em glow.',
        dartCode: 'Container(child: Text("Test"))',
        icon: Icons.account_circle_rounded,
        techApproach: 'CircleAvatar + Glow + Row',
      );

      expect(variation.id, 'var_test_1');
      expect(variation.title, 'Glass Card');
      expect(variation.styleTag, 'Glassmorphism Oval');
      expect(variation.description, 'Card translúcido com avatar em glow.');
      expect(variation.dartCode, contains('Container'));
      expect(variation.icon, Icons.account_circle_rounded);
      expect(variation.techApproach, 'CircleAvatar + Glow + Row');

      final copy = variation.copyWith(title: 'Updated Glass Card');
      expect(copy.title, 'Updated Glass Card');
      expect(copy.id, variation.id);

      final json = variation.toJson();
      expect(json['id'], 'var_test_1');
      expect(json['styleTag'], 'Glassmorphism Oval');

      final fromJson = WidgetVariation.fromJson(json, icon: Icons.account_circle_rounded);
      expect(fromJson, equals(variation));
      expect(fromJson.hashCode, equals(variation.hashCode));
      expect(variation.toString(), contains('var_test_1'));
    });
  });

  group('ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode', () {
    test('inserts widget snippet into screen children list with proper formatting', () {
      const snippet = '''Container(
  padding: const EdgeInsets.all(16),
  child: const Text('Widget Inserido'),
)''';

      final updated = ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode(
        sampleScreenCode,
        snippet,
      );

      expect(updated, contains('Widget Inserido'));
      expect(updated, contains('const Text(\'Bem-vindo ao painel\'),'));
      expect(updated, contains('children: ['));
      // Verify closing bracket remains after insertion
      expect(updated, contains('],\n          )'));
    });

    test('handles empty screen code by generating fallback scaffold', () {
      const snippet = 'const Text("Auto Generated")';
      final generated = ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode(
        '',
        snippet,
      );

      expect(generated, contains('Auto Generated'));
      expect(generated, contains('Scaffold('));
      expect(generated, contains('children: ['));
    });

    test('ScreenMaterialParser forwards insertWidgetSnippetIntoScreenCode', () {
      final updated = ScreenMaterialParser.insertWidgetSnippetIntoScreenCode(
        sampleScreenCode,
        'const Icon(Icons.star)',
      );
      expect(updated, contains('Icons.star'));
    });
  });

  group('GeminiAiService.generateWidgetVariations & synthesizeWidgetVariations', () {
    test('synthesizes 3 variations for profile/photo prompt', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'caixinha com foto de perfil do usuário logado e um bem vindo',
        preset: PresetType.cleanLite,
        routeNode: testNode,
      );

      expect(variations.length, 3);

      // Variation 1: Glassmorphism Card with CircleAvatar and glow
      expect(variations[0].styleTag, contains('Glassmorphism'));
      expect(variations[0].techApproach, contains('CircleAvatar'));
      expect(variations[0].dartCode, contains('CircleAvatar'));

      // Variation 2: Bento Grid Tile with ClipRRect
      expect(variations[1].styleTag, contains('Bento Grid'));
      expect(variations[1].techApproach, contains('ClipRRect'));
      expect(variations[1].dartCode, contains('ClipRRect'));

      // Variation 3: Hero Banner with gradient
      expect(variations[2].styleTag, contains('Hero'));
      expect(variations[2].techApproach, contains('Gradient'));
      expect(variations[2].dartCode, contains('LinearGradient'));
    });

    test('synthesizes 3 distinct variations for payment prompt', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'Seletor de pagamento Pix',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations.any((v) => v.styleTag.contains('Glassmorphism')), isTrue);
      expect(variations.any((v) => v.styleTag.contains('Bento Grid')), isTrue);
      expect(variations.any((v) => v.styleTag.contains('Hero')), isTrue);
    });

    test('synthesizes 3 distinct variations for metrics prompt with extracted user terms (Faturamento Mensal, Lucro)', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'Card de métricas com faturamento mensal e lucro',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations[0].title, contains('Faturamento Mensal'));
      expect(variations[0].title, contains('Lucro'));
      expect(variations[0].dartCode, contains('Faturamento Mensal'));
      expect(variations[0].dartCode, contains('Lucro'));

      expect(variations[1].title, contains('Faturamento Mensal'));
      expect(variations[1].title, contains('Lucro'));
      expect(variations[1].dartCode, contains('Lucro'));

      expect(variations[2].dartCode, contains('Faturamento Total Acumulado'));
    });

    test('synthesizes 3 distinct variations for search prompt', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'Busca com filtros de produtos',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations.any((v) => v.dartCode.contains('TextField')), isTrue);
    });

    test('synthesizes 3 distinct variations for bouncing physics ball prompt asserting animation, Curves.bounceOut, and spherical decorations', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'Uma bola que fica pingando',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);

      // Var 1: Bouncing Physics Ball with Curves.bounceOut and spherical decorations
      expect(variations[0].title, contains('Bouncing Physics Ball'));
      expect(variations[0].techApproach, contains('CurvedAnimation(curve: Curves.bounceOut)'));
      expect(variations[0].dartCode, contains('TweenAnimationBuilder'));
      expect(variations[0].dartCode, contains('Curves.bounceOut'));
      expect(variations[0].dartCode, contains('BoxShape.circle'));
      expect(variations[0].dartCode, contains('RadialGradient'));
      expect(variations[0].dartCode, contains('shadowScale'));

      // Var 2: Glowing Pulse Sphere
      expect(variations[1].title, contains('Glowing Pulse Sphere'));
      expect(variations[1].techApproach, contains('TweenAnimationBuilder + Scale & Neon Aura'));
      expect(variations[1].dartCode, contains('TweenAnimationBuilder'));
      expect(variations[1].dartCode, contains('BoxShape.circle'));
      expect(variations[1].dartCode, contains('RadialGradient'));

      // Var 3: Interactive Spring Ball with Curves.elasticOut
      expect(variations[2].title, contains('Interactive Spring Ball'));
      expect(variations[2].techApproach, contains('Curves.elasticOut'));
      expect(variations[2].dartCode, contains('Curves.elasticOut'));
      expect(variations[2].dartCode, contains('BoxShape.circle'));
    });

    test('synthesizes 3 distinct variations for counter prompt', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'contador de itens com mais e menos',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations[0].title, contains('Stepper Counter'));
      expect(variations[0].dartCode, contains('StatefulBuilder'));
      expect(variations[1].title, contains('Goal Counter'));
      expect(variations[2].title, contains('Counter Banner'));
    });

    test('synthesizes 3 distinct variations for custom prompt extracting keywords', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'painel solar inteligente com telemetria de voltagem',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations[0].title, contains('Painel Solar Inteligente'));
      expect(variations[0].styleTag, contains('Glassmorphism'));
      expect(variations[1].styleTag, contains('Bento Grid'));
      expect(variations[2].styleTag, contains('Hero'));
    });

    test('generateWidgetVariations falls back to synthesis when apiKey is null', () async {
      final variations = await GeminiAiService.generateWidgetVariations(
        prompt: 'avatar do usuário',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations[0].techApproach, contains('CircleAvatar'));
    });

    test('generateWidgetVariations calls Gemini 1.5 Flash API when apiKey is provided', () async {
      final mockClient = _MockHttpClient((request) async {
        expect(request.url.toString(), contains('gemini-1.5-flash'));
        expect(request.url.queryParameters['key'], 'AIzaFakeKey123');

        final fakeResponse = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode([
                      {
                        'id': 'api_var_1',
                        'title': 'AI Glass Profile',
                        'styleTag': 'Glassmorphism Oval',
                        'description': 'AI generated glassmorphic card.',
                        'techApproach': 'CircleAvatar + Glow + Row',
                        'dartCode': 'Container(child: Text("AI Profile 1"))'
                      },
                      {
                        'id': 'api_var_2',
                        'title': 'AI Bento Profile',
                        'styleTag': 'Bento Grid Profile',
                        'description': 'AI generated bento profile tile.',
                        'techApproach': 'ClipRRect + Bento Grid',
                        'dartCode': 'Container(child: Text("AI Profile 2"))'
                      },
                      {
                        'id': 'api_var_3',
                        'title': 'AI Hero Banner',
                        'styleTag': 'Hero Banner',
                        'description': 'AI generated hero action banner.',
                        'techApproach': 'Gradient Container + Action Button',
                        'dartCode': 'Container(child: Text("AI Profile 3"))'
                      }
                    ]),
                  }
                ]
              }
            }
          ]
        };

        return http.Response(jsonEncode(fakeResponse), 200, headers: {'content-type': 'application/json'});
      });

      final variations = await GeminiAiService.generateWidgetVariations(
        prompt: 'usuário logado',
        preset: PresetType.cleanLite,
        apiKey: 'AIzaFakeKey123',
        httpClient: mockClient,
      );

      expect(variations.length, 3);
      expect(variations[0].title, 'AI Glass Profile');
      expect(variations[1].title, 'AI Bento Profile');
      expect(variations[2].title, 'AI Hero Banner');
    });
  });

  group('ScreenMaterialsBuilder Criador de Widgets com IA Widget Tests', () {
    testWidgets('renders creator header, prompt input, inspiration chips, and generate button', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String code = sampleScreenCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenMaterialsBuilder(
                node: testNode,
                project: testProject,
                currentCode: code,
                onCodeChanged: (newCode) => code = newCode,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Criador Header
      expect(find.text('Criador de Widgets com IA'), findsOneWidget);
      expect(find.text('3 Variações'), findsOneWidget);

      // Check Prompt Input
      expect(find.byKey(const ValueKey('widget_creator_prompt_input')), findsOneWidget);

      // Check Inspiration Chips
      expect(find.text('👤 Foto de Perfil & Boas-Vindas'), findsOneWidget);
      expect(find.text('📊 Faturamento & Lucro'), findsOneWidget);
      expect(find.text('⚽ Bola Pingando (Física/Animação)'), findsOneWidget);
      expect(find.text('💳 Seletor Pix/Cartão'), findsOneWidget);
      expect(find.text('🔍 Busca com Filtro'), findsOneWidget);

      // Check Generate Button
      expect(find.byKey(const ValueKey('generate_widget_variations_button')), findsOneWidget);
      expect(find.text('✨ Gerar 3 Variações de Widgets com IA'), findsOneWidget);

      // Verify Screen Materials Stack still rendered below
      expect(find.textContaining('Widgets nesta Tela'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_enhance_materials_button')), findsOneWidget);
      expect(find.text('✨ Refinar Tela Inteira com IA'), findsOneWidget);
    });

    testWidgets('clicking inspiration chip fills the prompt input field', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String code = sampleScreenCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenMaterialsBuilder(
                node: testNode,
                project: testProject,
                currentCode: code,
                onCodeChanged: (newCode) => code = newCode,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Click on Profile Chip
      await tester.tap(find.text('👤 Foto de Perfil & Boas-Vindas'));
      await tester.pumpAndSettle();

      final input = tester.widget<TextField>(find.byKey(const ValueKey('widget_creator_prompt_input')));
      expect(input.controller?.text, contains('foto de perfil'));
    });

    testWidgets('generating variations displays 3 cards with styleTag, code viewer toggle, and choosing inserts widget', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String code = sampleScreenCode;
      bool codeChanged = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenMaterialsBuilder(
                node: testNode,
                project: testProject,
                currentCode: code,
                onCodeChanged: (newCode) {
                  code = newCode;
                  codeChanged = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select inspiration chip
      await tester.tap(find.text('👤 Foto de Perfil & Boas-Vindas'));
      await tester.pumpAndSettle();

      // Click Generate Button
      final generateBtn = find.byKey(const ValueKey('generate_widget_variations_button'));
      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      // Variations should be displayed
      expect(find.text('Variações Geradas (3):'), findsOneWidget);
      expect(find.text('Glassmorphism Oval'), findsOneWidget);
      expect(find.text('Bento Grid Profile'), findsOneWidget);
      expect(find.text('Hero Banner'), findsOneWidget);

      // Verify code viewer toggle
      final verCodigoBtns = find.text('👁️ Ver Código');
      expect(verCodigoBtns, findsWidgets);

      await tester.tap(verCodigoBtns.first);
      await tester.pumpAndSettle();
      expect(find.text('👁️ Ocultar Código'), findsOneWidget);

      // Click Choose Variation 0 button
      final chooseBtn = find.byKey(const ValueKey('choose_variation_button_0'));
      expect(chooseBtn, findsOneWidget);
      await tester.tap(chooseBtn);
      await tester.pumpAndSettle();

      // Verify code changed and widget was inserted
      expect(codeChanged, isTrue);
      expect(code, contains('CircleAvatar'));
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('asserts legacy palette chips are COMPLETELY GONE from ScreenMaterialsBuilder', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenMaterialsBuilder(
                node: testNode,
                project: testProject,
                currentCode: sampleScreenCode,
                onCodeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert legacy chips, drag target, and palette scroll are completely gone
      expect(find.text('Adicionar Componente (clique ou arraste):'), findsNothing);
      expect(find.text('+ AppBar'), findsNothing);
      expect(find.text('+ Título'), findsNothing);
      expect(find.text('+ Subtítulo'), findsNothing);
      expect(find.text('+ Input'), findsNothing);
      expect(find.text('+ Senha'), findsNothing);
      expect(find.text('+ Botão Primário'), findsNothing);
      expect(find.text('+ Botão Social'), findsNothing);
      expect(find.text('+ Card VIP'), findsNothing);
      expect(find.text('+ Switch'), findsNothing);
      expect(find.text('+ Checkbox'), findsNothing);
      expect(find.text('+ Ícone'), findsNothing);
      expect(find.byKey(const ValueKey('screen_materials_palette_scroll')), findsNothing);
      expect(find.byKey(const ValueKey('screen_materials_drop_target')), findsNothing);
    });

    testWidgets('tests AI provider and API key toggle (Pro Cloud vs BYOK) with auto-save', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScreenMaterialsBuilder(
                  node: testNode,
                  project: testProject,
                  currentCode: sampleScreenCode,
                  onCodeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default Pro Cloud
      expect(find.byKey(const ValueKey('widget_creator_provider_cloud')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_provider_byok')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_api_key_input')), findsNothing);
      expect(find.text('🟢 Gemini 1.5 Flash Ativo'), findsOneWidget);

      // Tap BYOK
      await tester.tap(find.byKey(const ValueKey('widget_creator_provider_byok')));
      await tester.pumpAndSettle();

      // Key input appears
      final keyField = find.byKey(const ValueKey('widget_creator_api_key_input'));
      expect(keyField, findsOneWidget);
      expect(find.text('⚡ Motor Neural Local'), findsOneWidget);

      // Enter key
      await tester.enterText(keyField, 'AIzaEngineTestKey888');
      await tester.pumpAndSettle();

      expect(container.read(aiSettingsProvider).apiKey, 'AIzaEngineTestKey888');
      expect(find.text('🟢 Gemini 1.5 Flash Ativo'), findsOneWidget);

      // Toggle back to Pro Cloud
      await tester.tap(find.byKey(const ValueKey('widget_creator_provider_cloud')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('widget_creator_api_key_input')), findsNothing);
      expect(find.text('🟢 Gemini 1.5 Flash Ativo'), findsOneWidget);
    });

    testWidgets('choosing widget variation correctly inserts into code and updates DeviceScreenEmulator Live Preview', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String liveCode = sampleScreenCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: ScreenMaterialsBuilder(
                          node: testNode,
                          project: testProject,
                          currentCode: liveCode,
                          onCodeChanged: (newCode) => setState(() => liveCode = newCode),
                        ),
                      ),
                    ),
                    Expanded(
                      child: DeviceScreenEmulator(
                        node: testNode,
                        project: testProject,
                        sourceCode: liveCode,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter ball prompt
      await tester.enterText(
        find.byKey(const ValueKey('widget_creator_prompt_input')),
        'Uma bola que fica pingando',
      );
      await tester.pumpAndSettle();

      // Generate
      await tester.tap(find.byKey(const ValueKey('generate_widget_variations_button')));
      await tester.pumpAndSettle();

      expect(find.text('Variações Geradas (3):'), findsOneWidget);

      // Choose variation 0
      final chooseBtn = find.byKey(const ValueKey('choose_variation_button_0'));
      expect(chooseBtn, findsOneWidget);
      await tester.tap(chooseBtn);
      await tester.pumpAndSettle();

      // Code contains Curves.bounceOut
      expect(liveCode, contains('Curves.bounceOut'));
      expect(find.byType(SnackBar), findsOneWidget);

      // Live Preview emulator receives updated code
      final emulator = tester.widget<DeviceScreenEmulator>(find.byType(DeviceScreenEmulator));
      expect(emulator.sourceCode, contains('Curves.bounceOut'));
      expect(tester.takeException(), isNull);
    });
  });
}
