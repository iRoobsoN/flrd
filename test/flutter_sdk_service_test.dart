import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/core/services/flutter_sdk_service.dart';
import 'package:flrd/core/widgets/flutter_sdk_dialog.dart';
import 'package:flrd/core/window/custom_titlebar.dart';
import 'package:flrd/features/hub/presentation/hub_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterSdkStatus Unit Tests', () {
    test('initial factory sets isChecking true and isInstalled false', () {
      final status = FlutterSdkStatus.initial();
      expect(status.isChecking, isTrue);
      expect(status.isInstalled, isFalse);
      expect(status.version, isNull);
      expect(status.sdkPath, isNull);
    });

    test('detected factory sets isInstalled true, version, and sdkPath', () {
      final status = FlutterSdkStatus.detected(
        version: 'v3.24.5',
        sdkPath: 'C:\\src\\flutter\\bin\\flutter.bat',
      );
      expect(status.isChecking, isFalse);
      expect(status.isInstalled, isTrue);
      expect(status.version, equals('v3.24.5'));
      expect(status.sdkPath, equals('C:\\src\\flutter\\bin\\flutter.bat'));
    });

    test('missing factory sets isInstalled false and error message', () {
      final status = FlutterSdkStatus.missing(error: 'Not found in PATH');
      expect(status.isChecking, isFalse);
      expect(status.isInstalled, isFalse);
      expect(status.error, equals('Not found in PATH'));
    });

    test('webSandbox factory sets isInstalled true and Web Sandbox version', () {
      final status = FlutterSdkStatus.webSandbox();
      expect(status.isChecking, isFalse);
      expect(status.isInstalled, isTrue);
      expect(status.version, equals('Web Sandbox'));
    });
  });

  group('FlutterSdkDialog Widget Tests', () {
    testWidgets('Renders detected status with version and path', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterSdkProvider.overrideWith(
              (ref) => _MockFlutterSdkNotifier(
                FlutterSdkStatus.detected(
                  version: 'v3.24.5',
                  sdkPath: 'C:\\src\\flutter\\bin\\flutter.bat',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FlutterSdkDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Flutter SDK Environment'), findsOneWidget);
      expect(find.text('Flutter v3.24.5'), findsOneWidget);
      expect(find.text('C:\\src\\flutter\\bin\\flutter.bat'), findsOneWidget);
      expect(find.text('Detected & Active'), findsOneWidget);
      expect(find.text('Re-check System'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Renders missing status with 3-step guide and download button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterSdkProvider.overrideWith(
              (ref) => _MockFlutterSdkNotifier(
                FlutterSdkStatus.missing(error: 'Not found'),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FlutterSdkDialog(requiredForGeneration: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Flutter SDK Environment'), findsOneWidget);
      expect(find.text('Flutter SDK was not found in your system PATH.'), findsOneWidget);
      expect(find.text('Why is the Flutter SDK required?'), findsOneWidget);
      expect(find.text('3-Step Quick Setup Guide:'), findsOneWidget);
      expect(find.text('Download Flutter SDK (Official)'), findsOneWidget);
      expect(find.text('Re-check System'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });

  group('CustomTitleBar Status Pill Integration Tests', () {
    testWidgets('Displays Flutter version in status pill and opens dialog on click', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterSdkProvider.overrideWith(
              (ref) => _MockFlutterSdkNotifier(
                FlutterSdkStatus.detected(
                  version: 'v3.24.5',
                  sdkPath: 'C:\\src\\flutter\\bin\\flutter.bat',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CustomTitleBar(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify status pill text
      expect(find.text('Flutter v3.24.5'), findsOneWidget);

      // Tap on the status pill
      await tester.tap(find.text('Flutter v3.24.5'));
      await tester.pumpAndSettle();

      // Verify dialog opened
      expect(find.byType(FlutterSdkDialog), findsOneWidget);
      expect(find.text('C:\\src\\flutter\\bin\\flutter.bat'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(FlutterSdkDialog), findsNothing);
    });

    testWidgets('Displays Flutter Missing warning when SDK not installed and opens guide on click',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterSdkProvider.overrideWith(
              (ref) => _MockFlutterSdkNotifier(
                FlutterSdkStatus.missing(error: 'Missing'),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CustomTitleBar(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify status pill warning text
      expect(find.text('Flutter Missing'), findsOneWidget);

      // Tap on the status pill
      await tester.tap(find.text('Flutter Missing'));
      await tester.pumpAndSettle();

      // Verify guide dialog opened
      expect(find.byType(FlutterSdkDialog), findsOneWidget);
      expect(find.text('Download Flutter SDK (Official)'), findsOneWidget);
    });
  });

  group('HubScreen Missing SDK Banner Integration Tests', () {
    testWidgets('Renders missing SDK banner on Hub when Flutter is not installed', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterSdkProvider.overrideWith(
              (ref) => _MockFlutterSdkNotifier(
                FlutterSdkStatus.missing(error: 'Not found in PATH'),
              ),
            ),
          ],
          child: const MaterialApp(
            home: HubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Banner title and CTA are visible
      expect(find.text('Flutter SDK not found on system'), findsOneWidget);
      expect(find.text('Setup Flutter SDK'), findsOneWidget);

      // Tap on CTA button opens FlutterSdkDialog
      await tester.tap(find.text('Setup Flutter SDK'));
      await tester.pumpAndSettle();

      expect(find.byType(FlutterSdkDialog), findsOneWidget);
      expect(find.text('3-Step Quick Setup Guide:'), findsOneWidget);
    });

    testWidgets('Dismiss button closes the missing SDK banner', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterSdkProvider.overrideWith(
              (ref) => _MockFlutterSdkNotifier(
                FlutterSdkStatus.missing(error: 'Not found in PATH'),
              ),
            ),
          ],
          child: const MaterialApp(
            home: HubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Flutter SDK not found on system'), findsOneWidget);

      // Tap dismiss icon
      await tester.tap(find.byTooltip('Dismiss / Fechar'));
      await tester.pumpAndSettle();

      expect(find.text('Flutter SDK not found on system'), findsNothing);
    });

    testWidgets('Does not render banner when Flutter is detected', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterSdkProvider.overrideWith(
              (ref) => _MockFlutterSdkNotifier(
                FlutterSdkStatus.detected(
                  version: 'v3.24.5',
                  sdkPath: 'C:\\flutter\\bin\\flutter.bat',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: HubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Flutter SDK not found on system'), findsNothing);
    });
  });
}

class _MockFlutterSdkNotifier extends StateNotifier<FlutterSdkStatus>
    implements FlutterSdkNotifier {
  _MockFlutterSdkNotifier(super.state);

  @override
  Future<void> checkSdk() async {}
}
