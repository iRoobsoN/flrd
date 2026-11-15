import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flrd/features/ai/providers/ai_settings_provider.dart';
import 'package:flrd/features/ai/services/gemini_ai_service.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/models/connected_device.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/models/terminal_session.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/android_debug_controls.dart';
import 'package:flrd/features/studio/presentation/widgets/embedded_code_viewer.dart';
import 'package:flrd/features/studio/providers/android_debug_provider.dart';
import 'package:flrd/features/studio/providers/terminal_provider.dart';
import 'package:flrd/features/studio/services/android_device_runner_service.dart';
import 'package:flrd/features/studio/services/terminal_shell_service.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class _FakeIOSink implements IOSink {
  final List<String> writtenLines = <String>[];
  final StringBuffer _buffer = StringBuffer();
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {
    write(encoding.decode(data));
  }

  @override
  void write(Object? object) {
    final text = object?.toString() ?? '';
    _buffer.write(text);
    final raw = _buffer.toString();
    if (raw.contains('\n')) {
      final parts = raw.split('\n');
      for (var i = 0; i < parts.length - 1; i++) {
        if (parts[i].isNotEmpty) {
          writtenLines.add(parts[i]);
        }
      }
      _buffer
        ..clear()
        ..write(parts.last);
    }
  }

  @override
  void writeln([Object? object = '']) {
    write('$object\n');
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    final leftover = _buffer.toString();
    if (leftover.isNotEmpty) {
      writtenLines.add(leftover);
      _buffer.clear();
    }
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  @override
  Future<void> get done => _doneCompleter.future;
}

class _FakeProcess implements Process {
  final StreamController<List<int>> stdoutController =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> stderrController =
      StreamController<List<int>>.broadcast();
  final _FakeIOSink fakeStdin = _FakeIOSink();
  final Completer<int> _exitCodeCompleter = Completer<int>();
  bool killed = false;

  @override
  int get pid => 42424;

  void emitStdoutLine(String line) {
    if (!stdoutController.isClosed) {
      stdoutController.add(utf8.encode('$line\n'));
    }
  }

  void emitStderrLine(String line) {
    if (!stderrController.isClosed) {
      stderrController.add(utf8.encode('$line\n'));
    }
  }

  void completeExit(int code) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
  }

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  IOSink get stdin => fakeStdin;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    completeExit(0);
    return true;
  }

  Future<void> disposeStreams() async {
    await fakeStdin.close();
    if (!stdoutController.isClosed) {
      await stdoutController.close();
    }
    if (!stderrController.isClosed) {
      await stderrController.close();
    }
  }
}

