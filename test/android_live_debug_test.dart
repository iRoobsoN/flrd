import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/models/connected_device.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/device_screen_emulator.dart';
import 'package:flrd/features/studio/presentation/widgets/embedded_code_viewer.dart';
import 'package:flrd/features/studio/providers/android_debug_provider.dart';
import 'package:flrd/features/studio/services/android_device_runner_service.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
      'launching on connected Android device hides internal simulator and stopping restores it',
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

        // Initially: simulator visible on right, Android USB scan button visible.
        expect(find.byKey(const ValueKey('anchored_live_preview_pane')),
            findsOneWidget);
        expect(find.byType(DeviceScreenEmulator), findsOneWidget);
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
        // Simulator stays visible until user actually launches on device
        expect(find.byKey(const ValueKey('anchored_live_preview_pane')),
            findsOneWidget);

        // Launch app on Pixel 8 -> internal simulator MUST be hidden automatically
        await tester.tap(find.byKey(const ValueKey('android_launch_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('anchored_live_preview_pane')),
            findsNothing);
        expect(find.byType(DeviceScreenEmulator), findsNothing);
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

        // Stop session -> simulator MUST be restored automatically
        await tester.tap(find.byKey(const ValueKey('android_stop_button')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('anchored_live_preview_pane')),
            findsOneWidget);
        expect(find.byType(DeviceScreenEmulator), findsOneWidget);
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
}
