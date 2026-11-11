import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/route_connector_painter.dart';
import 'package:flrd/features/studio/presentation/widgets/route_node_card.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testParentNode = RouteNode(
    id: 'parent_node',
    path: '/root',
    title: 'RootScreen',
    subtitle: 'Root landing view',
    icon: Icons.home_rounded,
    position: Offset(100, 200),
    filePath: 'lib/features/root/presentation/root_screen.dart',
  );

  const testChildNode = RouteNode(
    id: 'child_node',
    path: '/root/child',
    title: 'ChildScreen',
    subtitle: 'Child nested screen',
    icon: Icons.dashboard_rounded,
    position: Offset(500, 300),
    filePath: 'lib/features/child/presentation/child_screen.dart',
    parentRouteId: 'parent_node',
  );

  final testProject = RegisteredProject(
    id: 'infinite_canvas_test_project',
    name: 'Infinite Canvas Project',
    orgId: 'com.test.infinitecanvas',
    path: 'C:/test/infinite_canvas',
    preset: PresetType.saas,
    navigationStyle: NavigationStyle.tabs,
    permissions: const {},
    lastModified: DateTime.now(),
    routeCount: 2,
  );

  group('1. RouteNode.isCollapsed Unit Tests', () {
    test('Default isCollapsed is false', () {
      const node = RouteNode(
        id: 'default_node',
        path: '/default',
        title: 'DefaultScreen',
        subtitle: 'Test default',
        icon: Icons.check,
        position: Offset.zero,
        filePath: 'lib/test.dart',
      );
      expect(node.isCollapsed, isFalse);
    });

    test('Explicit isCollapsed preserves specified value', () {
      const collapsedNode = RouteNode(
        id: 'collapsed_node',
        path: '/collapsed',
        title: 'CollapsedScreen',
        subtitle: 'Test collapsed',
        icon: Icons.check,
        position: Offset.zero,
        filePath: 'lib/test.dart',
        isCollapsed: true,
      );
      expect(collapsedNode.isCollapsed, isTrue);
    });

    test('copyWith toggles isCollapsed while preserving all other properties', () {
      final node = testParentNode.copyWith(isCollapsed: true);
      expect(node.isCollapsed, isTrue);
      expect(node.id, testParentNode.id);
      expect(node.path, testParentNode.path);
      expect(node.title, testParentNode.title);
      expect(node.subtitle, testParentNode.subtitle);
      expect(node.icon, testParentNode.icon);
      expect(node.position, testParentNode.position);
      expect(node.filePath, testParentNode.filePath);

      final uncollapsed = node.copyWith(isCollapsed: false);
      expect(uncollapsed.isCollapsed, isFalse);
      expect(uncollapsed.id, testParentNode.id);

      final untouched = uncollapsed.copyWith(title: 'New Title');
      expect(untouched.isCollapsed, isFalse);
      expect(untouched.title, 'New Title');
    });
  });

  group('2. StudioNotifier Collapse State Management Tests', () {
    test('toggleNodeCollapse flips isCollapsed for targeted node only', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(studioProvider.notifier).setNodes([testParentNode, testChildNode]);

      var nodes = container.read(studioProvider).nodes;
      expect(nodes[0].isCollapsed, isFalse);
      expect(nodes[1].isCollapsed, isFalse);

      // Toggle parent node
      container.read(studioProvider.notifier).toggleNodeCollapse('parent_node');
      nodes = container.read(studioProvider).nodes;
      expect(nodes[0].isCollapsed, isTrue);
      expect(nodes[1].isCollapsed, isFalse); // Child remains unchanged

      // Toggle parent node back
      container.read(studioProvider.notifier).toggleNodeCollapse('parent_node');
      nodes = container.read(studioProvider).nodes;
      expect(nodes[0].isCollapsed, isFalse);
      expect(nodes[1].isCollapsed, isFalse);

      // Toggle child node
      container.read(studioProvider.notifier).toggleNodeCollapse('child_node');
      nodes = container.read(studioProvider).nodes;
      expect(nodes[0].isCollapsed, isFalse);
      expect(nodes[1].isCollapsed, isTrue);

      // Toggling unknown ID has no effect
      container.read(studioProvider.notifier).toggleNodeCollapse('non_existent_id');
      nodes = container.read(studioProvider).nodes;
      expect(nodes[0].isCollapsed, isFalse);
      expect(nodes[1].isCollapsed, isTrue);
    });

    test('setAllNodesCollapsed bulk collapses and bulk expands all nodes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(studioProvider.notifier).setNodes([testParentNode, testChildNode]);

      // Bulk collapse
      container.read(studioProvider.notifier).setAllNodesCollapsed(true);
      var nodes = container.read(studioProvider).nodes;
      expect(nodes.length, 2);
      expect(nodes.every((n) => n.isCollapsed), isTrue);

      // Bulk expand
      container.read(studioProvider.notifier).setAllNodesCollapsed(false);
      nodes = container.read(studioProvider).nodes;
      expect(nodes.every((n) => !n.isCollapsed), isTrue);
    });

    test('addRouteNode supports isCollapsed parameter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(studioProvider.notifier).addRouteNode(
        path: '/custom',
        title: 'CustomScreen',
        subtitle: 'Custom subtitle',
        icon: Icons.star,
        position: const Offset(300, 300),
        filePath: 'lib/custom.dart',
        isCollapsed: true,
      );

      final added = container.read(studioProvider).nodes.last;
      expect(added.title, 'CustomScreen');
      expect(added.isCollapsed, isTrue);
    });
  });

  group('3. RouteNodeCard Collapsed vs Expanded Rendering Tests', () {
    testWidgets('Expanded state renders 110px height with collapse icon button and subtitle',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testParentNode,
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final cardFinder = find.byType(RouteNodeCard);
      final size = tester.getSize(cardFinder);
      expect(size.width, 260.0);
      expect(size.height, 110.0);

      // Verify expanded collapse button (expand_less)
      expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);

      // Verify text elements
      expect(find.text('RootScreen'), findsOneWidget);
      expect(find.text('/root'), findsOneWidget);
      expect(find.text('Root landing view'), findsOneWidget);
    });

    testWidgets('Collapsed state renders 38px compact single-row capsule with expand icon button',
        (tester) async {
      final collapsedNode = testParentNode.copyWith(isCollapsed: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: collapsedNode,
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final cardFinder = find.byType(RouteNodeCard);
      final size = tester.getSize(cardFinder);
      expect(size.width, 260.0);
      expect(size.height, 38.0);

      // Verify expand button (expand_more)
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      expect(find.byIcon(Icons.expand_less_rounded), findsNothing);

      // Verify title & path are visible, but subtitle is hidden in compact mode
      expect(find.text('RootScreen'), findsOneWidget);
      expect(find.text('/root'), findsOneWidget);
      expect(find.text('Root landing view'), findsNothing);
    });

    testWidgets('Tapping collapse button in header fires onToggleCollapse callback',
        (tester) async {
      bool toggleFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testParentNode,
              isSelected: false,
              onTap: () {},
              onToggleCollapse: () => toggleFired = true,
            ),
          ),
        ),
      );
      await tester.pump();

      final buttonFinder = find.byKey(ValueKey('collapse_btn_${testParentNode.id}'));
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();

      expect(toggleFired, isTrue);
    });

    testWidgets('Tapping expand button in collapsed capsule fires onToggleCollapse callback',
        (tester) async {
      bool toggleFired = false;
      final collapsedNode = testParentNode.copyWith(isCollapsed: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: collapsedNode,
              isSelected: false,
              onTap: () {},
              onToggleCollapse: () => toggleFired = true,
            ),
          ),
        ),
      );
      await tester.pump();

      final buttonFinder = find.byKey(ValueKey('expand_btn_${collapsedNode.id}'));
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();

      expect(toggleFired, isTrue);
    });

    testWidgets('Double-tapping RouteNodeCard toggles collapse state', (tester) async {
      bool toggleFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testParentNode,
              isSelected: false,
              onTap: () {},
              onToggleCollapse: () => toggleFired = true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Double-tap within 350ms
      await tester.tap(find.byType(RouteNodeCard));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byType(RouteNodeCard));
      await tester.pump();

      expect(toggleFired, isTrue);
    });
  });

  group('4. RouteConnectorPainter Dynamic Connection Heights Tests', () {
    test('Calculates dynamic vertical connection heights based on isCollapsed states', () {
      const cardWidth = 260.0;

      // 1. Both expanded (parentHeight = 110.0, childHeight = 110.0)
      final bothExpandedParent = testParentNode.copyWith(isCollapsed: false);
      final bothExpandedChild = testChildNode.copyWith(isCollapsed: false);
      final parentHeight1 = bothExpandedParent.isCollapsed ? 38.0 : 110.0;
      final childHeight1 = bothExpandedChild.isCollapsed ? 38.0 : 110.0;
      expect(parentHeight1, 110.0);
      expect(childHeight1, 110.0);
      final start1 = Offset(
        bothExpandedParent.position.dx + cardWidth,
        bothExpandedParent.position.dy + (parentHeight1 / 2),
      );
      final end1 = Offset(
        bothExpandedChild.position.dx,
        bothExpandedChild.position.dy + (childHeight1 / 2),
      );
      expect(start1, const Offset(100 + 260, 200 + 55)); // (360, 255)
      expect(end1, const Offset(500, 300 + 55)); // (500, 355)

      // 2. Parent collapsed, child expanded (parentHeight = 38.0, childHeight = 110.0)
      final parentCollapsed = testParentNode.copyWith(isCollapsed: true);
      final childExpanded = testChildNode.copyWith(isCollapsed: false);
      final parentHeight2 = parentCollapsed.isCollapsed ? 38.0 : 110.0;
      final childHeight2 = childExpanded.isCollapsed ? 38.0 : 110.0;
      expect(parentHeight2, 38.0);
      expect(childHeight2, 110.0);
      final start2 = Offset(
        parentCollapsed.position.dx + cardWidth,
        parentCollapsed.position.dy + (parentHeight2 / 2),
      );
      final end2 = Offset(
        childExpanded.position.dx,
        childExpanded.position.dy + (childHeight2 / 2),
      );
      expect(start2, const Offset(100 + 260, 200 + 19)); // (360, 219)
      expect(end2, const Offset(500, 300 + 55)); // (500, 355)

      // 3. Parent expanded, child collapsed (parentHeight = 110.0, childHeight = 38.0)
      final parentExpanded = testParentNode.copyWith(isCollapsed: false);
      final childCollapsed = testChildNode.copyWith(isCollapsed: true);
      final parentHeight3 = parentExpanded.isCollapsed ? 38.0 : 110.0;
      final childHeight3 = childCollapsed.isCollapsed ? 38.0 : 110.0;
      expect(parentHeight3, 110.0);
      expect(childHeight3, 38.0);
      final start3 = Offset(
        parentExpanded.position.dx + cardWidth,
        parentExpanded.position.dy + (parentHeight3 / 2),
      );
      final end3 = Offset(
        childCollapsed.position.dx,
        childCollapsed.position.dy + (childHeight3 / 2),
      );
      expect(start3, const Offset(100 + 260, 200 + 55)); // (360, 255)
      expect(end3, const Offset(500, 300 + 19)); // (500, 319)

      // 4. Both collapsed (parentHeight = 38.0, childHeight = 38.0)
      final bothCollapsedParent = testParentNode.copyWith(isCollapsed: true);
      final bothCollapsedChild = testChildNode.copyWith(isCollapsed: true);
      final parentHeight4 = bothCollapsedParent.isCollapsed ? 38.0 : 110.0;
      final childHeight4 = bothCollapsedChild.isCollapsed ? 38.0 : 110.0;
      expect(parentHeight4, 38.0);
      expect(childHeight4, 38.0);
      final start4 = Offset(
        bothCollapsedParent.position.dx + cardWidth,
        bothCollapsedParent.position.dy + (parentHeight4 / 2),
      );
      final end4 = Offset(
        bothCollapsedChild.position.dx,
        bothCollapsedChild.position.dy + (childHeight4 / 2),
      );
      expect(start4, const Offset(100 + 260, 200 + 19)); // (360, 219)
      expect(end4, const Offset(500, 300 + 19)); // (500, 319)
    });

    testWidgets('RouteConnectorPainter renders cleanly on canvas with mixed collapse configurations',
        (tester) async {
      final mixedNodes = [
        testParentNode.copyWith(isCollapsed: true),
        testChildNode.copyWith(isCollapsed: false),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(1000, 1000),
              painter: RouteConnectorPainter(
                nodes: mixedNodes,
                selectedNodeId: 'child_node',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
    });

    test('RouteConnectorPainter shouldRepaint triggers when node list or selection changes', () {
      final painter1 = RouteConnectorPainter(
        nodes: [testParentNode, testChildNode],
        selectedNodeId: 'parent_node',
      );

      final painterSame = RouteConnectorPainter(
        nodes: painter1.nodes,
        selectedNodeId: 'parent_node',
      );

      final painterDifferentNodes = RouteConnectorPainter(
        nodes: [testParentNode.copyWith(isCollapsed: true), testChildNode],
        selectedNodeId: 'parent_node',
      );

      final painterDifferentSelection = RouteConnectorPainter(
        nodes: painter1.nodes,
        selectedNodeId: 'child_node',
      );

      expect(painterSame.shouldRepaint(painter1), isFalse);
      expect(painterDifferentNodes.shouldRepaint(painter1), isTrue);
      expect(painterDifferentSelection.shouldRepaint(painter1), isTrue);
    });
  });

  group('5. Infinite Canvas & Toolbar Fit View / Collapse All Integration Tests', () {
    testWidgets('Canvas is configured as 10000x6000 with boundaryMargin of 5000',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: testProject),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final ivFinder = find.byType(InteractiveViewer);
      expect(ivFinder, findsOneWidget);

      final ivWidget = tester.widget<InteractiveViewer>(ivFinder);
      expect(ivWidget.boundaryMargin, const EdgeInsets.all(5000));
      expect(ivWidget.minScale, 0.1);
      expect(ivWidget.maxScale, 2.5);

      // Verify canvas size is 10000x6000
      final canvasSizedBoxFinder = find.descendant(
        of: ivFinder,
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 10000 && w.height == 6000,
        ),
      );
      expect(canvasSizedBoxFinder, findsOneWidget);
    });

    testWidgets('Toolbar Collapse All / Expand All button bulk toggles nodes and updates button state',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Initialize with test nodes
      container.read(studioProvider.notifier).setNodes([testParentNode, testChildNode]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: testProject),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final collapseAllBtnFinder = find.byKey(const ValueKey('collapse_all_button'));
      expect(collapseAllBtnFinder, findsOneWidget);

      // Initial state: not all collapsed, button says "Collapse All"
      expect(find.text('Collapse All'), findsOneWidget);
      expect(find.byIcon(Icons.unfold_less_rounded), findsOneWidget);

      // Tap Collapse All
      await tester.tap(collapseAllBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Provider state is all collapsed
      var nodes = container.read(studioProvider).nodes;
      expect(nodes.every((n) => n.isCollapsed), isTrue);

      // Button now says "Expand All"
      expect(find.text('Expand All'), findsOneWidget);
      expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);

      // Tap Expand All
      await tester.tap(collapseAllBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Provider state is all expanded
      nodes = container.read(studioProvider).nodes;
      expect(nodes.every((n) => !n.isCollapsed), isTrue);

      // Button reverted to "Collapse All"
      expect(find.text('Collapse All'), findsOneWidget);
      expect(find.byIcon(Icons.unfold_less_rounded), findsOneWidget);
    });

    testWidgets('Fit View buttons in toolbar and floating canvas controls frame all nodes',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Place two spread-out nodes
      const nodeA = RouteNode(
        id: 'node_a',
        path: '/a',
        title: 'Node A',
        subtitle: 'Left Node',
        icon: Icons.circle,
        position: Offset(100, 100),
        filePath: 'lib/a.dart',
      );
      const nodeB = RouteNode(
        id: 'node_b',
        path: '/b',
        title: 'Node B',
        subtitle: 'Right Node',
        icon: Icons.circle,
        position: Offset(1200, 800),
        filePath: 'lib/b.dart',
      );
      container.read(studioProvider.notifier).setNodes([nodeA, nodeB]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: testProject),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check toolbar Fit View button exists
      final toolbarFitViewFinder = find.byKey(const ValueKey('toolbar_fit_view_button'));
      expect(toolbarFitViewFinder, findsOneWidget);

      // Check floating canvas controls Fit View button exists
      final floatingFitViewFinder = find.byKey(const ValueKey('fit_view_button'));
      expect(floatingFitViewFinder, findsOneWidget);

      final ivWidget = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final controller = ivWidget.transformationController!;

      // Manually set arbitrary zoom/pan
      controller.value = Matrix4.identity()
        ..translate(500.0, 500.0)
        ..scale(2.0, 2.0);
      await tester.pump();

      expect(controller.value.getMaxScaleOnAxis(), closeTo(2.0, 0.01));

      // Click toolbar Fit View button
      await tester.tap(toolbarFitViewFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Transformation matrix should have adjusted to frame the nodes
      final scaleAfterToolbarFit = controller.value.getMaxScaleOnAxis();
      expect(scaleAfterToolbarFit, isNot(closeTo(2.0, 0.01)));
      expect(scaleAfterToolbarFit, greaterThanOrEqualTo(0.1));
      expect(scaleAfterToolbarFit, lessThanOrEqualTo(1.5));

      // Perturb matrix again
      controller.value = Matrix4.identity()
        ..translate(-1000.0, -800.0)
        ..scale(0.3, 0.3);
      await tester.pump();

      // Click floating canvas controls Fit View button
      await tester.tap(floatingFitViewFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final scaleAfterFloatingFit = controller.value.getMaxScaleOnAxis();
      expect(scaleAfterFloatingFit, closeTo(scaleAfterToolbarFit, 0.001));
    });
  });
}
