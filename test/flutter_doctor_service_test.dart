import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/core/services/flutter_doctor_service.dart';

void main() {
  group('DoctorItem and DoctorItemStatus Tests', () {
    test('status getters work correctly', () {
      const healthy = DoctorItem(
        id: 'flutter',
        title: 'Flutter',
        status: DoctorItemStatus.healthy,
        details: 'v3.24.5',
      );
      expect(healthy.isHealthy, isTrue);
      expect(healthy.isWarning, isFalse);
      expect(healthy.isMissing, isFalse);
      expect(healthy.hasAction, isFalse);

      const warning = DoctorItem(
        id: 'android',
        title: 'Android',
        status: DoctorItemStatus.warning,
        details: 'Licenses',
        actionCommand: 'flutter doctor --android-licenses',
      );
      expect(warning.isHealthy, isFalse);
      expect(warning.isWarning, isTrue);
      expect(warning.isMissing, isFalse);
      expect(warning.hasAction, isTrue);

      const missing = DoctorItem(
        id: 'vs',
        title: 'Visual Studio',
        status: DoctorItemStatus.missing,
        details: 'Not found',
        actionUrl: 'https://visualstudio.microsoft.com',
      );
      expect(missing.isHealthy, isFalse);
      expect(missing.isWarning, isFalse);
      expect(missing.isMissing, isTrue);
      expect(missing.hasAction, isTrue);
    });

    test('copyWith updates properties accurately', () {
      const item = DoctorItem(
        id: 'test',
        title: 'Original Title',
        status: DoctorItemStatus.healthy,
        details: 'Original details',
      );

      final updated = item.copyWith(
        title: 'New Title',
        status: DoctorItemStatus.warning,
        solutionGuidance: 'Check configs',
      );

      expect(updated.id, equals('test'));
      expect(updated.title, equals('New Title'));
      expect(updated.status, equals(DoctorItemStatus.warning));
      expect(updated.solutionGuidance, equals('Check configs'));
      expect(updated.details, equals('Original details'));
    });
  });

  group('DoctorReport Model Tests', () {
    test('initial factory sets isScanning false and empty items', () {
      final report = DoctorReport.initial();
      expect(report.isScanning, isFalse);
      expect(report.healthyCount, equals(0));
      expect(report.totalCount, equals(0));
      expect(report.items, isEmpty);
      expect(report.scorePercentage, equals(0));
      expect(report.healthScore, equals(0.0));
      expect(report.hasIssues, isFalse);
      expect(report.isAllHealthy, isFalse);
    });

    test('missingSdk factory provides actionable Flutter SDK pre-flight item', () {
      final report = DoctorReport.missingSdk(error: 'Path not configured');
      expect(report.isScanning, isFalse);
      expect(report.healthyCount, equals(0));
      expect(report.totalCount, equals(1));
      expect(report.items.length, equals(1));
      expect(report.hasIssues, isTrue);
      expect(report.missingCount, equals(1));

      final sdkItem = report.items.first;
      expect(sdkItem.id, equals('flutter_sdk'));
      expect(sdkItem.status, equals(DoctorItemStatus.missing));
      expect(sdkItem.actionUrl, equals('https://docs.flutter.dev/get-started/install'));
      expect(sdkItem.solutionGuidance, isNotNull);
    });

    test('webSandbox factory sets 2 healthy items', () {
      final report = DoctorReport.webSandbox();
      expect(report.healthyCount, equals(2));
      expect(report.totalCount, equals(2));
      expect(report.scorePercentage, equals(100));
      expect(report.healthScore, equals(1.0));
      expect(report.isAllHealthy, isTrue);
      expect(report.hasIssues, isFalse);
    });

    test('health score and counts calculate correctly for mixed reports', () {
      const items = [
        DoctorItem(id: '1', title: 'A', status: DoctorItemStatus.healthy, details: ''),
        DoctorItem(id: '2', title: 'B', status: DoctorItemStatus.healthy, details: ''),
        DoctorItem(id: '3', title: 'C', status: DoctorItemStatus.warning, details: ''),
        DoctorItem(id: '4', title: 'D', status: DoctorItemStatus.missing, details: ''),
      ];

      final report = DoctorReport(
        isScanning: false,
        healthyCount: 2,
        totalCount: 4,
        items: items,
      );

      expect(report.healthyCount, equals(2));
      expect(report.totalCount, equals(4));
      expect(report.scorePercentage, equals(50));
      expect(report.healthScore, equals(0.5));
      expect(report.warningCount, equals(1));
      expect(report.missingCount, equals(1));
      expect(report.hasIssues, isTrue);
      expect(report.isAllHealthy, isFalse);
    });
  });

  group('FlutterDoctorService Parsing & Enrichment Tests', () {
    test('parses empty string cleanly into initial report', () {
      final report = FlutterDoctorService.parseDoctorOutput('');
      expect(report.items, isEmpty);
      expect(report.totalCount, equals(0));
    });

    test('parses complete flutter doctor -v output with timing metrics and footer', () {
      const sampleDoctorOutput = '''
[√] Flutter (Channel stable, 3.47.9, on Microsoft Windows [versÆo 10.0.26200.9974], locale pt-BR) [477ms]
    • Flutter version 3.47.9 on channel stable at C:\\src\\flutter
    • Upstream repository https://github.com/flutter/flutter.git
    • Framework revision c197ca5199 (13 days ago), 2026-10-29 10:10:20 -0400
    • Engine revision 89c39edfdf
    • Dart version 3.13.7
    • DevTools version 2.60.0

[√] Windows Version (Windows 11 or higher, 25H2, 2009) [1.925ms]

[X] Android toolchain - develop for Android devices [192ms]
    X Unable to locate Android SDK.
      Install Android Studio from: https://developer.android.com/studio/index.html
      On first launch it will assist you in installing the Android SDK components.
      (or visit https://flutter.dev/to/windows-android-setup for detailed instructions).
      If the Android SDK has been installed to a custom location, please use
      `flutter config --android-sdk` to update to that location.

[√] Chrome - develop for the web [168ms]
    • Chrome at C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe

[√] Visual Studio - develop Windows apps (Ferramentas de Build do Visual Studio 2022 17.14.44) [166ms]
    • Visual Studio at C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools

[√] Connected device (3 available) [150ms]
    • Windows (desktop) • windows • windows-x64    • Microsoft Windows [versÆo 10.0.26200.9974]
    • Chrome (web)      • chrome  • web-javascript • Google Chrome 157.0.8103.39

[√] Network resources [705ms]
    • All expected network resources are available.

! Doctor found issues in 1 category.
''';

      final report = FlutterDoctorService.parseDoctorOutput(sampleDoctorOutput);

      expect(report.totalCount, equals(7));
      expect(report.healthyCount, equals(6));
      expect(report.scorePercentage, equals(86));
      expect(report.hasIssues, isTrue);

      // 1. Flutter item
      final flutterItem = report.items[0];
      expect(flutterItem.id, equals('flutter'));
      expect(flutterItem.status, equals(DoctorItemStatus.healthy));
      expect(flutterItem.title, contains('Flutter (Channel stable'));
      // Verifies timing suffix was stripped
      expect(flutterItem.title.endsWith('[477ms]'), isFalse);
      expect(flutterItem.details, contains('Flutter version 3.47.9'));

      // 2. Windows Version item
      final winItem = report.items[1];
      expect(winItem.id, equals('windows_version'));
      expect(winItem.status, equals(DoctorItemStatus.healthy));
      expect(winItem.title, equals('Windows Version (Windows 11 or higher, 25H2, 2009)'));

      // 3. Android toolchain (Missing)
      final androidItem = report.items[2];
      expect(androidItem.id, equals('android_toolchain'));
      expect(androidItem.status, equals(DoctorItemStatus.missing));
      expect(androidItem.title, equals('Android toolchain - develop for Android devices'));
      expect(androidItem.actionUrl, equals('https://developer.android.com/studio'));
      expect(androidItem.actionCommand, equals('flutter config --android-sdk'));
      expect(androidItem.solutionGuidance, contains('Install Android Studio'));

      // 4. Chrome
      final chromeItem = report.items[3];
      expect(chromeItem.id, equals('chrome'));
      expect(chromeItem.status, equals(DoctorItemStatus.healthy));

      // 5. Visual Studio
      final vsItem = report.items[4];
      expect(vsItem.id, equals('visual_studio'));
      expect(vsItem.status, equals(DoctorItemStatus.healthy));

      // 6. Connected Device
      final devItem = report.items[5];
      expect(devItem.id, equals('connected_device'));
      expect(devItem.status, equals(DoctorItemStatus.healthy));

      // 7. Network
      final netItem = report.items[6];
      expect(netItem.id, equals('network_resources'));
      expect(netItem.status, equals(DoctorItemStatus.healthy));
    });

    test('enriches Android licenses warning with flutter doctor --android-licenses', () {
      const output = '''
[!] Android toolchain - develop for Android devices (Android SDK version 34.0.0)
    ! Some Android licenses not accepted. To resolve this, run:
      flutter doctor --android-licenses
''';

      final report = FlutterDoctorService.parseDoctorOutput(output);
      expect(report.items.length, equals(1));
      final item = report.items.first;

      expect(item.status, equals(DoctorItemStatus.warning));
      expect(item.actionCommand, equals('flutter doctor --android-licenses'));
      expect(item.solutionGuidance, contains('Accept the Android SDK platform licenses'));
      expect(item.actionUrl, isNotNull);
    });

    test('enriches missing Visual Studio with C++ workload guidance and downloads URL', () {
      const output = '''
[X] Visual Studio - develop Windows apps
    X Visual Studio not installed; this is necessary to develop Windows to build desktop applications.
      Download at https://visualstudio.microsoft.com/downloads/
''';

      final report = FlutterDoctorService.parseDoctorOutput(output);
      expect(report.items.length, equals(1));
      final item = report.items.first;

      expect(item.status, equals(DoctorItemStatus.missing));
      expect(item.actionUrl, equals('https://visualstudio.microsoft.com/downloads/'));
      expect(item.solutionGuidance, contains('Desktop development with C++'));
    });

    test('enriches missing Chrome with Chrome download URL', () {
      const output = '''
[X] Chrome - develop for the web
    X Cannot find Chrome.
''';

      final report = FlutterDoctorService.parseDoctorOutput(output);
      expect(report.items.length, equals(1));
      final item = report.items.first;

      expect(item.status, equals(DoctorItemStatus.missing));
      expect(item.actionUrl, equals('https://www.google.com/chrome/'));
      expect(item.solutionGuidance, contains('Install Google Chrome'));
    });

    test('enriches Xcode and CocoaPods warnings with fix commands', () {
      const output = '''
[!] Xcode - develop for iOS and macOS
    • CocoaPods not installed.
        CocoaPods is used to retrieve the iOS and macOS platform plugin code.
        See https://flutter.dev/to/macos-setup for installation instructions.
''';

      final report = FlutterDoctorService.parseDoctorOutput(output);
      expect(report.items.length, equals(1));
      final item = report.items.first;

      expect(item.status, equals(DoctorItemStatus.warning));
      expect(item.actionCommand, equals('sudo gem install cocoapods'));
      expect(item.actionUrl, contains('cocoapods.org'));
      expect(item.solutionGuidance, contains('Install CocoaPods'));
    });
  });

  group('FlutterDoctorService StateNotifier & Provider Tests', () {
    test('runDoctor with mocked runner parses doctor output and updates state', () async {
      const mockStdout = '''
[√] Flutter (Channel stable, 3.24.5)
[√] Windows Version (Installed)
[!] Android toolchain - develop for Android devices
    ! Some Android licenses not accepted. Run `flutter doctor --android-licenses`
• No issues found!
''';

      final service = FlutterDoctorService(
        autoScan: false,
        processRunner: (executable, arguments, {runInShell = true}) async {
          if (executable == 'where.exe' || executable == 'which') {
            return ProcessResult(1, 0, 'C:\\flutter\\bin\\flutter.bat', '');
          }
          if (executable == 'flutter') {
            return ProcessResult(2, 0, mockStdout, '');
          }
          return ProcessResult(3, 0, '', '');
        },
      );

      expect(service.state.isScanning, isFalse);
      expect(service.state.items, isEmpty);

      final report = await service.runDoctor();

      expect(report.isScanning, isFalse);
      expect(report.totalCount, equals(3));
      expect(report.healthyCount, equals(2));
      expect(report.hasIssues, isTrue);
      expect(service.state, equals(report));
    });

    test('runDoctor catches missing Flutter executable and returns missingSdk report', () async {
      final service = FlutterDoctorService(
        autoScan: false,
        processRunner: (executable, arguments, {runInShell = true}) async {
          if (executable == 'where.exe' || executable == 'which') {
            return ProcessResult(1, 1, '', 'not found');
          }
          return ProcessResult(2, 1, '', 'command not found');
        },
      );

      final report = await service.runDoctor();

      expect(report.isScanning, isFalse);
      expect(report.totalCount, equals(1));
      expect(report.healthyCount, equals(0));
      expect(report.items.first.id, equals('flutter_sdk'));
      expect(report.items.first.status, equals(DoctorItemStatus.missing));
      expect(report.error, contains('Flutter executable not found'));
    });

    test('Riverpod flutterDoctorProvider can be observed in ProviderContainer', () async {
      final container = ProviderContainer(
        overrides: [
          flutterDoctorProvider.overrideWith(
            (ref) => FlutterDoctorService(
              autoScan: false,
              processRunner: (executable, arguments, {runInShell = true}) async {
                return ProcessResult(1, 0, '[√] Flutter (Channel stable)', '');
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final initialState = container.read(flutterDoctorProvider);
      expect(initialState.isScanning, isFalse);

      final report = await container.read(flutterDoctorProvider.notifier).runDoctor();
      expect(report.healthyCount, equals(1));
      expect(container.read(flutterDoctorProvider).healthyCount, equals(1));
    });
  });
}
