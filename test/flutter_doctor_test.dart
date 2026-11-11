import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/core/localization/app_strings.dart';
import 'package:flrd/core/localization/language_provider.dart';
import 'package:flrd/core/services/flutter_doctor_service.dart';
import 'package:flrd/core/widgets/flutter_doctor_dialog.dart';

/// Test mock implementation of [FlutterDoctorService] enabling controlled state
/// and spy recording for rescan actions.
class TestDoctorService extends StateNotifier<DoctorReport>
    implements FlutterDoctorService {
  TestDoctorService(super.state);

  int rescanCallCount = 0;

  @override
  Future<DoctorReport> runDoctor() async {
    rescanCallCount++;
    return state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // SAMPLE FIXTURES
  // ---------------------------------------------------------------------------
  const fullGreenOutput = '''
[√] Flutter (Channel stable, 3.24.5, on Microsoft Windows [Version 10.0.22631.4317], locale en-US) [250ms]
    • Flutter version 3.24.5 on channel stable at C:\\src\\flutter
    • Upstream repository https://github.com/flutter/flutter.git
    • Framework revision dec2ee5c1f (3 weeks ago), 2024-10-24 11:15:00 -0700
    • Engine revision 3a3621e638
    • Dart version 3.5.4
    • DevTools version 2.37.3

[✓] Windows Version (Installed version of Windows is version 10 or higher) [12ms]

[√] Android toolchain - develop for Android devices (Android SDK version 34.0.0) [520ms]
    • Android SDK at C:\\Users\\User\\AppData\\Local\\Android\\sdk
    • Platform android-34, build-tools 34.0.0
    • Java binary at: C:\\Program Files\\Android\\Android Studio\\jbr\\bin\\java
    • Java version OpenJDK 64-Bit Server VM (build 17.0.11)
    • All Android licenses accepted.

[√] Chrome - develop for the web [45ms]
    • Chrome at C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe

[√] Visual Studio - develop Windows apps (Visual Studio Community 2022 17.9.6) [110ms]
    • Visual Studio at C:\\Program Files\\Microsoft Visual Studio\\2022\\Community
    • Visual Studio Community 2022 version 17.9.34728.123
    • Windows 10 SDK version 10.0.22621.0

[√] Connected device (2 available) [80ms]
    • Windows (desktop) • windows • windows-x64    • Microsoft Windows [Version 10.0.22631.4317]
    • Chrome (web)      • chrome  • web-javascript • Google Chrome 129.0.6668.101

[√] Network resources [1.4s]
    • All expected network resources are available.

• No issues found!
''';

  const mixedIssuesOutput = '''
[✓] Flutter (Channel stable, 3.24.5, on Microsoft Windows) [180ms]
    • Flutter version 3.24.5 on channel stable at C:\\src\\flutter

[!] Android toolchain - develop for Android devices (Android SDK version 34.0.0)
    • Android SDK at C:\\Users\\User\\AppData\\Local\\Android\\sdk
    ! Some Android licenses not accepted. To resolve this, run: flutter doctor --android-licenses

[X] Visual Studio - develop Windows apps
    X Visual Studio not installed; this is necessary to develop Windows apps.
      Download at https://visualstudio.microsoft.com/downloads/
      Please install the "Desktop development with C++" workload.

[!] Connected device
    ! No devices available

! Doctor found issues in 3 categories.
''';

  const alternateSymbolsOutput = '''
[+] Flutter (Channel master)
    • Up to date
[-] Android Studio
    ! Android Studio not installed
[✗] Chrome - develop for the web
    X Chrome not found
[x] Linux toolchain - develop for Linux desktop
    X clang++ not found. Run sudo apt-get install clang
''';

  final healthyItem = const DoctorItem(
    id: 'flutter',
    title: 'Flutter Engine 3.24.5',
    status: DoctorItemStatus.healthy,
    details: '• Flutter version 3.24.5 on channel stable\n• Up to date',
  );

  final warningItem = const DoctorItem(
    id: 'android_toolchain',
    title: 'Android Toolchain',
    status: DoctorItemStatus.warning,
    details: '! Some Android licenses not accepted.\nRun: flutter doctor --android-licenses',
    solutionGuidance: 'Accept licenses by running the command.',
    actionCommand: 'flutter doctor --android-licenses',
    actionUrl: 'https://flutter.dev/to/windows-android-setup',
  );

  final missingItem = const DoctorItem(
    id: 'visual_studio',
    title: 'Visual Studio 2022',
    status: DoctorItemStatus.missing,
    details: 'X Visual Studio missing Desktop development with C++ workload.\n• Second detail line here',
    solutionGuidance: 'Install Visual Studio Community 2022 with C++ build tools.',
    actionCommand: 'winget install Microsoft.VisualStudio.2022.BuildTools',
    actionUrl: 'https://visualstudio.microsoft.com/downloads/',
  );

  Widget createDialogWrapper({
    required DoctorReport report,
    TestDoctorService? service,
    AppLanguage language = AppLanguage.en,
  }) {
    return ProviderScope(
      overrides: [
        appLanguageProvider.overrideWith(
          (ref) => LanguageNotifier()..setLanguage(language),
        ),
        flutterDoctorProvider.overrideWith(
          (ref) => service ?? TestDoctorService(report),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: FlutterDoctorDialog(),
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION 1: DOCTOR REPORT PARSING TESTS
  // ===========================================================================
  group('1. DoctorReport Parsing Tests', () {
    test('Parses full green output correctly without timing suffixes', () {
      final report = FlutterDoctorService.parseDoctorOutput(fullGreenOutput);

      expect(report.isScanning, isFalse);
      expect(report.totalCount, equals(7));
      expect(report.healthyCount, equals(7));
      expect(report.scorePercentage, equals(100));
      expect(report.healthScore, equals(1.0));
      expect(report.isAllHealthy, isTrue);
      expect(report.hasIssues, isFalse);
      expect(report.warningCount, equals(0));
      expect(report.missingCount, equals(0));

      // Check timing brackets are stripped from headers
      expect(report.items[0].id, equals('flutter'));
      expect(
        report.items[0].title,
        equals('Flutter (Channel stable, 3.24.5, on Microsoft Windows [Version 10.0.22631.4317], locale en-US)'),
      );
      expect(report.items[0].status, equals(DoctorItemStatus.healthy));

      expect(report.items[1].id, equals('windows_version'));
      expect(report.items[1].title, equals('Windows Version (Installed version of Windows is version 10 or higher)'));
      expect(report.items[1].status, equals(DoctorItemStatus.healthy));

      expect(report.items[2].id, equals('android_toolchain'));
      expect(report.items[3].id, equals('chrome'));
      expect(report.items[4].id, equals('visual_studio'));
      expect(report.items[5].id, equals('connected_device'));
      expect(report.items[6].id, equals('network_resources'));
    });

    test('Parses mixed issues output with warnings and missing categories', () {
      final report = FlutterDoctorService.parseDoctorOutput(mixedIssuesOutput);

      expect(report.totalCount, equals(4));
      expect(report.healthyCount, equals(1));
      expect(report.warningCount, equals(2));
      expect(report.missingCount, equals(1));
      expect(report.scorePercentage, equals(25));
      expect(report.healthScore, equals(0.25));
      expect(report.isAllHealthy, isFalse);
      expect(report.hasIssues, isTrue);

      // Verify item details and status
      final flutter = report.items[0];
      expect(flutter.status, equals(DoctorItemStatus.healthy));

      final android = report.items[1];
      expect(android.id, equals('android_toolchain'));
      expect(android.status, equals(DoctorItemStatus.warning));
      expect(android.actionCommand, equals('flutter doctor --android-licenses'));

      final vs = report.items[2];
      expect(vs.id, equals('visual_studio'));
      expect(vs.status, equals(DoctorItemStatus.missing));
      expect(vs.actionUrl, equals('https://visualstudio.microsoft.com/downloads/'));

      final device = report.items[3];
      expect(device.id, equals('connected_device'));
      expect(device.status, equals(DoctorItemStatus.warning));
    });

    test('Handles alternate status symbols ([+], [-], [✗], [x]) correctly', () {
      final report = FlutterDoctorService.parseDoctorOutput(alternateSymbolsOutput);

      expect(report.totalCount, equals(4));
      expect(report.items[0].status, equals(DoctorItemStatus.healthy)); // [+]
      expect(report.items[1].status, equals(DoctorItemStatus.warning)); // [-]
      expect(report.items[2].status, equals(DoctorItemStatus.missing)); // [✗]
      expect(report.items[3].status, equals(DoctorItemStatus.missing)); // [x]
    });

    test('DoctorReport.initial creates blank default report', () {
      final initial = DoctorReport.initial();
      expect(initial.isScanning, isFalse);
      expect(initial.healthyCount, equals(0));
      expect(initial.totalCount, equals(0));
      expect(initial.items, isEmpty);
      expect(initial.scorePercentage, equals(0));
      expect(initial.hasIssues, isFalse);
    });

    test('DoctorReport.scanning creates active scanning state', () {
      final scanning = DoctorReport.scanning();
      expect(scanning.isScanning, isTrue);
      expect(scanning.items, isEmpty);
    });

    test('DoctorReport.missingSdk provides actionable missing Flutter item', () {
      final missing = DoctorReport.missingSdk(error: 'Flutter binary not found in PATH');
      expect(missing.isScanning, isFalse);
      expect(missing.totalCount, equals(1));
      expect(missing.healthyCount, equals(0));
      expect(missing.hasIssues, isTrue);
      expect(missing.error, contains('Flutter binary not found'));

      final item = missing.items.first;
      expect(item.id, equals('flutter_sdk'));
      expect(item.status, equals(DoctorItemStatus.missing));
      expect(item.actionUrl, equals('https://docs.flutter.dev/get-started/install'));
      expect(item.solutionGuidance, isNotNull);
    });

    test('DoctorReport.webSandbox provides 2 healthy sandbox items', () {
      final sandbox = DoctorReport.webSandbox();
      expect(sandbox.healthyCount, equals(2));
      expect(sandbox.totalCount, equals(2));
      expect(sandbox.scorePercentage, equals(100));
      expect(sandbox.isAllHealthy, isTrue);
      expect(sandbox.items[0].id, equals('flutter_web'));
      expect(sandbox.items[1].id, equals('browser_engine'));
    });

    test('Returns DoctorReport.initial when parsing empty or whitespace string', () {
      final emptyReport = FlutterDoctorService.parseDoctorOutput('');
      expect(emptyReport.totalCount, equals(0));
      expect(emptyReport.items, isEmpty);

      final whitespaceReport = FlutterDoctorService.parseDoctorOutput('   \n  \t  \n');
      expect(whitespaceReport.totalCount, equals(0));
      expect(whitespaceReport.items, isEmpty);
    });
  });

  // ===========================================================================
  // SECTION 2: ITEM STATUS CATEGORIZATION & ACTION ENRICHMENT
  // ===========================================================================
  group('2. Item Status Categorization & Action Enrichment Tests', () {
    test('DoctorItem status booleans and hasAction getter', () {
      const healthy = DoctorItem(
        id: 'h',
        title: 'H',
        status: DoctorItemStatus.healthy,
        details: 'ok',
      );
      expect(healthy.isHealthy, isTrue);
      expect(healthy.isWarning, isFalse);
      expect(healthy.isMissing, isFalse);
      expect(healthy.hasAction, isFalse);

      const actionCmd = DoctorItem(
        id: 'w',
        title: 'W',
        status: DoctorItemStatus.warning,
        details: 'warn',
        actionCommand: 'flutter doctor --android-licenses',
      );
      expect(actionCmd.isWarning, isTrue);
      expect(actionCmd.hasAction, isTrue);

      const actionUrl = DoctorItem(
        id: 'm',
        title: 'M',
        status: DoctorItemStatus.missing,
        details: 'missing',
        actionUrl: 'https://example.com',
      );
      expect(missingItem.isMissing, isTrue);
      expect(actionUrl.hasAction, isTrue);
    });

    test('Enriches Android licenses issue with command and URL', () {
      const item = DoctorItem(
        id: 'android_toolchain',
        title: 'Android toolchain - develop for Android devices',
        status: DoctorItemStatus.warning,
        details: '! Some Android licenses not accepted. Run `flutter doctor --android-licenses`',
      );
      final enriched = FlutterDoctorService.enrichDoctorItem(item);
      expect(enriched.actionCommand, equals('flutter doctor --android-licenses'));
      expect(enriched.actionUrl, isNotNull);
      expect(enriched.solutionGuidance, contains('Android SDK platform licenses'));
    });

    test('Enriches Android Studio missing with download URL', () {
      const item = DoctorItem(
        id: 'android_studio',
        title: 'Android Studio',
        status: DoctorItemStatus.missing,
        details: 'X Android Studio not installed',
      );
      final enriched = FlutterDoctorService.enrichDoctorItem(item);
      expect(enriched.actionUrl, equals('https://developer.android.com/studio'));
      expect(enriched.solutionGuidance, contains('Install Android Studio'));
    });

    test('Enriches cmdline-tools missing with Studio SDK Manager guidance', () {
      const item = DoctorItem(
        id: 'android_toolchain',
        title: 'Android toolchain',
        status: DoctorItemStatus.warning,
        details: 'X cmdline-tools component is missing',
      );
      final enriched = FlutterDoctorService.enrichDoctorItem(item);
      expect(enriched.actionUrl, equals('https://developer.android.com/studio'));
      expect(enriched.solutionGuidance, contains('Command-line Tools'));
    });

    test('Enriches Visual Studio missing with download URL and build tools guidance', () {
      const item = DoctorItem(
        id: 'visual_studio',
        title: 'Visual Studio - develop Windows apps',
        status: DoctorItemStatus.missing,
        details: 'X Visual Studio not installed',
      );
      final enriched = FlutterDoctorService.enrichDoctorItem(item);
      expect(enriched.actionUrl, equals('https://visualstudio.microsoft.com/downloads/'));
      expect(enriched.solutionGuidance, contains('Desktop development with C++'));
    });

    test('Enriches Google Chrome missing with Chrome URL', () {
      const item = DoctorItem(
        id: 'chrome',
        title: 'Chrome - develop for the web',
        status: DoctorItemStatus.missing,
        details: 'X Cannot find Chrome. Download at https://google.com/chrome',
      );
      final enriched = FlutterDoctorService.enrichDoctorItem(item);
      expect(enriched.actionUrl, equals('https://www.google.com/chrome/'));
      expect(enriched.solutionGuidance, contains('Install Google Chrome'));
    });

    test('Enriches CocoaPods missing with gem install command and guide URL', () {
      const item = DoctorItem(
        id: 'cocoapods',
        title: 'CocoaPods',
        status: DoctorItemStatus.missing,
        details: 'X CocoaPods not installed.',
      );
      final enriched = FlutterDoctorService.enrichDoctorItem(item);
      expect(enriched.actionCommand, equals('sudo gem install cocoapods'));
      expect(enriched.actionUrl, equals('https://guides.cocoapods.org/using/getting-started.html'));
    });

    test('Enriches Xcode missing with developer URL and xcode-select setup command', () {
      const item = DoctorItem(
        id: 'xcode',
        title: 'Xcode - develop for iOS and macOS',
        status: DoctorItemStatus.missing,
        details: 'X Xcode installation is incomplete',
      );
      final enriched = FlutterDoctorService.enrichDoctorItem(item);
      expect(enriched.actionUrl, equals('https://developer.apple.com/xcode/'));
      expect(enriched.actionCommand, contains('xcode-select'));
    });

    test('Enriches Linux toolchain with apt-get command and linux desktop URL', () {
      const item = DoctorItem(
        id: 'linux_toolchain',
        title: 'Linux toolchain',
        status: DoctorItemStatus.missing,
        details: 'X clang++ is required for Linux development',
      );
      final enriched = FlutterDoctorService.enrichDoctorItem(item);
      expect(enriched.actionCommand, contains('sudo apt-get install clang'));
      expect(enriched.actionUrl, contains('desktop'));
    });

    test('Dynamic fallback regex extracts embedded URLs and backtick commands', () {
      const item = DoctorItem(
        id: 'custom_service',
        title: 'Custom SDK Component',
        status: DoctorItemStatus.warning,
        details: 'Please visit https://flrd.dev/troubleshoot and run `flutter pub get` in terminal.',
      );
      final enriched = FlutterDoctorService.enrichDoctorItem(item);
      expect(enriched.actionUrl, equals('https://flrd.dev/troubleshoot'));
      expect(enriched.actionCommand, equals('flutter pub get'));
    });
  });

  // ===========================================================================
  // SECTION 3: FLUTTER DOCTOR DIALOG RENDERING TESTS
  // ===========================================================================
  group('3. FlutterDoctorDialog Rendering Tests', () {
    testWidgets('Renders header, health score fraction and progress bar in EN', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 1,
        totalCount: 3,
        items: [healthyItem, warningItem, missingItem],
        rawOutput: '[√] Flutter\n[!] Android\n[X] VS',
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.en));
      await tester.pumpAndSettle();

      // Title
      expect(find.text('FLRD Doctor - System Diagnostics'), findsOneWidget);
      // Health Score string: 1/3 Components Ready - 33%
      expect(find.text('1/3 Components Ready - 33%'), findsOneWidget);
      // Linear progress bar
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Status badges
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);
    });

    testWidgets('Renders properly in Portuguese (PT)', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 2,
        totalCount: 2,
        items: [healthyItem, healthyItem.copyWith(id: 'windows', title: 'Windows Version')],
        rawOutput: '[√] Flutter\n[√] Windows',
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.pt));
      await tester.pumpAndSettle();

      // Title in PT
      expect(find.text('FLRD Doctor - Diagnóstico do Sistema'), findsOneWidget);
      // 2/2 Componentes Prontos - 100%
      expect(find.text('2/2 Componentes Prontos - 100%'), findsOneWidget);
      // Badge in PT
      expect(find.text('Pronto'), findsNWidgets(2));
      // Rescan button in PT
      expect(find.text('Re-escanear Agora'), findsOneWidget);
    });

    testWidgets('Renders properly in Spanish (ES)', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 1,
        totalCount: 2,
        items: [healthyItem, missingItem],
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.es));
      await tester.pumpAndSettle();

      // Title in ES
      expect(find.text('FLRD Doctor - Diagnóstico del Sistema'), findsOneWidget);
      expect(find.text('1/2 Componentes Listos - 50%'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Faltante'), findsOneWidget);
    });

    testWidgets('Filtering items via segmented filter chips', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 1,
        totalCount: 3,
        items: [healthyItem, warningItem, missingItem],
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.en));
      await tester.pumpAndSettle();

      // Initially all 3 items are present
      expect(find.text('Flutter Engine 3.24.5'), findsOneWidget);
      expect(find.text('Android Toolchain'), findsOneWidget);
      expect(find.text('Visual Studio 2022'), findsOneWidget);

      // Filter by 'Needs Attention' (Issues)
      final issuesTab = find.text('Needs Attention (2)');
      expect(issuesTab, findsOneWidget);
      await tester.tap(issuesTab);
      await tester.pumpAndSettle();

      // Healthy item should be filtered out
      expect(find.text('Flutter Engine 3.24.5'), findsNothing);
      expect(find.text('Android Toolchain'), findsOneWidget);
      expect(find.text('Visual Studio 2022'), findsOneWidget);

      // Filter by 'Healthy'
      final readyTab = find.text('Healthy (1)');
      expect(readyTab, findsOneWidget);
      await tester.tap(readyTab);
      await tester.pumpAndSettle();

      expect(find.text('Flutter Engine 3.24.5'), findsOneWidget);
      expect(find.text('Android Toolchain'), findsNothing);
      expect(find.text('Visual Studio 2022'), findsNothing);

      // Filter back to 'All'
      final allTab = find.text('All (3)');
      expect(allTab, findsOneWidget);
      await tester.tap(allTab);
      await tester.pumpAndSettle();

      expect(find.text('Flutter Engine 3.24.5'), findsOneWidget);
      expect(find.text('Android Toolchain'), findsOneWidget);
      expect(find.text('Visual Studio 2022'), findsOneWidget);
    });

    testWidgets('Scanning state renders progress indicator on rescan button', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = const DoctorReport(
        isScanning: true,
        healthyCount: 0,
        totalCount: 0,
        items: [],
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.en));
      await tester.pump();

      // Scanning text and circular indicator
      expect(find.text('Scanning...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('Expand All and Collapse All buttons manipulate item expansion', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 2,
        totalCount: 2,
        items: [
          healthyItem,
          healthyItem.copyWith(
            id: 'windows',
            title: 'Windows Version',
            details: '• Windows 11 Build 22631\n• Secondary detail line',
          ),
        ],
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.en));
      await tester.pumpAndSettle();

      // Since all are healthy, initial state has only first item expanded
      final expandAllBtn = find.text('Expand All');
      expect(expandAllBtn, findsOneWidget);
      await tester.tap(expandAllBtn);
      await tester.pumpAndSettle();

      // After expand all, both items are expanded, button changes to Collapse All
      final collapseAllBtn = find.text('Collapse All');
      expect(collapseAllBtn, findsOneWidget);
      expect(find.text('Expand All'), findsNothing);

      // Tap Collapse All
      await tester.tap(collapseAllBtn);
      await tester.pumpAndSettle();

      expect(find.text('Expand All'), findsOneWidget);
      expect(find.text('Collapse All'), findsNothing);
    });

    testWidgets('Raw terminal output viewer can be toggled', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 1,
        totalCount: 1,
        items: [healthyItem],
        rawOutput: 'RAW_DOCTOR_TERMINAL_OUTPUT_TEST_LINE',
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.en));
      await tester.pumpAndSettle();

      expect(find.textContaining('RAW_DOCTOR_TERMINAL_OUTPUT_TEST_LINE'), findsNothing);

      // Toggle raw output using 'flutter doctor Output'
      final viewLogBtn = find.text('flutter doctor Output');
      expect(viewLogBtn, findsOneWidget);
      await tester.tap(viewLogBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('RAW_DOCTOR_TERMINAL_OUTPUT_TEST_LINE'), findsOneWidget);
      expect(find.text('Copy Log'), findsOneWidget);
    });
  });

  // ===========================================================================
  // SECTION 4: ACTIONS & INTERACTION TESTS
  // ===========================================================================
  group('4. FlutterDoctorDialog Actions & Interactivity Tests', () {
    testWidgets('Rescan button triggers runDoctor() on FlutterDoctorService', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = TestDoctorService(
        DoctorReport(
          isScanning: false,
          healthyCount: 1,
          totalCount: 1,
          items: [healthyItem],
        ),
      );

      await tester.pumpWidget(createDialogWrapper(
        report: service.state,
        service: service,
        language: AppLanguage.en,
      ));
      await tester.pumpAndSettle();

      expect(service.rescanCallCount, equals(0));

      // In EN, strings.doctorRescan is "Rescan Now"
      final rescanBtn = find.text('Rescan Now');
      expect(rescanBtn, findsOneWidget);
      await tester.tap(rescanBtn);
      await tester.pumpAndSettle();

      expect(service.rescanCallCount, equals(1));
    });

    testWidgets('Copy command button copies command to clipboard and shows SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? lastCopiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            lastCopiedText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          return null;
        },
      );

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 0,
        totalCount: 1,
        items: [warningItem],
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.en));
      await tester.pumpAndSettle();

      final copyCmdBtn = find.text('Copy Command');
      expect(copyCmdBtn, findsOneWidget);
      await tester.tap(copyCmdBtn);
      await tester.pump();

      // Verify copied command text
      expect(lastCopiedText, equals('flutter doctor --android-licenses'));

      // Verify SnackBar feedback
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Command copied to clipboard!'), findsOneWidget);
    });

    testWidgets('Copy raw log button copies output to clipboard and shows SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? lastCopiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            lastCopiedText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          return null;
        },
      );

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 1,
        totalCount: 1,
        items: [healthyItem],
        rawOutput: 'RAW_DIAGNOSTIC_LOG_CONTENT',
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.en));
      await tester.pumpAndSettle();

      // Open raw terminal viewer
      await tester.tap(find.text('flutter doctor Output'));
      await tester.pumpAndSettle();

      // Tap Copy Log
      final copyLogBtn = find.text('Copy Log');
      expect(copyLogBtn, findsOneWidget);
      await tester.tap(copyLogBtn);
      await tester.pump();

      expect(lastCopiedText, equals('RAW_DIAGNOSTIC_LOG_CONTENT'));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Terminal log copied!'), findsOneWidget);
    });

    testWidgets('Download / Docs action button renders and responds to tap', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 0,
        totalCount: 1,
        items: [missingItem],
      );

      await tester.pumpWidget(createDialogWrapper(report: report, language: AppLanguage.en));
      await tester.pumpAndSettle();

      final downloadBtn = find.text('Download / Docs');
      expect(downloadBtn, findsOneWidget);

      await tester.tap(downloadBtn);
      await tester.pump();
      // Verifies no exception thrown when tapping URL action
    });

    testWidgets('FlutterDoctorDialog.show static method displays modal dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 1,
        totalCount: 1,
        items: [healthyItem],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            flutterDoctorProvider.overrideWith(
              (ref) => TestDoctorService(report),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () => FlutterDoctorDialog.show(context),
                    child: const Text('Open FLRD Doctor'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlutterDoctorDialog), findsNothing);

      await tester.tap(find.text('Open FLRD Doctor'));
      await tester.pumpAndSettle();

      expect(find.byType(FlutterDoctorDialog), findsOneWidget);
      expect(find.text('FLRD Doctor - System Diagnostics'), findsOneWidget);

      // Close modal dialog
      final closeButton = find.byIcon(Icons.close_rounded);
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(find.byType(FlutterDoctorDialog), findsNothing);
    });
  });
}
