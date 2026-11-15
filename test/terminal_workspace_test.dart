import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/models/terminal_session.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/providers/android_debug_provider.dart';
import 'package:flrd/features/studio/providers/terminal_provider.dart';
import 'package:flrd/features/studio/services/android_device_runner_service.dart';
import 'package:flrd/features/studio/services/terminal_shell_service.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeSink implements IOSink {
  final List<String> writtenLines = <String>[];
  final StringBuffer _buf = StringBuffer();
  final Completer<void> _done = Completer<void>();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => write(encoding.decode(data));

  @override
  void write(Object? object) {
    _buf.write(object?.toString() ?? '');
    final raw = _buf.toString();
    if (raw.contains('\n')) {
      final parts = raw.split('\n');
      for (var i = 0; i < parts.length - 1; i++) {
        if (parts[i].isNotEmpty) writtenLines.add(parts[i]);
      }
      _buf
        ..clear()
        ..write(parts.last);
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
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (_buf.isNotEmpty) {
      writtenLines.add(_buf.toString());
      _buf.clear();
    }
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

class _FakeShellProcess implements Process {
  _FakeShellProcess({this.pidValue = 4242});

  final int pidValue;
  final _FakeSink fakeStdin = _FakeSink();
  final StreamController<List<int>> _stdoutCtrl =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderrCtrl =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exitCompleter = Completer<int>();
  bool killed = false;

  void emitStdoutLine(String line) {
    if (!_stdoutCtrl.isClosed) _stdoutCtrl.add(utf8.encode('$line\n'));
  }

  void emitStderrLine(String line) {
    if (!_stderrCtrl.isClosed) _stderrCtrl.add(utf8.encode('$line\n'));
  }

  void finishWithExitCode(int code) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
    _stdoutCtrl.close();
    _stderrCtrl.close();
  }

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finishWithExitCode(-1);
    return true;
  }

  @override
  int get pid => pidValue;

  @override
  IOSink get stdin => fakeStdin;

  @override
  Stream<List<int>> get stdout => _stdoutCtrl.stream;

  @override
  Stream<List<int>> get stderr => _stderrCtrl.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TerminalShellService & TerminalNotifier Unit Tests', () {
    test('stripAnsiCodes removes CSI and OSC escape sequences', () {
      const raw = '\x1B[32mSuccess\x1B[0m \x1B]0;Window Title\x07Done';
      expect(TerminalShellService.stripAnsiCodes(raw), 'Success Done');
    });

    test('resolveShellCommand maps Windows PowerShell/CMD and Unix shells', () {
      final winService = TerminalShellService(
        isWindowsOverride: true,
        dirExists: (_) => true,
      );
      final ps = winService.resolveShellCommand(TerminalShellProfile.powerShell);
      expect(ps.executable, 'cmd.exe');
      expect(ps.arguments.join(' '), contains('powershell.exe'));
      expect(ps.initCommands, isNotEmpty);

      final cmd = winService.resolveShellCommand(TerminalShellProfile.cmd);
      expect(cmd.executable, 'cmd.exe');
      expect(cmd.arguments, contains('/K'));

      final macService = TerminalShellService(
        isWindowsOverride: false,
        environmentProvider: () => const {'SHELL': '/bin/zsh'},
        dirExists: (_) => true,
      );
      final zsh = macService.resolveShellCommand(TerminalShellProfile.systemShell);
      expect(zsh.executable, '/bin/zsh');
    });

    test('TerminalNotifier manages multiple persistent tabs and keeps exited tabs alive', () async {
      final spawned = <_FakeShellProcess>[];
      final killedPids = <int>[];
      var nextPid = 9001;

      final shellService = TerminalShellService(
        isWindowsOverride: true,
        dirExists: (_) => true,
        processStarter: (exe, args, {workingDirectory, runInShell = true}) async {
          final proc = _FakeShellProcess(pidValue: nextPid++);
          spawned.add(proc);
          return proc;
        },
        processRunner: (exe, args, {workingDirectory, runInShell = true}) async {
          if (exe == 'taskkill') {
            final pid = int.tryParse(args.last) ?? -1;
            killedPids.add(pid);
            for (final p in spawned) {
              if (p.pid == pid) p.kill();
            }
          }
          return ProcessResult(1, 0, '', '');
        },
      );

      final container = ProviderContainer(
        overrides: [
          terminalShellServiceProvider.overrideWithValue(shellService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(terminalProvider.notifier);

      // Starts with pinned Debug Android tab that cannot be closed.
      expect(container.read(terminalProvider).tabs.length, 1);
      expect(
        container.read(terminalProvider).activeTabId,
        TerminalWorkspaceState.debugTabId,
      );
      await notifier.closeTab(TerminalWorkspaceState.debugTabId);
      expect(container.read(terminalProvider).tabs.length, 1);

      // Create 2 interactive shells just like VS Code.
      final tab1 = await notifier.createShellTerminal(
        workingDirectory: r'C:\proj',
        profile: TerminalShellProfile.powerShell,
      );
      final tab2 = await notifier.createShellTerminal(
        workingDirectory: r'C:\proj',
        profile: TerminalShellProfile.cmd,
      );

      expect(container.read(terminalProvider).tabs.length, 3);
      expect(container.read(terminalProvider).interactiveShellCount, 2);
      expect(container.read(terminalProvider).activeTabId, tab2);

      // Send commands & verify independent stdout/stderr buffers + history.
      await notifier.sendCommand(tab1, 'flutter devices');
      spawned[0].emitStdoutLine('Galaxy S25 Ultra • connected');
      spawned[1].emitStderrLine('some warning on cmd');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final session1 =
          container.read(terminalProvider).tabs.firstWhere((t) => t.id == tab1);
      final session2 =
          container.read(terminalProvider).tabs.firstWhere((t) => t.id == tab2);
      expect(
        spawned[0].fakeStdin.writtenLines,
        contains('flutter devices'),
      );
      expect(
        session1.lines.map((l) => l.text).join('\n'),
        contains('Galaxy S25 Ultra • connected'),
      );
      expect(session1.commandHistory, ['flutter devices']);
      expect(
        session2.lines.any((l) => l.isError && l.text.contains('some warning')),
        isTrue,
      );

      // Simulate process failure / exit in tab1 -> tab MUST remain open & respawn cleanly.
      spawned[0].finishWithExitCode(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final exitedTab1 =
          container.read(terminalProvider).tabs.firstWhere((t) => t.id == tab1);
      expect(exitedTab1.status, TerminalProcessStatus.exited);
      expect(exitedTab1.exitCode, 1);
      expect(
        exitedTab1.lines.last.text,
        contains('O terminal permanece aberto'),
      );

      // Sending a new command into exited tab1 transparently restarts shell.
      await notifier.sendCommand(tab1, 'flutter doctor');
      expect(spawned.length, 3);
      expect(
        spawned[2].fakeStdin.writtenLines,
        contains('flutter doctor'),
      );
      final revivedTab1 =
          container.read(terminalProvider).tabs.firstWhere((t) => t.id == tab1);
      expect(revivedTab1.status, TerminalProcessStatus.running);

      // Closing tab2 kills its process tree without affecting tab1 or Debug Android.
      await notifier.closeTab(tab2);
      expect(killedPids, contains(spawned[1].pid));
      expect(container.read(terminalProvider).tabs.length, 2);
      expect(container.read(terminalProvider).tabs.any((t) => t.id == tab1), isTrue);
    });
  });

  group('VS Code Persistent Multi-Tab Terminal Widget Tests', () {
    late Directory tempProjectDir;

    setUp(() {
      tempProjectDir = Directory.systemTemp.createTempSync('flrd_term_widget_');
      File(p.join(tempProjectDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: demo_term_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      Directory(p.join(tempProjectDir.path, 'lib')).createSync();
    });

    tearDown(() {
      if (tempProjectDir.existsSync()) {
        tempProjectDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'Terminal stays open after Android disconnect/error and supports multiple interactive shells',
      (tester) async {
        tester.view.physicalSize = const Size(1360, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final debugProcesses = <_FakeShellProcess>[];
        final shellProcesses = <_FakeShellProcess>[];
        var nextPid = 5000;

        final androidService = AndroidDeviceRunnerService(
          isWindowsOverride: true,
          processRunner: (exe, args, {workingDirectory, runInShell = true}) async {
            if (exe == 'flutter' &&
                args.isNotEmpty &&
                args.first == 'devices') {
              return ProcessResult(
                1,
                0,
                jsonEncode([
                  {
                    'name': 'Galaxy S25 Ultra',
                    'id': 'S25U-01',
                    'isSupported': true,
                    'targetPlatform': 'android-arm64',
                    'emulator': false,
                    'sdk': 'Android 15',
                  },
                ]),
                '',
              );
            }
            if (exe == 'taskkill') {
              final pid = int.tryParse(args.last) ?? -1;
              for (final p in [...debugProcesses, ...shellProcesses]) {
                if (p.pid == pid) p.kill();
              }
            }
            return ProcessResult(2, 0, '', '');
          },
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async {
            final proc = _FakeShellProcess(pidValue: nextPid++);
            debugProcesses.add(proc);
            return proc;
          },
        );

        final shellService = TerminalShellService(
          isWindowsOverride: true,
          dirExists: (_) => true,
          processRunner: (exe, args, {workingDirectory, runInShell = true}) async {
            if (exe == 'taskkill') {
              final pid = int.tryParse(args.last) ?? -1;
              for (final p in shellProcesses) {
                if (p.pid == pid) p.kill();
              }
            }
            return ProcessResult(3, 0, '', '');
          },
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async {
            final proc = _FakeShellProcess(pidValue: nextPid++);
            shellProcesses.add(proc);
            return proc;
          },
        );

        final project = RegisteredProject(
          id: 'proj-term-1',
          name: 'demo_term_app',
          orgId: 'com.example',
          path: tempProjectDir.path,
          preset: PresetType.saas,
          navigationStyle: NavigationStyle.tabs,
          permissions: const {},
          lastModified: DateTime(2026),
          routeCount: 1,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              androidDeviceRunnerServiceProvider
                  .overrideWithValue(androidService),
              terminalShellServiceProvider.overrideWithValue(shellService),
            ],
            child: MaterialApp(
              home: AppStudioScreen(project: project),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // 1. Terminal toggle pill is always accessible even before launching.
        expect(find.byKey(const ValueKey('android_logs_button')), findsOneWidget);

        // 2. Scan and launch on Galaxy S25 Ultra -> opens persistent terminal.
        await tester.tap(find.byKey(const ValueKey('android_scan_devices_button')));
        await tester.pumpAndSettle();
        // Allow the 3s AppToast SnackBar to expire so it does not cover bottom controls.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('android_launch_button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('android_debug_console_panel')),
          findsOneWidget,
        );

        debugProcesses.first.emitStdoutLine(
          '[{"event":"app.start","params":{"appId":"app-s25"}}]',
        );
        debugProcesses.first.emitStdoutLine(
          '[{"event":"app.started","params":{"appId":"app-s25"}}]',
        );
        await tester.pumpAndSettle();

        // 3. Phone disconnects / exits cleanly OR fails -> terminal MUST NOT DIE.
        debugProcesses.first.emitStdoutLine(
          '[{"event":"app.stop","params":{"appId":"app-s25"}}]',
        );
        debugProcesses.first.finishWithExitCode(0);
        await tester.pumpAndSettle();

        // Fake simulator remains absent on stop/disconnect, AND terminal stays visible!
        expect(find.byKey(const ValueKey('anchored_live_preview_pane')), findsNothing);
        expect(
          find.byKey(const ValueKey('android_debug_console_panel')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Terminal mantido aberto'),
          findsOneWidget,
        );

        // 4. Launching a second time preserves previous run logs instead of wiping.
        await tester.tap(find.byKey(const ValueKey('android_launch_button')));
        await tester.pumpAndSettle();
        debugProcesses.last.finishWithExitCode(1);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('android_debug_console_panel')),
          findsOneWidget,
        );
        expect(find.textContaining('código 1'), findsWidgets);

        // 5. Create two extra persistent shell terminals using "+ Novo Terminal".
        await tester.tap(find.byKey(const ValueKey('terminal_add_tab_button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('terminal_tab_shell-1')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('terminal_add_tab_button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('terminal_tab_shell-2')),
          findsOneWidget,
        );
        expect(shellProcesses.length, 2);

        // 6. Execute interactive command in active terminal tab (shell-2).
        await tester.enterText(
          find.byKey(const ValueKey('terminal_command_input')),
          'adb devices -l',
        );
        await tester.tap(
          find.byKey(const ValueKey('terminal_send_command_button')),
        );
        shellProcesses[1].emitStdoutLine('List of devices attached: S25U-01');
        await tester.pumpAndSettle();

        expect(
          shellProcesses[1].fakeStdin.writtenLines,
          contains('adb devices -l'),
        );
        expect(
          find.textContaining('List of devices attached: S25U-01'),
          findsOneWidget,
        );

        // 7. Close shell-2 while keeping shell-1 & Debug Android intact.
        await tester.tap(
          find.byKey(const ValueKey('terminal_close_tab_shell-2')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('terminal_tab_shell-2')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('terminal_tab_shell-1')),
          findsOneWidget,
        );

        // 8. Minimize and reopen panel -> extra terminal tab is still open!
        await tester.tap(
          find.byKey(const ValueKey('android_close_console_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('android_debug_console_panel')),
          findsNothing,
        );

        await tester.tap(find.byKey(const ValueKey('android_logs_button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('android_debug_console_panel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('terminal_tab_shell-1')),
          findsOneWidget,
        );
      },
    );
  });
}
