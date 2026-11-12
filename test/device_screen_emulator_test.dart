import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/core/localization/app_strings.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/device_screen_emulator.dart';
import 'package:flrd/features/studio/presentation/widgets/embedded_code_viewer.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1400, 950),
  }) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    );
  }

  group('Unit Tests: EmulatorDevice & RouteArchetype Enums', () {
    test('EmulatorDevice.iphone15Pro has correct physical specs', () {
      const dev = EmulatorDevice.iphone15Pro;
      expect(dev.name, 'iPhone 15 Pro');
      expect(dev.platform, TargetPlatform.iOS);
      expect(dev.width, 393);
      expect(dev.height, 852);
      expect(dev.cornerRadius, 50);
      expect(dev.bezelWidth, 10);
      expect(dev.hasDynamicIsland, isTrue);
      expect(dev.hasPunchHole, isFalse);
      expect(dev.hasHomeIndicator, isTrue);
    });

    test('EmulatorDevice.pixel8 has correct physical specs', () {
      const dev = EmulatorDevice.pixel8;
      expect(dev.name, 'Pixel 8');
      expect(dev.platform, TargetPlatform.android);
      expect(dev.width, 412);
      expect(dev.height, 892);
      expect(dev.cornerRadius, 42);
      expect(dev.bezelWidth, 9);
      expect(dev.hasDynamicIsland, isFalse);
      expect(dev.hasPunchHole, isTrue);
      expect(dev.hasHomeIndicator, isTrue);
    });

    test('RouteArchetype contains all 6 required archetypes', () {
      expect(
        RouteArchetype.values,
        containsAll([
          RouteArchetype.splash,
          RouteArchetype.auth,
          RouteArchetype.dashboard,
          RouteArchetype.explore,
          RouteArchetype.profile,
          RouteArchetype.custom,
        ]),
      );
      expect(RouteArchetype.values.length, 6);
    });
  });

  group('DeviceScreenEmulator - Shell & Hardware Features', () {
    testWidgets('Renders iPhone 15 Pro with Dynamic Island, Status Bar and Home Indicator',
        (tester) async {
      const node = RouteNode(
        id: 'splash',
        path: '/',
        title: 'SplashScreen',
        subtitle: 'App initial entry & auth guard',
        icon: Icons.alt_route_rounded,
        position: Offset.zero,
        filePath: 'lib/main.dart',
      );

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pumpAndSettle();

      // Check Status Bar elements
      expect(find.text('9:41'), findsOneWidget);
      expect(find.text('5G'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
      expect(find.byIcon(Icons.signal_cellular_alt_rounded), findsOneWidget);

      // Dynamic Island is present
      // Tapping Dynamic Island expands it
      await tester.tap(find.byKey(const Key('dynamic_island')));
      await tester.pumpAndSettle();
      expect(find.text('FLRD Dev'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);

      // Tapping again contracts it
      await tester.tap(find.byKey(const Key('dynamic_island')));
      await tester.pumpAndSettle();
      expect(find.text('FLRD Dev'), findsNothing);
    });

    testWidgets('Switches device shell from iPhone 15 Pro to Pixel 8 with punch hole',
        (tester) async {
      const node = RouteNode(
        id: 'splash',
        path: '/',
        title: 'SplashScreen',
        subtitle: 'Splash screen entry',
        icon: Icons.alt_route_rounded,
        position: Offset.zero,
        filePath: 'lib/main.dart',
      );

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pumpAndSettle();

      // Open device switcher dropdown
      await tester.tap(find.text('iPhone 15 Pro'));
      await tester.pumpAndSettle();

      // Select Pixel 8
      await tester.tap(find.text('Pixel 8').last);
      await tester.pumpAndSettle();

      // Pixel 8 status bar features: 94% battery percentage text
      expect(find.text('94%'), findsOneWidget);
      expect(find.byIcon(Icons.signal_cellular_4_bar_rounded), findsOneWidget);
    });

    testWidgets('Toggles dark and light mode in toolbar', (tester) async {
      const node = RouteNode(
        id: 'dashboard',
        path: '/dashboard',
        title: 'DashboardScreen',
        subtitle: 'Metrics',
        icon: Icons.space_dashboard_rounded,
        position: Offset.zero,
        filePath: 'lib/dashboard.dart',
      );

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pumpAndSettle();

      // Initially dark mode
      expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);

      // Tap theme toggle to switch to light mode
      await tester.tap(find.byIcon(Icons.dark_mode_rounded));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);

      // Tap back to dark mode
      await tester.tap(find.byIcon(Icons.light_mode_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    });

    testWidgets('Scale controls toggle preset scales and reset simulation reinitializes state',
        (tester) async {
      const node = RouteNode(
        id: 'dashboard',
        path: '/dashboard',
        title: 'DashboardScreen',
        subtitle: 'Metrics',
        icon: Icons.space_dashboard_rounded,
        position: Offset.zero,
        filePath: 'lib/dashboard.dart',
      );

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pumpAndSettle();

      expect(find.text('Fit'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.text('75%'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('100%'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fit'));
      await tester.pumpAndSettle();

      // Reset button resets simulation
      final resetBtn = find.byTooltip('Reset Screen Simulation');
      expect(resetBtn, findsOneWidget);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();
      expect(find.text('DashboardScreen'), findsWidgets);
      expect(find.text('LIVE READY'), findsOneWidget);
    });
  });

  group('DeviceScreenEmulator - Pure Live Code Rendering', () {
    testWidgets('ProfileScreen pure live rendering: parses AppBar, avatar container, and profile labels',
        (tester) async {
      const node = RouteNode(
        id: 'profile',
        path: '/profile',
        title: 'ProfileScreen',
        subtitle: 'User account & device permissions',
        icon: Icons.account_circle_rounded,
        position: Offset.zero,
        filePath: 'lib/profile.dart',
      );

      const profileCode = '''
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Color(0xFF1E293B),
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: const [
              Icon(Icons.account_circle_rounded, size: 48),
              Text('Alex Morgan'),
              Text('FLRD PRO TIER'),
            ],
          ),
        ),
      ),
    );
  }
}
''';

      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(node: node, sourceCode: profileCode),
        ),
      );
      await tester.pumpAndSettle();

      // Elements parsed from live code
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('FLRD PRO TIER'), findsOneWidget);
      expect(find.byIcon(Icons.account_circle_rounded), findsWidgets);
      expect(find.text('🎨 Archetype Mock'), findsNothing);
      expect(find.text('📸 Screenshot'), findsOneWidget);
    });

    testWidgets('AuthScreen pure live rendering: parses inputs and submit CTA',
        (tester) async {
      const node = RouteNode(
        id: 'login',
        path: '/auth/login',
        title: 'LoginScreen',
        subtitle: 'Supabase authentication',
        icon: Icons.lock_outline_rounded,
        position: Offset.zero,
        filePath: 'lib/login.dart',
      );

      const authCode = '''
import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Welcome Back'),
        backgroundColor: Color(0xFF1E293B),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const TextField(decoration: InputDecoration(labelText: 'Email Address')),
            const TextField(decoration: InputDecoration(labelText: 'Password')),
            ElevatedButton(
              onPressed: () {},
              child: const Text('Sign In to Workspace'),
            ),
          ],
        ),
      ),
    );
  }
}
''';

      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(node: node, sourceCode: authCode),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign In to Workspace'), findsOneWidget);
      expect(find.text('🎨 Archetype Mock'), findsNothing);
    });

    testWidgets('DashboardScreen pure live rendering: parses KPI metrics and actions',
        (tester) async {
      const node = RouteNode(
        id: 'dashboard',
        path: '/dashboard',
        title: 'DashboardScreen',
        subtitle: 'Metrics & stats',
        icon: Icons.space_dashboard_rounded,
        position: Offset.zero,
        filePath: 'lib/dashboard.dart',
      );

      const dashboardCode = '''
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Dashboard Analytics'),
        backgroundColor: Color(0xFF1E293B),
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: const [
              Text('Total Revenue'),
              Text('\$24,850'),
              Text('Active Users'),
            ],
          ),
        ),
      ),
    );
  }
}
''';

      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(node: node, sourceCode: dashboardCode),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Analytics'), findsOneWidget);
      expect(find.text('Total Revenue'), findsOneWidget);
      expect(find.text('\$24,850'), findsOneWidget);
      expect(find.text('Active Users'), findsOneWidget);
      expect(find.text('🎨 Archetype Mock'), findsNothing);
    });

    testWidgets('ExploreScreen pure live rendering: parses catalog items and cards',
        (tester) async {
      const node = RouteNode(
        id: 'explore',
        path: '/explore',
        title: 'ExploreScreen',
        subtitle: 'Community feed',
        icon: Icons.explore_rounded,
        position: Offset.zero,
        filePath: 'lib/explore.dart',
      );

      const exploreCode = '''
import 'package:flutter/material.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Community Explore'),
        backgroundColor: Color(0xFF1E293B),
      ),
      body: Center(
        child: Column(
          children: const [
            Text('SaaS Dashboard Pro'),
            Text('Supabase Clean Auth'),
            Text('Gemini 1.5 Code Copilot'),
          ],
        ),
      ),
    );
  }
}
''';

      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(node: node, sourceCode: exploreCode),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Community Explore'), findsOneWidget);
      expect(find.text('SaaS Dashboard Pro'), findsOneWidget);
      expect(find.text('Supabase Clean Auth'), findsOneWidget);
      expect(find.text('Gemini 1.5 Code Copilot'), findsOneWidget);
      expect(find.text('🎨 Archetype Mock'), findsNothing);
    });

    testWidgets('SplashScreen pure live rendering: parses splash pipeline and logo',
        (tester) async {
      const node = RouteNode(
        id: 'root',
        path: '/',
        title: 'Splash & AuthGuard',
        subtitle: 'Redirection via GoRouter',
        icon: Icons.alt_route_rounded,
        position: Offset.zero,
        filePath: 'lib/router.dart',
      );

      const splashCode = '''
import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('FLRD Studio'),
        backgroundColor: Color(0xFF1E293B),
      ),
      body: Center(
        child: Column(
          children: const [
            Text('GoRouter AuthGuard Pipeline'),
            Text('Simulate Launch Transition'),
          ],
        ),
      ),
    );
  }
}
''';

      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(node: node, sourceCode: splashCode),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FLRD Studio'), findsOneWidget);
      expect(find.text('GoRouter AuthGuard Pipeline'), findsOneWidget);
      expect(find.text('Simulate Launch Transition'), findsOneWidget);
      expect(find.text('🎨 Archetype Mock'), findsNothing);
    });

    testWidgets('Custom / AI Screen pure live rendering: parses hardware permissions and action dispatcher',
        (tester) async {
      const node = RouteNode(
        id: 'custom_camera_screen',
        path: '/camera',
        title: 'CameraScanScreen',
        subtitle: 'Custom barcode camera feed',
        icon: Icons.qr_code_scanner_rounded,
        isAIGenerated: true,
        requiredPermissions: [DevicePermission.camera],
        position: Offset.zero,
        filePath: 'lib/camera.dart',
      );

      const customCode = '''
import 'package:flutter/material.dart';

class CameraScanScreen extends StatelessWidget {
  const CameraScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('CameraScanScreen'),
        backgroundColor: Color(0xFF1E293B),
      ),
      body: Center(
        child: Column(
          children: [
            const Text('AI Screen'),
            const Text('Camera Live Feed'),
            ElevatedButton(
              onPressed: () {},
              child: const Text('Dispatch Screen Action'),
            ),
          ],
        ),
      ),
    );
  }
}
''';

      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(node: node, sourceCode: customCode),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CameraScanScreen'), findsOneWidget);
      expect(find.text('AI Screen'), findsOneWidget);
      expect(find.text('Camera Live Feed'), findsOneWidget);
      expect(find.text('Dispatch Screen Action'), findsOneWidget);
      expect(find.text('🎨 Archetype Mock'), findsNothing);
    });

    testWidgets('DeviceScreenEmulator.showModal opens dialog and dismisses',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const node = RouteNode(
        id: 'profile',
        path: '/profile',
        title: 'ProfileScreen',
        subtitle: 'Profile',
        icon: Icons.person_rounded,
        position: Offset.zero,
        filePath: 'lib/profile.dart',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => DeviceScreenEmulator.showModal(context, node: node),
                child: const Text('Open Modal'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsOneWidget);
      expect(find.byKey(const Key('modal_screenshot_button')), findsOneWidget);

      // Close via close modal button
      await tester.tap(find.byTooltip('Close Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('AppStudioScreen - 2-Tab Inspector & Right-Anchored Live Preview Integration', () {
    testWidgets('Renders 2 tabs in inspector switcher and right-anchored preview pane when _showLivePreview is active',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'switcher_test_project',
        name: 'Switcher Test App',
        orgId: 'com.switcher.test',
        path: Directory.systemTemp.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 4,
      );

      final container = ProviderContainer();
      final nodes = container.read(studioProvider).nodes;
      expect(nodes.isNotEmpty, isTrue);

      // Select dashboard node
      final dashboardNode = nodes.firstWhere((n) => n.id == 'dashboard');
      container.read(studioProvider.notifier).selectNode(dashboardNode.id);

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

      // 1. Verify 2 segmented tab buttons are present and Emulate is removed
      expect(find.text('⚙️ Details'), findsOneWidget);
      expect(find.text('💻 Code'), findsOneWidget);
      expect(find.text('📱 Emulate'), findsNothing);

      // 2. Default tab is Details (Tab 0) - Route details editor is shown
      expect(find.text('GoRouter Route Path'), findsOneWidget);
      expect(find.byType(EmbeddedCodeViewer), findsNothing);

      // 3. Right-anchored preview pane is active and contains DeviceScreenEmulator
      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsOneWidget);
      expect(find.text('Live Screen Preview'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('anchored_live_preview_pane')),
          matching: find.byType(DeviceScreenEmulator),
        ),
        findsOneWidget,
      );

      // Pure Reality: Archetype mock toggle is removed, Screenshot button is present
      expect(find.text('🎨 Archetype Mock'), findsNothing);
      expect(find.text('📸 Screenshot'), findsOneWidget);

      // Selected node is dashboard: renders real route fallback with LIVE READY badge
      expect(find.text('DashboardScreen'), findsWidgets);
      expect(find.text('LIVE READY'), findsOneWidget);

      // 4. Switch to Tab 1: Code
      await tester.tap(find.text('💻 Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsOneWidget);

      // 5. Hide preview pane via close button
      final closePreviewBtn = find.byKey(const ValueKey('close_live_preview_pane_button'));
      expect(closePreviewBtn, findsOneWidget);
      await tester.tap(closePreviewBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsNothing);
      expect(find.byType(DeviceScreenEmulator), findsNothing);
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);

      // 6. Restore preview pane via inspector toggle button
      final inspectorToggleBtn = find.byKey(const ValueKey('inspector_toggle_preview_button'));
      expect(inspectorToggleBtn, findsOneWidget);
      await tester.tap(inspectorToggleBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsOneWidget);

      // 7. Switch back to Tab 0: Details
      await tester.tap(find.text('⚙️ Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('GoRouter Route Path'), findsOneWidget);
      expect(find.byType(EmbeddedCodeViewer), findsNothing);
      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsOneWidget);

      // No RenderFlex overflow
      expect(tester.takeException(), isNull);
    });

    testWidgets('Switching selected route node updates DeviceScreenEmulator content',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'node_switch_test_project',
        name: 'Node Switcher Test App',
        orgId: 'com.switcher.node',
        path: Directory.systemTemp.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 4,
      );

      final container = ProviderContainer();
      final studioNotifier = container.read(studioProvider.notifier);

      // Start with profile node
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

      // Live preview pane is anchored on the right showing Profile screen content
      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsOneWidget);
      expect(find.text('ProfileScreen'), findsWidgets);
      expect(find.text('/profile'), findsWidgets);
      expect(find.text('LIVE READY'), findsOneWidget);

      // Now select login node
      studioNotifier.selectNode('login');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Login screen content is now shown
      expect(find.text('LoginScreen'), findsWidgets);
      expect(find.text('/auth/login'), findsWidgets);

      // Now select explore node
      studioNotifier.selectNode('explore');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Explore screen content is now shown
      expect(find.text('ExploreScreen'), findsWidgets);
      expect(find.text('/explore'), findsWidgets);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Inspector sidebar expands to 500px on desktop when in code mode and shrinks back',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'width_resize_proj',
        name: 'Width Resize App',
        orgId: 'com.width.resize',
        path: Directory.systemTemp.path,
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 4,
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

      final sidebarFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.key != const ValueKey('anchored_live_preview_pane') &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border is Border &&
            ((widget.decoration as BoxDecoration).border as Border).top == BorderSide.none &&
            ((widget.decoration as BoxDecoration).border as Border).left != BorderSide.none,
      );
      expect(sidebarFinder, findsOneWidget);

      // Initially on Tab 0 (Details): width is 440px
      RenderBox sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(440.0, 1.0));

      // Switch to Code Tab (Tab 1)
      await tester.tap(find.text('💻 Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // In Code mode: width widens to 500px
      sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(500.0, 1.0));

      // Switch back to Details Tab (Tab 0)
      await tester.tap(find.text('⚙️ Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Returns to 440px
      sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(440.0, 1.0));

      // Also verify right-anchored preview pane is present
      final previewFinder = find.byKey(const ValueKey('anchored_live_preview_pane'));
      expect(previewFinder, findsOneWidget);
      final RenderBox previewBox = tester.renderObject(previewFinder);
      expect(previewBox.size.width, closeTo(420.0, 1.0));

      expect(tester.takeException(), isNull);
    });

    testWidgets('AppStrings provides localized labels for all 3 inspector tabs across languages',
        (tester) async {
      final en = AppStrings(AppLanguage.en);
      expect(en.routeDetailsTab, 'Details');
      expect(en.viewCodeTab, 'Code');
      expect(en.emulateScreenTab, 'Emulate');

      final pt = AppStrings(AppLanguage.pt);
      expect(pt.routeDetailsTab, 'Detalhes');
      expect(pt.viewCodeTab, 'Código');
      expect(pt.emulateScreenTab, 'Emular');

      final es = AppStrings(AppLanguage.es);
      expect(es.routeDetailsTab, 'Detalles');
      expect(es.viewCodeTab, 'Código');
      expect(es.emulateScreenTab, 'Emular');
    });
  });
}
