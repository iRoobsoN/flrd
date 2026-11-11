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
      expect(find.text('Welcome back, Alex 👋'), findsOneWidget);
    });
  });

  group('DeviceScreenEmulator - RouteNode Archetypes', () {
    testWidgets('ProfileScreen simulation: renders avatar, pro badge, and interactive toggles',
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

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pumpAndSettle();

      // Elements of ProfileScreen
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('FLRD PRO TIER'), findsOneWidget);
      expect(find.text('Biometric Authentication'), findsOneWidget);
      expect(find.text('Push Notifications'), findsOneWidget);
      expect(find.text('Developer Sandbox Mode'), findsOneWidget);
      expect(find.text('Auto Cloud Sync'), findsOneWidget);
      expect(find.text('Clear Cache'), findsOneWidget);

      // Toggle switches
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(4));

      // Tap first switch (Biometrics)
      await tester.tap(switches.first);
      await tester.pumpAndSettle();

      // Tap Clear Cache
      await tester.tap(find.text('Clear Cache'));
      await tester.pumpAndSettle();
      expect(find.text('Local Cache: 0 MB'), findsOneWidget);

      // Tap edit profile button
      await tester.tap(find.byIcon(Icons.edit_note_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Alexandra M. Dev'), findsOneWidget);
    });

    testWidgets('AuthScreen simulation: renders Sign In / Register, inputs and submit CTA',
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

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pumpAndSettle();

      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Password visibility toggle
      final eyeIcon = find.byIcon(Icons.visibility_rounded);
      expect(eyeIcon, findsOneWidget);
      await tester.tap(eyeIcon);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);

      // Checkbox toggle
      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Submit sign in
      await tester.tap(find.text('Sign In to Workspace'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.textContaining('Authenticated as'), findsOneWidget);

      // Switch to Register Tab
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      expect(find.text('Create Free Account'), findsWidgets);
      expect(find.text('Full Name'), findsOneWidget);
    });

    testWidgets('DashboardScreen simulation: renders KPI metrics, filters, and bottom nav',
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

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back, Alex 👋'), findsOneWidget);
      expect(find.text('Total Revenue'), findsOneWidget);
      expect(find.text('\$24,850'), findsOneWidget);
      expect(find.text('Active Users'), findsOneWidget);
      expect(find.text('API Latency'), findsOneWidget);
      expect(find.text('Error Rate'), findsOneWidget);

      // Filter chips
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('7D'), findsOneWidget);
      expect(find.text('30D'), findsOneWidget);
      expect(find.text('1Y'), findsOneWidget);
      await tester.tap(find.text('7D'));
      await tester.pumpAndSettle();

      // Quick action button
      await tester.tap(find.text('Deploy Screen'));
      await tester.pumpAndSettle();

      // Bottom nav bar items
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Metrics'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
    });

    testWidgets('ExploreScreen simulation: search bar, filter chips, and feed cards',
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

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pumpAndSettle();

      expect(find.text('SaaS Dashboard Pro'), findsOneWidget);
      expect(find.text('Supabase Clean Auth'), findsOneWidget);
      expect(find.text('Gemini 1.5 Code Copilot'), findsOneWidget);

      // Search bar interaction
      await tester.enterText(find.byType(TextField).first, 'Gemini');
      await tester.pumpAndSettle();

      expect(find.text('Gemini 1.5 Code Copilot'), findsOneWidget);
      expect(find.text('SaaS Dashboard Pro'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();
      expect(find.text('SaaS Dashboard Pro'), findsOneWidget);

      // Install button toggle
      final installButton = find.text('Install').first;
      await tester.tap(installButton);
      await tester.pumpAndSettle();
      expect(find.text('Installed'), findsWidgets);
    });

    testWidgets('SplashScreen simulation: pulsing logo and AuthGuard pipeline',
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

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('FLRD Studio'), findsOneWidget);
      expect(find.text('GoRouter AuthGuard Pipeline'), findsOneWidget);
      expect(find.text('Simulate Launch Transition'), findsOneWidget);

      await tester.tap(find.text('Simulate Launch Transition'));
      await tester.pumpAndSettle();
      expect(find.text('Route Guard Approved'), findsOneWidget);
    });

    testWidgets('Custom / AI Screen simulation: permissions switches and action dispatcher',
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

      await tester.pumpWidget(buildTestableWidget(tester, const DeviceScreenEmulator(node: node)));
      await tester.pumpAndSettle();

      expect(find.text('CameraScanScreen'), findsOneWidget);
      expect(find.text('AI Screen'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Dispatch Screen Action'), findsOneWidget);

      // Dispatch action
      await tester.tap(find.text('Dispatch Screen Action'));
      await tester.pumpAndSettle();
      expect(find.textContaining('State updated successfully'), findsOneWidget);
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

      // Close via fullscreen exit icon
      await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('AppStudioScreen - 3-Tab Inspector Switching & Emulate Integration', () {
    testWidgets('Renders 3 tabs and switches seamlessly between Details, Code and Emulate',
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

      // 1. Verify all 3 segmented tab buttons are present
      expect(find.text('⚙️ Details'), findsOneWidget);
      expect(find.text('💻 Code'), findsOneWidget);
      expect(find.text('📱 Emulate'), findsOneWidget);

      // 2. Default tab is Details (Tab 0) - Route details editor is shown
      expect(find.text('GoRouter Route Path'), findsOneWidget);
      expect(find.byType(EmbeddedCodeViewer), findsNothing);
      expect(find.byType(DeviceScreenEmulator), findsNothing);

      // 3. Switch to Tab 1: Code
      await tester.tap(find.text('💻 Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsNothing);

      // 4. Switch to Tab 2: Emulate
      await tester.tap(find.text('📱 Emulate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(DeviceScreenEmulator), findsOneWidget);
      expect(find.byType(EmbeddedCodeViewer), findsNothing);
      // Dashboard archetype inside emulator
      expect(find.text('Welcome back, Alex 👋'), findsOneWidget);

      // 5. Switch back to Tab 0: Details
      await tester.tap(find.text('⚙️ Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('GoRouter Route Path'), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsNothing);

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

      // Switch to Emulate Tab
      await tester.tap(find.text('📱 Emulate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Profile screen content is shown
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('FLRD PRO TIER'), findsOneWidget);

      // Now select login node
      studioNotifier.selectNode('login');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Login screen content is now shown
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);

      // Now select explore node
      studioNotifier.selectNode('explore');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Explore screen content is now shown
      expect(find.text('SaaS Dashboard Pro'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Inspector sidebar expands to 480px on desktop when in emulate mode and shrinks back',
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
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border is Border &&
            ((widget.decoration as BoxDecoration).border as Border).top == BorderSide.none &&
            ((widget.decoration as BoxDecoration).border as Border).left != BorderSide.none,
      );
      expect(sidebarFinder, findsOneWidget);

      // Initially on Tab 0 (Details): width is 440px
      RenderBox sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(440.0, 1.0));

      // Switch to Emulate Tab (Tab 2)
      await tester.tap(find.text('📱 Emulate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // In Emulate mode: width widens to 480px
      sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(480.0, 1.0));

      // Switch to Code Tab (Tab 1)
      await tester.tap(find.text('💻 Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Returns to 440px
      sidebarBox = tester.renderObject(sidebarFinder);
      expect(sidebarBox.size.width, closeTo(440.0, 1.0));

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
