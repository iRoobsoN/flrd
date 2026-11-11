import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/projects/presentation/widgets/import_project_dialog.dart';
import 'package:flrd/features/projects/providers/projects_provider.dart';
import 'package:flrd/features/projects/services/project_analyzer_service.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/device_screen_emulator.dart';
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

    testWidgets('AppStudioScreen inspector switcher displays 3 tabs and renders DeviceScreenEmulator on tab 2',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'emulator_test_proj',
        name: 'Emulator Test App',
        orgId: 'com.emulator.test',
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

      // Verify all 3 tabs are present in inspector switcher
      expect(find.text('⚙️ Details'), findsOneWidget);
      expect(find.text('💻 Code'), findsOneWidget);
      expect(find.text('📱 Emulate'), findsOneWidget);

      // Initially on tab 0 (Details)
      expect(find.text('GoRouter Route Path'), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsNothing);

      // Switch to tab 1 (Code)
      await tester.tap(find.text('💻 Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);

      // Switch to tab 2 (Emulate)
      await tester.tap(find.text('📱 Emulate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify DeviceScreenEmulator is rendered
      expect(find.byType(DeviceScreenEmulator), findsOneWidget);

      // Verify no RenderFlex overflow
      final err = tester.takeException();
      expect(err, isNull);
    });

    testWidgets('AppStudioScreen inspector panel widens to 480px on desktop when in emulate mode',
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
      // Look for the sidebar Container (which has Border(left: BorderSide(...)))
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

      // Tap tab 2 (Emulate)
      await tester.tap(find.text('📱 Emulate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Sidebar should expand to 480px on desktop
      sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(480.0, 1.0));

      final err = tester.takeException();
      expect(err, isNull);
    });
  });
}
