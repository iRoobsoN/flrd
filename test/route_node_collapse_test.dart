import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/widgets/route_node_card.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';

void main() {
  const testNode = RouteNode(
    id: 'home',
    path: '/home',
    title: 'HomeScreen',
    subtitle: 'Main dashboard view',
    icon: Icons.home_rounded,
    position: Offset(100, 100),
    filePath: 'lib/features/home/presentation/home_screen.dart',
  );

  group('RouteNode Model Collapsed Tests', () {
    test('Default isCollapsed is false', () {
      expect(testNode.isCollapsed, isFalse);
    });

    test('copyWith toggles isCollapsed', () {
      final collapsed = testNode.copyWith(isCollapsed: true);
      expect(collapsed.isCollapsed, isTrue);
      expect(collapsed.title, testNode.title);
      expect(collapsed.path, testNode.path);

      final expanded = collapsed.copyWith(isCollapsed: false);
      expect(expanded.isCollapsed, isFalse);
    });
  });

  group('StudioNotifier Collapse State Management Tests', () {
    test('toggleNodeCollapse flips isCollapsed for target node', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialNodes = container.read(studioProvider).nodes;
      final targetId = initialNodes.first.id;
      expect(initialNodes.first.isCollapsed, isFalse);

      container.read(studioProvider.notifier).toggleNodeCollapse(targetId);
      final updatedNode = container
          .read(studioProvider)
          .nodes
          .firstWhere((n) => n.id == targetId);
      expect(updatedNode.isCollapsed, isTrue);

      container.read(studioProvider.notifier).toggleNodeCollapse(targetId);
      final revertedNode = container
          .read(studioProvider)
          .nodes
          .firstWhere((n) => n.id == targetId);
      expect(revertedNode.isCollapsed, isFalse);
    });

    test('setAllNodesCollapsed modifies all nodes uniformly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(studioProvider.notifier).setAllNodesCollapsed(true);
      final nodes = container.read(studioProvider).nodes;
      expect(nodes.every((n) => n.isCollapsed), isTrue);

      container.read(studioProvider.notifier).setAllNodesCollapsed(false);
      final expandedNodes = container.read(studioProvider).nodes;
      expect(expandedNodes.every((n) => !n.isCollapsed), isTrue);
    });
  });

  group('RouteNodeCard Visual & Interaction Tests', () {
    testWidgets('Expanded state renders 110px height with collapse button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testNode,
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final cardSize = tester.getSize(find.byType(RouteNodeCard));
      expect(cardSize.width, 260.0);
      expect(cardSize.height, 110.0);

      expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);
      expect(find.text('HomeScreen'), findsOneWidget);
      expect(find.text('/home'), findsOneWidget);
      expect(find.text('Main dashboard view'), findsOneWidget);
    });

    testWidgets('Collapsed state renders 38px height with compact capsule',
        (tester) async {
      final collapsedNode = testNode.copyWith(isCollapsed: true);

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

      final cardSize = tester.getSize(find.byType(RouteNodeCard));
      expect(cardSize.width, 260.0);
      expect(cardSize.height, 38.0);

      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      expect(find.text('HomeScreen'), findsOneWidget);
      expect(find.text('/home'), findsOneWidget);
      // Subtitle is hidden in compact mode
      expect(find.text('Main dashboard view'), findsNothing);
    });

    testWidgets('Tapping collapse button in header toggles state',
        (tester) async {
      bool toggleCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testNode,
              isSelected: false,
              onTap: () {},
              onToggleCollapse: () => toggleCalled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      final collapseBtn = find.byIcon(Icons.expand_less_rounded);
      expect(collapseBtn, findsOneWidget);

      await tester.tap(collapseBtn);
      await tester.pump();

      expect(toggleCalled, isTrue);
    });

    testWidgets('Double-tapping card toggles collapse state', (tester) async {
      bool toggleCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testNode,
              isSelected: false,
              onTap: () {},
              onToggleCollapse: () => toggleCalled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      // First tap
      await tester.tap(find.byType(RouteNodeCard));
      await tester.pump(const Duration(milliseconds: 50));

      // Second tap within 350ms window
      await tester.tap(find.byType(RouteNodeCard));
      await tester.pump();

      expect(toggleCalled, isTrue);
    });

    testWidgets('Local toggle works when onToggleCollapse is omitted',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testNode,
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(RouteNodeCard)).height, 110.0);

      // Tap collapse button
      await tester.tap(find.byIcon(Icons.expand_less_rounded));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(RouteNodeCard)).height, 38.0);
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);

      // Tap expand button
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(RouteNodeCard)).height, 110.0);
      expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);
    });
  });
}
