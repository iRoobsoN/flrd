import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/core/theme/app_colors.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/route_node_card.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testNode = RouteNode(
    id: 'home_node',
    path: '/home',
    title: 'Home Screen',
    subtitle: 'Main dashboard view',
    icon: Icons.home_rounded,
    position: Offset(100, 100),
    filePath: 'lib/features/home/presentation/home_screen.dart',
  );

  group('RouteNodeCard Fluid Drag & Cursor Tests', () {
    testWidgets('Displays grab cursor initially and grabbing cursor during drag',
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

      final nodeCardMouseRegion = find.descendant(
        of: find.byType(RouteNodeCard),
        matching: find.byType(MouseRegion),
      );

      // Initially grab cursor
      expect(tester.widget<MouseRegion>(nodeCardMouseRegion).cursor, SystemMouseCursors.grab);

      // Start drag gesture and move past touch slop
      final gesture = await tester.startGesture(tester.getCenter(find.byType(RouteNodeCard)));
      await gesture.moveBy(const Offset(25, 25));
      await tester.pump();

      // During drag: grabbing cursor
      expect(tester.widget<MouseRegion>(nodeCardMouseRegion).cursor, SystemMouseCursors.grabbing);

      // End drag gesture
      await gesture.up();
      await tester.pump();

      // Returns to grab cursor
      expect(tester.widget<MouseRegion>(nodeCardMouseRegion).cursor, SystemMouseCursors.grab);
    });

    testWidgets('Triggers onDragStart, onDragUpdate, onDrag, and onDragEnd callbacks',
        (tester) async {
      bool dragStarted = false;
      bool dragEnded = false;
      Offset accumulatedDelta = Offset.zero;
      Offset? lastNewPos;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testNode,
              isSelected: false,
              onTap: () {},
              onDragStart: () => dragStarted = true,
              onDragUpdate: (delta) => accumulatedDelta += delta,
              onDrag: (newPos) => lastNewPos = newPos,
              onDragEnd: () => dragEnded = true,
            ),
          ),
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(find.byType(RouteNodeCard)));
      // First move exceeds drag touch slop to trigger onPanStart
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump();

      expect(dragStarted, isTrue);
      expect(dragEnded, isFalse);

      // Subsequent moves trigger onPanUpdate
      await gesture.moveBy(const Offset(30, 40));
      await tester.pump();

      expect(accumulatedDelta, const Offset(30, 40));
      expect(lastNewPos, testNode.position + const Offset(30, 40));

      await gesture.up();
      await tester.pump();
      expect(dragEnded, isTrue);
    });

    testWidgets('Triggers onDragEnd when pan is canceled', (tester) async {
      bool dragEnded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testNode,
              isSelected: false,
              onTap: () {},
              onDragEnd: () => dragEnded = true,
            ),
          ),
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(find.byType(RouteNodeCard)));
      await gesture.moveBy(const Offset(25, 25));
      await tester.pump();

      await gesture.cancel();
      await tester.pump();
      expect(dragEnded, isTrue);

      final nodeCardMouseRegion = find.descendant(
        of: find.byType(RouteNodeCard),
        matching: find.byType(MouseRegion),
      );
      expect(tester.widget<MouseRegion>(nodeCardMouseRegion).cursor, SystemMouseCursors.grab);
    });

    testWidgets('Eliminates 150ms animation lag during drag with Duration.zero',
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

      // In idle state, duration is 150ms
      final idleContainer = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(idleContainer.duration, const Duration(milliseconds: 150));

      // Start drag and move past touch slop
      final gesture = await tester.startGesture(tester.getCenter(find.byType(RouteNodeCard)));
      await gesture.moveBy(const Offset(25, 25));
      await tester.pump();

      // During drag, duration is Duration.zero to prevent lag
      final draggingContainer = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(draggingContainer.duration, Duration.zero);

      // Release drag
      await gesture.up();
      await tester.pump();

      // Returns to 150ms
      final releasedContainer = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(releasedContainer.duration, const Duration(milliseconds: 150));
    });

    testWidgets('Applies elevated lift shadow and border glow when dragged',
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

      final gesture = await tester.startGesture(tester.getCenter(find.byType(RouteNodeCard)));
      await gesture.moveBy(const Offset(25, 25));
      await tester.pump();

      final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      final decoration = container.decoration as BoxDecoration;

      // Elevated shadow has blurRadius: 24
      expect(decoration.boxShadow, isNotNull);
      expect(
        decoration.boxShadow!.any((s) => s.blurRadius == 24 && s.spreadRadius == 2),
        isTrue,
      );

      // Border width increases to 1.8 when dragged
      final border = decoration.border as Border;
      expect(border.top.width, 1.8);
      expect(border.top.color, AppColors.secondary);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('Applies primary color glow when selected node is dragged',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteNodeCard(
              node: testNode,
              isSelected: true,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(find.byType(RouteNodeCard)));
      await gesture.moveBy(const Offset(25, 25));
      await tester.pump();

      final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.any((s) => s.blurRadius == 24), isTrue);

      final border = decoration.border as Border;
      expect(border.top.color, AppColors.primary);

      await gesture.up();
      await tester.pump();
    });
  });

  group('InteractiveViewer Pan Disabling during Node Drag Tests', () {
    testWidgets('Disables InteractiveViewer pan when node drag begins and re-enables on end',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'drag_pan_test_proj',
        name: 'Drag Pan Test',
        orgId: 'com.test.pan',
        path: 'C:/test/path',
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 3,
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

      // Initially, InteractiveViewer.panEnabled must be true
      final ivInitial = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(ivInitial.panEnabled, isTrue);

      // Start drag on a RouteNodeCard and move to activate drag
      final cardFinder = find.widgetWithText(RouteNodeCard, 'Splash & AuthGuard');
      final gesture = await tester.startGesture(tester.getCenter(cardFinder));
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();

      // During drag: panEnabled is FALSE to avoid gesture conflict
      final ivDuringDrag = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(ivDuringDrag.panEnabled, isFalse);

      // Release drag
      await gesture.up();
      await tester.pump();

      // Post-drag: panEnabled is restored to TRUE
      final ivPostDrag = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(ivPostDrag.panEnabled, isTrue);
    });
  });

  group('Scale-Compensated Motion & Boundary Clamping Tests', () {
    test('Calculates zoom-compensated delta accurately at various zoom levels', () {
      // Scale 1.0 (identity)
      final matrix1 = Matrix4.identity();
      final scale1 = matrix1.getMaxScaleOnAxis().clamp(0.2, 5.0);
      expect(scale1, 1.0);
      const delta1 = Offset(10, 20);
      final canvasDelta1 = delta1 / scale1;
      expect(canvasDelta1, const Offset(10, 20));

      // Zoom In: Scale 2.0 (canvas moves half as many units for the same screen pointer motion)
      final matrix2 = Matrix4.identity()..scale(2.0, 2.0);
      final scale2 = matrix2.getMaxScaleOnAxis().clamp(0.2, 5.0);
      expect(scale2, 2.0);
      final canvasDelta2 = delta1 / scale2;
      expect(canvasDelta2, const Offset(5, 10));

      // Zoom Out: Scale 0.5 (canvas moves double units)
      final matrix3 = Matrix4.identity()..scale(0.5, 0.5);
      final scale3 = matrix3.getMaxScaleOnAxis().clamp(0.2, 5.0);
      expect(scale3, 0.5);
      final canvasDelta3 = delta1 / scale3;
      expect(canvasDelta3, const Offset(20, 40));

      // Extreme Scale Clamp Check (min 0.2, max 5.0)
      final matrixMin = Matrix4.identity()..scale(0.05, 0.05);
      expect(matrixMin.getMaxScaleOnAxis().clamp(0.2, 5.0), 0.2);

      final matrixMax = Matrix4.identity()..scale(10.0, 10.0);
      expect(matrixMax.getMaxScaleOnAxis().clamp(0.2, 5.0), 5.0);
    });

    test('Clamps node position within canvas boundary rules (dx: 20..1530, dy: 20..780)', () {
      const minX = 20.0;
      const maxX = 1800.0 - 270.0; // 1530.0
      const minY = 20.0;
      const maxY = 900.0 - 120.0;  // 780.0

      expect(maxX, 1530.0);
      expect(maxY, 780.0);

      // In-bounds position
      final pos1 = Offset(
        (500.0).clamp(minX, maxX),
        (300.0).clamp(minY, maxY),
      );
      expect(pos1, const Offset(500.0, 300.0));

      // Upper-left out-of-bounds (negative coordinates)
      final pos2 = Offset(
        (-150.0).clamp(minX, maxX),
        (-80.0).clamp(minY, maxY),
      );
      expect(pos2, const Offset(20.0, 20.0));

      // Bottom-right out-of-bounds
      final pos3 = Offset(
        (2500.0).clamp(minX, maxX),
        (1200.0).clamp(minY, maxY),
      );
      expect(pos3, const Offset(1530.0, 780.0));
    });

    testWidgets('Dragging RouteNodeCard in AppStudioScreen updates node position in studioProvider',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'node_drag_update_proj',
        name: 'Node Drag Update Test',
        orgId: 'com.test.dragupdate',
        path: 'C:/test/path',
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 3,
      );

      final container = ProviderContainer();
      final initialNode = container.read(studioProvider).nodes.first;
      final initialPos = initialNode.position;

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

      final cardFinder = find.widgetWithText(RouteNodeCard, initialNode.title);
      final center = tester.getCenter(cardFinder);

      final gesture = await tester.startGesture(center);
      // First move to exceed touch slop and enter drag mode
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();

      // Subsequent move for actual drag displacement
      await gesture.moveBy(const Offset(50, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final updatedNode = container
          .read(studioProvider)
          .nodes
          .firstWhere((n) => n.id == initialNode.id);

      expect(updatedNode.position.dx, closeTo(initialPos.dx + 50, 0.5));
      expect(updatedNode.position.dy, closeTo(initialPos.dy + 30, 0.5));
    });

    testWidgets('Dragging node beyond canvas boundaries is clamped to min and max limits',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'node_clamp_test_proj',
        name: 'Node Clamp Test',
        orgId: 'com.test.clamp',
        path: 'C:/test/path',
        preset: PresetType.cleanLite,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 3,
      );

      final container = ProviderContainer();
      final initialNode = container.read(studioProvider).nodes.first;

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

      final cardFinder = find.widgetWithText(RouteNodeCard, initialNode.title);
      final center = tester.getCenter(cardFinder);

      // Drag far beyond bottom-right limits first (from visible initial position)
      final gestureBottomRight = await tester.startGesture(center);
      await gestureBottomRight.moveBy(const Offset(30, 30)); // exceed slop
      await tester.pump();
      await gestureBottomRight.moveBy(const Offset(3000, 3000));
      await tester.pump();
      await gestureBottomRight.up();
      await tester.pump();

      var node = container
          .read(studioProvider)
          .nodes
          .firstWhere((n) => n.id == initialNode.id);
      expect(node.position.dx, 1530.0); // 1800 - 270
      expect(node.position.dy, 780.0);  // 900 - 120

      // Drag a second node (login node at 380, 80) beyond top-left limits
      final loginNode = container.read(studioProvider).nodes[1];
      final loginFinder = find.widgetWithText(RouteNodeCard, loginNode.title);
      final loginCenter = tester.getCenter(loginFinder);

      final gestureTopLeft = await tester.startGesture(loginCenter);
      await gestureTopLeft.moveBy(const Offset(-30, -30)); // exceed slop
      await tester.pump();
      await gestureTopLeft.moveBy(const Offset(-3000, -3000));
      await tester.pump();
      await gestureTopLeft.up();
      await tester.pump();

      final updatedLogin = container
          .read(studioProvider)
          .nodes
          .firstWhere((n) => n.id == loginNode.id);
      expect(updatedLogin.position.dx, 20.0);
      expect(updatedLogin.position.dy, 20.0);
    });

    testWidgets('Drag motion is compensated when canvas zoom level changes',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'node_zoom_test_proj',
        name: 'Node Zoom Test',
        orgId: 'com.test.zoom',
        path: 'C:/test/path',
        preset: PresetType.offline,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 3,
      );

      final container = ProviderContainer();
      final initialNode = container.read(studioProvider).nodes.first;

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

      // Click Zoom In button twice (each scales by 1.2 => 1.44x)
      final zoomInButton = find.byTooltip('Aumentar Zoom');
      expect(zoomInButton, findsOneWidget);
      await tester.tap(zoomInButton);
      await tester.pump();
      await tester.tap(zoomInButton);
      await tester.pump();

      final currentPos = container
          .read(studioProvider)
          .nodes
          .firstWhere((n) => n.id == initialNode.id)
          .position;

      final cardFinder = find.widgetWithText(RouteNodeCard, initialNode.title);
      final center = tester.getCenter(cardFinder);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(30, 30)); // exceed slop
      await tester.pump();

      // Move by 72 screen pixels (in scaled coordinates: 72 / 1.44 = 50, then compensated by scale 1.44: 50 / 1.44 = 34.72)
      await gesture.moveBy(const Offset(72, 72));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final zoomedNode = container
          .read(studioProvider)
          .nodes
          .firstWhere((n) => n.id == initialNode.id);

      expect(zoomedNode.position.dx, closeTo(currentPos.dx + (50.0 / 1.44), 0.5));
      expect(zoomedNode.position.dy, closeTo(currentPos.dy + (50.0 / 1.44), 0.5));
    });
  });
}
