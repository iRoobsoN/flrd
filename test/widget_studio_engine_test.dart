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
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/domain/widget_variation.dart';
import 'package:flrd/features/studio/models/route_node.dart';
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

Future<void> _pumpThroughRealAsync(
  WidgetTester tester, {
  int maxSteps = 100,
}) async {
  await tester.pump();
  for (var i = 0; i < maxSteps; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
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

    test('generateWidgetVariations calls Gemini 2.5 Flash API when apiKey is provided', () async {
      final mockClient = _MockHttpClient((request) async {
        expect(request.url.toString(), contains('gemini-2.5-flash'));
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
    testWidgets('renders creator header, prompt input, placement input, honest BYOK controls, inspiration chips, and Plan button', (tester) async {
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

      // Check Criador Header & Plan-First controls
      expect(find.text('Criador de Widgets com IA'), findsOneWidget);
      expect(find.text('Gemini 2.5 · Plan-First'), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_prompt_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_placement_prompt_input')), findsOneWidget);
      expect(find.text('🔑 Chave Gemini (BYOK) necessária'), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_model_flash')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_model_pro')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_provider_cloud')), findsNothing);
      expect(find.text('⚡ FLRD Pro Cloud'), findsNothing);
      expect(find.text('🟢 Gemini 1.5 Flash Ativo'), findsNothing);

      // Check Inspiration Chips
      expect(find.text('👤 Foto de Perfil & Boas-Vindas'), findsOneWidget);
      expect(find.text('📊 Faturamento & Lucro'), findsOneWidget);
      expect(find.text('⚽ Bola Pingando (Física/Animação)'), findsOneWidget);
      expect(find.text('💳 Seletor Pix/Cartão'), findsOneWidget);
      expect(find.text('🔍 Busca com Filtro'), findsOneWidget);

      // Check Plan Button
      expect(find.byKey(const ValueKey('generate_widget_variations_button')), findsOneWidget);
      expect(find.text('Planejar Widget (Gemini 2.5)'), findsOneWidget);

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

    testWidgets('Plan -> Preview -> Execute with mocked Gemini 2.5 HTTP client shows plan, code preview, and creates extracted widget + updates screen', (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync('flrd_engine_plan_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      const dashboardCode = '''import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Column(
        children: const [
          Text('Welcome'),
          SizedBox(height: 16),
          ElevatedButton(onPressed: null, child: Text('Abrir Relatório')),
        ],
      ),
    );
  }
}
''';

      File(p.join(tempDir.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: engine_demo_app
version: 1.0.0+1
environment:
  sdk: ">=3.2.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
      File(p.join(tempDir.path, 'lib/features/dashboard/dashboard_screen.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(dashboardCode);

      final localProject = RegisteredProject(
        id: 'engine_proj_disk',
        name: 'engine_demo_app',
        orgId: 'com.engine.demo',
        path: tempDir.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 1,
      );

      const clockWidgetCode = '''import 'dart:async';
import 'package:flutter/material.dart';

class DigitalClock extends StatefulWidget {
  const DigitalClock({super.key});

  @override
  State<DigitalClock> createState() => _DigitalClockState();
}

class _DigitalClockState extends State<DigitalClock> {
  Timer? _timer;
  int _styleIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _styleIndex = (_styleIndex + 1) % 3),
      child: const Text('10:42:00'),
    );
  }
}''';

      var callIndex = 0;
      final mockClient = _MockHttpClient((request) async {
        callIndex++;
        if (callIndex == 1) {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text': jsonEncode({
                          'goalSummary': 'Relógio digital interativo que muda estilo ao toque.',
                          'widgetName': 'DigitalClock',
                          'architectureType': 'statefulWidgetClass',
                          'stateFields': ['Timer? _timer', 'int _styleIndex'],
                          'interactions': ['onTap alterna estilos'],
                          'requiredImports': ['dart:async', 'package:flutter/material.dart'],
                          'requiredPackages': [],
                          'placementStrategy': 'separateWidgetFile',
                          'extractedWidgetFilePath': 'lib/features/dashboard/widgets/digital_clock.dart',
                          'visualAnchorDescription': 'Logo abaixo do card Welcome',
                          'insertionAnchorHint': 'after_text:Welcome',
                        }),
                      }
                    ],
                  },
                }
              ],
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'id': 'clock_var_1',
                        'title': 'Digital Clock Stateful',
                        'styleTag': 'Material 3 Clock',
                        'description': 'Relógio com Timer.periodic e _styleIndex.',
                        'techApproach': 'StatefulWidget + Timer.periodic',
                        'requiredImports': ['dart:async', 'package:flutter/material.dart'],
                        'extractedWidgetCode': clockWidgetCode,
                        'callSiteSnippet': 'const DigitalClock()',
                        'dartCode': clockWidgetCode,
                      }),
                    }
                  ],
                },
              }
            ],
          }),
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.inMemory(
              const AiSettingsState(apiKey: 'AIzaEngineLiveKey'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      String code = dashboardCode;
      bool codeChanged = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScreenMaterialsBuilder(
                  node: testNode,
                  project: localProject,
                  currentCode: code,
                  aiHttpClient: mockClient,
                  onCodeChanged: (newCode) {
                    code = newCode;
                    codeChanged = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('widget_creator_prompt_input')),
        'Relógio digital interativo',
      );
      await tester.enterText(
        find.byKey(const ValueKey('widget_placement_prompt_input')),
        'logo abaixo do card Welcome',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await _pumpThroughRealAsync(tester);

      expect(find.byKey(const ValueKey('widget_execution_plan_card')), findsOneWidget);
      expect(find.text('Logo abaixo do card Welcome'), findsOneWidget);
      expect(find.text('Timer? _timer'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('generate_from_plan_button')),
      );
      await tester.tap(find.byKey(const ValueKey('generate_from_plan_button')));
      await _pumpThroughRealAsync(tester);

      expect(find.text('✅ Plano Aprovado'), findsOneWidget);

      // Verify code viewer toggle
      final verCodigoBtns = find.text('👁️ Ver Código');
      expect(verCodigoBtns, findsWidgets);
      await tester.ensureVisible(verCodigoBtns.first);
      await tester.tap(verCodigoBtns.first);
      await tester.pumpAndSettle();
      expect(find.text('👁️ Ocultar Código'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SelectableText),
          matching: find.textContaining('Timer.periodic'),
        ),
        findsOneWidget,
      );

      // Click Insert Widget button
      final chooseBtn = find.byKey(const ValueKey('choose_variation_button_0'));
      expect(chooseBtn, findsOneWidget);
      await tester.ensureVisible(chooseBtn);
      await tester.tap(chooseBtn);
      await _pumpThroughRealAsync(tester);

      // Verify code changed, extracted file created, and widget inserted after Welcome
      expect(codeChanged, isTrue);
      expect(code, contains('const DigitalClock()'));
      expect(
        File(p.join(tempDir.path, 'lib/features/dashboard/widgets/digital_clock.dart')).existsSync(),
        isTrue,
      );
      expect(
        code.indexOf('const DigitalClock()'),
        greaterThan(code.indexOf("Text('Welcome')")),
      );
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

    testWidgets('tests honest BYOK Gemini 2.5 controls, unconfigured blocking, inline save/edit/clear, and Flash/Pro toggle', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

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

      // Unconfigured BYOK state
      expect(find.byKey(const ValueKey('widget_creator_provider_cloud')), findsNothing);
      expect(find.byKey(const ValueKey('widget_creator_provider_byok')), findsNothing);
      expect(find.text('🔑 Chave Gemini (BYOK) necessária'), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_api_key_input')), findsOneWidget);

      // Plan without key blocks and shows error banner
      await tester.enterText(
        find.byKey(const ValueKey('widget_creator_prompt_input')),
        'Um relogio digital muito bonito',
      );
      await tester.tap(find.byKey(const ValueKey('generate_widget_variations_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('widget_ai_error_banner')), findsOneWidget);
      expect(find.textContaining('Relogio Digital Muito'), findsNothing);

      // Enter key and Save
      await tester.enterText(
        find.byKey(const ValueKey('widget_creator_api_key_input')),
        'AIzaEngineTestKey888',
      );
      await tester.tap(find.byKey(const ValueKey('widget_creator_api_key_save_button')));
      await tester.pumpAndSettle();

      expect(container.read(aiSettingsProvider).apiKey, 'AIzaEngineTestKey888');
      expect(find.text('⚡ BYOK Ativo · Gemini 2.5 Flash'), findsOneWidget);

      // Switch to Pro
      await tester.tap(find.byKey(const ValueKey('widget_creator_model_pro')));
      await tester.pumpAndSettle();
      expect(container.read(aiSettingsProvider).selectedModel, AiSettingsState.geminiProModel);
      expect(find.text('⚡ BYOK Ativo · Gemini 2.5 Pro'), findsOneWidget);

      // Clear key
      await tester.tap(find.byKey(const ValueKey('widget_creator_api_key_clear_button')));
      await tester.pumpAndSettle();
      expect(container.read(aiSettingsProvider).apiKey, isNull);
      expect(find.text('🔑 Chave Gemini (BYOK) necessária'), findsOneWidget);
    });

    testWidgets('does not overwrite live code or show false success toast when injection fails on invalid screen', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync('flrd_engine_fail_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      const brokenCode = 'class BrokenScreen { int value() => 42; }';
      File(p.join(tempDir.path, 'lib/features/dashboard/dashboard_screen.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(brokenCode);

      final localProject = RegisteredProject(
        id: 'engine_proj_fail',
        name: 'engine_fail_app',
        orgId: 'com.engine.fail',
        path: tempDir.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 1,
      );

      var callIndex = 0;
      final mockClient = _MockHttpClient((request) async {
        callIndex++;
        if (callIndex == 1) {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text': jsonEncode({
                          'goalSummary': 'Card simples',
                          'widgetName': 'SimpleCard',
                          'architectureType': 'statelessSnippet',
                          'placementStrategy': 'inlineInScreen',
                          'visualAnchorDescription': 'No topo da tela',
                          'insertionAnchorHint': 'top_of_body',
                        }),
                      }
                    ],
                  },
                }
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'id': 'var_1',
                        'title': 'Simple Card',
                        'styleTag': 'Minimal',
                        'description': 'Simple card widget.',
                        'techApproach': 'StatelessWidget',
                        'dartCode': "const Text('Simple')",
                      }),
                    }
                  ],
                },
              }
            ],
          }),
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.inMemory(
              const AiSettingsState(apiKey: 'AIzaTestKey'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      String liveCode = brokenCode;
      var codeChangedCalled = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return SingleChildScrollView(
                    child: ScreenMaterialsBuilder(
                      node: testNode,
                      project: localProject,
                      currentCode: liveCode,
                      aiHttpClient: mockClient,
                      onCodeChanged: (newCode) {
                        codeChangedCalled = true;
                        setState(() => liveCode = newCode);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('widget_creator_prompt_input')),
        'Card simples',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await _pumpThroughRealAsync(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('generate_from_plan_button')),
      );
      await tester.tap(find.byKey(const ValueKey('generate_from_plan_button')));
      await _pumpThroughRealAsync(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('choose_variation_button_0')),
      );
      await tester.tap(find.byKey(const ValueKey('choose_variation_button_0')));
      await _pumpThroughRealAsync(tester);

      expect(codeChangedCalled, isFalse);
      expect(liveCode, equals(brokenCode));
      expect(find.byKey(const ValueKey('widget_ai_error_banner')), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
