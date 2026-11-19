import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flrd/features/studio/models/connected_device.dart';
import 'package:flrd/features/studio/providers/android_debug_provider.dart';
import 'package:flrd/features/studio/providers/terminal_provider.dart';
import 'package:flrd/features/studio/services/android_device_runner_service.dart';
import 'package:flrd/features/studio/services/terminal_shell_service.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeSink implements IOSink {
  final List<String> writtenLines = <String>[];
  final Completer<void> _done = Completer<void>();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => write(encoding.decode(data));

  @override
  void write(Object? object) {
    final text = object?.toString() ?? '';
    for (final line in text.split('\n')) {
      if (line.isNotEmpty) writtenLines.add(line);
    }
  }

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

class _FakeProc implements Process {
  final StreamController<List<int>> out = StreamController<List<int>>.broadcast();
  final StreamController<List<int>> err = StreamController<List<int>>.broadcast();
  final _FakeSink sink = _FakeSink();
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  @override
  int get pid => 55555;

  void emitLine(String line) {
    if (!out.isClosed) out.add(utf8.encode('$line\n'));
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => out.stream;

  @override
  Stream<List<int>> get stderr => err.stream;

  @override
  IOSink get stdin => sink;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }

  Future<void> dispose() async {
    await sink.close();
    if (!out.isClosed) await out.close();
    if (!err.isClosed) await err.close();
  }
}

void main() {
  group('Cross-platform CI path & OS regression tests', () {
    test(
      'Windows override on POSIX-rooted projectPath preserves POSIX slashes for project files and Windows slashes for Windows SDK paths',
      () async {
        const fakePosixProject = '/tmp/flrd_linux_ci_proj';
        const expectedCmakePath =
            '/tmp/flrd_linux_ci_proj/android/app/src/main/cpp/CMakeLists.txt';
        const expectedCxxPath = '/tmp/flrd_linux_ci_proj/android/app/.cxx';
        const expectedGradlewPath = '/tmp/flrd_linux_ci_proj/android/gradlew.bat';
        const clExe =
            r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe';
        const sdkPath = r'C:\FakeLocal\Android\Sdk';
        const adbPath = r'C:\FakeLocal\Android\Sdk\platform-tools\adb.exe';

        String? writtenCmakePath;
        String? writtenCmakeContent;
        String? deletedCxxPath;
        String? stoppedGradlePath;

        final service = AndroidDeviceRunnerService(
          isWindowsOverride: true,
          environmentProvider: () => const {
            'LOCALAPPDATA': r'C:\FakeLocal',
            'ProgramFiles(x86)': r'C:\Program Files (x86)',
            'ProgramFiles': r'C:\Program Files',
          },
          dirExists: (path) =>
              path == sdkPath ||
              path == expectedCxxPath ||
              path == r'C:\Program Files (x86)\Microsoft Visual Studio' ||
              path == r'C:\Program Files (x86)\Microsoft Visual Studio\2022' ||
              path ==
                  r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools' ||
              path ==
                  r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC',
          fileExists: (path) =>
              path == adbPath ||
              path == clExe ||
              path == expectedCmakePath ||
              path == expectedGradlewPath,
          listSubdirectories: (dir) => dir ==
                  r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC'
              ? const [
                  r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207',
                ]
              : const [],
          readFileSync: (path) => path == expectedCmakePath
              ? 'cmake_minimum_required(VERSION 3.22.1)\nproject(app)\nadd_subdirectory(sd)\n'
              : null,
          writeFileSync: (path, content) {
            writtenCmakePath = path;
            writtenCmakeContent = content;
            return true;
          },
          deleteDirectorySync: (path) {
            deletedCxxPath = path;
            return true;
          },
          processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
            if (exec == 'flutter') return ProcessResult(1, 0, '[]', '');
            if (exec == 'java') return ProcessResult(2, 0, 'openjdk 17', '');
            if (exec == adbPath) {
              return ProcessResult(
                3,
                0,
                'List of devices attached\nRXGL20BSBJX unauthorized usb:1-2\n',
                '',
              );
            }
            if (exec == expectedGradlewPath && args.contains('--stop')) {
              stoppedGradlePath = exec;
              return ProcessResult(4, 0, 'Stopping Daemon', '');
            }
            return ProcessResult(5, 1, '', '');
          },
        );

        final diag = await service.scanAndroidEnvironment();
        expect(diag.issueType, AndroidConnectionIssueType.unauthorized);

        final patched =
            await service.applyWindowsHostToolchainCmakeFix(fakePosixProject);
        expect(patched, isTrue);
        expect(writtenCmakePath, expectedCmakePath);
        expect(writtenCmakeContent, contains('FLRD_WINDOWS_HOST_TOOLCHAIN_FIX'));

        final cleared = await service.clearAndroidCxxCache(fakePosixProject);
        expect(cleared, isTrue);
        expect(deletedCxxPath, expectedCxxPath);

        final stopped = await service.stopProjectGradleDaemons(
          projectPath: fakePosixProject,
        );
        expect(stopped, isTrue);
        expect(stoppedGradlePath, expectedGradlewPath);
      },
    );

    testWidgets(
      'AppStudioScreen live Android session lifecycle works cleanly under POSIX/Linux overrides',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final tempDir = Directory.systemTemp.createTempSync('flrd_linux_studio_');
        File(p.join(tempDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: linux_app\nversion: 1.0.0\n');
        final fakeProc = _FakeProc();
        addTearDown(() async {
          await fakeProc.dispose();
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final fakeService = AndroidDeviceRunnerService(
          isWindowsOverride: false,
          processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
            if (exec == 'flutter' && args.isNotEmpty && args.first == 'devices') {
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
            return ProcessResult(2, 0, '', '');
          },
          processStarter: (exec, args, {workingDirectory, runInShell = true}) async =>
              fakeProc,
        );

        final fakeShellService = TerminalShellService(isWindowsOverride: false);

        final project = RegisteredProject(
          id: 'proj-linux-test',
          name: 'android_live_app',
          orgId: 'com.example',
          path: tempDir.path,
          preset: PresetType.saas,
          navigationStyle: NavigationStyle.tabs,
          permissions: const {},
          lastModified: DateTime(2026),
          routeCount: 4,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              androidDeviceRunnerServiceProvider.overrideWithValue(fakeService),
              terminalShellServiceProvider.overrideWithValue(fakeShellService),
            ],
            child: MaterialApp(home: AppStudioScreen(project: project)),
          ),
        );
        await tester.pumpAndSettle();

        await tester
            .tap(find.byKey(const ValueKey('android_scan_devices_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('android_launch_button')));
        await tester.pumpAndSettle();

        fakeProc.emitLine(
          '[{"event":"app.start","params":{"appId":"app-linux-1"}}]',
        );
        fakeProc.emitLine(
          '[{"event":"app.started","params":{"appId":"app-linux-1"}}]',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Ao Vivo • Pixel 8'), findsOneWidget);

        await tester
            .tap(find.byKey(const ValueKey('android_hot_reload_button')));
        await tester.pump();
        expect(
          fakeProc.sink.writtenLines.any((l) => l.contains('app.restart')),
          isTrue,
        );

        await tester
            .tap(find.byKey(const ValueKey('android_close_console_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('android_logs_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('android_stop_button')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(fakeProc.killed, isTrue);
        expect(find.byKey(const ValueKey('android_launch_button')),
            findsOneWidget);
      },
    );
  });
}
