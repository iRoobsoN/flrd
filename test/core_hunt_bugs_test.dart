import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/core/localization/app_strings.dart';
import 'package:flrd/core/localization/language_provider.dart';
import 'package:flrd/core/services/flutter_doctor_service.dart';
import 'package:flrd/core/services/flutter_sdk_service.dart';
import 'package:flrd/core/widgets/donate_dialog.dart';
import 'package:flrd/core/widgets/flutter_doctor_dialog.dart';
import 'package:flrd/core/widgets/flutter_sdk_dialog.dart';
import 'package:flrd/core/window/custom_titlebar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Core Bug Hunt: FlutterSdkService & Doctor Resilience', () {
    test('FlutterSdkNotifier checkSdk safely handles locator failure with direct flutter fallback', () async {
      final notifier = FlutterSdkNotifier();
      addTearDown(notifier.dispose);

      // Should complete without unhandled exception regardless of local environment
      await notifier.checkSdk();
      expect(notifier.state, isA<FlutterSdkStatus>());
    });

    test('FlutterDoctorService handles unmounted disposal cleanly without StateError', () async {
      final service = FlutterDoctorService(
        autoScan: false,
        processRunner: (cmd, args, {runInShell = true}) async =>
            ProcessResult(0, 0, '[√] Flutter (Ready)', ''),
      );
      service.dispose();

      // Running doctor after dispose should not throw StateError due to if (mounted) checks
      final report = await service.runDoctor();
      expect(report, isA<DoctorReport>());
    });

    test('LanguageNotifier ignores state changes when unmounted', () {
      final notifier = LanguageNotifier();
      notifier.dispose();

      expect(() => notifier.setLanguage(AppLanguage.pt), returnsNormally);
    });
  });

  group('Core Bug Hunt: Layout Overflows & Dialog Sizing', () {
    testWidgets('FlutterSdkDialog does not overflow in constrained vertical viewport (400px height)', (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterSdkProvider.overrideWith(
              (ref) => _MockSdkNotifier(
                FlutterSdkStatus.missing(error: 'Missing SDK test'),
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

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterSdkDialog), findsOneWidget);
    });

    testWidgets('FlutterDoctorDialog header text does not overflow on narrow viewport (450px width)', (tester) async {
      tester.view.physicalSize = const Size(450, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const mixedReport = DoctorReport(
        isScanning: false,
        healthyCount: 5,
        totalCount: 7,
        items: [
          DoctorItem(
            id: 'android',
            title: 'Android Toolchain with very long description line',
            status: DoctorItemStatus.warning,
            details: 'Some licenses not accepted',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterDoctorProvider.overrideWith(
              (ref) => FlutterDoctorService(autoScan: false)..state = mixedReport,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FlutterDoctorDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterDoctorDialog), findsOneWidget);
    });

    testWidgets('CustomTitleBar handles long version strings without horizontal overflow', (tester) async {
      tester.view.physicalSize = const Size(600, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterSdkProvider.overrideWith(
              (ref) => _MockSdkNotifier(
                FlutterSdkStatus.detected(
                  version: 'v3.24.5-custom-build-candidate-channel-extended',
                  sdkPath: 'C:\\very\\long\\path\\to\\flutter\\bin\\flutter.bat',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CustomTitleBar(showBackButton: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomTitleBar), findsOneWidget);
    });

    testWidgets('DonateDialog does not overflow and handles copy safely', (tester) async {
      tester.view.physicalSize = const Size(600, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DonateDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Copiar Chave'), findsOneWidget);

      await tester.tap(find.text('Copiar Chave'));
      await tester.pumpAndSettle();
      final exc3 = tester.takeException();
      if (exc3 != null) {
        debugPrint('OVERFLOW EXCEPTION DETAILS: $exc3');
      }
      expect(exc3, isNull);
    });
  });
}

class _MockSdkNotifier extends StateNotifier<FlutterSdkStatus>
    implements FlutterSdkNotifier {
  _MockSdkNotifier(super.state);

  @override
  Future<void> checkSdk() async {}
}
