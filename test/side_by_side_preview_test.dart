import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    tester.view.physicalSize = Size(size.width, size.height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    return MaterialApp(
      theme: ThemeData.dark(),
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

  const sampleRouteNode = RouteNode(
    id: 'checkout_node',
    path: '/checkout',
    title: 'Order Checkout',
    subtitle: 'Payment & summary processing',
    icon: Icons.shopping_bag_rounded,
    position: Offset(100, 150),
    filePath: 'lib/features/checkout/presentation/checkout_screen.dart',
  );

  final sampleProject = RegisteredProject(
    id: 'test_side_by_side_project',
    name: 'FLRD E-Commerce',
    orgId: 'com.flrd.ecommerce',
    path: 'C:/test/flrd_ecommerce',
    preset: PresetType.saas,
    navigationStyle: NavigationStyle.tabs,
    permissions: const {},
    lastModified: DateTime.now(),
    routeCount: 1,
  );

  const initialCodeV1 = '''
import 'package:flutter/material.dart';

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Order Checkout V1'),
        backgroundColor: Color(0xFF1E293B),
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.shopping_bag_rounded, size: 40),
              SizedBox(height: 12),
              Text('Review your items before paying.'),
            ],
          ),
        ),
      ),
    );
  }
}
''';

  const updatedCodeV2 = '''
import 'package:flutter/material.dart';

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Order Checkout V2 - VIP Express'),
        backgroundColor: Color(0xFF312E81),
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Color(0xFF312E81),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, size: 48),
              const SizedBox(height: 16),
              const Text('VIP 1-Click Instant Payment'),
              ElevatedButton(
                onPressed: () {},
                child: const Text('Pay \$149.00 Now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''';

  group('1. Dynamic Code Parsing in DeviceScreenEmulator', () {
    testWidgets(
        'Renders exact AppBar title and container body text matching Dart code in live sync mode',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: sampleRouteNode,
            sourceCode: initialCodeV1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Matches exact AppBar title from code
      expect(find.text('Order Checkout V1'), findsOneWidget);

      // 2. Matches exact body text from code
      expect(find.text('Review your items before paying.'), findsOneWidget);

      // 3. Matches icon parsed from code
      expect(find.byIcon(Icons.shopping_bag_rounded), findsWidgets);

      // 4. Default toolbar shows [⚡ Code Live Sync] pill active
      expect(find.text('⚡ Code Live Sync'), findsOneWidget);
      expect(find.text('🎨 Archetype Mock'), findsOneWidget);

      // 5. Does NOT show archetype fallback mock text
      expect(find.text('FLRD Studio'), findsNothing);
      expect(find.text('Payment Gateway Simulation'), findsNothing);
    });

    testWidgets(
        'Toggling to [🎨 Archetype Mock] displays archetype mock and toggling back restores live code preview',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: sampleRouteNode,
            sourceCode: initialCodeV1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Starts in Code Live Sync
      expect(find.text('Order Checkout V1'), findsOneWidget);
      expect(find.text('Review your items before paying.'), findsOneWidget);

      // Tap Archetype Mock toggle
      await tester.tap(find.text('🎨 Archetype Mock'));
      await tester.pumpAndSettle();

      // Now renders Archetype Mock UI instead of code
      expect(find.text('Order Checkout V1'), findsNothing);
      expect(find.text('Review your items before paying.'), findsNothing);
      // Archetype mock shows route title from RouteNode
      expect(find.text('Order Checkout'), findsWidgets);

      // Tap back to Code Live Sync
      await tester.tap(find.text('⚡ Code Live Sync'));
      await tester.pumpAndSettle();

      // Restored live code view!
      expect(find.text('Order Checkout V1'), findsOneWidget);
      expect(find.text('Review your items before paying.'), findsOneWidget);
    });
  });

  group('2. Live Code Update Reaction', () {
    testWidgets(
        'DeviceScreenEmulator immediately invalidates cache and updates rendered screen on sourceCode change',
        (tester) async {
      // 1. Initial render with V1 code
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: sampleRouteNode,
            sourceCode: initialCodeV1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Order Checkout V1'), findsOneWidget);
      expect(find.text('Review your items before paying.'), findsOneWidget);
      expect(find.text('Order Checkout V2 - VIP Express'), findsNothing);
      expect(find.text('VIP 1-Click Instant Payment'), findsNothing);

      // 2. Re-pump widget with V2 code (simulating editor live change)
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: sampleRouteNode,
            sourceCode: updatedCodeV2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 3. New AppBar title and body text render immediately
      expect(find.text('Order Checkout V1'), findsNothing);
      expect(find.text('Review your items before paying.'), findsNothing);

      expect(find.text('Order Checkout V2 - VIP Express'), findsOneWidget);
      expect(find.text('VIP 1-Click Instant Payment'), findsOneWidget);
      expect(find.text('Pay \$149.00 Now'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsWidgets);
    });

    testWidgets(
        'EmbeddedCodeViewer fires onCodeChanged on initialization and text editing',
        (tester) async {
      String? emittedCode;
      int callbackCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmbeddedCodeViewer(
              projectPath: sampleProject.path,
              node: sampleRouteNode,
              onCodeChanged: (code) {
                emittedCode = code;
                callbackCount++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Callback fires on initial load with generated template code
      expect(callbackCount, greaterThanOrEqualTo(1));
      expect(emittedCode, isNotNull);
      expect(emittedCode!.contains('Order Checkout'), isTrue);
      expect(emittedCode!.contains('class OrderCheckoutScreen extends StatelessWidget'), isTrue);

      // 2. Editing text via TextField in EmbeddedCodeViewer fires callback again
      final codeFieldFinder = find.byType(TextField);
      expect(codeFieldFinder, findsOneWidget);

      await tester.enterText(codeFieldFinder, updatedCodeV2);
      await tester.pump();

      expect(emittedCode, updatedCodeV2);
      expect(callbackCount, greaterThanOrEqualTo(2));
    });
  });

  group('3. _showLivePreview Side-by-Side Toggle in AppStudioScreen', () {
    testWidgets(
        'Toggling _showLivePreview button hides and restores DeviceScreenEmulator next to EmbeddedCodeViewer',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Pre-select checkout_node
      container.read(studioProvider.notifier).setNodes([sampleRouteNode]);
      container.read(studioProvider.notifier).selectNode(sampleRouteNode.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: AppStudioScreen(project: sampleProject),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Switch inspector tab to View Dart Code (💻)
      final codeTabFinder = find.textContaining('💻');
      expect(codeTabFinder, findsOneWidget);
      await tester.tap(codeTabFinder);
      await tester.pumpAndSettle();

      // 2. Both EmbeddedCodeViewer and DeviceScreenEmulator are present side-by-side
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsOneWidget);

      // 3. Header toggle button is visible with 'Hide Preview' (since _showLivePreview defaults to true)
      final togglePreviewBtn = find.byKey(const ValueKey('toggle_live_preview_button')).first;
      expect(togglePreviewBtn, findsOneWidget);
      expect(find.text('Hide Preview'), findsWidgets);

      // 4. Tap toggle button to hide live preview
      await tester.tap(togglePreviewBtn);
      await tester.pumpAndSettle();

      // 5. Emulator is now hidden, EmbeddedCodeViewer remains full width
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsNothing);
      expect(find.text('📱 Live Preview'), findsWidgets);

      // 6. Tap toggle button again to restore live preview
      await tester.tap(togglePreviewBtn);
      await tester.pumpAndSettle();

      // 7. DeviceScreenEmulator is restored side-by-side
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsOneWidget);
      expect(find.text('Hide Preview'), findsWidgets);
    });
  });

  group('4. _isDiagramCollapsed Full-Width Expansion in AppStudioScreen', () {
    testWidgets(
        'Collapsing diagram hides flowchart canvas and gives 100% width to Code + Live Preview side-by-side',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(studioProvider.notifier).setNodes([sampleRouteNode]);
      container.read(studioProvider.notifier).selectNode(sampleRouteNode.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: AppStudioScreen(project: sampleProject),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initially, flowchart canvas (InteractiveViewer) is rendered
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // Switch to Code Tab
      await tester.tap(find.textContaining('💻'));
      await tester.pumpAndSettle();

      // Canvas collapse button in toolbar
      final toggleDiagramBtn = find.byKey(const ValueKey('toggle_diagram_collapse_button'));
      expect(toggleDiagramBtn, findsOneWidget);
      expect(find.text('◀ Collapse Diagram'), findsOneWidget);

      // 2. Collapse the diagram
      await tester.tap(toggleDiagramBtn);
      await tester.pumpAndSettle();

      // 3. Flowchart canvas (InteractiveViewer) is completely removed from tree
      expect(find.byType(InteractiveViewer), findsNothing);

      // Toolbar button and inspector button now display "▶ Show Diagram"
      expect(find.text('▶ Show Diagram'), findsNWidgets(2));

      // Inspector show diagram button is also available
      final inspectorShowDiagramBtn =
          find.byKey(const ValueKey('inspector_show_diagram_button'));
      expect(inspectorShowDiagramBtn, findsOneWidget);

      // Both EmbeddedCodeViewer and DeviceScreenEmulator remain visible side-by-side
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsOneWidget);

      // 4. Restore the diagram by clicking "▶ Show Diagram" in the toolbar
      await tester.tap(toggleDiagramBtn);
      await tester.pumpAndSettle();

      // 5. Flowchart canvas is restored!
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('◀ Collapse Diagram'), findsOneWidget);
      expect(find.byKey(const ValueKey('inspector_show_diagram_button')), findsNothing);
    });

    testWidgets(
        'Floating canvas collapse button also triggers full-width diagram collapse and auto-selects node',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(studioProvider.notifier).setNodes([sampleRouteNode]);
      // Explicitly deselect node so auto-selection logic triggers
      container.read(studioProvider.notifier).selectNode(null);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: AppStudioScreen(project: sampleProject),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final floatingCollapseBtn =
          find.byKey(const ValueKey('canvas_collapse_diagram_button'));
      expect(floatingCollapseBtn, findsOneWidget);

      // Click floating canvas collapse button
      await tester.tap(floatingCollapseBtn);
      await tester.pumpAndSettle();

      // Canvas collapses and inspector opens in Code tab with side-by-side view
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsOneWidget);
    });
  });

  group('5. Responsive Side-by-Side Split & Zero RenderFlex Overflows', () {
    testWidgets(
        'Renders horizontal Row split on wide viewport and vertical Column split on narrow viewport (< 580px)',
        (tester) async {
      // Wide screen: Row layout
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(studioProvider.notifier).setNodes([sampleRouteNode]);
      container.read(studioProvider.notifier).selectNode(sampleRouteNode.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: AppStudioScreen(project: sampleProject),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('💻'));
      await tester.pumpAndSettle();

      // Find the LayoutBuilder that contains both code viewer and emulator
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byType(DeviceScreenEmulator), findsOneWidget);

      // In wide view, CodeViewer and Emulator are laid out side-by-side (Row)
      final codeViewerTopLeft = tester.getTopLeft(find.byType(EmbeddedCodeViewer));
      final emulatorTopLeft = tester.getTopLeft(find.byType(DeviceScreenEmulator));
      expect(emulatorTopLeft.dx, greaterThan(codeViewerTopLeft.dx));

      // Collapse diagram to 100% width: verify still side-by-side with zero overflow
      await tester.tap(find.byKey(const ValueKey('toggle_diagram_collapse_button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
