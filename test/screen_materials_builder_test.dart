import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/ai_screen_generator_dialog.dart';
import 'package:flrd/features/studio/presentation/widgets/screen_materials_builder.dart';
import 'package:flrd/features/studio/providers/android_debug_provider.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/studio/services/android_device_runner_service.dart';
import 'package:flrd/features/ai/providers/ai_settings_provider.dart';
import 'package:flrd/features/ai/services/gemini_ai_service.dart';

class _TrackingAndroidDebugNotifier extends AndroidDebugNotifier {
  final List<String> onCodeSavedPaths = [];

  _TrackingAndroidDebugNotifier() : super(AndroidDeviceRunnerService());

  @override
  void onCodeSaved(String projectPath) {
    onCodeSavedPaths.add(projectPath);
    super.onCodeSaved(projectPath);
  }
}

class _MockGeminiHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  _MockGeminiHttpClient(this.handler);

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

Map<String, dynamic> _geminiTextPayload(String text) {
  return {
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  };
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

  final dummyProject = RegisteredProject(
    id: 'proj_materials_test',
    name: 'Materials Test Project',
    orgId: 'com.materials.test',
    path: Directory.systemTemp.path,
    preset: PresetType.cleanLite,
    navigationStyle: NavigationStyle.tabs,
    permissions: const {},
    lastModified: DateTime.now(),
    routeCount: 4,
  );

  const testNode = RouteNode(
    id: 'login',
    title: 'LoginScreen',
    subtitle: 'Autenticação',
    path: '/auth/login',
    filePath: 'lib/features/auth/login_screen.dart',
    position: Offset(100, 100),
    isProtected: false,
    icon: Icons.login_rounded,
  );

  const sampleDartCode = '''
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Entrar'),
        leading: const Icon(Icons.arrow_back),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Text(
              'Bem-vindo de volta!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              'Acesse com suas credenciais',
              style: TextStyle(fontSize: 14),
            ),
            TextField(
              decoration: InputDecoration(
                labelText: 'E-mail ou Usuário',
                hintText: 'user@flrd.dev',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            TextFormField(
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Senha de Acesso',
                hintText: '••••••••',
                prefixIcon: Icon(Icons.lock_rounded),
              ),
            ),
            ElevatedButton(
              onPressed: () {},
              child: const Text('Entrar na Conta'),
            ),
          ],
        ),
      ),
    );
  }
}
''';

  group('ScreenMaterialParser & Domain Integration', () {
    test('extractMaterialsFromCode extracts AppBar, Text, Inputs, and Buttons', () {
      final materials = ScreenMaterialParser.extractMaterialsFromCode(
        sampleDartCode,
        testNode.title,
      );

      expect(materials.length, greaterThanOrEqualTo(4));
      expect(materials.any((m) => m.type == ScreenMaterialType.appBar), isTrue);
      expect(materials.any((m) => m.type == ScreenMaterialType.headerText), isTrue);
      expect(materials.any((m) => m.type == ScreenMaterialType.textInput), isTrue);
      expect(materials.any((m) => m.type == ScreenMaterialType.passwordInput), isTrue);
      expect(materials.any((m) => m.type == ScreenMaterialType.primaryButton), isTrue);
    });

    test('extractMaterialsFromCode extracts Cards, Containers, Icons, Switches and Checkboxes', () {
      const complexCode = '''
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel de Controle'),
      ),
      body: Column(
        children: [
          Card(
            child: Text('Card de Saldo'),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text('Card de Investimentos'),
          ),
          Icon(Icons.stars_rounded),
          SwitchListTile(
            title: const Text('Notificações Ativas'),
            value: true,
            onChanged: (v) {},
          ),
          CheckboxListTile(
            title: const Text('Aceito os Termos'),
            value: true,
            onChanged: (v) {},
          ),
        ],
      ),
    );
  }
}
''';

      final materials = ScreenMaterialParser.extractMaterialsFromCode(
        complexCode,
        'DashboardScreen',
      );

      expect(materials.any((m) => m.type == ScreenMaterialType.appBar), isTrue);
      expect(materials.where((m) => m.type == ScreenMaterialType.containerCard).length, equals(2));
      expect(materials.any((m) => m.type == ScreenMaterialType.icon), isTrue);
      expect(materials.any((m) => m.type == ScreenMaterialType.switchTile), isTrue);
      expect(materials.any((m) => m.type == ScreenMaterialType.checkboxTile), isTrue);
    });

    test('addMaterialToCode emits matching AST widget elements in generated code', () {
      final cardMat = const ScreenMaterialItem(
        id: 'palette_card',
        type: ScreenMaterialType.containerCard,
        label: 'Card VIP',
      ).createInstance();

      final codeWithCard = ScreenMaterialCodeUpdater.addMaterialToCode(
        currentCode: sampleDartCode,
        newMaterial: cardMat,
        screenClassName: testNode.title,
        routePath: testNode.path,
        routeTitle: testNode.title,
      );

      // Verify AST code elements are emitted
      expect(codeWithCard, contains('Container('));
      expect(codeWithCard, contains('BoxDecoration('));
      expect(codeWithCard, contains('Card VIP'));
      expect(codeWithCard, contains('AppColors.surfaceCard'));

      // Verify AST code parses back with the new element present
      final extracted = ScreenMaterialParser.extractMaterialsFromCode(
        codeWithCard,
        testNode.title,
      );
      expect(extracted.any((m) => m.type == ScreenMaterialType.containerCard && m.label == 'Card VIP'), isTrue);
    });

    test('addMaterialToCode appends new material and returns valid Dart code', () {
      final newMat = const ScreenMaterialItem(
        id: 'palette_social_button',
        type: ScreenMaterialType.socialButton,
        label: 'Continuar com Google',
      ).createInstance();

      final updatedCode = ScreenMaterialCodeUpdater.addMaterialToCode(
        currentCode: sampleDartCode,
        newMaterial: newMat,
        screenClassName: testNode.title,
        routePath: testNode.path,
        routeTitle: testNode.title,
        isProtected: testNode.isProtected,
      );

      expect(updatedCode, contains('LoginScreen'));
      expect(updatedCode, contains('Continuar com Google'));

      final parsedAgain = ScreenMaterialParser.extractMaterialsFromCode(
        updatedCode,
        testNode.title,
      );
      expect(parsedAgain.any((m) => m.type == ScreenMaterialType.socialButton), isTrue);
    });

    test('removeMaterialAtIndexInCode deletes material from code', () {
      final materialsBefore = ScreenMaterialParser.extractMaterialsFromCode(
        sampleDartCode,
        testNode.title,
      );
      expect(materialsBefore.isNotEmpty, isTrue);

      final updatedCode = ScreenMaterialCodeUpdater.removeMaterialAtIndexInCode(
        currentCode: sampleDartCode,
        index: 0,
        screenClassName: testNode.title,
        routePath: testNode.path,
        routeTitle: testNode.title,
      );

      final materialsAfter = ScreenMaterialParser.extractMaterialsFromCode(
        updatedCode,
        testNode.title,
      );
      expect(materialsAfter.length, equals(materialsBefore.length - 1));
    });

    test('reorderMaterialsInCode swaps positions of materials in code', () {
      final baseCode = ScreenMaterialCodeUpdater.buildDartCodeFromMaterials(
        screenClassName: 'DemoScreen',
        routePath: '/demo',
        materials: [
          const ScreenMaterialItem(
            id: 'head_0',
            type: ScreenMaterialType.headerText,
            label: 'Topo',
          ),
          const ScreenMaterialItem(
            id: 'sub_1',
            type: ScreenMaterialType.subtitleText,
            label: 'Meio',
          ),
          const ScreenMaterialItem(
            id: 'btn_2',
            type: ScreenMaterialType.primaryButton,
            label: 'Fim',
          ),
        ],
      );

      final reorderedCode = ScreenMaterialCodeUpdater.reorderMaterialsInCode(
        currentCode: baseCode,
        oldIndex: 2,
        newIndex: 0,
        screenClassName: 'DemoScreen',
        routePath: '/demo',
      );

      final materialsAfter = ScreenMaterialParser.extractMaterialsFromCode(
        reorderedCode,
        'DemoScreen',
      );
      expect(materialsAfter[0].label, equals('Fim'));
      expect(materialsAfter[1].label, equals('Topo'));
      expect(materialsAfter[2].label, equals('Meio'));
    });
  });

  group('ScreenMaterialsBuilder Widget Tests', () {
    testWidgets('Renders Criador de Widgets com IA, honest BYOK Gemini 2.5 controls, placement input, and Widgets nesta Tela stack',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenMaterialsBuilder(
                node: testNode,
                project: dummyProject,
                currentCode: currentCode,
                onCodeChanged: (newCode) => currentCode = newCode,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Criador Header & Plan-First Inputs
      expect(find.text('Criador de Widgets com IA'), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_prompt_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_placement_prompt_input')), findsOneWidget);
      expect(find.text('Onde deseja posicionar na tela? (com suas palavras)'), findsOneWidget);

      // Verify Honest BYOK Controls (NO fake Pro Cloud or Gemini 1.5 badges)
      expect(find.byKey(const ValueKey('widget_creator_status_indicator')), findsOneWidget);
      expect(find.text('🔑 Chave Gemini (BYOK) necessária'), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_model_flash')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_model_pro')), findsOneWidget);
      expect(find.text('Gemini 2.5 Flash'), findsOneWidget);
      expect(find.text('Gemini 2.5 Pro'), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_api_key_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_api_key_save_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_provider_cloud')), findsNothing);
      expect(find.text('⚡ FLRD Pro Cloud'), findsNothing);
      expect(find.text('🟢 Gemini 1.5 Flash Ativo'), findsNothing);

      // Verify Inspiration Chips
      expect(find.text('👤 Foto de Perfil & Boas-Vindas'), findsOneWidget);
      expect(find.text('📊 Faturamento & Lucro'), findsOneWidget);
      expect(find.text('⚽ Bola Pingando (Física/Animação)'), findsOneWidget);
      expect(find.text('💳 Seletor Pix/Cartão'), findsOneWidget);
      expect(find.text('🔍 Busca com Filtro'), findsOneWidget);

      // Verify Plan Button
      expect(find.byKey(const ValueKey('generate_widget_variations_button')), findsOneWidget);
      expect(find.text('Planejar Widget (Gemini 2.5)'), findsOneWidget);

      // Verify Bottom Section Header & Refine Button
      expect(find.textContaining('Widgets nesta Tela'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_enhance_materials_button')), findsOneWidget);
      expect(find.text('✨ Refinar Tela Inteira com IA'), findsOneWidget);

      // Verify Materials Stack items
      expect(find.byKey(const ValueKey('screen_materials_list')), findsOneWidget);
      expect(find.byKey(const ValueKey('material_item_0')), findsOneWidget);
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
                project: dummyProject,
                currentCode: sampleDartCode,
                onCodeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert legacy palette header, chips, and drag targets are completely absent
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

    testWidgets('Unconfigured BYOK blocks generation without fake cards, allows inline key save/edit/clear & Gemini 2.5 Flash/Pro switch',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;
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
                  project: dummyProject,
                  currentCode: currentCode,
                  onCodeChanged: (newCode) => currentCode = newCode,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unconfigured initial state
      expect(find.text('🔑 Chave Gemini (BYOK) necessária'), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_api_key_input')), findsOneWidget);

      // Clicking Plan without API key blocks and shows error banner, NEVER fake boxes
      await tester.enterText(
        find.byKey(const ValueKey('widget_creator_prompt_input')),
        'Um relogio digital muito bonito',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('generate_widget_variations_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('widget_ai_error_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_execution_plan_card')), findsNothing);
      expect(find.byKey(const ValueKey('choose_variation_button_0')), findsNothing);
      expect(find.textContaining('Relogio Digital Muito'), findsNothing);

      // Enter API key and click Save
      final keyInput = find.byKey(const ValueKey('widget_creator_api_key_input'));
      await tester.enterText(keyInput, 'AIzaTestGeminiKey777');
      await tester.tap(find.byKey(const ValueKey('widget_creator_api_key_save_button')));
      await tester.pumpAndSettle();

      expect(container.read(aiSettingsProvider).apiKey, equals('AIzaTestGeminiKey777'));
      expect(find.text('⚡ BYOK Ativo · Gemini 2.5 Flash'), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_ai_error_banner')), findsNothing);

      // Switch model to Gemini 2.5 Pro
      await tester.tap(find.byKey(const ValueKey('widget_creator_model_pro')));
      await tester.pumpAndSettle();

      expect(
        container.read(aiSettingsProvider).selectedModel,
        equals(AiSettingsState.geminiProModel),
      );
      expect(find.text('⚡ BYOK Ativo · Gemini 2.5 Pro'), findsOneWidget);

      // Switch back to Gemini 2.5 Flash
      await tester.tap(find.byKey(const ValueKey('widget_creator_model_flash')));
      await tester.pumpAndSettle();

      expect(
        container.read(aiSettingsProvider).selectedModel,
        equals(AiSettingsState.geminiFlashModel),
      );
      expect(find.text('⚡ BYOK Ativo · Gemini 2.5 Flash'), findsOneWidget);

      // Edit & replace key inline
      await tester.tap(find.byKey(const ValueKey('widget_creator_api_key_edit_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('widget_creator_api_key_input')),
        'AIzaUpdatedKey888',
      );
      await tester.tap(find.byKey(const ValueKey('widget_creator_api_key_save_button')));
      await tester.pumpAndSettle();

      expect(container.read(aiSettingsProvider).apiKey, equals('AIzaUpdatedKey888'));

      // Clear key inline
      await tester.tap(find.byKey(const ValueKey('widget_creator_api_key_clear_button')));
      await tester.pumpAndSettle();

      expect(container.read(aiSettingsProvider).apiKey, isNull);
      expect(find.text('🔑 Chave Gemini (BYOK) necessária'), findsOneWidget);
    });

    testWidgets('Delete button removes material item', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ScreenMaterialsBuilder(
                    node: testNode,
                    project: dummyProject,
                    currentCode: currentCode,
                    onCodeChanged: (newCode) {
                      setState(() => currentCode = newCode);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final initialCount = ScreenMaterialParser.extractMaterialsFromCode(
        currentCode,
        testNode.title,
      ).length;

      // Click delete on first item
      final deleteBtn = find.byKey(const ValueKey('material_delete_0'));
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      final afterCount = ScreenMaterialParser.extractMaterialsFromCode(
        currentCode,
        testNode.title,
      ).length;
      expect(afterCount, equals(initialCount - 1));
    });

    testWidgets('Reorder Up and Down buttons swap materials', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ScreenMaterialsBuilder(
                    node: testNode,
                    project: dummyProject,
                    currentCode: currentCode,
                    onCodeChanged: (newCode) {
                      setState(() => currentCode = newCode);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final downBtn = find.byKey(const ValueKey('material_down_0'));
      expect(downBtn, findsOneWidget);
      await tester.tap(downBtn);
      await tester.pumpAndSettle();

      final upBtn = find.byKey(const ValueKey('material_up_1'));
      expect(upBtn, findsOneWidget);
      await tester.tap(upBtn);
      await tester.pumpAndSettle();
    });

    testWidgets('Clicking AI Enhance button opens AiScreenGeneratorDialog with pre-filled prompt',
        (tester) async {
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
                  project: dummyProject,
                  currentCode: sampleDartCode,
                  onCodeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final aiButton = find.byKey(const ValueKey('ai_enhance_materials_button'));
      expect(aiButton, findsOneWidget);
      await tester.tap(aiButton);
      await tester.pumpAndSettle();

      // Verify that AiScreenGeneratorDialog opened
      expect(find.byType(AiScreenGeneratorDialog), findsOneWidget);
      expect(find.text('LoginScreen'), findsWidgets);
    });

    testWidgets('Prompt clear button clears the widget creator text field',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenMaterialsBuilder(
                node: testNode,
                project: dummyProject,
                currentCode: currentCode,
                onCodeChanged: (newCode) => currentCode = newCode,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final input = find.byKey(const ValueKey('widget_creator_prompt_input'));
      await tester.enterText(input, 'Card com animação de pulso');
      await tester.pumpAndSettle();

      // Clear button should be visible
      final clearBtn = find.byKey(const ValueKey('widget_creator_prompt_clear'));
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      final textWidget = tester.widget<TextField>(input);
      expect(textWidget.controller?.text, isEmpty);
      expect(find.byKey(const ValueKey('widget_creator_prompt_clear')), findsNothing);
    });

    testWidgets('Adding, editing, and clearing a component note updates UI and code',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ScreenMaterialsBuilder(
                    node: testNode,
                    project: dummyProject,
                    currentCode: currentCode,
                    onCodeChanged: (newCode) => setState(() => currentCode = newCode),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial note button exists
      final noteButton = find.byKey(const ValueKey('material_note_button_0'));
      expect(noteButton, findsOneWidget);

      // Open note dialog
      await tester.tap(noteButton);
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Anotação / Prompt do Widget'), findsOneWidget);
      expect(find.byKey(const ValueKey('material_note_text_field')), findsOneWidget);

      // Enter behavioral prompt
      await tester.enterText(
        find.byKey(const ValueKey('material_note_text_field')),
        'Botão azul com feedback tátil e validação assíncrona',
      );
      await tester.pumpAndSettle();

      // Save note
      await tester.tap(find.byKey(const ValueKey('material_note_dialog_save')));
      await tester.pumpAndSettle();

      // Note card should now be visible with italic quote
      expect(find.byKey(const ValueKey('material_note_card_0')), findsOneWidget);
      expect(
        find.text('"Botão azul com feedback tátil e validação assíncrona"'),
        findsOneWidget,
      );

      // Single-widget AI Refine button should also be visible on annotated card
      expect(find.byKey(const ValueKey('material_ai_refine_0')), findsOneWidget);
      expect(find.text('✨ Refinar este Widget com IA'), findsOneWidget);

      // Code should now contain the note comment
      expect(currentCode, contains('Botão azul com feedback tátil'));

      // Edit the note
      await tester.tap(find.byKey(const ValueKey('material_note_edit_0')));
      await tester.pumpAndSettle();

      expect(find.text('Anotação / Prompt do Widget'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('material_note_text_field')),
        'Nota atualizada com animação suave',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('material_note_dialog_save')));
      await tester.pumpAndSettle();

      expect(find.text('"Nota atualizada com animação suave"'), findsOneWidget);

      // Clear the note
      await tester.tap(find.byKey(const ValueKey('material_note_clear_0')));
      await tester.pumpAndSettle();

      // Note card should be gone, note button should be back
      expect(find.byKey(const ValueKey('material_note_card_0')), findsNothing);
      expect(find.byKey(const ValueKey('material_note_button_0')), findsOneWidget);
    });

    testWidgets('Clicking [✨ Refinar este Widget com IA] triggers focused AiScreenGeneratorDialog',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScreenMaterialsBuilder(
                  node: testNode,
                  project: dummyProject,
                  currentCode: currentCode,
                  onCodeChanged: (newCode) => currentCode = newCode,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Add a note first so the card becomes annotated
      await tester.tap(find.byKey(const ValueKey('material_note_button_0')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('material_note_text_field')),
        'Barra de topo transparente com blur glassmorphism',
      );
      await tester.tap(find.byKey(const ValueKey('material_note_dialog_save')));
      await tester.pumpAndSettle();

      // Now tap the [✨ Refinar este Widget com IA] button
      final refineButton = find.byKey(const ValueKey('material_ai_refine_0'));
      expect(refineButton, findsOneWidget);
      await tester.tap(refineButton);
      await tester.pumpAndSettle();

      // AiScreenGeneratorDialog should open in widget-focused mode
      expect(find.byType(AiScreenGeneratorDialog), findsOneWidget);
      expect(find.textContaining('Refinar Widget com IA:'), findsOneWidget);
      expect(find.text('✨ Refinar e Injetar Widget'), findsOneWidget);
    });
  });

  group('AppStudioScreen Route Details Materials Integration', () {
    testWidgets('AppStudioScreen details tab displays ScreenMaterialsBuilder without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      final node = container.read(studioProvider).nodes.first;
      container.read(studioProvider.notifier).selectNode(node.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: dummyProject),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Inspector details tab should contain ScreenMaterialsBuilder
      expect(find.byType(ScreenMaterialsBuilder), findsOneWidget);
      expect(find.textContaining('Widgets nesta Tela'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_enhance_materials_button')), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });

  group('ScreenMaterialsBuilder Criador de Widgets com IA Integration', () {
    testWidgets('renders Criador de Widgets com IA prompt input, placement input, inspiration chips, and Plan button',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenMaterialsBuilder(
                node: testNode,
                project: dummyProject,
                currentCode: currentCode,
                onCodeChanged: (newCode) => currentCode = newCode,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header and creator components
      expect(find.text('Criador de Widgets com IA'), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_creator_prompt_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_placement_prompt_input')), findsOneWidget);
      expect(find.text('👤 Foto de Perfil & Boas-Vindas'), findsOneWidget);
      expect(find.text('📊 Faturamento & Lucro'), findsOneWidget);
      expect(find.text('⚽ Bola Pingando (Física/Animação)'), findsOneWidget);
      expect(find.text('💳 Seletor Pix/Cartão'), findsOneWidget);
      expect(find.text('🔍 Busca com Filtro'), findsOneWidget);
      expect(find.byKey(const ValueKey('generate_widget_variations_button')), findsOneWidget);
      expect(find.text('Planejar Widget (Gemini 2.5)'), findsOneWidget);

      // Verify Screen Materials Stack below remains intact
      expect(find.textContaining('Widgets nesta Tela'), findsOneWidget);
    });

    testWidgets('clicking an inspiration chip fills the prompt input field', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenMaterialsBuilder(
                node: testNode,
                project: dummyProject,
                currentCode: currentCode,
                onCodeChanged: (newCode) => currentCode = newCode,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Click on '👤 Foto de Perfil & Boas-Vindas'
      await tester.tap(find.text('👤 Foto de Perfil & Boas-Vindas'));
      await tester.pumpAndSettle();

      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('widget_creator_prompt_input')),
      );
      expect(input.controller?.text, contains('foto de perfil'));
    });

    testWidgets(
        'Plan -> Preview -> Execute with mocked Gemini 2.5 HTTP client creates extracted DigitalClock StatefulWidget and inserts below Welcome card',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync('flrd_builder_plan_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      const initialHomeCode = '''import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Column(
        children: const [
          Text('Welcome'),
          SizedBox(height: 16),
          ElevatedButton(onPressed: null, child: Text('Continue')),
        ],
      ),
    );
  }
}
''';

      File(p.join(tempDir.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: demo_clock_app
version: 1.0.0+1
environment:
  sdk: ">=3.2.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
      File(p.join(tempDir.path, 'lib/features/home/home_screen.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(initialHomeCode);

      final project = RegisteredProject(
        id: 'proj_clock_plan',
        name: 'demo_clock_app',
        orgId: 'com.demo.clock',
        path: tempDir.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 1,
      );
      const node = RouteNode(
        id: 'home',
        title: 'HomeScreen',
        subtitle: 'Início',
        path: '/home',
        filePath: 'lib/features/home/home_screen.dart',
        position: Offset(100, 100),
        isProtected: false,
        icon: Icons.home_rounded,
      );

      const clockStatefulCode = '''import 'dart:async';
import 'package:flutter/material.dart';

class DigitalClock extends StatefulWidget {
  const DigitalClock({super.key});

  @override
  State<DigitalClock> createState() => _DigitalClockState();
}

class _DigitalClockState extends State<DigitalClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();
  int _styleIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
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
      child: Text('\${_now.hour}:\${_now.minute}:\${_now.second}'),
    );
  }
}''';

      var requestCount = 0;
      late String capturedPlanRequestBody;
      final mockClient = _MockGeminiHttpClient((request) async {
        requestCount++;
        expect(request.url.toString(), contains('gemini-2.5-flash'));
        if (requestCount == 1) {
          capturedPlanRequestBody = request.body;
          return http.Response(
            jsonEncode(
              _geminiTextPayload(
                jsonEncode({
                  'goalSummary':
                      'Relógio digital em tempo real que alterna estilos ao toque.',
                  'widgetName': 'DigitalClock',
                  'architectureType': 'statefulWidgetClass',
                  'stateFields': [
                    'Timer? _timer',
                    'DateTime _now',
                    'int _styleIndex',
                  ],
                  'interactions': ['onTap alterna _styleIndex'],
                  'requiredImports': [
                    'dart:async',
                    'package:flutter/material.dart',
                  ],
                  'requiredPackages': [],
                  'placementStrategy': 'separateWidgetFile',
                  'targetFilePath': 'lib/features/home/home_screen.dart',
                  'extractedWidgetFilePath':
                      'lib/features/home/widgets/digital_clock.dart',
                  'visualAnchorDescription':
                      'Logo abaixo do card Welcome na Column principal',
                  'insertionAnchorHint': 'after_text:Welcome',
                }),
              ),
            ),
            200,
          );
        }

        return http.Response(
          jsonEncode(
            _geminiTextPayload(
              jsonEncode({
                'id': 'clock_plan_1',
                'title': 'Digital Clock Interativo',
                'styleTag': 'Stateful Clock',
                'description':
                    'Relógio digital ao vivo com Timer.periodic e estilos por toque.',
                'techApproach': 'StatefulWidget + Timer.periodic + _styleIndex',
                'requiredImports': [
                  'dart:async',
                  'package:flutter/material.dart',
                ],
                'extractedWidgetCode': clockStatefulCode,
                'callSiteSnippet': 'const DigitalClock()',
                'dartCode': clockStatefulCode,
              }),
            ),
          ),
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.inMemory(
              const AiSettingsState(
                apiKey: 'AIzaLiveTestKey',
                selectedModel: AiSettingsState.geminiFlashModel,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      String currentCode = initialHomeCode;
      var onCodeChangedCount = 0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return SingleChildScrollView(
                    child: ScreenMaterialsBuilder(
                      node: node,
                      project: project,
                      currentCode: currentCode,
                      aiHttpClient: mockClient,
                      onCodeChanged: (newCode) {
                        onCodeChangedCount++;
                        setState(() => currentCode = newCode);
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

      expect(find.text('⚡ BYOK Ativo · Gemini 2.5 Flash'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('widget_creator_prompt_input')),
        'Relógio digital que troca de estilo ao clicar',
      );
      await tester.enterText(
        find.byKey(const ValueKey('widget_placement_prompt_input')),
        'logo abaixo do card Welcome',
      );
      await tester.pumpAndSettle();

      // Step 1: Plan
      await tester.ensureVisible(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await _pumpThroughRealAsync(tester);

      expect(requestCount, equals(1));
      expect(capturedPlanRequestBody, contains('logo abaixo do card Welcome'));
      expect(find.byKey(const ValueKey('widget_execution_plan_card')), findsOneWidget);
      expect(find.text('DigitalClock'), findsOneWidget);
      expect(find.text('StatefulWidget'), findsOneWidget);
      expect(find.text('Onde será inserido:'), findsOneWidget);
      expect(
        find.text('Logo abaixo do card Welcome na Column principal'),
        findsOneWidget,
      );
      expect(find.text('Timer? _timer'), findsOneWidget);
      expect(find.text('int _styleIndex'), findsOneWidget);
      expect(find.byKey(const ValueKey('replan_widget_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('generate_from_plan_button')), findsOneWidget);

      // Step 2: Generate Code from Plan
      await tester.ensureVisible(
        find.byKey(const ValueKey('generate_from_plan_button')),
      );
      await tester.tap(find.byKey(const ValueKey('generate_from_plan_button')));
      await _pumpThroughRealAsync(tester);

      expect(requestCount, equals(2));
      expect(find.text('✅ Plano Aprovado'), findsOneWidget);
      expect(find.text('Digital Clock Interativo'), findsOneWidget);

      // Toggle code preview and verify imports + StatefulWidget + callSite
      await tester.ensureVisible(
        find.byKey(const ValueKey('toggle_variation_code_button_0')),
      );
      await tester.tap(
        find.byKey(const ValueKey('toggle_variation_code_button_0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('👁️ Ocultar Código'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SelectableText),
          matching: find.textContaining('Timer.periodic'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SelectableText),
          matching: find.textContaining('const DigitalClock()'),
        ),
        findsOneWidget,
      );

      // Step 3: Insert Widget into Screen
      final chooseBtn = find.byKey(const ValueKey('choose_variation_button_0'));
      expect(chooseBtn, findsOneWidget);
      await tester.ensureVisible(chooseBtn);
      await tester.tap(chooseBtn);
      await _pumpThroughRealAsync(tester);

      expect(onCodeChangedCount, equals(1));

      // Verify extracted widget file on disk
      final widgetFile = File(
        p.join(tempDir.path, 'lib/features/home/widgets/digital_clock.dart'),
      );
      expect(widgetFile.existsSync(), isTrue);
      final widgetContent = widgetFile.readAsStringSync();
      expect(widgetContent, contains("import 'dart:async';"));
      expect(widgetContent, contains('class DigitalClock extends StatefulWidget'));
      expect(widgetContent, contains('Timer.periodic'));
      expect(widgetContent, contains('_styleIndex'));

      // Verify screen file updated at exact anchor below Welcome & before Continue
      final screenContent = File(
        p.join(tempDir.path, 'lib/features/home/home_screen.dart'),
      ).readAsStringSync();
      expect(currentCode, equals(screenContent));
      expect(
        screenContent,
        contains("import 'package:demo_clock_app/features/home/widgets/digital_clock.dart';"),
      );
      expect(screenContent, isNot(contains('children: const [')));

      final welcomePos = screenContent.indexOf("Text('Welcome')");
      final clockPos = screenContent.indexOf('const DigitalClock()');
      final continuePos = screenContent.indexOf("Text('Continue')");
      expect(welcomePos, greaterThan(-1));
      expect(clockPos, greaterThan(welcomePos));
      expect(continuePos, greaterThan(clockPos));

      expect(find.byKey(const ValueKey('widget_injection_result_banner')), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('GeminiAiService.synthesizeWidgetVariations Deep Synthesis Tests', () {
    test('synthesizes bouncing ball with animation controllers, Curves.bounceOut, and spherical decorations', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'Uma bola que fica pingando',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);

      final var1 = variations[0];
      expect(var1.title, contains('Bouncing Physics Ball'));
      expect(var1.techApproach, contains('Curves.bounceOut'));
      expect(var1.dartCode, contains('TweenAnimationBuilder'));
      expect(var1.dartCode, contains('Curves.bounceOut'));
      expect(var1.dartCode, contains('BoxShape.circle'));
      expect(var1.dartCode, contains('RadialGradient'));
      expect(var1.dartCode, contains('shadowScale'));

      final var2 = variations[1];
      expect(var2.title, contains('Glowing Pulse Sphere'));
      expect(var2.dartCode, contains('TweenAnimationBuilder'));
      expect(var2.dartCode, contains('BoxShape.circle'));
      expect(var2.dartCode, contains('RadialGradient'));

      final var3 = variations[2];
      expect(var3.title, contains('Interactive Spring Ball'));
      expect(var3.dartCode, contains('Curves.elasticOut'));
      expect(var3.dartCode, contains('BoxShape.circle'));
    });

    test('synthesizes metric cards with extracted user terms (Faturamento Mensal, Lucro)', () {
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

    test('synthesizes arbitrary custom prompt reflecting extracted user keywords', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'dispositivo rastreador veicular com velocímetro digital',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations[0].title, contains('Dispositivo'));
      expect(variations[0].title, contains('Rastreador'));
      expect(variations[0].dartCode, contains('Dispositivo'));
      expect(variations[1].title, contains('Dispositivo'));
    });
  });

  group('ScreenMaterialsBuilder Error Handling & Injection Failure Guarantees', () {
    testWidgets('shows widget_ai_error_banner without dummy cards on Gemini HTTP 401 and supports Ajustar / Replanejar',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var returnError = true;
      final mockClient = _MockGeminiHttpClient((request) async {
        if (returnError) {
          return http.Response(
            jsonEncode({
              'error': {'code': 401, 'message': 'Invalid API Key'},
            }),
            401,
          );
        }
        return http.Response(
          jsonEncode(
            _geminiTextPayload(
              jsonEncode({
                'goalSummary': 'Banner informativo',
                'widgetName': 'InfoBannerWidget',
                'architectureType': 'statelessSnippet',
                'stateFields': [],
                'interactions': [],
                'requiredImports': ['package:flutter/material.dart'],
                'requiredPackages': [],
                'placementStrategy': 'inlineInScreen',
                'visualAnchorDescription': 'No topo da tela',
                'insertionAnchorHint': 'top_of_body',
              }),
            ),
          ),
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.inMemory(
              const AiSettingsState(apiKey: 'AIzaBadKey'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      String liveCode = sampleDartCode;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScreenMaterialsBuilder(
                  node: testNode,
                  project: dummyProject,
                  currentCode: liveCode,
                  aiHttpClient: mockClient,
                  onCodeChanged: (newCode) => liveCode = newCode,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('widget_creator_prompt_input')),
        'Banner de alerta',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await _pumpThroughRealAsync(tester);

      expect(find.byKey(const ValueKey('widget_ai_error_banner')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('widget_ai_error_banner')),
          matching: find.textContaining('HTTP 401'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('HTTP 401'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('widget_execution_plan_card')), findsNothing);
      expect(find.byKey(const ValueKey('choose_variation_button_0')), findsNothing);
      expect(liveCode, equals(sampleDartCode));

      // Recover and verify Replan clears plan card cleanly
      returnError = false;
      await tester.ensureVisible(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('generate_widget_variations_button')),
      );
      await _pumpThroughRealAsync(tester);

      expect(find.byKey(const ValueKey('widget_execution_plan_card')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('replan_widget_button')),
      );
      await tester.tap(find.byKey(const ValueKey('replan_widget_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('widget_execution_plan_card')), findsNothing);
      expect(liveCode, equals(sampleDartCode));
    });

    testWidgets('shows AppToast.error and inline banner without overwriting code when DartWidgetInjectorService fails',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync('flrd_builder_fail_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      const unplaceableScreen = 'class BrokenNoScaffold { int x() => 1; }';
      File(p.join(tempDir.path, 'lib/broken_screen.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(unplaceableScreen);

      final project = RegisteredProject(
        id: 'proj_fail_inject',
        name: 'fail_app',
        orgId: 'com.fail.app',
        path: tempDir.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 1,
      );
      const node = RouteNode(
        id: 'broken',
        title: 'BrokenNoScaffold',
        subtitle: 'Broken',
        path: '/broken',
        filePath: 'lib/broken_screen.dart',
        position: Offset(0, 0),
        isProtected: false,
        icon: Icons.broken_image_rounded,
      );

      var callIdx = 0;
      final mockClient = _MockGeminiHttpClient((request) async {
        callIdx++;
        if (callIdx == 1) {
          return http.Response(
            jsonEncode(
              _geminiTextPayload(
                jsonEncode({
                  'goalSummary': 'Widget de teste',
                  'widgetName': 'SampleBanner',
                  'architectureType': 'statelessSnippet',
                  'requiredImports': ['package:flutter/material.dart'],
                  'placementStrategy': 'inlineInScreen',
                  'visualAnchorDescription': 'No topo da tela',
                  'insertionAnchorHint': 'top_of_body',
                }),
              ),
            ),
            200,
          );
        }
        return http.Response(
          jsonEncode(
            _geminiTextPayload(
              jsonEncode({
                'id': 'var_fail',
                'title': 'Sample Banner',
                'styleTag': 'Card',
                'description': 'Simple banner',
                'techApproach': 'StatelessWidget',
                'dartCode': "const Text('Hello')",
              }),
            ),
          ),
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

      String liveCode = unplaceableScreen;
      var codeChangedCalled = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScreenMaterialsBuilder(
                  node: node,
                  project: project,
                  currentCode: liveCode,
                  aiHttpClient: mockClient,
                  onCodeChanged: (newCode) {
                    codeChangedCalled = true;
                    liveCode = newCode;
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
        'Banner simples',
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
      expect(liveCode, equals(unplaceableScreen));
      expect(
        File(p.join(tempDir.path, 'lib/broken_screen.dart')).readAsStringSync(),
        equals(unplaceableScreen),
      );
      expect(find.byKey(const ValueKey('widget_ai_error_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('widget_injection_result_banner')), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ScreenMaterialsBuilder Post-Injection Verification, Auto-Repair & Rollback', () {
    testWidgets(
        'runs flutter analyze after injection, renders ✅ Verificado badge, and triggers Hot Reload on pass',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync('flrd_verify_pass_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      const initialHomeCode = '''import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Column(
        children: const [
          Text('Welcome'),
          ElevatedButton(onPressed: null, child: Text('Go')),
        ],
      ),
    );
  }
}
''';

      File(p.join(tempDir.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: verify_pass_app
version: 1.0.0+1
environment:
  sdk: ">=3.2.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
      File(p.join(tempDir.path, 'lib/features/home/home_screen.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(initialHomeCode);

      final project = RegisteredProject(
        id: 'proj_verify_pass',
        name: 'verify_pass_app',
        orgId: 'com.verify.pass',
        path: tempDir.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 1,
      );
      const node = RouteNode(
        id: 'home',
        title: 'HomeScreen',
        subtitle: 'Início',
        path: '/home',
        filePath: 'lib/features/home/home_screen.dart',
        position: Offset(100, 100),
        isProtected: false,
        icon: Icons.home_rounded,
      );

      var requestCount = 0;
      final mockClient = _MockGeminiHttpClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(
            jsonEncode(
              _geminiTextPayload(
                jsonEncode({
                  'goalSummary': 'Relógio simples em tempo real',
                  'widgetName': 'SimpleClock',
                  'architectureType': 'statelessSnippet',
                  'requiredImports': ['package:flutter/material.dart'],
                  'placementStrategy': 'inlineInScreen',
                  'visualAnchorDescription': 'No topo da tela',
                  'insertionAnchorHint': 'top_of_body',
                }),
              ),
            ),
            200,
          );
        }
        return http.Response(
          jsonEncode(
            _geminiTextPayload(
              jsonEncode({
                'id': 'var_pass',
                'title': 'Simple Clock',
                'styleTag': 'Minimal',
                'description': 'Clean clock widget',
                'techApproach': 'StatelessWidget',
                'dartCode': "const Text('12:00')",
              }),
            ),
          ),
          200,
        );
      });

      final verifyCalls = <List<String>>[];
      Future<ProcessResult> passingRunner(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        verifyCalls.add(List<String>.from(args));
        return ProcessResult(1, 0, 'No issues found!\n', '');
      }

      final debugNotifier = _TrackingAndroidDebugNotifier();
      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.inMemory(
              const AiSettingsState(apiKey: 'AIzaVerifyPassKey'),
            ),
          ),
          androidDebugProvider.overrideWith((ref) => debugNotifier),
        ],
      );
      addTearDown(container.dispose);

      String liveCode = initialHomeCode;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return SingleChildScrollView(
                    child: ScreenMaterialsBuilder(
                      node: node,
                      project: project,
                      currentCode: liveCode,
                      aiHttpClient: mockClient,
                      verificationProcessRunner: passingRunner,
                      onCodeChanged: (newCode) =>
                          setState(() => liveCode = newCode),
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
        'Relógio simples',
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

      expect(verifyCalls, hasLength(1));
      expect(verifyCalls.single, contains('analyze'));
      expect(verifyCalls.single, contains('lib/features/home/home_screen.dart'));
      expect(debugNotifier.onCodeSavedPaths, equals([tempDir.path]));
      expect(find.text('✅ Verificado (flutter analyze)'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'auto-repairs analyzer error on injected screen, re-reads repaired code, renders ✅ Verificado, and triggers Hot Reload',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync('flrd_verify_repair_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      const initialHomeCode = '''import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Column(
        children: const [
          Text('Welcome'),
        ],
      ),
    );
  }
}
''';

      File(p.join(tempDir.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: verify_repair_app
version: 1.0.0+1
environment:
  sdk: ">=3.2.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
      final screenFile =
          File(p.join(tempDir.path, 'lib/features/home/home_screen.dart'))
            ..createSync(recursive: true)
            ..writeAsStringSync(initialHomeCode);

      final project = RegisteredProject(
        id: 'proj_verify_repair',
        name: 'verify_repair_app',
        orgId: 'com.verify.repair',
        path: tempDir.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 1,
      );
      const node = RouteNode(
        id: 'home',
        title: 'HomeScreen',
        subtitle: 'Início',
        path: '/home',
        filePath: 'lib/features/home/home_screen.dart',
        position: Offset(100, 100),
        isProtected: false,
        icon: Icons.home_rounded,
      );

      var requestCount = 0;
      final mockClient = _MockGeminiHttpClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(
            jsonEncode(
              _geminiTextPayload(
                jsonEncode({
                  'goalSummary': 'Badge com cor primária',
                  'widgetName': 'PrimaryBadge',
                  'architectureType': 'statelessSnippet',
                  'requiredImports': ['package:flutter/material.dart'],
                  'placementStrategy': 'inlineInScreen',
                  'visualAnchorDescription': 'No topo da tela',
                  'insertionAnchorHint': 'top_of_body',
                }),
              ),
            ),
            200,
          );
        }
        if (requestCount == 2) {
          return http.Response(
            jsonEncode(
              _geminiTextPayload(
                jsonEncode({
                  'id': 'var_repair',
                  'title': 'Primary Badge',
                  'styleTag': 'Badge',
                  'description': 'Badge widget',
                  'techApproach': 'Container',
                  'dartCode':
                      "Container(color: AppColors.primary, child: const Text('VIP'))",
                }),
              ),
            ),
            200,
          );
        }
        // Call 3: Gemini auto-repair patch replacing undefined AppColors.primary
        final patchesJson = jsonEncode({
          'patches': [
            {
              'relativePath': 'lib/features/home/home_screen.dart',
              'description':
                  'Substituir AppColors.primary por Theme.of(context).colorScheme.primary',
              'searchText':
                  "Container(color: AppColors.primary, child: const Text('VIP'))",
              'replaceText':
                  "Container(color: Theme.of(context).colorScheme.primary, child: const Text('VIP'))",
            },
          ],
        });
        return http.Response(
          jsonEncode(
            _geminiTextPayload(
              '### Correção\n```json\n$patchesJson\n```',
            ),
          ),
          200,
        );
      });

      var analyzeAttempt = 0;
      Future<ProcessResult> repairRunner(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        analyzeAttempt++;
        if (analyzeAttempt == 1) {
          return ProcessResult(
            201,
            1,
            "  error • Undefined name 'AppColors' • lib/features/home/home_screen.dart:12:30 • undefined_identifier\n",
            '',
          );
        }
        return ProcessResult(202, 0, 'No issues found!\n', '');
      }

      final debugNotifier = _TrackingAndroidDebugNotifier();
      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.inMemory(
              const AiSettingsState(apiKey: 'AIzaRepairKey'),
            ),
          ),
          androidDebugProvider.overrideWith((ref) => debugNotifier),
        ],
      );
      addTearDown(container.dispose);

      String liveCode = initialHomeCode;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return SingleChildScrollView(
                    child: ScreenMaterialsBuilder(
                      node: node,
                      project: project,
                      currentCode: liveCode,
                      aiHttpClient: mockClient,
                      verificationProcessRunner: repairRunner,
                      onCodeChanged: (newCode) =>
                          setState(() => liveCode = newCode),
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
        'Badge VIP',
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

      expect(analyzeAttempt, equals(2));
      expect(requestCount, equals(3));
      expect(liveCode, contains('Theme.of(context).colorScheme.primary'));
      expect(liveCode, isNot(contains('AppColors.primary')));
      expect(screenFile.readAsStringSync(), equals(liveCode));
      expect(debugNotifier.onCodeSavedPaths, equals([tempDir.path]));
      expect(find.text('✅ Verificado (flutter analyze)'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'blocks Hot Reload and green toast on persistent analyzer error, shows ⚠️ badge and 1-click Reverter Alterações restoring backup',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir =
          Directory.systemTemp.createTempSync('flrd_verify_rollback_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      const initialHomeCode = '''import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Column(
        children: const [
          Text('Welcome'),
        ],
      ),
    );
  }
}
''';

      File(p.join(tempDir.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: verify_rollback_app
version: 1.0.0+1
environment:
  sdk: ">=3.2.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
      final screenFile =
          File(p.join(tempDir.path, 'lib/features/home/home_screen.dart'))
            ..createSync(recursive: true)
            ..writeAsStringSync(initialHomeCode);

      final project = RegisteredProject(
        id: 'proj_verify_rollback',
        name: 'verify_rollback_app',
        orgId: 'com.verify.rollback',
        path: tempDir.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 1,
      );
      const node = RouteNode(
        id: 'home',
        title: 'HomeScreen',
        subtitle: 'Início',
        path: '/home',
        filePath: 'lib/features/home/home_screen.dart',
        position: Offset(100, 100),
        isProtected: false,
        icon: Icons.home_rounded,
      );

      var requestCount = 0;
      final mockClient = _MockGeminiHttpClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(
            jsonEncode(
              _geminiTextPayload(
                jsonEncode({
                  'goalSummary': 'Widget com erro não reparável',
                  'widgetName': 'BrokenClockWidget',
                  'architectureType': 'statefulWidgetClass',
                  'requiredImports': ['package:flutter/material.dart'],
                  'placementStrategy': 'separateWidgetFile',
                  'extractedWidgetFilePath':
                      'lib/features/home/widgets/broken_clock_widget.dart',
                  'visualAnchorDescription': 'Logo abaixo de Welcome',
                  'insertionAnchorHint': 'after_text:Welcome',
                }),
              ),
            ),
            200,
          );
        }
        if (requestCount == 2) {
          return http.Response(
            jsonEncode(
              _geminiTextPayload(
                jsonEncode({
                  'id': 'var_broken',
                  'title': 'Broken Clock',
                  'styleTag': 'Widget',
                  'description': 'Clock widget',
                  'techApproach': 'StatefulWidget',
                  'extractedWidgetCode': '''import 'package:flutter/material.dart';

class BrokenClockWidget extends StatelessWidget {
  const BrokenClockWidget({super.key});
  @override
  Widget build(BuildContext context) => Text(UnknownBrokenSymbol.value);
}''',
                  'callSiteSnippet': 'const BrokenClockWidget()',
                  'dartCode': 'const BrokenClockWidget()',
                }),
              ),
            ),
            200,
          );
        }
        return http.Response(
          jsonEncode(_geminiTextPayload('Não foi possível reparar.')),
          200,
        );
      });

      Future<ProcessResult> failingRunner(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        return ProcessResult(
          301,
          1,
          "  error • Undefined name 'UnknownBrokenSymbol' • lib/features/home/widgets/broken_clock_widget.dart:6:45 • undefined_identifier\n",
          '',
        );
      }

      final debugNotifier = _TrackingAndroidDebugNotifier();
      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.inMemory(
              const AiSettingsState(apiKey: 'AIzaRollbackKey'),
            ),
          ),
          androidDebugProvider.overrideWith((ref) => debugNotifier),
        ],
      );
      addTearDown(container.dispose);

      String liveCode = initialHomeCode;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return SingleChildScrollView(
                    child: ScreenMaterialsBuilder(
                      node: node,
                      project: project,
                      currentCode: liveCode,
                      aiHttpClient: mockClient,
                      verificationProcessRunner: failingRunner,
                      onCodeChanged: (newCode) =>
                          setState(() => liveCode = newCode),
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
        'Relógio quebrado',
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

      // Hot Reload MUST NOT fire and green toast MUST NOT appear when analyzer fails
      expect(debugNotifier.onCodeSavedPaths, isEmpty);
      expect(find.textContaining('inserido em'), findsNothing);
      expect(find.text('✅ Verificado (flutter analyze)'), findsNothing);
      expect(find.text('⚠️ Analyzer encontrou 1 erro(s)'), findsOneWidget);

      final createdWidgetFile = File(
        p.join(tempDir.path, 'lib/features/home/widgets/broken_clock_widget.dart'),
      );
      expect(createdWidgetFile.existsSync(), isTrue);

      // Tap 1-click Rollback
      final rollbackBtn = find.byKey(
        const ValueKey('widget_verification_rollback_button'),
      );
      expect(rollbackBtn, findsOneWidget);
      await tester.ensureVisible(rollbackBtn);
      await tester.tap(rollbackBtn);
      await _pumpThroughRealAsync(tester);

      expect(screenFile.readAsStringSync(), equals(initialHomeCode));
      expect(liveCode, equals(initialHomeCode));
      expect(createdWidgetFile.existsSync(), isFalse);
      expect(find.text('↩️ Alterações revertidas via backup'), findsOneWidget);
      expect(debugNotifier.onCodeSavedPaths, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
