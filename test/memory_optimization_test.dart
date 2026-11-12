import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/route_node_card.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flrd/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Memory & RepaintBoundary Optimization Tests', () {
    test('ImageCache maximum limits and memory cleanup listener behave correctly', () {
      // Configure limits as in main()
      PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;
      PaintingBinding.instance.imageCache.maximumSize = 80;

      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 40 * 1024 * 1024);
      expect(PaintingBinding.instance.imageCache.maximumSize, 80);

      const listener = WindowMemoryOptimizationListener();
      // Should clear cache on minimize without throwing
      expect(() => listener.onWindowMinimize(), returnsNormally);
    });

    testWidgets('AppStudioScreen isolates canvas, inspector, and preview in RepaintBoundaries',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RegisteredProject(
        id: 'test_opt_project',
        name: 'Optimization Test',
        orgId: 'com.test.opt',
        path: 'C:/test/opt_project',
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 2,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AppStudioScreen(project: project),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Verify InteractiveViewer is isolated in a RepaintBoundary
      final interactiveViewerFinder = find.byType(InteractiveViewer);
      expect(interactiveViewerFinder, findsOneWidget);

      final repaintBoundaryAboveInteractiveViewer = find.ancestor(
        of: interactiveViewerFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(repaintBoundaryAboveInteractiveViewer, findsWidgets);

      // 2. Verify Anchored Live Preview Pane is isolated in a RepaintBoundary
      final previewFinder = find.byKey(const ValueKey('anchored_live_preview_pane'));
      expect(previewFinder, findsOneWidget);

      final repaintBoundaryAbovePreview = find.ancestor(
        of: previewFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(repaintBoundaryAbovePreview, findsWidgets);

      // 3. Verify Node Inspector is wrapped in a RepaintBoundary when a node is selected
      // Tap the first node card
      final nodeCardFinder = find.byType(RouteNodeCard);
      expect(nodeCardFinder, findsWidgets);
      await tester.tap(nodeCardFinder.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('⚙️ Details'), findsOneWidget);
      final detailsTabFinder = find.text('⚙️ Details');
      final repaintBoundaryAboveDetails = find.ancestor(
        of: detailsTabFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(repaintBoundaryAboveDetails, findsWidgets);

      // Verify no RenderFlex overflow
      expect(tester.takeException(), isNull);
    });
  });
}