void main() {
  group('AndroidDeviceRunnerService', () {
    test('parseDevicesOutput filters non-Android/unsupported and sorts physical devices first', () {
      const rawOutput = '''
Some Flutter CLI preamble log
[
  {
    "name": "Windows (desktop)",
    "id": "windows",
    "isSupported": true,
    "targetPlatform": "windows-x64",
    "emulator": false,
    "sdk": "Microsoft Windows"
  },
  {
    "name": "Chrome (web)",
    "id": "chrome",
    "isSupported": true,
    "targetPlatform": "web-javascript",
    "emulator": false,
    "sdk": "Google Chrome"
  },
  {
    "name": "Pixel 7 Emulator",
    "id": "emulator-5554",
    "isSupported": true,
    "targetPlatform": "android-x64",
    "emulator": true,
    "sdk": "Android 14 (API 34)"
  },
  {
    "name": "Broken Android",
    "id": "broken-01",
    "isSupported": false,
    "targetPlatform": "android-arm64",
    "emulator": false,
    "sdk": "Android 13"
  },
  {
    "name": "Samsung Galaxy S24",
    "id": "RFCW123456",
    "isSupported": true,
    "targetPlatform": "android-arm64",
    "emulator": false,
    "sdk": "Android 14 (API 34)"
  },
  {
    "name": "Motorola Edge",
    "id": "MOTO9988",
    "isSupported": true,
    "targetPlatform": "android-arm64",
    "emulator": false,
    "sdk": "Android 14"
  }
]
''';

      final parsed = AndroidDeviceRunnerService.parseDevicesOutput(rawOutput);
      expect(parsed.length, 3);
      expect(parsed[0].id, 'MOTO9988');
      expect(parsed[0].isEmulator, isFalse);
      expect(parsed[1].id, 'RFCW123456');
      expect(parsed[1].isEmulator, isFalse);
      expect(parsed[2].id, 'emulator-5554');
      expect(parsed[2].isEmulator, isTrue);
      expect(parsed[2].displayLabel, 'Pixel 7 Emulator (Emulador)');
    });

    test('parseDaemonMessageLine and encodeDaemonCommand handle JSON-RPC framing', () {
      expect(
        AndroidDeviceRunnerService.parseDaemonMessageLine(
          'Launching lib/main.dart on Pixel 8 in debug mode...',
        ),
        isNull,
      );

      final event = AndroidDeviceRunnerService.parseDaemonMessageLine(
        '[{"event":"app.started","params":{"appId":"app-1"}}]',
      );
      expect(event, isNotNull);
      expect(event!['event'], 'app.started');
      expect((event['params'] as Map)['appId'], 'app-1');

      final encoded = AndroidDeviceRunnerService.encodeDaemonCommand(
        id: 7,
        method: 'app.restart',
        params: {'appId': 'app-1', 'fullRestart': false, 'reason': 'save'},
      );
      expect(encoded.endsWith('\n'), isTrue);
      final decoded = jsonDecode(encoded.trim()) as List;
      expect(decoded.first['id'], 7);
      expect(decoded.first['method'], 'app.restart');
      expect(decoded.first['params']['fullRestart'], isFalse);
    });
  });

  group('AndroidDebugNotifier', () {
    late Directory tempProjectDir;
    late _FakeProcess fakeProcess;

    setUp(() {
      tempProjectDir =
          Directory.systemTemp.createTempSync('flrd_android_debug_test_');
      File(p.join(tempProjectDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: test_app\nversion: 1.0.0\n',
      );
      fakeProcess = _FakeProcess();
    });

    tearDown(() async {
      await fakeProcess.disposeStreams();
      if (tempProjectDir.existsSync()) {
        tempProjectDir.deleteSync(recursive: true);
      }
    });

    AndroidDeviceRunnerService buildFakeService({
      bool includeDevices = true,
    }) {
      return AndroidDeviceRunnerService(
        processRunner: (executable, arguments, {workingDirectory, runInShell = true}) async {
          if (executable == 'flutter' &&
              arguments.length >= 2 &&
              arguments[0] == 'devices') {
            if (!includeDevices) {
              return ProcessResult(1, 0, '[]', '');
            }
            return ProcessResult(
              1,
              0,
              jsonEncode([
                {
                  'name': 'Pixel 8',
                  'id': 'PIX8001',
                  'isSupported': true,
                  'targetPlatform': 'android-arm64',
                  'emulator': false,
                  'sdk': 'Android 14',
                },
                {
                  'name': 'Pixel Emulator',
                  'id': 'emulator-5554',
                  'isSupported': true,
                  'targetPlatform': 'android-x64',
                  'emulator': true,
                  'sdk': 'Android 14',
                },
              ]),
              '',
            );
          }
          if (executable == 'taskkill') {
            fakeProcess.kill();
            return ProcessResult(2, 0, '', '');
          }
          return ProcessResult(3, 1, '', 'unexpected command');
        },
        processStarter: (executable, arguments, {workingDirectory, runInShell = true}) async {
          return fakeProcess;
        },
      );
    }

    test('scanDevices populates physical devices first and rejects missing pubspec.yaml', () async {
      final notifier = AndroidDebugNotifier(buildFakeService());
      addTearDown(notifier.dispose);

      await notifier.scanDevices();
      expect(notifier.state.devices.length, 2);
      expect(notifier.state.selectedDevice?.id, 'PIX8001');

      final badDir = Directory.systemTemp.createTempSync('flrd_missing_pubspec_');
      try {
        final started = await notifier.launchProject(badDir.path);
        expect(started, isFalse);
        expect(notifier.state.status, DeviceRunStatus.error);
        expect(notifier.state.errorMessage, contains('pubspec.yaml'));
      } finally {
        badDir.deleteSync(recursive: true);
      }
    });

    test('full daemon lifecycle: launch, events, manual reload, debounced save reload, stop', () async {
      final notifier = AndroidDebugNotifier(buildFakeService());
      addTearDown(notifier.dispose);

      await notifier.scanDevices();
      final launched = await notifier.launchProject(tempProjectDir.path);
      expect(launched, isTrue);
      expect(notifier.state.status, DeviceRunStatus.launching);
      expect(notifier.state.isActiveSession, isTrue);

      fakeProcess.emitStdoutLine(
        '[{"event":"app.start","params":{"appId":"app-123"}}]',
      );
      fakeProcess.emitStdoutLine(
        '[{"event":"app.progress","params":{"message":"Running Gradle task..."}}]',
      );
      fakeProcess.emitStdoutLine(
        '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:50505/ws"}}]',
      );
      fakeProcess.emitStdoutLine(
        '[{"event":"app.devTools","params":{"uri":"http://127.0.0.1:9100"}}]',
      );
      fakeProcess.emitStdoutLine(
        '[{"event":"app.started","params":{"appId":"app-123"}}]',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifier.state.activeAppId, 'app-123');
      expect(notifier.state.status, DeviceRunStatus.running);
      expect(notifier.state.vmServiceUri, 'ws://127.0.0.1:50505/ws');
      expect(notifier.state.devToolsUri, 'http://127.0.0.1:9100');
      expect(notifier.state.progressMessage, isNull);

      // Manual Hot Reload
      await notifier.hotReload();
      expect(notifier.state.status, DeviceRunStatus.reloading);
      expect(fakeProcess.fakeStdin.writtenLines.length, 1);
      final reloadCmd =
          (jsonDecode(fakeProcess.fakeStdin.writtenLines.first) as List).first
              as Map<String, dynamic>;
      expect(reloadCmd['method'], 'app.restart');
      expect(reloadCmd['params']['fullRestart'], isFalse);

      // Acknowledge RPC response
      fakeProcess.emitStdoutLine(
        '[{"id":${reloadCmd['id']},"result":{"code":0}}]',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifier.state.status, DeviceRunStatus.running);

      // Unrelated project path must NOT schedule a hot reload
      notifier.onCodeSaved(p.join(Directory.systemTemp.path, 'other_app'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(fakeProcess.fakeStdin.writtenLines.length, 1);

      // Rapid saves inside active project debounce into ONE hot reload
      notifier.onCodeSaved(tempProjectDir.path);
      notifier.onCodeSaved(tempProjectDir.path);
      await Future<void>.delayed(const Duration(milliseconds: 320));
      expect(fakeProcess.fakeStdin.writtenLines.length, 2);
      final saveCmd =
          (jsonDecode(fakeProcess.fakeStdin.writtenLines.last) as List).first
              as Map<String, dynamic>;
      expect(saveCmd['params']['reason'], 'save');
      expect(saveCmd['params']['fullRestart'], isFalse);

      // Respond before stop
      fakeProcess.emitStdoutLine(
        '[{"id":${saveCmd['id']},"result":{"code":0}}]',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Hot Restart sends fullRestart: true
      await notifier.hotRestart();
      expect(notifier.state.status, DeviceRunStatus.reloading);
      final restartCmd =
          (jsonDecode(fakeProcess.fakeStdin.writtenLines.last) as List).first
              as Map<String, dynamic>;
      expect(restartCmd['method'], 'app.restart');
      expect(restartCmd['params']['fullRestart'], isTrue);
      fakeProcess.emitStdoutLine(
        '[{"id":${restartCmd['id']},"result":{"code":0}}]',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifier.state.status, DeviceRunStatus.running);

      // Stop session sends app.stop and kills process tree
      await notifier.stopSession();
      expect(notifier.state.status, DeviceRunStatus.idle);
      expect(notifier.state.isActiveSession, isFalse);
      expect(notifier.state.activeAppId, isNull);
      expect(fakeProcess.killed, isTrue);
      final stopCmd =
          (jsonDecode(fakeProcess.fakeStdin.writtenLines.last) as List).first
              as Map<String, dynamic>;
      expect(stopCmd['method'], 'app.stop');
      expect(stopCmd['params']['appId'], 'app-123');
    });
  });

  group('AppStudioScreen Android Live Debug Widget Integration', () {
    late Directory tempProjectDir;
    late _FakeProcess fakeProcess;

    setUp(() {
      tempProjectDir =
          Directory.systemTemp.createTempSync('flrd_studio_android_widget_');
      File(p.join(tempProjectDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: widget_test_app\nversion: 1.0.0\n',
      );
      fakeProcess = _FakeProcess();
    });

    tearDown(() async {
      await fakeProcess.disposeStreams();
      if (tempProjectDir.existsSync()) {
        tempProjectDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'scanning, launching, hot reloading, toggling console and stopping work directly on AppStudioScreen without internal simulator',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeService = AndroidDeviceRunnerService(
          processRunner: (executable, arguments,
              {workingDirectory, runInShell = true}) async {
            if (executable == 'flutter' &&
                arguments.isNotEmpty &&
                arguments.first == 'devices') {
              return ProcessResult(
                1,
                0,
                jsonEncode([
                  {
                    'name': 'Pixel 8',
                    'id': 'PIX8001',
                    'isSupported': true,
                    'targetPlatform': 'android-arm64',
                    'emulator': false,
                    'sdk': 'Android 14',
                  },
                ]),
                '',
              );
            }
            if (executable == 'taskkill') {
              fakeProcess.kill();
              return ProcessResult(2, 0, '', '');
            }
            return ProcessResult(3, 0, '', '');
          },
          processStarter: (executable, arguments,
              {workingDirectory, runInShell = true}) async {
            return fakeProcess;
          },
        );

        final project = RegisteredProject(
          id: 'proj-android-test',
          name: 'android_live_app',
          orgId: 'com.example',
          path: tempProjectDir.path,
          preset: PresetType.saas,
          navigationStyle: NavigationStyle.tabs,
          permissions: const {},
          lastModified: DateTime(2026),
          routeCount: 4,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              androidDeviceRunnerServiceProvider
                  .overrideWithValue(fakeService),
            ],
            child: MaterialApp(
              home: AppStudioScreen(project: project),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No fake simulator pane exists; Android USB scan button is immediately available.
        expect(find.byKey(const ValueKey('anchored_live_preview_pane')),
            findsNothing);
        expect(find.byKey(const ValueKey('android_scan_devices_button')),
            findsOneWidget);

        // Scan for connected Android devices
        await tester
            .tap(find.byKey(const ValueKey('android_scan_devices_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('android_device_selector')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('android_launch_button')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('anchored_live_preview_pane')),
            findsNothing);

        // Launch app on Pixel 8 -> Android debug console opens automatically
        await tester.tap(find.byKey(const ValueKey('android_launch_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('android_running_badge')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('android_debug_console_panel')),
            findsOneWidget);

        // Transition daemon to started
        fakeProcess.emitStdoutLine(
          '[{"event":"app.start","params":{"appId":"app-widget-1"}}]',
        );
        fakeProcess.emitStdoutLine(
          '[{"event":"app.started","params":{"appId":"app-widget-1"}}]',
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Ao Vivo • Pixel 8'), findsOneWidget);

        // Trigger Hot Reload button
        await tester
            .tap(find.byKey(const ValueKey('android_hot_reload_button')));
        await tester.pump();
        expect(
          fakeProcess.fakeStdin.writtenLines.any((l) => l.contains('app.restart')),
          isTrue,
        );

        // Toggle console panel closed and open again
        await tester
            .tap(find.byKey(const ValueKey('android_close_console_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('android_debug_console_panel')),
            findsNothing);

        await tester.tap(find.byKey(const ValueKey('android_logs_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('android_debug_console_panel')),
            findsOneWidget);

        // Stop session -> persistent console remains accessible and launch button returns
        await tester.tap(find.byKey(const ValueKey('android_stop_button')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('anchored_live_preview_pane')),
            findsNothing);
        expect(find.byKey(const ValueKey('android_debug_console_panel')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('android_launch_button')),
            findsOneWidget);
      },
    );

    testWidgets(
      'EmbeddedCodeViewer Save to Disk triggers debounced Hot Reload when running on Android',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final targetFile = File(p.join(tempProjectDir.path, 'lib', 'home.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('import \'package:flutter/material.dart\';\nclass Home extends StatelessWidget { const Home({super.key}); @override Widget build(BuildContext context) => const SizedBox(); }\n');

        final fakeService = AndroidDeviceRunnerService(
          processRunner: (executable, arguments,
              {workingDirectory, runInShell = true}) async {
            if (executable == 'flutter' &&
                arguments.isNotEmpty &&
                arguments.first == 'devices') {
              return ProcessResult(
                1,
                0,
                jsonEncode([
                  {
                    'name': 'Pixel 8',
                    'id': 'PIX8001',
                    'isSupported': true,
                    'targetPlatform': 'android-arm64',
                    'emulator': false,
                    'sdk': 'Android 14',
                  },
                ]),
                '',
              );
            }
            if (executable == 'taskkill') {
              fakeProcess.kill();
              return ProcessResult(2, 0, '', '');
            }
            return ProcessResult(3, 0, '', '');
          },
          processStarter: (executable, arguments,
              {workingDirectory, runInShell = true}) async {
            return fakeProcess;
          },
        );

        final container = ProviderContainer(
          overrides: [
            androidDeviceRunnerServiceProvider.overrideWithValue(fakeService),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(androidDebugProvider.notifier);
        await tester.runAsync(() async {
          await notifier.scanDevices();
          await notifier.launchProject(tempProjectDir.path);
          fakeProcess.emitStdoutLine(
            '[{"event":"app.start","params":{"appId":"app-save-1"}}]',
          );
          fakeProcess.emitStdoutLine(
            '[{"event":"app.started","params":{"appId":"app-save-1"}}]',
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });

        const node = RouteNode(
          id: 'home',
          path: '/home',
          title: 'Home',
          subtitle: 'Home Screen',
          icon: Icons.home,
          position: Offset.zero,
          filePath: 'lib/home.dart',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: EmbeddedCodeViewer(
                  projectPath: tempProjectDir.path,
                  node: node,
                ),
              ),
            ),
          ),
        );
        // Wait for async _loadFileContent() File I/O to finish on Windows disk.
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }

        expect(targetFile.existsSync(), isTrue);
        await tester.tap(find.text('Save to Disk'));
        await tester.pump();

        // Wait for async saveCodeToDisk() (flush: true) to complete on Windows disk.
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }

        // Advance FakeAsync past the 250ms debounce in onCodeSaved().
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          fakeProcess.fakeStdin.writtenLines.any(
            (l) => l.contains('app.restart') && l.contains('"reason":"save"'),
          ),
          isTrue,
        );

        unawaited(notifier.stopSession());
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });

  group('Android Connection Diagnostics & Troubleshooter', () {
    test('parseAdbDevicesOutput parses device, unauthorized, and offline lines', () {
      const adbStdout = '''
* daemon not running; starting now at tcp:5037
* daemon started successfully
List of devices attached
RXGL20BSBJX            unauthorized usb:1-2 transport_id:1
EMU5554                offline transport_id:2
PIX8001                device product:shiba model:Pixel_8 device:shiba transport_id:3
''';
      final parsed = AndroidDeviceRunnerService.parseAdbDevicesOutput(adbStdout);
      expect(parsed.length, 3);
      expect(parsed[0].serial, 'RXGL20BSBJX');
      expect(parsed[0].isUnauthorized, isTrue);
      expect(parsed[1].serial, 'EMU5554');
      expect(parsed[1].isOffline, isTrue);
      expect(parsed[2].serial, 'PIX8001');
      expect(parsed[2].isReady, isTrue);
      expect(parsed[2].model, 'Pixel 8');
    });

    test('parseWindowsUsbDevicesJson handles PowerShell CompatibleID object and correlates MTP + ADB', () {
      final rawJson = jsonEncode([
        {
          'Name': 'S25 Ultra de Robson',
          'Status': 'OK',
          'ConfigManagerErrorCode': 0,
          'Service': 'WUDFWpdMtp',
          'DeviceID': r'USB\VID_04E8&PID_6860&MI_00\7&33E2BE27&0&0000',
          'CompatibleID': {
            'value': [r'USB\MS_COMP_MTP'],
            'Count': 1,
          },
        },
        {
          'Name': 'Camera DFU Device',
          'Status': 'OK',
          'ConfigManagerErrorCode': 0,
          'Service': 'WINUSB',
          'DeviceID': r'USB\VID_174F&PID_2459&MI_02\7&6C047C5&0&0002',
          'CompatibleID': {
            'value': [r'USB\MS_COMP_WINUSB', r'USB\Class_fe&SubClass_01&Prot_00'],
            'Count': 2,
          },
        },
        {
          'Name': 'ADB Interface',
          'Status': 'OK',
          'ConfigManagerErrorCode': 0,
          'Service': 'WINUSB',
          'DeviceID': r'USB\VID_04E8&PID_6860&MI_03\7&33E2BE27&0&0003',
          'CompatibleID': {
            'value': [
              r'USB\MS_COMP_WINUSB',
              r'USB\COMPAT_VID_04e8&Class_ff&SubClass_42&Prot_01',
            ],
            'Count': 2,
          },
        },
      ]);

      final clixmlWrappedJson = '#< CLIXML\n$rawJson\n<Objs Version="1.1.0.1"></Objs>';
      final usb = AndroidDeviceRunnerService.parseWindowsUsbDevicesJson(
        clixmlWrappedJson,
      );
      expect(usb.length, 3);
      expect(usb[0].isPhoneLike, isTrue);
      expect(usb[0].isAdbInterface, isFalse);
      expect(usb[1].isAdbInterface, isFalse);
      expect(usb[2].isAdbInterface, isTrue);
      expect(usb[2].vidPidKey, 'VID_04E8&PID_6860');
    });

    test('scanAndroidEnvironment diagnoses S25 Ultra USB ADB connected without Android SDK/ADB', () async {
      final service = AndroidDeviceRunnerService(
        isWindowsOverride: true,
        environmentProvider: () => const {'LOCALAPPDATA': r'C:\FakeLocal'},
        fileExists: (_) => false,
        dirExists: (_) => false,
        processRunner: (executable, arguments,
            {workingDirectory, runInShell = true}) async {
          if (executable == 'flutter' &&
              arguments.isNotEmpty &&
              arguments.first == 'devices') {
            return ProcessResult(
              1,
              0,
              jsonEncode([
                {
                  'name': 'Windows (desktop)',
                  'id': 'windows',
                  'isSupported': true,
                  'targetPlatform': 'windows-x64',
                  'emulator': false,
                },
              ]),
              '',
            );
          }
          if (executable == 'powershell') {
            return ProcessResult(
              2,
              0,
              jsonEncode([
                {
                  'Name': 'S25 Ultra de Robson',
                  'Status': 'OK',
                  'ConfigManagerErrorCode': 0,
                  'Service': 'WUDFWpdMtp',
                  'DeviceID': r'USB\VID_04E8&PID_6860&MI_00\1',
                  'CompatibleID': [r'USB\MS_COMP_MTP'],
                },
                {
                  'Name': 'ADB Interface',
                  'Status': 'OK',
                  'ConfigManagerErrorCode': 0,
                  'Service': 'WINUSB',
                  'DeviceID': r'USB\VID_04E8&PID_6860&MI_03\1',
                  'CompatibleID': [
                    r'USB\COMPAT_VID_04e8&Class_ff&SubClass_42&Prot_01',
                  ],
                },
              ]),
              '',
            );
          }
          return ProcessResult(3, 1, '', 'not found');
        },
      );

      final diag = await service.scanAndroidEnvironment();
      expect(diag.devices, isEmpty);
      expect(diag.issueType, AndroidConnectionIssueType.usbInterfaceWithoutSdk);
      expect(diag.detectedUsbDeviceName, 'S25 Ultra de Robson (ADB Interface)');
      expect(diag.hasJava, isFalse);
      expect(diag.suggestedCommand, contains('Google.AndroidStudio'));
      expect(diag.suggestedCommand, contains('EclipseAdoptium.Temurin.17.JDK'));
      expect(diag.actionUrl, 'https://developer.android.com/studio');
    });

    test('scanAndroidEnvironment detects unauthorized phone and Samsung driver issues when ADB exists', () async {
      const sdkPath = r'C:\FakeLocal\Android\Sdk';
      const adbPath = r'C:\FakeLocal\Android\Sdk\platform-tools\adb.exe';

      // Case A: unauthorized
      final unauthService = AndroidDeviceRunnerService(
        isWindowsOverride: true,
        environmentProvider: () => const {'LOCALAPPDATA': r'C:\FakeLocal'},
        dirExists: (path) => path == sdkPath,
        fileExists: (path) => path == adbPath,
        processRunner: (executable, arguments,
            {workingDirectory, runInShell = true}) async {
          if (executable == 'flutter') return ProcessResult(1, 0, '[]', '');
          if (executable == 'java') return ProcessResult(2, 0, 'openjdk 17', '');
          if (executable == adbPath) {
            return ProcessResult(
              3,
              0,
              'List of devices attached\nRXGL20BSBJX unauthorized usb:1-2\n',
              '',
            );
          }
          return ProcessResult(4, 0, '[]', '');
        },
      );

      final unauthDiag = await unauthService.scanAndroidEnvironment();
      expect(unauthDiag.issueType, AndroidConnectionIssueType.unauthorized);
      expect(unauthDiag.hasJava, isTrue);

      // Case B: ADB exists, Samsung USB ADB interface visible, yet adb returns 0 devices
      final samsungDriverService = AndroidDeviceRunnerService(
        isWindowsOverride: true,
        environmentProvider: () => const {'LOCALAPPDATA': r'C:\FakeLocal'},
        dirExists: (path) => path == sdkPath,
        fileExists: (path) => path == adbPath,
        processRunner: (executable, arguments,
            {workingDirectory, runInShell = true}) async {
          if (executable == 'flutter') return ProcessResult(1, 0, '[]', '');
          if (executable == 'java') return ProcessResult(2, 0, 'openjdk 17', '');
          if (executable == adbPath) {
            return ProcessResult(3, 0, 'List of devices attached\n', '');
          }
          if (executable == 'powershell') {
            return ProcessResult(
              4,
              0,
              jsonEncode([
                {
                  'Name': 'S25 Ultra de Robson',
                  'Status': 'OK',
                  'ConfigManagerErrorCode': 0,
                  'Service': 'WUDFWpdMtp',
                  'DeviceID': r'USB\VID_04E8&PID_6860&MI_00\1',
                  'CompatibleID': [r'USB\MS_COMP_MTP'],
                },
                {
                  'Name': 'ADB Interface',
                  'Status': 'OK',
                  'ConfigManagerErrorCode': 0,
                  'Service': 'WINUSB',
                  'DeviceID': r'USB\VID_04E8&PID_6860&MI_03\1',
                  'CompatibleID': [
                    r'USB\COMPAT_VID_04e8&Class_ff&SubClass_42&Prot_01',
                  ],
                },
              ]),
              '',
            );
          }
          return ProcessResult(5, 1, '', '');
        },
      );

      final driverDiag = await samsungDriverService.scanAndroidEnvironment();
      expect(
        driverDiag.issueType,
        AndroidConnectionIssueType.driverOrUsbModeSuspected,
      );
      expect(driverDiag.actionUrl, 'https://developer.samsung.com/android-usb-driver');
    });

    testWidgets(
      'clicking Android USB opens troubleshooter on S25 Ultra SDK issue and recovers on re-test',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        var simulateFixed = false;
        const fakeSdkPath = r'C:\FakeLocal\Android\Sdk';
        final executedCommands = <String>[];

        final service = AndroidDeviceRunnerService(
          isWindowsOverride: true,
          environmentProvider: () => const {'LOCALAPPDATA': r'C:\FakeLocal'},
          dirExists: (path) => path == fakeSdkPath,
          fileExists: (_) => false,
          processRunner: (executable, arguments,
              {workingDirectory, runInShell = true}) async {
            executedCommands.add('$executable ${arguments.join(' ')}');
            if (executable == 'flutter' &&
                arguments.isNotEmpty &&
                arguments.first == 'devices') {
              if (!simulateFixed) {
                return ProcessResult(1, 0, '[]', '');
              }
              return ProcessResult(
                1,
                0,
                jsonEncode([
                  {
                    'name': 'SM S938B',
                    'id': 'RXGL20BSBJX',
                    'isSupported': true,
                    'targetPlatform': 'android-arm64',
                    'emulator': false,
                    'sdk': 'Android 15',
                  },
                ]),
                '',
              );
            }
            if (executable == 'flutter' &&
                arguments.length >= 3 &&
                arguments[0] == 'config' &&
                arguments[1] == '--android-sdk') {
              return ProcessResult(2, 0, 'Setting "android-sdk" value to "$fakeSdkPath".', '');
            }
            if (executable == 'powershell') {
              return ProcessResult(
                3,
                0,
                jsonEncode([
                  {
                    'Name': 'S25 Ultra de Robson',
                    'Status': 'OK',
                    'ConfigManagerErrorCode': 0,
                    'Service': 'WUDFWpdMtp',
                    'DeviceID': r'USB\VID_04E8&PID_6860&MI_00\1',
                    'CompatibleID': [r'USB\MS_COMP_MTP'],
                  },
                  {
                    'Name': 'ADB Interface',
                    'Status': 'OK',
                    'ConfigManagerErrorCode': 0,
                    'Service': 'WINUSB',
                    'DeviceID': r'USB\VID_04E8&PID_6860&MI_03\1',
                    'CompatibleID': [
                      r'USB\COMPAT_VID_04e8&Class_ff&SubClass_42&Prot_01',
                    ],
                  },
                ]),
                '',
              );
            }
            return ProcessResult(4, 1, '', '');
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              androidDeviceRunnerServiceProvider.overrideWithValue(service),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: AndroidDebugToolbarControls(
                    projectPath: r'C:\FakeProject',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Click Android USB while SDK/adb.exe is missing -> opens Troubleshooter Dialog!
        await tester.tap(find.byKey(const ValueKey('android_scan_devices_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('android_connection_troubleshooter_dialog')),
          findsOneWidget,
        );
        expect(find.textContaining('S25 Ultra de Robson'), findsWidgets);
        expect(
          find.byKey(const ValueKey('android_troubleshooter_configure_sdk_button')),
          findsOneWidget,
        );

        // Clicking Configure SDK invokes `flutter config --android-sdk`
        await tester.tap(
          find.byKey(const ValueKey('android_troubleshooter_configure_sdk_button')),
        );
        await tester.pumpAndSettle();
        expect(
          executedCommands.any(
            (c) => c.contains('flutter config --android-sdk $fakeSdkPath'),
          ),
          isTrue,
        );

        // Now simulate user finished setup & re-tests connection inside the dialog
        simulateFixed = true;
        await tester.tap(
          find.byKey(const ValueKey('android_troubleshooter_rescan_button')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('SM S938B conectado e pronto!'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('android_troubleshooter_done_button')),
        );
        await tester.pumpAndSettle();

        // Toolbar switched to ready launch button for SM S938B!
        expect(find.byKey(const ValueKey('android_launch_button')), findsOneWidget);
        expect(find.textContaining('SM S938B'), findsWidgets);
      },
    );

    group('Build Failure Diagnostics & 1-Click JDK Remediation', () {
      test('parses Java release versions, major versions, and Gradle compatibility', () {
        expect(
          AndroidDeviceRunnerService.parseJavaReleaseVersion(
            'IMPLEMENTOR="Eclipse Adoptium"\nJAVA_VERSION="17.0.21"\nOS_NAME="Windows"',
          ),
          '17.0.21',
        );
        expect(
          AndroidDeviceRunnerService.parseJavaReleaseVersion('JAVA_VERSION="25.0.4"'),
          '25.0.4',
        );
        expect(AndroidDeviceRunnerService.parseJavaMajorVersion('25.0.4'), 25);
        expect(AndroidDeviceRunnerService.parseJavaMajorVersion('17.0.21'), 17);
        expect(AndroidDeviceRunnerService.parseJavaMajorVersion('1.8.0_402'), 8);

        expect(
          AndroidDeviceRunnerService.extractGradleWrapperVersion(
            r'distributionUrl=https\://services.gradle.org/distributions/gradle-8.14-all.zip',
          ),
          '8.14',
        );

        expect(
          AndroidDeviceRunnerService.isJavaCompatibleWithGradle(
            javaMajor: 25,
            gradleVersion: '8.14',
          ),
          isFalse,
        );
        expect(
          AndroidDeviceRunnerService.isJavaCompatibleWithGradle(
            javaMajor: 17,
            gradleVersion: '8.14',
          ),
          isTrue,
        );
        expect(
          AndroidDeviceRunnerService.isJavaCompatibleWithGradle(
            javaMajor: 25,
            gradleVersion: '9.1.0',
          ),
          isTrue,
        );
        expect(
          AndroidDeviceRunnerService.isJavaCompatibleWithGradle(
            javaMajor: 11,
            gradleVersion: '8.14',
          ),
          isFalse,
        );
      });

      test('discovers compatible LTS JDKs while skipping Java 25 JBR', () async {
        const jdk17Dir = r'C:\Program Files\Eclipse Adoptium\jdk-17.0.21';
        const jdk21Dir = r'C:\Program Files\Eclipse Adoptium\jdk-21.0.5';
        const jbr25Dir = r'C:\Program Files\Android\Android Studio\jbr';

        final dirs = <String>{
          r'C:\Program Files\Eclipse Adoptium',
          jdk17Dir,
          jdk21Dir,
          jbr25Dir,
        };
        final files = <String, String>{
          '$jdk17Dir\\release': 'JAVA_VERSION="17.0.21"',
          '$jdk17Dir\\bin\\java.exe': 'bin',
          '$jdk21Dir\\release': 'JAVA_VERSION="21.0.5"',
          '$jdk21Dir\\bin\\java.exe': 'bin',
          '$jbr25Dir\\release': 'JAVA_VERSION="25.0.4"',
          '$jbr25Dir\\bin\\java.exe': 'bin',
        };

        final service = AndroidDeviceRunnerService(
          isWindowsOverride: true,
          environmentProvider: () => const {
            'JAVA_HOME': jdk17Dir,
            'ProgramFiles': r'C:\Program Files',
          },
          dirExists: dirs.contains,
          fileExists: files.containsKey,
          readFileSync: (path) => files[path],
          listSubdirectories: (dir) =>
              dir == r'C:\Program Files\Eclipse Adoptium'
                  ? [jdk21Dir, jdk17Dir]
                  : const [],
        );

        final jdks = await service.discoverCompatibleJdks();
        expect(jdks.map((j) => j.majorVersion).toList(), [17, 21]);
        expect(jdks.first.path, jdk17Dir);
        expect(jdks.first.source, 'JAVA_HOME');
      });

      test('diagnoses Java 25 / Gradle 8.14 and CMake Ninja build failures', () async {
        const jdk17Dir = r'C:\Program Files\Eclipse Adoptium\jdk-17.0.21';
        final filesWithJdk = <String, String>{
          '$jdk17Dir\\release': 'JAVA_VERSION="17.0.21"',
          '$jdk17Dir\\bin\\java.exe': 'bin',
        };

        final serviceWithJdk = AndroidDeviceRunnerService(
          isWindowsOverride: true,
          environmentProvider: () => const {'JAVA_HOME': jdk17Dir},
          dirExists: (p) => p == jdk17Dir,
          fileExists: filesWithJdk.containsKey,
          readFileSync: (p) => filesWithJdk[p],
          listSubdirectories: (_) => const [],
        );

        final javaDiag = await serviceWithJdk.diagnoseBuildFailure([
          'Error: Gradle build failed due to Java/Gradle incompatibility.',
          'The Java version used for the build is 25.0.4, which is incompatible with Gradle 8.14.',
          'App failed to start',
        ]);
        expect(javaDiag, isNotNull);
        expect(javaDiag!.issueType, AndroidBuildIssueType.javaGradleIncompatibility);
        expect(javaDiag.detectedJavaVersion, '25.0.4');
        expect(javaDiag.gradleVersion, '8.14');
        expect(javaDiag.canAutoApplyJdk, isTrue);
        expect(javaDiag.compatibleJdk!.path, jdk17Dir);

        final serviceWithoutJdk = AndroidDeviceRunnerService(
          isWindowsOverride: true,
          environmentProvider: () => const {},
          dirExists: (_) => false,
          fileExists: (_) => false,
          readFileSync: (_) => null,
          listSubdirectories: (_) => const [],
        );
        final noJdkDiag = await serviceWithoutJdk.diagnoseBuildFailure([
          'Error: Gradle build failed due to Java/Gradle incompatibility.',
          'The Java version used for the build is 25.0.4, which is incompatible with Gradle 8.14.',
        ]);
        expect(noJdkDiag, isNotNull);
        expect(noJdkDiag!.canAutoApplyJdk, isFalse);
        expect(noJdkDiag.suggestedTerminalCommand, contains('Temurin.17'));
        expect(noJdkDiag.externalHelpUrl, contains('adoptium.net'));

        final ninjaDiag = await serviceWithoutJdk.diagnoseBuildFailure([
          'CMake Error: CMake was unable to find a build program corresponding to "Ninja".',
          'CMAKE_MAKE_PROGRAM is not set.',
        ]);
        expect(ninjaDiag, isNotNull);
        expect(ninjaDiag!.issueType, AndroidBuildIssueType.cmakeBuildToolMissing);
        expect(ninjaDiag.suggestedTerminalCommand, contains('Ninja-build.Ninja'));
      });

      test('notifier promotes silent app.stop + App failed to start to error and applies JDK fix', () async {
        const jdk17Dir = r'C:\Program Files\Eclipse Adoptium\jdk-17.0.21';
        final tempProj = Directory.systemTemp.createTempSync('flrd_jdk_unit_');
        File(p.join(tempProj.path, 'pubspec.yaml')).writeAsStringSync('name: snapia\n');
        addTearDown(() {
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final processes = <_FakeProcess>[];
        final configuredArgs = <List<String>>[];

        final files = <String, String>{
          '$jdk17Dir\\release': 'JAVA_VERSION="17.0.21"',
          '$jdk17Dir\\bin\\java.exe': 'bin',
        };

        final service = AndroidDeviceRunnerService(
          isWindowsOverride: true,
          environmentProvider: () => const {'JAVA_HOME': jdk17Dir},
          dirExists: (p) => p == jdk17Dir,
          fileExists: files.containsKey,
          readFileSync: (p) => files[p],
          listSubdirectories: (_) => const [],
          processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
            if (exec == 'flutter' && args.length >= 3 && args[0] == 'config') {
              configuredArgs.add(List<String>.from(args));
              return ProcessResult(1, 0, 'Setting "jdk-dir" value to "$jdk17Dir".', '');
            }
            return ProcessResult(2, 0, '', '');
          },
          processStarter: (exec, args, {workingDirectory, runInShell = true}) async {
            final proc = _FakeProcess();
            processes.add(proc);
            return proc;
          },
        );

        final notifier = AndroidDebugNotifier(service);
        const device = ConnectedAndroidDevice(
          id: 'RXGL20BSBJX',
          name: 'SM S938B',
          targetPlatform: 'android-arm64',
          sdk: 'Android 16',
        );

        final launched = await notifier.launchProject(
          tempProj.path,
          device: device,
        );
        expect(launched, isTrue);

        final firstProc = processes.single;
        firstProc.emitStdoutLine('[{"event":"app.start","params":{"appId":"1"}}]');
        firstProc.emitStdoutLine('Error: Gradle build failed due to Java/Gradle incompatibility.');
        firstProc.emitStdoutLine(
          'The Java version used for the build is 25.0.4, which is incompatible with Gradle 8.14.',
        );
        // Simulate real flutter_tools daemon quirk: app.stop has NO params.error!
        firstProc.emitStdoutLine('[{"event":"app.stop","params":{"appId":"1"}}]');
        firstProc.emitStdoutLine('App failed to start');
        firstProc.completeExit(1);

        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(notifier.state.status, DeviceRunStatus.error);
        expect(notifier.state.buildDiagnostic, isNotNull);
        expect(
          notifier.state.buildDiagnostic!.issueType,
          AndroidBuildIssueType.javaGradleIncompatibility,
        );
        expect(notifier.state.buildDiagnostic!.compatibleJdk?.path, jdk17Dir);

        // Apply 1-click JDK fix & automatic relaunch
        final relaunched = await notifier.applyCompatibleJdkAndRelaunch();
        expect(relaunched, isTrue);
        expect(configuredArgs, [
          ['config', '--jdk-dir', jdk17Dir],
        ]);
        expect(processes.length, 2);
        expect(notifier.state.buildDiagnostic, isNull);

        processes[1].emitStdoutLine('[{"event":"app.started","params":{"appId":"2"}}]');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(notifier.state.status, DeviceRunStatus.running);

        notifier.dispose();
      });

      testWidgets(
        'AndroidDebugConsolePanel shows 1-click JDK fix without overflow even at 140px and supports Run in Terminal',
        (tester) async {
          const jdk17Dir = r'C:\Program Files\Eclipse Adoptium\jdk-17.0.21';
          final tempProj = Directory.systemTemp.createTempSync('flrd_jdk_widget_');
          File(p.join(tempProj.path, 'pubspec.yaml')).writeAsStringSync('name: snapia\n');
          addTearDown(() {
            if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
          });

          final appProcesses = <_FakeProcess>[];
          final shellProcesses = <_FakeProcess>[];
          final configuredJdkArgs = <String>[];

          final files = <String, String>{
            '$jdk17Dir\\release': 'JAVA_VERSION="17.0.21"',
            '$jdk17Dir\\bin\\java.exe': 'bin',
          };

          final androidService = AndroidDeviceRunnerService(
            isWindowsOverride: true,
            environmentProvider: () => const {'JAVA_HOME': jdk17Dir},
            dirExists: (p) => p == jdk17Dir,
            fileExists: files.containsKey,
            readFileSync: (p) => files[p],
            listSubdirectories: (_) => const [],
            processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
              if (exec == 'flutter' &&
                  args.length >= 3 &&
                  args[0] == 'config' &&
                  args[1] == '--jdk-dir') {
                configuredJdkArgs.add(args[2]);
                return ProcessResult(10, 0, '', '');
              }
              return ProcessResult(11, 0, '', '');
            },
            processStarter: (exec, args, {workingDirectory, runInShell = true}) async {
              final proc = _FakeProcess();
              appProcesses.add(proc);
              return proc;
            },
          );

          final shellService = TerminalShellService(
            isWindowsOverride: true,
            dirExists: (_) => true,
            processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
              if (exec == 'where' && args.contains('pwsh.exe')) {
                return ProcessResult(12, 0, r'C:\Program Files\PowerShell\7\pwsh.exe', '');
              }
              return ProcessResult(13, 1, '', '');
            },
            processStarter: (exec, args, {workingDirectory, runInShell = true}) async {
              final proc = _FakeProcess();
              shellProcesses.add(proc);
              return proc;
            },
          );

          final container = ProviderContainer(
            overrides: [
              androidDeviceRunnerServiceProvider.overrideWithValue(androidService),
              terminalShellServiceProvider.overrideWithValue(shellService),
            ],
          );
          addTearDown(container.dispose);

          // Shrink panel height to minimum (140px) first.
          container.read(terminalProvider.notifier).setPanelHeight(140.0);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: AndroidDebugConsolePanel(
                      projectPath: tempProj.path,
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final debugNotifier = container.read(androidDebugProvider.notifier);
          await debugNotifier.launchProject(
            tempProj.path,
            device: const ConnectedAndroidDevice(
              id: 'RXGL20BSBJX',
              name: 'SM S938B',
              targetPlatform: 'android-arm64',
              sdk: 'Android 16',
            ),
          );

          appProcesses.first.emitStdoutLine('[{"event":"app.start","params":{"appId":"1"}}]');
          appProcesses.first.emitStdoutLine(
            'Error: Gradle build failed due to Java/Gradle incompatibility.',
          );
          appProcesses.first.emitStdoutLine(
            'The Java version used for the build is 25.0.4, which is incompatible with Gradle 8.14.',
          );
          appProcesses.first.emitStdoutLine('[{"event":"app.stop","params":{"appId":"1"}}]');
          appProcesses.first.emitStdoutLine('App failed to start');
          appProcesses.first.completeExit(1);
          await tester.pump(const Duration(milliseconds: 60));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('android_build_diagnostic_card')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('android_fix_jdk_button')),
            findsOneWidget,
          );

          // Expand panel for spacious click & click 1-click JDK fix button
          container.read(terminalProvider.notifier).setPanelHeight(300.0);
          await tester.pumpAndSettle();

          await tester.ensureVisible(
            find.byKey(const ValueKey('android_fix_jdk_button')),
          );
          await tester.tap(find.byKey(const ValueKey('android_fix_jdk_button')));
          // Do not pumpAndSettle here because relaunch enters DeviceRunStatus.launching spinner.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(configuredJdkArgs, [jdk17Dir]);
          expect(appProcesses.length, 2);

          // Simulate second build hitting CMake Ninja missing error and verify "Executar no Terminal"
          appProcesses[1].emitStdoutLine('[{"event":"app.start","params":{"appId":"2"}}]');
          appProcesses[1].emitStdoutLine(
            'CMake Error: CMake was unable to find a build program corresponding to "Ninja".',
          );
          appProcesses[1].emitStdoutLine('CMAKE_MAKE_PROGRAM is not set.');
          appProcesses[1].emitStdoutLine('[{"event":"app.stop","params":{"appId":"2"}}]');
          appProcesses[1].completeExit(1);
          await tester.pump(const Duration(milliseconds: 60));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('android_run_fix_in_terminal_button')),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('android_run_fix_in_terminal_button')),
          );
          await tester.tap(
            find.byKey(const ValueKey('android_run_fix_in_terminal_button')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));

          expect(shellProcesses.length, 1);
          expect(
            shellProcesses.single.fakeStdin.writtenLines
                .any((l) => l.contains('Ninja-build.Ninja')),
            isTrue,
          );

          // Clear any remaining AppToast dismissal timers cleanly before teardown.
          await tester.pump(const Duration(seconds: 5));
        },
      );
    });

    group('Windows Ninja, NDK glslc & MSVC auto-remediation', () {
      test(
        'mergePathEntries prioritizes new dirs and deduplicates case-insensitively on Windows',
        () {
          final merged = AndroidDeviceRunnerService.mergePathEntries(
            r'C:\Windows\System32;C:\Users\Rob\AppData\Local\Microsoft\WinGet\Links\;C:\flutter\bin',
            const [
              r'C:\Users\Rob\AppData\Local\Microsoft\WinGet\Links',
              r'C:\Users\Rob\AppData\Local\Android\Sdk\cmake\3.22.1\bin',
              r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64',
            ],
            isWindows: true,
          );

          final parts = merged.split(';');
          expect(
            parts,
            equals([
              r'C:\Users\Rob\AppData\Local\Microsoft\WinGet\Links',
              r'C:\Users\Rob\AppData\Local\Android\Sdk\cmake\3.22.1\bin',
              r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64',
              r'C:\Windows\System32',
              r'C:\flutter\bin',
            ]),
          );
        },
      );

      test(
        'buildBuildEnvironment and startAppProcess inject WinGet Ninja, NDK glslc, Registry PATH and MSVC vcvars64',
        () async {
          const wingetLinks =
              r'C:\Users\Rob\AppData\Local\Microsoft\WinGet\Links';
          const sdkRoot = r'C:\Users\Rob\AppData\Local\Android\Sdk';
          const cmakeBin = r'C:\Users\Rob\AppData\Local\Android\Sdk\cmake\3.22.1\bin';
          const ndkShaderDir =
              r'C:\Users\Rob\AppData\Local\Android\Sdk\ndk\28.2.13676358\shader-tools\windows-x86_64';
          const vsRoot =
              r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools';
          const vcvarsBat =
              r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat';
          const msvcVerDir =
              r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207';
          const clExe =
              r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe';
          const vswhereExe =
              r'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe';

          final existingFiles = <String>{
            '$wingetLinks\\ninja.exe',
            '$cmakeBin\\ninja.exe',
            '$ndkShaderDir\\glslc.exe',
            vcvarsBat,
            clExe,
            vswhereExe,
          };
          final existingDirs = <String>{
            sdkRoot,
            r'C:\Users\Rob\AppData\Local\Android\Sdk\cmake',
            r'C:\Users\Rob\AppData\Local\Android\Sdk\ndk',
            vsRoot,
            r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC',
          };

          Map<String, String>? capturedEnv;
          final service = AndroidDeviceRunnerService(
            isWindowsOverride: true,
            environmentProvider: () => const {
              'LOCALAPPDATA': r'C:\Users\Rob\AppData\Local',
              'ProgramFiles(x86)': r'C:\Program Files (x86)',
              'ProgramFiles': r'C:\Program Files',
              'Path': r'C:\Windows\System32;C:\flutter\bin',
            },
            fileExists: existingFiles.contains,
            dirExists: existingDirs.contains,
            listSubdirectories: (dir) {
              if (dir == r'C:\Users\Rob\AppData\Local\Android\Sdk\cmake') {
                return const [r'C:\Users\Rob\AppData\Local\Android\Sdk\cmake\3.22.1'];
              }
              if (dir == r'C:\Users\Rob\AppData\Local\Android\Sdk\ndk') {
                return const [
                  r'C:\Users\Rob\AppData\Local\Android\Sdk\ndk\28.2.13676358',
                ];
              }
              if (dir ==
                  r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC') {
                return const [msvcVerDir];
              }
              return const [];
            },
            processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
              if (exec == vswhereExe) {
                return ProcessResult(1, 0, '$vsRoot\r\n', '');
              }
              if (exec == 'cmd.exe' &&
                  args.any((a) => a.contains('vcvars64.bat'))) {
                expect(args, equals(['/c', 'call', vcvarsBat, '&&', 'set']));
                return ProcessResult(
                  2,
                  0,
                  'INCLUDE=C:\\VS\\include\r\n'
                      'LIB=C:\\VS\\lib\\x64\r\n'
                      'Path=$msvcVerDir\\bin\\Hostx64\\x64;C:\\Windows\\System32\r\n',
                  '',
                );
              }
              if (exec == 'reg' && args.contains(r'HKCU\Environment')) {
                return ProcessResult(
                  3,
                  0,
                  '    Path    REG_EXPAND_SZ    %LOCALAPPDATA%\\CustomTools\r\n',
                  '',
                );
              }
              return ProcessResult(4, 1, '', '');
            },
            processEnvStarter: (
              exec,
              args, {
              workingDirectory,
              runInShell = true,
              environment,
            }) async {
              capturedEnv = environment;
              return _FakeProcess();
            },
          );

          await service.startAppProcess(
            projectPath: r'C:\Users\Rob\Downloads\snapia',
            deviceId: 'RXGL20BSBJX',
          );

          expect(capturedEnv, isNotNull);
          expect(capturedEnv!['INCLUDE'], r'C:\VS\include');
          expect(capturedEnv!['LIB'], r'C:\VS\lib\x64');
          final pathValue = capturedEnv!['Path'] ?? '';
          expect(pathValue, contains(wingetLinks));
          expect(pathValue, contains(cmakeBin));
          expect(pathValue, contains(ndkShaderDir));
          expect(pathValue, contains(r'C:\Users\Rob\AppData\Local\CustomTools'));
          expect(pathValue, contains('$msvcVerDir\\bin\\Hostx64\\x64'));
        },
      );

      test(
        'diagnoseBuildFailure detects locally installed Ninja + MSVC host compiler mismatch and patches CMakeLists idempotently',
        () async {
          final files = <String, String>{
            r'C:\Users\Rob\AppData\Local\Microsoft\WinGet\Links\ninja.exe':
                'bin',
            r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe':
                'bin',
            r'C:\proj\android\app\src\main\cpp\CMakeLists.txt':
                'cmake_minimum_required(VERSION 3.22.1)\r\n'
                    'project(gguf_engine)\r\n\r\n'
                    'add_subdirectory(stable-diffusion.cpp)\r\n'
                    'add_library(gguf_engine SHARED bridge.cpp)\r\n',
          };
          final dirs = <String>{
            r'C:\Program Files (x86)\Microsoft Visual Studio',
            r'C:\Program Files (x86)\Microsoft Visual Studio\2022',
            r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools',
            r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC',
            r'C:\proj\android\app\.cxx',
          };

          final service = AndroidDeviceRunnerService(
            isWindowsOverride: true,
            environmentProvider: () => const {
              'LOCALAPPDATA': r'C:\Users\Rob\AppData\Local',
              'ProgramFiles(x86)': r'C:\Program Files (x86)',
              'ProgramFiles': r'C:\Program Files',
              'Path': r'C:\Windows\System32',
            },
            fileExists: files.containsKey,
            dirExists: dirs.contains,
            readFileSync: (path) => files[path],
            writeFileSync: (path, content) {
              files[path] = content;
              return true;
            },
            deleteDirectorySync: (path) {
              dirs.remove(path);
              return true;
            },
            listSubdirectories: (dir) {
              if (dir ==
                  r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC') {
                return const [
                  r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207',
                ];
              }
              return const [];
            },
          );

          // 1) Ninja exists on disk but CMake complained about missing Ninja -> 1-click cache clear + relaunch
          final ninjaDiag = await service.diagnoseBuildFailure(
            const [
              'CMake Error: CMake was unable to find a build program corresponding to "Ninja".',
              'CMAKE_MAKE_PROGRAM is not set.',
            ],
            projectPath: r'C:\proj',
          );
          expect(ninjaDiag, isNotNull);
          expect(ninjaDiag!.issueType, AndroidBuildIssueType.cmakeBuildToolMissing);
          expect(ninjaDiag.canClearCxxCache, isTrue);
          expect(ninjaDiag.canAutoFixCmake, isTrue);
          expect(ninjaDiag.canFixCmakeHostToolchain, isFalse);

          // 2) Cross-compile vulkan-shaders-gen picked NDK clang.exe -> -lkernel32 failure -> 1-click MSVC/glslc CMake patch
          final hostDiag = await service.diagnoseBuildFailure(
            const [
              "Performing configure step for 'vulkan-shaders-gen'",
              ' host-toolchain.cmake -- Check for working C compiler: C:/Android/Sdk/ndk/28/clang.exe',
              'ld.lld: error: unable to find library -lkernel32',
              'is not able to compile a simple test program.',
            ],
            projectPath: r'C:\proj',
          );
          expect(hostDiag, isNotNull);
          expect(
            hostDiag!.issueType,
            AndroidBuildIssueType.cmakeHostCompilerMismatch,
          );
          expect(hostDiag.canFixCmakeHostToolchain, isTrue);
          expect(hostDiag.canClearCxxCache, isTrue);
          expect(hostDiag.canAutoFixCmake, isTrue);

          final ok1 = await service.applyWindowsHostToolchainCmakeFix(
            r'C:\proj',
            msvcCompilerPath: hostDiag.detectedToolPath,
          );
          expect(ok1, isTrue);
          final patchedContent =
              files[r'C:\proj\android\app\src\main\cpp\CMakeLists.txt']!;
          expect(patchedContent, contains('FLRD_WINDOWS_HOST_TOOLCHAIN_FIX'));
          expect(patchedContent, contains('HOST_C_COMPILER'));
          expect(patchedContent, contains('HOST_CXX_COMPILER'));
          expect(patchedContent, contains('Vulkan_GLSLC_EXECUTABLE'));
          expect(
            patchedContent.indexOf('FLRD_WINDOWS_HOST_TOOLCHAIN_FIX'),
            lessThan(patchedContent.indexOf('add_subdirectory(stable-diffusion.cpp)')),
          );

          // Idempotent on second call
          final ok2 = await service.applyWindowsHostToolchainCmakeFix(r'C:\proj');
          expect(ok2, isTrue);
          expect(
            files[r'C:\proj\android\app\src\main\cpp\CMakeLists.txt'],
            patchedContent,
          );

          expect(await service.clearAndroidCxxCache(r'C:\proj'), isTrue);
          expect(dirs.contains(r'C:\proj\android\app\.cxx'), isFalse);
        },
      );

      test(
        'TerminalShellService forwards refreshed PATH from buildEnvironmentResolver',
        () async {
          Map<String, String>? capturedEnv;
          final shellService = TerminalShellService(
            isWindowsOverride: true,
            dirExists: (_) => true,
            buildEnvironmentResolver: () async => const {
              'Path':
                  r'C:\Users\Rob\AppData\Local\Microsoft\WinGet\Links;C:\Windows\System32',
            },
            processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
              return ProcessResult(1, 0, r'C:\Program Files\PowerShell\7\pwsh.exe', '');
            },
            processEnvStarter: (
              exec,
              args, {
              workingDirectory,
              runInShell = true,
              environment,
            }) async {
              capturedEnv = environment;
              return _FakeProcess();
            },
          );

          await shellService.startInteractiveShell(
            workingDirectory: r'C:\Users\Rob\Downloads\snapia',
            profile: TerminalShellProfile.powerShell,
          );

          expect(
            capturedEnv?['Path'],
            contains(r'Microsoft\WinGet\Links'),
          );
        },
      );

      testWidgets(
        'AndroidDebugConsolePanel 1-click MSVC/Vulkan CMake fix patches file, clears .cxx, and relaunches with enriched env',
        (tester) async {
          final tempProj = Directory.systemTemp.createTempSync('flrd_cmake_fix_');
          File(p.join(tempProj.path, 'pubspec.yaml'))
              .writeAsStringSync('name: snapia\n');
          final cppDir = Directory(
            p.join(tempProj.path, 'android', 'app', 'src', 'main', 'cpp'),
          )..createSync(recursive: true);
          final cmakeFile = File(p.join(cppDir.path, 'CMakeLists.txt'))
            ..writeAsStringSync(
              'cmake_minimum_required(VERSION 3.22.1)\n'
              'project(gguf_engine)\n'
              'add_subdirectory(stable-diffusion.cpp)\n',
            );
          final cxxDir = Directory(p.join(tempProj.path, 'android', 'app', '.cxx'))
            ..createSync(recursive: true);
          addTearDown(() {
            if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
          });

          const clExe =
              r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe';
          const vcvarsBat =
              r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat';
          final appProcesses = <_FakeProcess>[];
          final launchEnvs = <Map<String, String>?>[];

          final androidService = AndroidDeviceRunnerService(
            isWindowsOverride: true,
            environmentProvider: () => const {
              'LOCALAPPDATA': r'C:\Users\Rob\AppData\Local',
              'ProgramFiles(x86)': r'C:\Program Files (x86)',
              'ProgramFiles': r'C:\Program Files',
              'Path': r'C:\Windows\System32',
            },
            fileExists: (path) =>
                path == clExe ||
                path == vcvarsBat ||
                (p.isWithin(tempProj.path, path) && File(path).existsSync()),
            dirExists: (path) =>
                path == r'C:\Program Files (x86)\Microsoft Visual Studio' ||
                path == r'C:\Program Files (x86)\Microsoft Visual Studio\2022' ||
                path == r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools' ||
                path ==
                    r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC' ||
                ((path == tempProj.path || p.isWithin(tempProj.path, path)) &&
                    Directory(path).existsSync()),
            listSubdirectories: (dir) {
              if (dir ==
                  r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC') {
                return const [
                  r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207',
                ];
              }
              return const [];
            },
            processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
              if (exec == 'cmd.exe' &&
                  args.any((a) => a.contains('vcvars64.bat'))) {
                expect(args, equals(['/c', 'call', vcvarsBat, '&&', 'set']));
                return ProcessResult(
                  20,
                  0,
                  'INCLUDE=C:\\VS\\include\r\nLIB=C:\\VS\\lib\r\nPath=C:\\VS\\bin\r\n',
                  '',
                );
              }
              return ProcessResult(21, 1, '', '');
            },
            processEnvStarter: (
              exec,
              args, {
              workingDirectory,
              runInShell = true,
              environment,
            }) async {
              launchEnvs.add(environment);
              final proc = _FakeProcess();
              appProcesses.add(proc);
              return proc;
            },
          );

          final container = ProviderContainer(
            overrides: [
              androidDeviceRunnerServiceProvider
                  .overrideWithValue(androidService),
            ],
          );
          addTearDown(container.dispose);

          container.read(terminalProvider.notifier).setPanelHeight(320.0);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: AndroidDebugConsolePanel(
                      projectPath: tempProj.path,
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final debugNotifier = container.read(androidDebugProvider.notifier);
          await debugNotifier.launchProject(
            tempProj.path,
            device: const ConnectedAndroidDevice(
              id: 'RXGL20BSBJX',
              name: 'SM S938B',
              targetPlatform: 'android-arm64',
              sdk: 'Android 16',
            ),
          );

          appProcesses.first.emitStdoutLine('[{"event":"app.start","params":{"appId":"1"}}]');
          appProcesses.first.emitStdoutLine(
            "Performing configure step for 'vulkan-shaders-gen'",
          );
          appProcesses.first.emitStdoutLine(
            'host-toolchain.cmake -- Check for working C compiler: clang.exe',
          );
          appProcesses.first.emitStdoutLine(
            'ld.lld: error: unable to find library -lkernel32',
          );
          appProcesses.first.emitStdoutLine('[{"event":"app.stop","params":{"appId":"1"}}]');
          appProcesses.first.completeExit(1);
          await tester.pump(const Duration(milliseconds: 60));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('android_fix_cmake_host_button')),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('android_fix_cmake_host_button')),
          );
          await tester.tap(
            find.byKey(const ValueKey('android_fix_cmake_host_button')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));

          expect(cxxDir.existsSync(), isFalse);
          final updatedCmake = cmakeFile.readAsStringSync();
          expect(updatedCmake, contains('FLRD_WINDOWS_HOST_TOOLCHAIN_FIX'));
          expect(updatedCmake, contains('HOST_C_COMPILER'));
          expect(appProcesses.length, 2);
          expect(launchEnvs.length, 2);
          expect(launchEnvs[1]?['INCLUDE'], r'C:\VS\include');
          expect(launchEnvs[1]?['LIB'], r'C:\VS\lib');

          await tester.pump(const Duration(seconds: 5));
        },
      );

      testWidgets(
        'AndroidDebugConsolePanel diagnoses cl.exe LNK1181/CMAKE_MT-NOTFOUND, stops Gradle daemon, clears .cxx, and relaunches',
        (tester) async {
          final tempProj = Directory.systemTemp.createTempSync('flrd_msvc_sdk_');
          File(p.join(tempProj.path, 'pubspec.yaml'))
              .writeAsStringSync('name: snapia\n');
          final androidDir = Directory(p.join(tempProj.path, 'android'))
            ..createSync(recursive: true);
          final gradlewFile = File(p.join(androidDir.path, 'gradlew.bat'))
            ..writeAsStringSync('@echo off\n');
          final cxxDir = Directory(p.join(tempProj.path, 'android', 'app', '.cxx'))
            ..createSync(recursive: true);
          addTearDown(() {
            if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
          });

          const vcvarsBat =
              r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat';
          final appProcesses = <_FakeProcess>[];
          final stoppedGradleCalls = <String>[];

          final androidService = AndroidDeviceRunnerService(
            isWindowsOverride: true,
            environmentProvider: () => const {
              'ProgramFiles(x86)': r'C:\Program Files (x86)',
              'ProgramFiles': r'C:\Program Files',
              'Path': r'C:\Windows\System32',
            },
            fileExists: (path) =>
                path == vcvarsBat ||
                path == gradlewFile.path ||
                (p.isWithin(tempProj.path, path) && File(path).existsSync()),
            dirExists: (path) =>
                path == r'C:\Program Files (x86)\Microsoft Visual Studio' ||
                path == r'C:\Program Files (x86)\Microsoft Visual Studio\2022' ||
                path == r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools' ||
                ((path == tempProj.path || p.isWithin(tempProj.path, path)) &&
                    Directory(path).existsSync()),
            listSubdirectories: (_) => const [],
            processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
              if (exec == 'cmd.exe' &&
                  args.length >= 3 &&
                  args[1] == 'call' &&
                  args[2] == vcvarsBat) {
                return ProcessResult(
                  30,
                  0,
                  'INCLUDE=C:\\VS\\include\r\nLIB=C:\\VS\\lib\r\nPath=C:\\VS\\bin\r\n',
                  '',
                );
              }
              if (exec == gradlewFile.path && args.contains('--stop')) {
                stoppedGradleCalls.add(exec);
                return ProcessResult(31, 0, 'Stopping Daemon', '');
              }
              return ProcessResult(32, 1, '', '');
            },
            processEnvStarter: (
              exec,
              args, {
              workingDirectory,
              runInShell = true,
              environment,
            }) async {
              final proc = _FakeProcess();
              appProcesses.add(proc);
              return proc;
            },
          );

          final container = ProviderContainer(
            overrides: [
              androidDeviceRunnerServiceProvider
                  .overrideWithValue(androidService),
            ],
          );
          addTearDown(container.dispose);

          container.read(terminalProvider.notifier).setPanelHeight(320.0);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: AndroidDebugConsolePanel(
                      projectPath: tempProj.path,
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final debugNotifier = container.read(androidDebugProvider.notifier);
          await debugNotifier.launchProject(
            tempProj.path,
            device: const ConnectedAndroidDevice(
              id: 'RXGL20BSBJX',
              name: 'SM S938B',
              targetPlatform: 'android-arm64',
              sdk: 'Android 16',
            ),
          );

          appProcesses.first.emitStdoutLine('[{"event":"app.start","params":{"appId":"1"}}]');
          appProcesses.first.emitStdoutLine(
            '-- Check for working C compiler: C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe - broken',
          );
          appProcesses.first.emitStdoutLine(
            'cmake.exe -E vs_link_exe --rc=rc --mt=CMAKE_MT-NOTFOUND -- link.exe',
          );
          appProcesses.first.emitStdoutLine(
            "LINK : fatal error LNK1181: não foi possível abrir o arquivo de entrada 'kernel32.lib'",
          );
          appProcesses.first.emitStdoutLine('[{"event":"app.stop","params":{"appId":"1"}}]');
          appProcesses.first.completeExit(1);
          await tester.pump(const Duration(milliseconds: 60));
          await tester.pumpAndSettle();

          expect(
            container.read(androidDebugProvider).buildDiagnostic?.issueType,
            AndroidBuildIssueType.cmakeMsvcEnvironmentMissing,
          );
          expect(
            find.byKey(const ValueKey('android_fix_cmake_msvc_env_button')),
            findsOneWidget,
          );

          await tester.ensureVisible(
            find.byKey(const ValueKey('android_fix_cmake_msvc_env_button')),
          );
          await tester.tap(
            find.byKey(const ValueKey('android_fix_cmake_msvc_env_button')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));

          expect(stoppedGradleCalls, equals([gradlewFile.path]));
          expect(cxxDir.existsSync(), isFalse);
          expect(appProcesses.length, 2);

          await tester.pump(const Duration(seconds: 5));
        },
      );
    });
  });

  group('Runtime Crash & Install Failure Classification', () {
    test(
      'classifies AdrenoVK shader/pipeline SIGSEGV crash ahead of generic SIGSEGV and extracts native + Java frame',
      () async {
        final service = AndroidDeviceRunnerService();
        final logs = <String>[
          'I/flutter (12345): Running inference on image...',
          'E/AdrenoVK-0(12345): Failed to link shaders.',
          'E/ggml-vulkan(12345): Pipeline create failed for shader mul_mat_f16',
          'F/libc    (12345): Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0',
          '      #00 pc 00000000001a2c34  /data/app/~~abc==/com.snapia-1/lib/arm64/libgguf_engine.so (generate_image+124)',
          '      #01 pc 0000000000084110  /vendor/lib64/hw/vulkan.adreno.so (vkCmdBindPipeline+64)',
          '      at com.snapia.MainActivity.processarGGUF(MainActivity.java:88)',
        ];

        final diag = await service.diagnoseBuildFailure(logs);
        expect(diag, isNotNull);
        expect(diag!.issueType, AndroidBuildIssueType.vulkanAdrenoPipelineCrash);
        expect(diag.isRuntimeCrash, isTrue);
        expect(diag.title, contains('Vulkan'));
        expect(diag.explanation.toLowerCase(), anyOf(contains('adreno'), contains('shader'), contains('pipeline')));
        expect(
          diag.affectedLocation,
          anyOf(
            contains('libgguf_engine.so'),
            contains('generate_image'),
            contains('vkCmdBindPipeline'),
            contains('MainActivity'),
          ),
        );
        expect(diag.crashSummary, isNotNull);
        expect(
          diag.steps.join(' '),
          anyOf(
            contains('GGML_VULKAN_COOPMAT'),
            contains('CPU'),
            contains('Vulkan'),
          ),
        );
        expect(diag.relevantLogLines, isNotEmpty);
      },
    );

    test(
      'classifies adb device not found and enables Re-detectar & Rodar action',
      () async {
        final service = AndroidDeviceRunnerService();
        final diag1 = await service.diagnoseBuildFailure(const [
          "adb.exe: device 'RXGL20BSBJX' not found",
          'Error: ADB exited with exit code 1',
        ]);
        expect(diag1, isNotNull);
        expect(diag1!.issueType, AndroidBuildIssueType.adbDeviceDisconnected);
        expect(diag1.canRescanAndRelaunch, isTrue);

        final diag2 = await service.diagnoseBuildFailure(const [
          'adb: error: no devices/emulators found',
        ]);
        expect(diag2, isNotNull);
        expect(diag2!.issueType, AndroidBuildIssueType.adbDeviceDisconnected);
        expect(diag2.canRescanAndRelaunch, isTrue);
      },
    );

    test(
      'classifies INSTALL_FAILED_* errors with concrete ADB explanation',
      () async {
        final service = AndroidDeviceRunnerService();
        final diag = await service.diagnoseBuildFailure(const [
          'Installing build\\app\\outputs\\flutter-apk\\app-debug.apk...',
          'adb: failed to install app-debug.apk: Failure [INSTALL_FAILED_VERSION_DOWNGRADE]',
          'Error launching application on SM S938B.',
        ]);
        expect(diag, isNotNull);
        expect(diag!.issueType, AndroidBuildIssueType.androidInstallFailed);
        expect(diag.crashSummary, contains('INSTALL_FAILED_VERSION_DOWNGRADE'));
      },
    );

    test(
      'classifies OutOfMemoryError / std::bad_alloc / OutOfDeviceMemory before SIGABRT',
      () async {
        final service = AndroidDeviceRunnerService();
        final javaOom = await service.diagnoseBuildFailure(const [
          'E/AndroidRuntime(999): java.lang.OutOfMemoryError: Failed to allocate a 67108876 byte allocation',
          'F/libc    (999): Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE)',
        ]);
        expect(javaOom, isNotNull);
        expect(javaOom!.issueType, AndroidBuildIssueType.androidOutOfMemory);
        expect(javaOom.isRuntimeCrash, isTrue);

        final cppOom = await service.diagnoseBuildFailure(const [
          'terminating with uncaught exception of type std::bad_alloc: std::bad_alloc',
          'Error: vk::OutOfDeviceMemoryError in allocator',
        ]);
        expect(cppOom, isNotNull);
        expect(cppOom!.issueType, AndroidBuildIssueType.androidOutOfMemory);
      },
    );

    test(
      'classifies native SIGSEGV / SIGABRT crashes with null pointer and .so backtrace',
      () async {
        final service = AndroidDeviceRunnerService();
        final diag = await service.diagnoseBuildFailure(const [
          'F/libc    (4510): Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0',
          'F/DEBUG   (4599): Cause: null pointer dereference',
          'F/DEBUG   (4599): backtrace:',
          'F/DEBUG   (4599):       #00 pc 0000000000041230  /data/app/~~xyz/lib/arm64/libimage_ops.so (apply_filter+48)',
        ]);
        expect(diag, isNotNull);
        expect(diag!.issueType, AndroidBuildIssueType.nativeCrashSigsegvOrSigabrt);
        expect(diag.isRuntimeCrash, isTrue);
        expect(diag.affectedLocation, contains('libimage_ops.so'));
        expect(diag.crashSummary, contains('SIGSEGV'));
      },
    );

    test(
      'classifies Dart Unhandled Exception and Flutter EXCEPTION CAUGHT BY with lib/*.dart line',
      () async {
        final service = AndroidDeviceRunnerService();
        final diag = await service.diagnoseBuildFailure(const [
          'E/flutter (2222): [ERROR:flutter/runtime/dart_vm_initializer.cc(41)] Unhandled Exception: Bad state: No element',
          'E/flutter (2222): #0      InferenceService.run (package:snapia/services/inference_service.dart:142:9)',
          'E/flutter (2222): #1      HomeScreen._generate (package:snapia/screens/home_screen.dart:85:5)',
        ]);
        expect(diag, isNotNull);
        expect(diag!.issueType, AndroidBuildIssueType.dartRuntimeException);
        expect(diag.isRuntimeCrash, isTrue);
        expect(
          diag.affectedLocation,
          anyOf(
            contains('inference_service.dart:142'),
            contains('package:snapia/services/inference_service.dart'),
          ),
        );

        final widgetEx = await service.diagnoseBuildFailure(const [
          '══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════════════════════════════════════',
          'The following RangeError was thrown building PreviewCard:',
          '#0      PreviewCard.build (lib/widgets/preview_card.dart:51:12)',
        ]);
        expect(widgetEx, isNotNull);
        expect(widgetEx!.issueType, AndroidBuildIssueType.dartRuntimeException);
        expect(widgetEx.affectedLocation, contains('preview_card.dart:51'));
      },
    );
  });

  group('AndroidDebugNotifier Runtime Crash, Heartbeat & Rescan', () {
    test(
      'detects AdrenoVK + vkCmdBindPipeline SIGSEGV after app.started and attaches diagnostic card',
      () async {
        final tempProj = Directory.systemTemp.createTempSync('flrd_rt_vk_');
        File(p.join(tempProj.path, 'pubspec.yaml'))
            .writeAsStringSync('name: snapia\n');
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );
        final notifier = AndroidDebugNotifier(service);
        addTearDown(notifier.dispose);

        await notifier.launchProject(
          tempProj.path,
          device: const ConnectedAndroidDevice(
            id: 'RXGL20BSBJX',
            name: 'SM S938B',
            targetPlatform: 'android-arm64',
            sdk: 'Android 16',
          ),
        );

        proc.emitStdoutLine('[{"event":"app.start","params":{"appId":"1"}}]');
        proc.emitStdoutLine('[{"event":"app.started","params":{"appId":"1"}}]');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(notifier.state.status, DeviceRunStatus.running);

        proc.emitStdoutLine('E/AdrenoVK-0: Failed to link shaders.');
        proc.emitStdoutLine('E/ggml-vulkan: Pipeline create failed');
        proc.emitStdoutLine(
            'F/libc: Fatal signal 11 (SIGSEGV), code 1, fault addr 0x0');
        proc.emitStdoutLine(
            '      #00 pc 00001a2c /data/local/tmp/libgguf_engine.so (generate_image+124)');
        proc.emitStdoutLine(
            '      #01 pc 00008410 /vendor/lib64/vulkan.adreno.so (vkCmdBindPipeline+64)');
        proc.emitStdoutLine('Lost connection to device.');
        proc.completeExit(1);

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(notifier.state.status, DeviceRunStatus.error);
        expect(notifier.state.buildDiagnostic, isNotNull);
        expect(
          notifier.state.buildDiagnostic!.issueType,
          AndroidBuildIssueType.vulkanAdrenoPipelineCrash,
        );
        expect(notifier.state.buildDiagnostic!.isRuntimeCrash, isTrue);
      },
    );

    test(
      'detects live Dart Unhandled Exception via app.log while app keeps running',
      () async {
        final tempProj = Directory.systemTemp.createTempSync('flrd_rt_dart_');
        File(p.join(tempProj.path, 'pubspec.yaml'))
            .writeAsStringSync('name: test_app\n');
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );
        final notifier = AndroidDebugNotifier(service);
        addTearDown(notifier.dispose);

        await notifier.launchProject(
          tempProj.path,
          device: const ConnectedAndroidDevice(
            id: 'PIX8001',
            name: 'Pixel 8',
            targetPlatform: 'android-arm64',
            sdk: 'Android 14',
          ),
        );

        proc.emitStdoutLine('[{"event":"app.start","params":{"appId":"1"}}]');
        proc.emitStdoutLine('[{"event":"app.started","params":{"appId":"1"}}]');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(notifier.state.status, DeviceRunStatus.running);

        proc.emitStdoutLine(
          jsonEncode([
            {
              'event': 'app.log',
              'params': {
                'error': true,
                'log':
                    'Unhandled Exception: StateError: Bad state\n#0 MainCtrl.go (package:test_app/main.dart:77:5)',
              },
            }
          ]),
        );

        await Future<void>.delayed(const Duration(milliseconds: 180));

        expect(notifier.state.status, DeviceRunStatus.running);
        expect(notifier.state.buildDiagnostic, isNotNull);
        expect(
          notifier.state.buildDiagnostic!.issueType,
          AndroidBuildIssueType.dartRuntimeException,
        );
        expect(
          notifier.state.buildDiagnostic!.affectedLocation,
          contains('main.dart:77'),
        );
      },
    );

    test(
      'emits periodic heartbeat logs during long Gradle/CMake build, stops on app.started, and never classifies user Stop as crash',
      () async {
        final tempProj = Directory.systemTemp.createTempSync('flrd_hb_');
        File(p.join(tempProj.path, 'pubspec.yaml'))
            .writeAsStringSync('name: native_app\n');
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processRunner: (exe, args, {workingDirectory, runInShell = true}) async {
            if (exe == 'taskkill') {
              proc.kill();
            }
            return ProcessResult(1, 0, '', '');
          },
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );
        final notifier = AndroidDebugNotifier(
          service,
          buildHeartbeatInterval: const Duration(milliseconds: 45),
        );
        addTearDown(notifier.dispose);

        await notifier.launchProject(
          tempProj.path,
          device: const ConnectedAndroidDevice(
            id: 'PIX8001',
            name: 'Pixel 8',
            targetPlatform: 'android-arm64',
            sdk: 'Android 14',
          ),
        );

        proc.emitStdoutLine(
          '[{"event":"app.progress","params":{"message":"Running Gradle task \'assembleDebug\'..."}}]',
        );
        await Future<void>.delayed(const Duration(milliseconds: 130));

        expect(
          notifier.state.logs.any(
            (e) =>
                e.message.contains('Compilação Gradle/C++/CMake em andamento'),
          ),
          isTrue,
        );

        final countBeforeStarted = notifier.state.logs
            .where((e) => e.message.contains('Compilação Gradle/C++/CMake'))
            .length;

        proc.emitStdoutLine('[{"event":"app.start","params":{"appId":"1"}}]');
        proc.emitStdoutLine('[{"event":"app.started","params":{"appId":"1"}}]');
        await Future<void>.delayed(const Duration(milliseconds: 120));

        final countAfterStarted = notifier.state.logs
            .where((e) => e.message.contains('Compilação Gradle/C++/CMake'))
            .length;
        expect(countAfterStarted, equals(countBeforeStarted));

        // User-requested stop must NOT produce runtime crash diagnostic even with non-zero exit
        await notifier.stopSession();
        proc.completeExit(1);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(notifier.state.status, DeviceRunStatus.idle);
        expect(notifier.state.buildDiagnostic, isNull);
      },
    );
  });

  group('GeminiAiService.diagnoseAndSuggestAppFix', () {
    test(
      'scans referenced local project files and calls Gemini API when apiKey and httpClient are provided',
      () async {
        final tempProj = Directory.systemTemp.createTempSync('flrd_ai_diag_');
        File(p.join(tempProj.path, 'pubspec.yaml'))
            .writeAsStringSync('name: snapia\n');
        Directory(p.join(tempProj.path, 'lib')).createSync(recursive: true);
        File(p.join(tempProj.path, 'lib', 'main.dart')).writeAsStringSync(
          'void main() { /* run snapia */ }\n',
        );
        final cppDir =
            Directory(p.join(tempProj.path, 'android', 'app', 'src', 'main', 'cpp'))
              ..createSync(recursive: true);
        File(p.join(cppDir.path, 'CMakeLists.txt')).writeAsStringSync(
          'add_definitions(-DGGML_USE_VULKAN)\n',
        );
        File(p.join(cppDir.path, 'gguf_engine.cpp')).writeAsStringSync(
          'void generate_image() { /* vkCmdBindPipeline */ }\n',
        );
        addTearDown(() {
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        Uri? capturedUri;
        String? capturedBody;
        final fakeClient = _FakeAiHttpClient((request) async {
          capturedUri = request.url;
          capturedBody = request.body;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text':
                            '1. **Causa Raiz Exata**: AdrenoVK falhou ao linkar shader FP16.\n2. Desative GGML_VULKAN_COOPMAT.',
                      }
                    ]
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final suggestion = await GeminiAiService.diagnoseAndSuggestAppFix(
          projectPath: tempProj.path,
          issueTitle: 'Crash Vulkan/Adreno ao criar pipeline ou linkar shaders',
          affectedLocation: 'libgguf_engine.so (generate_image+124)',
          crashLogs: const [
            'E/AdrenoVK-0: Failed to link shaders.',
            'E/ggml-vulkan: Pipeline create failed',
            'Fatal signal 11 (SIGSEGV)',
          ],
          apiKey: 'fake-gemini-key',
          httpClient: fakeClient,
        );

        expect(capturedUri, isNotNull);
        expect(capturedUri.toString(),
            contains('generativelanguage.googleapis.com'));
        expect(capturedUri.toString(), contains('gemini-1.5-flash'));
        expect(capturedBody, contains('CMakeLists.txt'));
        expect(capturedBody, contains('GGML_USE_VULKAN'));
        expect(capturedBody, contains('Failed to link shaders'));
        expect(suggestion, contains('Causa Raiz Exata'));
        expect(suggestion, contains('GGML_VULKAN_COOPMAT'));
      },
    );

    test(
      'returns structured Portuguese offline engineering fallback without API key or on HTTP error',
      () async {
        final offline = await GeminiAiService.diagnoseAndSuggestAppFix(
          projectPath: '',
          issueTitle: 'Crash Vulkan/Adreno ao criar pipeline ou linkar shaders',
          affectedLocation: 'vkCmdBindPipeline',
          crashLogs: const [
            'AdrenoVK-0: Failed to link shaders.',
            'Fatal signal 11 (SIGSEGV)',
          ],
          apiKey: null,
        );

        expect(offline, contains('Causa Raiz'));
        expect(offline.toLowerCase(), contains('vulkan'));
        expect(
          offline,
          anyOf(contains('GGML_VULKAN_COOPMAT'), contains('CPU')),
        );

        final failingClient = _FakeAiHttpClient((_) async {
          return http.Response('Internal Server Error', 500);
        });
        final httpFallback = await GeminiAiService.diagnoseAndSuggestAppFix(
          projectPath: '',
          issueTitle: 'Memória / VRAM Esgotada (OutOfMemoryError)',
          crashLogs: const ['java.lang.OutOfMemoryError: Failed to allocate'],
          apiKey: 'fake-key',
          httpClient: failingClient,
        );
        expect(httpFallback, contains('Causa Raiz'));
        expect(httpFallback.toLowerCase(), anyOf(contains('memória'), contains('vram')));
      },
    );
  });

  group('AndroidDebugConsolePanel Runtime Crash & AI Fix UI', () {
    testWidgets(
      'displays Vulkan runtime crash card, runs 1-click AI diagnosis and copies solution & report',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        String? copiedClipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map?;
            copiedClipboardText = args?['text'] as String?;
          }
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final tempProj = Directory.systemTemp.createTempSync('flrd_panel_ai_');
        File(p.join(tempProj.path, 'pubspec.yaml'))
            .writeAsStringSync('name: snapia\n');
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );
        final fakeClient = _FakeAiHttpClient((_) async {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text':
                            'Solução IA: Desabilite GGML_VULKAN_COOPMAT no CMakeLists.txt e reduza a resolução para 512x512.',
                      }
                    ]
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final container = ProviderContainer(
          overrides: [
            androidDeviceRunnerServiceProvider.overrideWithValue(service),
            aiDiagnosticHttpClientProvider.overrideWithValue(fakeClient),
            aiSettingsProvider.overrideWith(
              (ref) => AiSettingsNotifier(
                const AiSettingsState(apiKey: 'fake-gemini-key'),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: AndroidDebugConsolePanel(
                    projectPath: tempProj.path,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final notifier = container.read(androidDebugProvider.notifier);
        await notifier.launchProject(
          tempProj.path,
          device: const ConnectedAndroidDevice(
            id: 'RXGL20BSBJX',
            name: 'SM S938B',
            targetPlatform: 'android-arm64',
            sdk: 'Android 16',
          ),
        );

        proc.emitStdoutLine('[{"event":"app.start","params":{"appId":"1"}}]');
        proc.emitStdoutLine('[{"event":"app.started","params":{"appId":"1"}}]');
        await tester.pump();

        proc.emitStdoutLine('E/AdrenoVK-0: Failed to link shaders.');
        proc.emitStdoutLine('E/ggml-vulkan: Pipeline create failed');
        proc.emitStdoutLine(
            'F/libc: Fatal signal 11 (SIGSEGV), code 1, fault addr 0x0');
        proc.emitStdoutLine(
            '      #00 pc 00001a2c /data/app/libgguf_engine.so (generate_image+124)');
        proc.emitStdoutLine(
            '      #01 pc 00008410 /vendor/lib64/vulkan.adreno.so (vkCmdBindPipeline+64)');
        proc.emitStdoutLine('Lost connection to device.');
        proc.completeExit(1);

        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('android_runtime_crash_badge')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('android_ai_diagnose_button')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('android_copy_ai_report_button')),
            findsOneWidget);

        // Trigger AI diagnosis button
        await tester.ensureVisible(
          find.byKey(const ValueKey('android_ai_diagnose_button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('android_ai_diagnose_button')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('android_ai_fix_box')), findsOneWidget);
        expect(
          find.textContaining('Desabilite GGML_VULKAN_COOPMAT'),
          findsOneWidget,
        );

        // Copy AI fix
        await tester.ensureVisible(
          find.byKey(const ValueKey('android_copy_ai_fix_button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('android_copy_ai_fix_button')),
        );
        await tester.pump();
        expect(copiedClipboardText, contains('Desabilite GGML_VULKAN_COOPMAT'));

        // Copy full AI report
        await tester.ensureVisible(
          find.byKey(const ValueKey('android_copy_ai_report_button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('android_copy_ai_report_button')),
        );
        await tester.pump();
        expect(
          copiedClipboardText,
          contains('=== FLRD Android Diagnostic Report ==='),
        );
        expect(copiedClipboardText, contains('Failed to link shaders'));

        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'displays Re-detectar & Rodar button on adb disconnect and relaunches when device reconnects',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final tempProj = Directory.systemTemp.createTempSync('flrd_adb_rescan_');
        File(p.join(tempProj.path, 'pubspec.yaml'))
            .writeAsStringSync('name: snapia\n');
        final procs = <_FakeProcess>[];
        var deviceConnectedOnScan = false;
        addTearDown(() async {
          for (final proc in procs) {
            await proc.disposeStreams();
          }
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processRunner: (exe, args, {workingDirectory, runInShell = true}) async {
            if (exe == 'flutter' &&
                args.isNotEmpty &&
                args.first == 'devices') {
              if (!deviceConnectedOnScan) {
                return ProcessResult(1, 0, '[]', '');
              }
              return ProcessResult(
                1,
                0,
                jsonEncode([
                  {
                    'name': 'SM S938B',
                    'id': 'RXGL20BSBJX',
                    'isSupported': true,
                    'targetPlatform': 'android-arm64',
                    'emulator': false,
                    'sdk': 'Android 16',
                  },
                ]),
                '',
              );
            }
            return ProcessResult(2, 0, '', '');
          },
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async {
            final proc = _FakeProcess();
            procs.add(proc);
            return proc;
          },
        );

        final container = ProviderContainer(
          overrides: [
            androidDeviceRunnerServiceProvider.overrideWithValue(service),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: AndroidDebugConsolePanel(
                    projectPath: tempProj.path,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final notifier = container.read(androidDebugProvider.notifier);
        await notifier.launchProject(
          tempProj.path,
          device: const ConnectedAndroidDevice(
            id: 'RXGL20BSBJX',
            name: 'SM S938B',
            targetPlatform: 'android-arm64',
            sdk: 'Android 16',
          ),
        );

        procs.first.emitStdoutLine("adb.exe: device 'RXGL20BSBJX' not found");
        procs.first.emitStdoutLine('Error: ADB exited with exit code 1');
        procs.first.completeExit(1);

        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('android_rescan_and_run_button')),
            findsOneWidget);

        // User replugs USB cable and taps Re-detectar & Rodar
        deviceConnectedOnScan = true;
        await tester.ensureVisible(
          find.byKey(const ValueKey('android_rescan_and_run_button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('android_rescan_and_run_button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(procs.length, 2);

        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}

class _FakeAiHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) _handler;

  _FakeAiHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    final response = await _handler(req);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([response.bodyBytes]),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
