import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/embedded_code_viewer.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flrd_code_viewer_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> pumpViewer(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('EmbeddedCodeViewer Template Generation Tests', () {
    test('generateTemplateCode produces valid Flutter code with Scaffold, AppBar and AppColors', () {
      const node = RouteNode(
        id: 'checkout',
        path: '/checkout',
        title: 'Checkout & Cart',
        subtitle: 'Finalize sua compra',
        icon: Icons.shopping_cart,
        position: Offset(100, 100),
        filePath: 'lib/features/checkout/presentation/checkout_screen.dart',
      );

      final code = EmbeddedCodeViewer.generateTemplateCode(node);

      expect(code, contains('class AppColors'));
      expect(code, contains('static const Color background'));
      expect(code, contains('static const Color primary'));
      expect(code, contains('class CheckoutCartScreen extends StatelessWidget'));
      expect(code, contains('Scaffold('));
      expect(code, contains('AppBar('));
      expect(code, contains('Checkout & Cart'));
      expect(code, contains('/checkout'));
    });

    test('saveCodeToDisk writes file to disk creating parent directories', () async {
      const node = RouteNode(
        id: 'billing',
        path: '/billing',
        title: 'Billing',
        subtitle: 'Faturamento',
        icon: Icons.payment,
        position: Offset(100, 100),
        filePath: 'lib/features/billing/presentation/billing_screen.dart',
      );

      const sampleCode = '// Billing code test';
      final file = await EmbeddedCodeViewer.saveCodeToDisk(
        projectPath: tempDir.path,
        node: node,
        code: sampleCode,
      );

      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), sampleCode);
      expect(p.normalize(file.path), p.normalize(p.join(tempDir.path, node.filePath)));
    });
  });

  group('EmbeddedCodeViewer Widget Tests', () {
    testWidgets('Loads template code when file does not exist on disk', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const node = RouteNode(
        id: 'dashboard',
        path: '/dashboard',
        title: 'Dashboard Screen',
        subtitle: 'Visão geral',
        icon: Icons.dashboard,
        position: Offset(50, 50),
        filePath: 'lib/features/dashboard/presentation/dashboard_screen.dart',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: EmbeddedCodeViewer(
                  projectPath: tempDir.path,
                  node: node,
                  isExpanded: false,
                ),
              ),
            ),
          ),
        ),
      );

      await pumpViewer(tester);

      // Top bar elements
      expect(find.text('lib/features/dashboard/presentation/dashboard_screen.dart'), findsOneWidget);
      expect(find.byIcon(Icons.flutter_dash), findsOneWidget);
      expect(find.text('Template'), findsOneWidget);
      expect(find.text('Save to Disk'), findsOneWidget);
      expect(find.text('Copy Code'), findsOneWidget);

      // Line numbers gutter exists
      expect(find.text('1'), findsWidgets);

      // Code editor text contains template code
      expect(find.textContaining('class DashboardScreen extends StatelessWidget'), findsOneWidget);
      expect(find.textContaining('AppColors'), findsWidgets);
    });

    testWidgets('Loads existing file content when file exists on disk', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const filePath = 'lib/features/home/presentation/home_screen.dart';
      final physicalFile = File(p.join(tempDir.path, filePath));
      physicalFile.parent.createSync(recursive: true);
      physicalFile.writeAsStringSync('// Custom Home Screen Content\nclass MyExistingHomeScreen {}');

      const node = RouteNode(
        id: 'home',
        path: '/',
        title: 'Home',
        subtitle: 'Página inicial',
        icon: Icons.home,
        position: Offset(50, 50),
        filePath: filePath,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: EmbeddedCodeViewer(
                  projectPath: tempDir.path,
                  node: node,
                  isExpanded: false,
                ),
              ),
            ),
          ),
        ),
      );

      await pumpViewer(tester);

      // Shows existing file content
      expect(find.textContaining('// Custom Home Screen Content'), findsOneWidget);
      expect(find.textContaining('class MyExistingHomeScreen'), findsOneWidget);
      // "Template" badge should not be present
      expect(find.text('Template'), findsNothing);
    });

    testWidgets('Salvar no Disco button triggers onSave callback and shows SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? savedCode;
      const filePath = 'lib/features/settings/presentation/settings_screen.dart';
      const node = RouteNode(
        id: 'settings',
        path: '/settings',
        title: 'Settings',
        subtitle: 'Configurações',
        icon: Icons.settings,
        position: Offset(50, 50),
        filePath: filePath,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: EmbeddedCodeViewer(
                  projectPath: tempDir.path,
                  node: node,
                  onSave: (code) async {
                    savedCode = code;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await pumpViewer(tester);

      // Click "Save to Disk"
      final saveButton = find.text('Save to Disk');
      expect(saveButton, findsOneWidget);

      await tester.tap(saveButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(savedCode, isNotNull);
      expect(savedCode, contains('class SettingsScreen extends StatelessWidget'));
      expect(find.textContaining('Arquivo salvo com sucesso'), findsOneWidget);
    });

    testWidgets('Copiar Código copies code to Clipboard and shows SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const filePath = 'lib/features/profile/presentation/profile_screen.dart';
      const node = RouteNode(
        id: 'profile',
        path: '/profile',
        title: 'Profile',
        subtitle: 'Perfil',
        icon: Icons.person,
        position: Offset(50, 50),
        filePath: filePath,
      );

      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final data = methodCall.arguments as Map<dynamic, dynamic>;
            clipboardText = data['text'] as String?;
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: EmbeddedCodeViewer(
                  projectPath: tempDir.path,
                  node: node,
                ),
              ),
            ),
          ),
        ),
      );

      await pumpViewer(tester);

      // Tap "Copy Code"
      final copyButton = find.text('Copy Code');
      expect(copyButton, findsOneWidget);

      await tester.tap(copyButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('class ProfileScreen extends StatelessWidget'));
      expect(find.text('Code copied to clipboard!'), findsOneWidget);
    });

    testWidgets('Expandir / Recolher button toggles and triggers onToggleExpand', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool toggleCalled = false;
      bool isExpanded = false;

      const node = RouteNode(
        id: 'feed',
        path: '/feed',
        title: 'Feed',
        subtitle: 'Feed social',
        icon: Icons.feed,
        position: Offset(50, 50),
        filePath: 'lib/features/feed/presentation/feed_screen.dart',
      );

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: EmbeddedCodeViewer(
                      projectPath: tempDir.path,
                      node: node,
                      isExpanded: isExpanded,
                      onToggleExpand: () {
                        toggleCalled = true;
                        setState(() {
                          isExpanded = !isExpanded;
                        });
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

      await pumpViewer(tester);

      expect(find.text('Expand'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

      await tester.tap(find.text('Expand'));
      await pumpViewer(tester);

      expect(toggleCalled, isTrue);
      expect(find.text('Collapse'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
    });

    testWidgets('Expand button is omitted when onToggleExpand is null', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const node = RouteNode(
        id: 'about',
        path: '/about',
        title: 'About',
        subtitle: 'Sobre',
        icon: Icons.info,
        position: Offset(50, 50),
        filePath: 'lib/features/about/presentation/about_screen.dart',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: EmbeddedCodeViewer(
                  projectPath: tempDir.path,
                  node: node,
                  onToggleExpand: null,
                ),
              ),
            ),
          ),
        ),
      );

      await pumpViewer(tester);

      expect(find.text('Expandir'), findsNothing);
      expect(find.text('Recolher'), findsNothing);
    });
  });

  group('AppStudioScreen EmbeddedCodeViewer Integration Tests', () {
    late RegisteredProject testProject;

    setUp(() {
      testProject = RegisteredProject(
        id: 'test_flrd_studio',
        name: 'Studio Test App',
        orgId: 'com.flrd.test',
        path: tempDir.path,
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 5,
      );
    });

    testWidgets('Inspector panel opens with 440px width when node is selected',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late ProviderContainer container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(),
          child: MaterialApp(
            home: AppStudioScreen(project: testProject),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no node is selected
      expect(find.text('⚙️ Detalhes da Rota'), findsNothing);

      // Select 'login' node
      container.read(studioProvider.notifier).selectNode('login');
      await tester.pumpAndSettle();

      // Right-hand panel is visible with 440px width
      final panelFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints == const BoxConstraints.tightFor(width: 440.0),
      );
      expect(panelFinder, findsOneWidget);

      final renderBox = tester.renderObject<RenderBox>(panelFinder);
      expect(renderBox.size.width, 440.0);
    });

    testWidgets('Switcher alternates between [⚙️ Details], [💻 Code], and [📱 Emulate]',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      container.read(studioProvider.notifier).selectNode('dashboard');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: testProject),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switcher options exist
      expect(find.text('⚙️ Details'), findsOneWidget);
      expect(find.text('💻 Code'), findsOneWidget);
      expect(find.text('📱 Emulate'), findsOneWidget);

      // Default: Route Details tab is active
      expect(find.text('GoRouter Route Path'), findsOneWidget);
      expect(find.text('Source Code File'), findsOneWidget);
      expect(find.byType(EmbeddedCodeViewer), findsNothing);

      // Switch to '💻 Code'
      await tester.tap(find.text('💻 Code'));
      await tester.pumpAndSettle();

      // EmbeddedCodeViewer and modal button are now visible
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.text('Open in Fullscreen Modal'), findsOneWidget);
      expect(find.text('GoRouter Route Path'), findsNothing);

      // Switch back to '⚙️ Details'
      await tester.tap(find.text('⚙️ Details'));
      await tester.pumpAndSettle();

      expect(find.byType(EmbeddedCodeViewer), findsNothing);
      expect(find.text('GoRouter Route Path'), findsOneWidget);
    });

    testWidgets('Opens 750px wide code dialog via fullscreen modal button and dismisses it',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      container.read(studioProvider.notifier).selectNode('explore');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: testProject),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Code Tab
      await tester.tap(find.text('💻 Code'));
      await tester.pumpAndSettle();

      // Tap 'Open in Fullscreen Modal'
      final openModalButton = find.text('Open in Fullscreen Modal');
      expect(openModalButton, findsOneWidget);
      await tester.tap(openModalButton);
      await tester.pumpAndSettle();

      // Fullscreen code dialog is open
      expect(find.byType(Dialog), findsOneWidget);

      // Dialog is 750px wide
      final dialogSizedBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 750.0),
        ),
      );
      expect(dialogSizedBox.width, 750.0);

      // Contains EmbeddedCodeViewer with Collapse button
      expect(find.text('Collapse'), findsOneWidget);

      // Tap 'Collapse' to dismiss modal
      await tester.tap(find.text('Collapse'));
      await tester.pumpAndSettle();

      // Dialog dismissed
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('AppStudioScreen.showFullscreenCodeModal directly opens 750px wide dialog',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const node = RouteNode(
        id: 'settings',
        path: '/settings',
        title: 'SettingsScreen',
        subtitle: 'Configurações gerais',
        icon: Icons.settings,
        position: Offset(50, 50),
        filePath: 'lib/features/settings/presentation/settings_screen.dart',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    AppStudioScreen.showFullscreenCodeModal(
                      context,
                      projectPath: tempDir.path,
                      node: node,
                    );
                  },
                  child: const Text('Open Modal'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);

      final modalBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 750.0),
        ),
      );
      expect(modalBox.width, 750.0);
      expect(find.text('lib/features/settings/presentation/settings_screen.dart'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Collapse'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });
  });
}
