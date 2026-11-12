import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/widgets/device_screen_emulator.dart';

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
    id: 'analytics_node',
    path: '/analytics/realtime',
    title: 'Realtime Analytics',
    subtitle: 'Realtime traffic & conversion metrics',
    icon: Icons.query_stats_rounded,
    position: Offset.zero,
    filePath: 'lib/features/analytics/realtime_screen.dart',
  );

  const sampleDartCode = '''
import 'package:flutter/material.dart';

class RealtimeScreen extends StatelessWidget {
  const RealtimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Live Analytics Monitor'),
        backgroundColor: Color(0xFF1E293B),
      ),
      body: Center(
        child: Text('4,281 Active Sessions Now'),
      ),
    );
  }
}
''';

  group('DeviceScreenEmulator - Pure Reality Engine Tests', () {
    testWidgets(
        'Renders dynamic code directly when sourceCode is provided and never shows fake archetype mocks',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: sampleRouteNode,
            sourceCode: sampleDartCode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Renders parsed live code elements
      expect(find.text('Live Analytics Monitor'), findsOneWidget);
      expect(find.text('4,281 Active Sessions Now'), findsOneWidget);

      // Archetype toggle pill is completely eliminated
      expect(find.text('⚡ Code Live Sync'), findsNothing);
      expect(find.text('🎨 Archetype Mock'), findsNothing);

      // No fake archetype data
      expect(find.text('Alex Morgan'), findsNothing);
      expect(find.text('FLRD PRO TIER'), findsNothing);
      expect(find.text('Welcome back, Alex 👋'), findsNothing);
    });

    testWidgets(
        'Renders sleek dynamic real route fallback when sourceCode is null or empty',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: sampleRouteNode,
            sourceCode: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Displays real route metadata
      expect(find.text('Realtime Analytics'), findsWidgets);
      expect(find.text('/analytics/realtime'), findsWidgets);
      expect(find.text('LIVE READY'), findsOneWidget);
      expect(find.text('Pure Reality Live Sync'), findsOneWidget);
      expect(find.byIcon(Icons.query_stats_rounded), findsWidgets);

      // No fake archetype data
      expect(find.text('Alex Morgan'), findsNothing);
      expect(find.text('FLRD PRO TIER'), findsNothing);
      expect(find.text('Welcome back, Alex 👋'), findsNothing);
    });
  });

  group('DeviceScreenEmulator - Screenshot / Print Capability', () {
    testWidgets(
        'Toolbar contains [📸 Screenshot] button with screenshot_button key',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: sampleRouteNode,
            sourceCode: sampleDartCode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final screenshotBtn = find.byKey(const Key('screenshot_button'));
      expect(screenshotBtn, findsOneWidget);
      expect(find.text('📸 Screenshot'), findsOneWidget);
    });

    testWidgets(
        'Tapping [📸 Screenshot] triggers high-resolution image capture and saves PNG to screenshots directory',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: sampleRouteNode,
            sourceCode: sampleDartCode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final screenshotBtn = find.byKey(const Key('screenshot_button'));
      await tester.tap(screenshotBtn);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should display toast with screenshots/...
      expect(find.textContaining('📸 Screenshot salvo em: screenshots/'), findsOneWidget);

      // Verify screenshot file was generated on disk
      final screenshotsDir = Directory('${Directory.current.path}/screenshots');
      expect(screenshotsDir.existsSync(), isTrue);
      final files = screenshotsDir.listSync().whereType<File>().where((f) => f.path.contains('analytics_realtime')).toList();
      expect(files.isNotEmpty, isTrue);

      // Clean up test file
      for (final f in files) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    });

    testWidgets(
        'DeviceScreenEmulator.showModal displays modal header with [📸 Screenshot] button and close button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  DeviceScreenEmulator.showModal(
                    context,
                    node: sampleRouteNode,
                    sourceCode: sampleDartCode,
                  );
                },
                child: const Text('Open Modal'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Verify modal screenshot button exists
      final modalScreenshotBtn = find.byKey(const Key('modal_screenshot_button'));
      expect(modalScreenshotBtn, findsOneWidget);

      // Tap modal screenshot button
      await tester.tap(modalScreenshotBtn);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('📸 Screenshot salvo em: screenshots/'), findsOneWidget);

      // Clean up generated files
      final screenshotsDir = Directory('${Directory.current.path}/screenshots');
      if (screenshotsDir.existsSync()) {
        final files = screenshotsDir.listSync().whereType<File>().where((f) => f.path.contains('analytics_realtime')).toList();
        for (final f in files) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }

      // Close modal
      final closeBtn = find.byTooltip('Close Modal');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });
  });
}
