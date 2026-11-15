import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flrd/features/hub/presentation/widgets/projects_grid_view.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/projects/presentation/widgets/import_project_dialog.dart';
import 'package:flrd/features/projects/providers/projects_provider.dart';
import 'package:flrd/features/projects/services/project_analyzer_service.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/embedded_code_viewer.dart';
import 'package:flrd/features/studio/presentation/widgets/route_node_card.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flrd_studio_hub_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('StudioProvider & Route Selection Desync Fix Tests', () {
    test('selectNode(null) successfully deselects node and sets selectedNodeId to null', () {
      final container = ProviderContainer();
      final notifier = container.read(studioProvider.notifier);

      expect(container.read(studioProvider).selectedNodeId, isNull);

      notifier.selectNode('login');
      expect(container.read(studioProvider).selectedNodeId, 'login');
      expect(container.read(studioProvider).selectedNode, isNotNull);
      expect(container.read(studioProvider).selectedNode!.id, 'login');

      // Deselect
      notifier.selectNode(null);
      expect(container.read(studioProvider).selectedNodeId, isNull);
      expect(container.read(studioProvider).selectedNode, isNull);
    });

    test('removeNode clears selectedNodeId if deleted node was currently selected', () {
      final container = ProviderContainer();
      final notifier = container.read(studioProvider.notifier);

      notifier.selectNode('dashboard');
      expect(container.read(studioProvider).selectedNodeId, 'dashboard');

      // Remove the selected node
      notifier.removeNode('dashboard');
      expect(container.read(studioProvider).selectedNodeId, isNull);
      expect(container.read(studioProvider).selectedNode, isNull);
    });

    test('removeNode preserves selectedNodeId if a different node is removed', () {
      final container = ProviderContainer();
      final notifier = container.read(studioProvider.notifier);

      notifier.selectNode('login');
      expect(container.read(studioProvider).selectedNodeId, 'login');

      notifier.removeNode('dashboard');
      expect(container.read(studioProvider).selectedNodeId, 'login');
      expect(container.read(studioProvider).selectedNode?.id, 'login');
    });

    test('setNodes with empty list clears selectedNodeId to null', () {
      final container = ProviderContainer();
      final notifier = container.read(studioProvider.notifier);

      notifier.selectNode('login');
      expect(container.read(studioProvider).selectedNodeId, 'login');

      notifier.setNodes([]);
      expect(container.read(studioProvider).selectedNodeId, isNull);
      expect(container.read(studioProvider).nodes, isEmpty);
    });

    test('RouteNode.copyWith allows clearing parentRouteId to null', () {
      const node = RouteNode(
        id: 'child',
        path: '/child',
        title: 'Child',
        subtitle: 'Sub',
        icon: Icons.abc,
        position: Offset(100, 100),
        filePath: 'lib/child.dart',
        parentRouteId: 'root',
      );

      expect(node.parentRouteId, 'root');

      final unparented = node.copyWith(parentRouteId: null);
      expect(unparented.parentRouteId, isNull);

      // copyWith without parentRouteId keeps current parentRouteId
      final kept = node.copyWith(title: 'New Title');
      expect(kept.parentRouteId, 'root');
      expect(kept.title, 'New Title');
    });
  });

  group('ProjectsProvider State Selection & Desync Tests', () {
    test('selectProject(null) successfully clears selectedProjectId', () {
      final container = ProviderContainer();
      final notifier = container.read(projectsProvider.notifier);

      notifier.selectProject('my_awesome_app');
      expect(container.read(projectsProvider).selectedProjectId, 'my_awesome_app');

      notifier.selectProject(null);
      expect(container.read(projectsProvider).selectedProjectId, isNull);
    });

    test('removeProject clears selectedProjectId if active project is deleted', () {
      final container = ProviderContainer();
      final notifier = container.read(projectsProvider.notifier);

      notifier.selectProject('my_awesome_app');
      expect(container.read(projectsProvider).selectedProjectId, 'my_awesome_app');

      notifier.removeProject('my_awesome_app');
      expect(container.read(projectsProvider).selectedProjectId, isNull);
    });
  });

  group('ImportProjectDialog & ProjectAnalyzerService Path Validation Tests', () {
    test('ProjectAnalyzerService sanitizes paths with quotes and resolves pubspec.yaml file', () async {
      final projectDir = Directory(p.join(tempDir.path, 'quoted_app'));
      await projectDir.create(recursive: true);
      final pubspec = File(p.join(projectDir.path, 'pubspec.yaml'));
      await pubspec.writeAsString('''
name: quoted_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
''');

      // Test path with enclosing double quotes
      final quotedPath = '"${projectDir.path}"';
      final result1 = await ProjectAnalyzerService.analyzeProject(quotedPath);
      expect(result1.project.name, 'quoted_app');

      // Test path directly to pubspec.yaml file
      final directFilePath = pubspec.path;
      final result2 = await ProjectAnalyzerService.analyzeProject(directFilePath);
      expect(result2.project.name, 'quoted_app');
    });

    testWidgets('ImportProjectDialog shows validation error when directory does not exist',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ImportProjectDialog(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Enter non-existent directory
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'C:/non_existent_folder_xyz_123');
      await tester.pump();

      // Click Analisar e Importar
      final importButton = find.text('Analisar e Importar');
      await tester.tap(importButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Error message should appear
      expect(find.textContaining('O diretório informado não foi encontrado'), findsOneWidget);
    });

    testWidgets('ImportProjectDialog shows validation error when pubspec.yaml is missing',
        (tester) async {
      final emptyDir = Directory(p.join(tempDir.path, 'empty_dir'))..createSync(recursive: true);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ImportProjectDialog(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final textField = find.byType(TextField);
      await tester.enterText(textField, emptyDir.path);
      await tester.pump();

      final importButton = find.text('Analisar e Importar');
      await tester.tap(importButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Nenhum pubspec.yaml encontrado'), findsOneWidget);
    });
  });

  group('Narrow Screen & Responsive Layout Tests', () {
    testWidgets('RouteNodeCard renders without overflow when path is extremely long',
        (tester) async {
      const node = RouteNode(
        id: 'long_route',
        path: '/organization/departments/engineering/projects/mobile/features/checkout/details/v2',
        title: 'Very Long Route Title That Could Overflow',
        subtitle: 'Sub-route with extensive description',
        icon: Icons.alt_route,
        isProtected: true,
        isAIGenerated: true,
        requiredPermissions: [DevicePermission.camera, DevicePermission.location],
        position: Offset.zero,
        filePath: 'lib/features/very/deeply/nested/path/to/some/long_screen.dart',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                height: 110,
                child: RouteNodeCard(
                  node: node,
                  isSelected: false,
                  onTap: () {},
                  onDrag: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Ensure no RenderFlex overflow exceptions were thrown
      final err = tester.takeException();
      if (err is FlutterError) {
        // ignore: avoid_print
        print('FOUND EXCEPTION DEEP: ${err.toStringDeep()}');
      }
      expect(err, isNull);
      expect(find.text(node.title), findsOneWidget);
    });

    testWidgets('EmbeddedCodeViewer top bar renders without overflow on 360px narrow screens',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const node = RouteNode(
        id: 'compact_node',
        path: '/compact/view',
        title: 'Compact Screen',
        subtitle: 'Sub',
        icon: Icons.code,
        position: Offset.zero,
        filePath: 'lib/features/compact/presentation/compact_screen.dart',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 500,
                child: EmbeddedCodeViewer(
                  projectPath: tempDir.path,
                  node: node,
                  onToggleExpand: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final err = tester.takeException();
      if (err is FlutterError) {
        // ignore: avoid_print
        print('FOUND EXCEPTION DEEP: ${err.toStringDeep()}');
      }
      expect(err, isNull);
      expect(find.text('Save to Disk'), findsOneWidget);
      expect(find.text('Copy Code'), findsOneWidget);
      expect(find.text('Expand'), findsOneWidget);
    });

    testWidgets('AppStudioScreen renders without overflow on narrow width',
        (tester) async {
      tester.view.physicalSize = const Size(750, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'narrow_test',
        name: 'Narrow Test Project With Long Name',
        orgId: 'com.narrow.test',
        path: 'C:/Very/Long/Path/To/A/Nested/Project/Directory/narrow_app',
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 4,
      );

      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: project),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final err = tester.takeException();
      if (err is FlutterError) {
        // ignore: avoid_print
        print('FOUND EXCEPTION DEEP: ${err.toStringDeep()}');
      }
      expect(err, isNull);
      expect(find.text('Narrow Test Project With Long Name'), findsOneWidget);
      expect(find.text('Routes Flowchart'), findsOneWidget);
    });

    testWidgets('AppStudioScreen inspector switcher displays 2 tabs and hides removed fake preview pane',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'inspector_test_proj',
        name: 'Inspector Test App',
        orgId: 'com.inspector.test',
        path: tempDir.path,
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 3,
      );

      final container = ProviderContainer();
      // Select the first node
      final firstNode = container.read(studioProvider).nodes.first;
      container.read(studioProvider.notifier).selectNode(firstNode.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: project),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify 2 tabs are present in inspector switcher and Emulate tab is removed
      expect(find.text('⚙️ Details'), findsOneWidget);
      expect(find.text('💻 Code'), findsOneWidget);
      expect(find.text('📱 Emulate'), findsNothing);

      // Initially on tab 0 (Details)
      expect(find.text('GoRouter Route Path'), findsOneWidget);

      // Verify fake live preview pane and toggle buttons are removed
      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsNothing);
      expect(find.byKey(const ValueKey('toggle_live_preview_button')), findsNothing);
      expect(find.text('Live Screen Preview'), findsNothing);

      // Switch to tab 1 (Code)
      await tester.tap(find.text('💻 Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsNothing);
      expect(find.byKey(const ValueKey('inspector_toggle_preview_button')), findsNothing);

      // Verify no RenderFlex overflow
      final err = tester.takeException();
      expect(err, isNull);
    });

    testWidgets('Switching selected route node updates inspector details cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'node_switch_test_project',
        name: 'Node Switcher Test App',
        orgId: 'com.switcher.node',
        path: tempDir.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 4,
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final studioNotifier = container.read(studioProvider.notifier);

      studioNotifier.selectNode('profile');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: project),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ProfileScreen'), findsWidgets);
      expect(find.text('/profile'), findsWidgets);

      studioNotifier.selectNode('login');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('LoginScreen'), findsWidgets);
      expect(find.text('/auth/login'), findsWidgets);

      studioNotifier.selectNode('explore');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ExploreScreen'), findsWidgets);
      expect(find.text('/explore'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppStudioScreen inspector panel widens to 500px on desktop when in code mode',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'width_test_proj',
        name: 'Width Test App',
        orgId: 'com.width.test',
        path: tempDir.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 3,
      );

      final container = ProviderContainer();
      final firstNode = container.read(studioProvider).nodes.first;
      container.read(studioProvider.notifier).selectNode(firstNode.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: project),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // When tab 0 is active, sidebar width is 440px
      // Look for the sidebar Container
      final sidebarFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border is Border &&
            ((widget.decoration as BoxDecoration).border as Border).top == BorderSide.none &&
            ((widget.decoration as BoxDecoration).border as Border).left != BorderSide.none,
      );
      expect(sidebarFinder, findsOneWidget);
      RenderBox sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(440.0, 1.0));

      // Tap tab 1 (Code)
      await tester.tap(find.text('💻 Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Sidebar should expand to 500px on desktop
      sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(500.0, 1.0));

      // Tap tab 0 (Details) to return
      await tester.tap(find.text('⚙️ Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(440.0, 1.0));

      final err = tester.takeException();
      expect(err, isNull);
    });
  });

  group('Hub Open & Studio Route Rescan Tests', () {
    RegisteredProject createMultiScreenDiskProjectSync() {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: multi_screen_app
dependencies:
  flutter:
    sdk: flutter
''');
      final libDir = Directory(p.join(tempDir.path, 'lib'));
      libDir.createSync(recursive: true);
      File(p.join(libDir.path, 'main.dart')).writeAsStringSync('''
import 'package:flutter/material.dart';
import 'screens.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Scaffold(
        body: TabBarView(
          children: [Txt2ImgScreen(), SettingsScreen()],
        ),
      ),
    );
  }
}
''');
      File(p.join(libDir.path, 'screens.dart')).writeAsStringSync('''
import 'package:flutter/material.dart';

class Txt2ImgScreen extends StatelessWidget {
  const Txt2ImgScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Txt2Img'));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Settings'));
}
''');
      return RegisteredProject(
        id: 'multi-screen-id',
        name: 'multi_screen_app',
        orgId: 'com.example',
        path: tempDir.path,
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime(2026),
        routeCount: 1,
      );
    }

    testWidgets(
      'Opening project card in ProjectsGridView analyzes disk routes into studioProvider',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final project = createMultiScreenDiskProjectSync();
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(projectsProvider.notifier).registerProject(project);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: ProjectsGridView(),
              ),
            ),
          ),
        );
        await tester.pump();

        final cardFinder = find.text('multi_screen_app');
        await tester.ensureVisible(cardFinder);
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(cardFinder);
          for (var i = 0; i < 40; i++) {
            if (container.read(studioProvider).nodes.length == 4) break;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final titles =
            container.read(studioProvider).nodes.map((n) => n.title).toList();
        expect(
          titles,
          containsAll(<String>[
            'Root / Entry',
            'MainScreen',
            'Txt2ImgScreen',
            'SettingsScreen',
          ]),
        );
        expect(find.byType(AppStudioScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'AppStudioScreen Reescanear button rescans disk routes when graph only has root',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final project = createMultiScreenDiskProjectSync();
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(studioProvider.notifier).setNodes([
          const RouteNode(
            id: 'root',
            path: '/',
            title: 'Root / Entry',
            subtitle: 'App initial route & shell navigation',
            icon: Icons.account_tree_rounded,
            filePath: 'lib/main.dart',
            position: Offset(80, 200),
          ),
        ]);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: AppStudioScreen(project: project),
            ),
          ),
        );
        await tester.pump();

        expect(container.read(studioProvider).nodes.length, 1);

        final rescanBtn =
            find.byKey(const ValueKey('studio_rescan_routes_button'));
        expect(rescanBtn, findsOneWidget);
        await tester.ensureVisible(rescanBtn);
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(rescanBtn);
          for (var i = 0; i < 40; i++) {
            if (container.read(studioProvider).nodes.length == 4) break;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        });
        await tester.pump();

        final titles =
            container.read(studioProvider).nodes.map((n) => n.title).toList();
        expect(
          titles,
          containsAll(<String>[
            'Root / Entry',
            'MainScreen',
            'Txt2ImgScreen',
            'SettingsScreen',
          ]),
        );
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
