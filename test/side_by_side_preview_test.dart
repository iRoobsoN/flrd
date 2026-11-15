import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/embedded_code_viewer.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('1. Live Code Update Reaction', () {
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
      expect(
        emittedCode!.contains('class OrderCheckoutScreen extends StatelessWidget'),
        isTrue,
      );

      // 2. Editing text via TextField in EmbeddedCodeViewer fires callback again
      final codeFieldFinder = find.byType(TextField);
      expect(codeFieldFinder, findsOneWidget);

      await tester.enterText(codeFieldFinder, updatedCodeV2);
      await tester.pump();

      expect(emittedCode, updatedCodeV2);
      expect(callbackCount, greaterThanOrEqualTo(2));
    });
  });

  group('2. Fake Live Preview Removal in AppStudioScreen', () {
    testWidgets(
        'AppStudioScreen omits fake live preview pane and toggle buttons while keeping EmbeddedCodeViewer active',
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

      // Switch inspector tab to View Dart Code (💻)
      final codeTabFinder = find.textContaining('💻');
      expect(codeTabFinder, findsOneWidget);
      await tester.tap(codeTabFinder);
      await tester.pumpAndSettle();

      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsNothing);
      expect(find.byKey(const ValueKey('toggle_live_preview_button')), findsNothing);
      expect(find.byKey(const ValueKey('inspector_toggle_preview_button')), findsNothing);
      expect(find.text('Hide Preview'), findsNothing);
      expect(find.text('📱 Live Preview'), findsNothing);
      expect(find.text('Live Screen Preview'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('3. _isDiagramCollapsed Full-Width Expansion in AppStudioScreen', () {
    testWidgets(
        'Collapsing diagram hides flowchart canvas and gives 100% width to Inspector/Code',
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
      final toggleDiagramBtn =
          find.byKey(const ValueKey('toggle_diagram_collapse_button'));
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

      // EmbeddedCodeViewer remains visible cleanly
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);

      // 4. Restore the diagram by clicking "▶ Show Diagram" in the toolbar
      await tester.tap(toggleDiagramBtn);
      await tester.pumpAndSettle();

      // 5. Flowchart canvas is restored!
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('◀ Collapse Diagram'), findsOneWidget);
      expect(find.byKey(const ValueKey('inspector_show_diagram_button')), findsNothing);
      expect(tester.takeException(), isNull);
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

      // Canvas collapses and inspector opens in Code tab
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('4. Responsive Full-Width Inspector & Zero RenderFlex Overflows', () {
    testWidgets(
        'Renders code inspector and collapses diagram to 100% width with zero RenderFlex overflow',
        (tester) async {
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

      expect(find.byType(EmbeddedCodeViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsNothing);

      // Collapse diagram to 100% width: verify zero overflow
      await tester.tap(find.byKey(const ValueKey('toggle_diagram_collapse_button')));
      await tester.pumpAndSettle();

      final box = tester.renderObject<RenderBox>(find.byType(EmbeddedCodeViewer));
      expect(box.size.width, greaterThan(1000.0));
      expect(tester.takeException(), isNull);
    });
  });
}
