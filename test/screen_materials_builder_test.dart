import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/ai_screen_generator_dialog.dart';
import 'package:flrd/features/studio/presentation/widgets/screen_materials_builder.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';

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
    testWidgets('Renders header, AI enhance button, palette chips, and materials stack',
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

      // Verify Header
      expect(find.text('Materiais & Componentes da Tela'), findsOneWidget);

      // Verify AI Button
      expect(find.byKey(const ValueKey('ai_enhance_materials_button')), findsOneWidget);
      expect(find.text('✨ Melhorar & Organizar com IA'), findsOneWidget);

      // Verify Palette Chips
      expect(find.byKey(const ValueKey('palette_chip_textInput')), findsOneWidget);
      expect(find.byKey(const ValueKey('palette_chip_passwordInput')), findsOneWidget);
      expect(find.byKey(const ValueKey('palette_chip_primaryButton')), findsOneWidget);
      expect(find.byKey(const ValueKey('palette_chip_headerText')), findsOneWidget);

      // Verify Materials Stack items
      expect(find.byKey(const ValueKey('screen_materials_list')), findsOneWidget);
      expect(find.byKey(const ValueKey('material_item_0')), findsOneWidget);
    });

    testWidgets('1-Click palette chip adds material and triggers onCodeChanged',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;
      bool codeChanged = false;

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
                      setState(() {
                        currentCode = newCode;
                        codeChanged = true;
                      });
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Click on [+ 🔘 Botão] chip
      final btnChip = find.byKey(const ValueKey('palette_chip_primaryButton'));
      expect(btnChip, findsOneWidget);
      await tester.tap(btnChip);
      await tester.pumpAndSettle();

      expect(codeChanged, isTrue);
      expect(currentCode, contains('Ação Principal'));
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

    testWidgets('Drag-and-drop from palette into DragTarget triggers addition',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;
      bool added = false;

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
                      setState(() {
                        currentCode = newCode;
                        added = true;
                      });
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const ValueKey('palette_chip_passwordInput'));
      final targetFinder = find.byKey(const ValueKey('materials_drag_target'));

      expect(chipFinder, findsOneWidget);
      expect(targetFinder, findsOneWidget);

      final drag = await tester.startGesture(tester.getCenter(chipFinder));
      await tester.pump(const Duration(milliseconds: 100));
      await drag.moveTo(tester.getCenter(targetFinder));
      await tester.pump(const Duration(milliseconds: 100));
      await drag.up();
      await tester.pumpAndSettle();

      expect(added, isTrue);
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
      expect(find.text('Materiais & Componentes da Tela'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_enhance_materials_button')), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
