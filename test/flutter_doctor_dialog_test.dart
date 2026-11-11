import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/core/localization/app_strings.dart';
import 'package:flrd/core/localization/language_provider.dart';
import 'package:flrd/core/services/flutter_doctor_service.dart';
import 'package:flrd/core/widgets/flutter_doctor_dialog.dart';

class MockDoctorService extends StateNotifier<DoctorReport>
    implements FlutterDoctorService {
  MockDoctorService(super.state);

  bool rescanCalled = false;

  @override
  Future<DoctorReport> runDoctor() async {
    rescanCalled = true;
    return state;
  }
}

void main() {
  const sampleItems = [
    DoctorItem(
      id: 'flutter_engine',
      title: 'Flutter Engine (Channel stable, 3.24.5)',
      status: DoctorItemStatus.healthy,
      details: '• Flutter version 3.24.5 on Microsoft Windows 11\n• Up to date',
    ),
    DoctorItem(
      id: 'android_toolchain',
      title: 'Android Toolchain - develop for Android devices',
      status: DoctorItemStatus.warning,
      details: '! Some Android licenses not accepted.\nTo resolve: flutter doctor --android-licenses',
      solutionGuidance: 'Run the licenses agreement command and accept all terms with "y".',
      actionCommand: 'flutter doctor --android-licenses',
    ),
    DoctorItem(
      id: 'visual_studio',
      title: 'Visual Studio - develop Windows apps',
      status: DoctorItemStatus.missing,
      details: 'X Visual Studio not installed.\nRequires Desktop development with C++ workload.',
      solutionGuidance: 'Download Visual Studio Community 2022 and check Desktop development with C++.',
      actionCommand: 'winget install Microsoft.VisualStudio.2022.Community',
      actionUrl: 'https://visualstudio.microsoft.com/downloads/',
    ),
  ];

  const sampleReport = DoctorReport(
    isScanning: false,
    healthyCount: 1,
    totalCount: 3,
    items: sampleItems,
    rawOutput: '[√] Flutter (Channel stable, 3.24.5)\n[!] Android toolchain\n[X] Visual Studio',
  );

  Widget createTestWidget({
    DoctorReport report = sampleReport,
    MockDoctorService? mockService,
    AppLanguage language = AppLanguage.en,
    Key? key,
  }) {
    return ProviderScope(
      key: key,
      overrides: [
        appLanguageProvider.overrideWith((ref) => LanguageNotifier()..setLanguage(language)),
        flutterDoctorProvider.overrideWith(
          (ref) => mockService ?? MockDoctorService(report),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: FlutterDoctorDialog(),
        ),
      ),
    );
  }

  group('FlutterDoctorDialog Widget Tests', () {
    testWidgets('Renders header, health score bar, and status badges correctly in EN', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(language: AppLanguage.en));
      await tester.pumpAndSettle();

      // Header title
      expect(find.text('FLRD Doctor - System Diagnostics'), findsOneWidget);

      // Health Score text: 1/3 Components Ready - 33%
      expect(find.text('1/3 Components Ready - 33%'), findsOneWidget);

      // LinearProgressIndicator exists
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Status badges
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);

      // Item titles
      expect(find.text('Flutter Engine (Channel stable, 3.24.5)'), findsOneWidget);
      expect(find.text('Android Toolchain - develop for Android devices'), findsOneWidget);
      expect(find.text('Visual Studio - develop Windows apps'), findsOneWidget);
    });

    testWidgets('Renders PT strings gracefully when language is Portuguese', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(language: AppLanguage.pt));
      await tester.pumpAndSettle();

      // Header in PT
      expect(find.text('FLRD Doctor - Diagnóstico do Sistema'), findsOneWidget);
      expect(find.text('1/3 Componentes Prontos - 33%'), findsOneWidget);

      // Badges in PT
      expect(find.text('Pronto'), findsOneWidget);
      expect(find.text('Aviso'), findsOneWidget);
      expect(find.text('Faltando'), findsOneWidget);

      // Rescan button in PT
      expect(find.text('Re-escanear Agora'), findsOneWidget);
    });

    testWidgets('Auto-expands items with issues and toggles expansion on card header tap', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(language: AppLanguage.en));
      await tester.pumpAndSettle();

      // Since Android and Visual Studio have issues, their solution guidance is expanded
      expect(find.text('Recommended Solution'), findsNWidgets(2));
      expect(find.text('Run the licenses agreement command and accept all terms with "y".'), findsOneWidget);

      // Flutter is healthy, so its details are initially collapsed
      // Tap on Flutter Engine header to expand it
      await tester.tap(find.text('Flutter Engine (Channel stable, 3.24.5)'));
      await tester.pumpAndSettle();

      expect(find.text('• Flutter version 3.24.5 on Microsoft Windows 11\n• Up to date'), findsOneWidget);

      // Tap again to collapse it
      await tester.tap(find.text('Flutter Engine (Channel stable, 3.24.5)'));
      await tester.pumpAndSettle();

      // Details inside expanded block no longer visible as full block
      // (The preview line in header shows first line)
      expect(find.text('• Flutter version 3.24.5 on Microsoft Windows 11'), findsOneWidget);
    });

    testWidgets('Action buttons: Copy Command to clipboard and verify SnackBar feedback', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Intercept clipboard calls
      String? copiedClipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copiedClipboardText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(createTestWidget(language: AppLanguage.en));
      await tester.pumpAndSettle();

      // Find "Copy Command" buttons
      final copyButtons = find.text('Copy Command');
      expect(copyButtons, findsWidgets);

      await tester.ensureVisible(copyButtons.first);
      await tester.pumpAndSettle();

      // Tap the first Copy Command button (Android licenses)
      await tester.tap(copyButtons.first);
      await tester.pump();

      expect(copiedClipboardText, equals('flutter doctor --android-licenses'));
      expect(find.text('Command copied to clipboard!'), findsOneWidget);
    });

    testWidgets('Action buttons: Download / Docs URL button is present with correct label', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(language: AppLanguage.en));
      await tester.pumpAndSettle();

      expect(find.text('Download / Docs'), findsOneWidget);
    });

    testWidgets('Rescan button triggers runDoctor and displays loading state when isScanning', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockDoctorService(sampleReport);
      await tester.pumpWidget(
        createTestWidget(
          key: const ValueKey('idle-scope'),
          mockService: mockService,
          language: AppLanguage.en,
        ),
      );
      await tester.pumpAndSettle();

      expect(mockService.rescanCalled, isFalse);
      await tester.tap(find.text('Rescan Now'));
      await tester.pump();

      expect(mockService.rescanCalled, isTrue);

      // Test scanning state UI
      const scanningReport = DoctorReport(
        isScanning: true,
        healthyCount: 0,
        totalCount: 0,
        items: [],
      );

      await tester.pumpWidget(
        createTestWidget(
          key: const ValueKey('scanning-scope'),
          report: scanningReport,
          language: AppLanguage.en,
        ),
      );
      await tester.pump();

      expect(find.text('Scanning environment...'), findsWidgets);
      expect(find.text('flutter doctor -v'), findsOneWidget);
    });

    testWidgets('Filters work correctly: Needs Attention and Healthy Only', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(language: AppLanguage.en));
      await tester.pumpAndSettle();

      // Initially all 3 items visible
      expect(find.text('Flutter Engine (Channel stable, 3.24.5)'), findsOneWidget);
      expect(find.text('Android Toolchain - develop for Android devices'), findsOneWidget);
      expect(find.text('Visual Studio - develop Windows apps'), findsOneWidget);

      // Tap "Needs Attention (2)" filter
      await tester.tap(find.text('Needs Attention (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Flutter Engine (Channel stable, 3.24.5)'), findsNothing);
      expect(find.text('Android Toolchain - develop for Android devices'), findsOneWidget);
      expect(find.text('Visual Studio - develop Windows apps'), findsOneWidget);

      // Tap "Healthy (1)" filter
      await tester.tap(find.text('Healthy (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Flutter Engine (Channel stable, 3.24.5)'), findsOneWidget);
      expect(find.text('Android Toolchain - develop for Android devices'), findsNothing);
      expect(find.text('Visual Studio - develop Windows apps'), findsNothing);
    });

    testWidgets('Expand All and Collapse All buttons operate properly', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(language: AppLanguage.en));
      await tester.pumpAndSettle();

      // Tap "Expand All"
      await tester.tap(find.text('Expand All'));
      await tester.pumpAndSettle();

      expect(find.text('Collapse All'), findsOneWidget);

      // Tap "Collapse All"
      await tester.tap(find.text('Collapse All'));
      await tester.pumpAndSettle();

      expect(find.text('Expand All'), findsOneWidget);
      expect(find.text('Recommended Solution'), findsNothing);
    });

    testWidgets('Raw output collapsible section opens and displays terminal log', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(language: AppLanguage.en));
      await tester.pumpAndSettle();

      expect(find.text('flutter doctor Output'), findsOneWidget);
      expect(find.text('Copy Log'), findsNothing);

      // Tap to expand raw output
      await tester.tap(find.text('flutter doctor Output'));
      await tester.pumpAndSettle();

      expect(find.text('Copy Log'), findsOneWidget);
      expect(find.textContaining('[√] Flutter (Channel stable, 3.24.5)'), findsOneWidget);
    });

    testWidgets('Static FlutterDoctorDialog.show(context) helper displays dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterDoctorProvider.overrideWith((ref) => MockDoctorService(sampleReport)),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => FlutterDoctorDialog.show(ctx),
                  child: const Text('Open Doctor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlutterDoctorDialog), findsNothing);

      await tester.tap(find.text('Open Doctor'));
      await tester.pumpAndSettle();

      expect(find.byType(FlutterDoctorDialog), findsOneWidget);
    });
  });
}
