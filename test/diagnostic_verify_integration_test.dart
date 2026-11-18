import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flrd/features/ai/services/dart_verification_service.dart';
import 'package:flrd/features/studio/models/connected_device.dart';
import 'package:flrd/features/studio/providers/android_debug_provider.dart';
import 'package:flrd/features/studio/services/android_device_runner_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeIOSink implements IOSink {
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  void write(Object? object) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
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

  @override
  int get pid => 81818;

  void emitStdoutLine(String line) {
    if (!stdoutController.isClosed) {
      stdoutController.add(utf8.encode('$line\n'));
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

class _RecordedVerifyCall {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;

  const _RecordedVerifyCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });
}

const ConnectedAndroidDevice _testDevice = ConnectedAndroidDevice(
  id: 'RXGL20BSBJX',
  name: 'SM S938B',
  targetPlatform: 'android-arm64',
  sdk: 'Android 16',
);

const List<String> _dartCompileFailureLogs = <String>[
  'Launching lib\\main.dart on SM S938B in debug mode...',
  "Running Gradle task 'assembleDebug'...",
  'Your project is configured to compile against Android SDK 36, but the following plugin(s) require to be compiled against a higher Android SDK version:',
  '- permission_handler_android compiles against Android SDK 37',
  "lib/core/theme/app_theme.dart:18:73: Error: The argument type 'TextTheme/*1*/' can't be assigned to the parameter type 'TextTheme/*2*/?'.",
  " - 'TextTheme/*1*/' is from 'package:flutter/src/material/text_theme.dart'.",
  " - 'TextTheme/*2*/' is from 'package:material_ui/src/text_theme.dart'.",
  '      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme),',
  '                                                                        ^',
  "lib/core/theme/app_theme.dart:37:72: Error: The argument type 'TextTheme/*1*/' can't be assigned to the parameter type 'TextTheme/*2*/?'.",
  '      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),',
  '                                                                       ^',
  'Target kernel_snapshot_program failed: Exception',
  "Execution failed for task ':app:compileFlutterBuildDebug'.",
  'Error: Gradle task assembleDebug failed with exit code 1',
];

const String _brokenAppThemeDart = '''
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.light,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.dark,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),
    );
  }
}
''';

Future<Directory> _createSampleProject({
  String prefix = 'flrd_diag_verify_',
}) async {
  final tempProj = Directory.systemTemp.createTempSync(prefix);
  File(p.join(tempProj.path, 'pubspec.yaml'))
    ..createSync(recursive: true)
    ..writeAsStringSync('name: sample_app\n');
  File(p.join(tempProj.path, 'lib', 'core', 'theme', 'app_theme.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_brokenAppThemeDart);
  File(p.join(tempProj.path, 'android', 'app', 'build.gradle.kts'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
android {
    compileSdk = 36
}
''');
  return tempProj;
}

Future<void> _triggerBuildDiagnostic(
  AndroidDebugNotifier notifier,
  _FakeProcess proc,
  String projectPath,
) async {
  final launched = await notifier.launchProject(
    projectPath,
    device: _testDevice,
  );
  expect(launched, isTrue);

  for (final line in _dartCompileFailureLogs) {
    proc.emitStdoutLine(line);
  }
  proc.completeExit(1);

  for (var i = 0; i < 40; i++) {
    if (notifier.state.buildDiagnostic != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(notifier.state.buildDiagnostic, isNotNull);
}

void main() {
  group('AndroidDebugNotifier post-patch flutter analyze verification', () {
    test(
      'runs DartVerificationService on patched .dart files and logs passing verification',
      () async {
        final tempProj = await _createSampleProject();
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );

        final verifyCalls = <_RecordedVerifyCall>[];
        Future<ProcessResult> mockRunner(
          String exe,
          List<String> args, {
          String? workingDirectory,
        }) async {
          verifyCalls.add(
            _RecordedVerifyCall(
              executable: exe,
              arguments: List<String>.from(args),
              workingDirectory: workingDirectory,
            ),
          );
          return ProcessResult(
            101,
            0,
            'Analyzing lib/core/theme/app_theme.dart...\nNo issues found! (ran in 1.0s)',
            '',
          );
        }
        final VerificationProcessRunner typedRunner = mockRunner;
        final notifier = AndroidDebugNotifier(
          service,
          verificationProcessRunner: typedRunner,
        );
        addTearDown(notifier.dispose);

        await _triggerBuildDiagnostic(notifier, proc, tempProj.path);
        expect(notifier.state.buildDiagnostic!.suggestedPatches.length, 3);

        final applyResult = await notifier.applyDiagnosticPatches(
          projectPath: tempProj.path,
        );

        expect(applyResult.isSuccess, isTrue);
        expect(verifyCalls, hasLength(1));
        expect(
          verifyCalls.single.arguments,
          equals([
            'analyze',
            '--no-fatal-infos',
            'lib/core/theme/app_theme.dart',
          ]),
        );
        expect(
          verifyCalls.single.workingDirectory,
          equals(p.normalize(p.absolute(tempProj.path))),
        );
        expect(notifier.state.isApplyingBuildFix, isFalse);
        expect(notifier.state.buildDiagnostic?.lastAppliedBackupDir, isNotNull);

        final matchingLogs = notifier.state.logs.where(
          (entry) =>
              entry.message ==
              '✅ Verificação flutter analyze aprovada em 1 arquivo(s) Dart.',
        );
        expect(matchingLogs, hasLength(1));
        expect(matchingLogs.single.isSystem, isTrue);
        expect(matchingLogs.single.isResolution, isTrue);
        expect(matchingLogs.single.isError, isFalse);
      },
    );

    test(
      'logs exact error count and first error summary when post-patch flutter analyze fails, keeping backup revertable',
      () async {
        final tempProj = await _createSampleProject();
        final appThemeFile = File(
          p.join(tempProj.path, 'lib', 'core', 'theme', 'app_theme.dart'),
        );
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );

        final notifier = AndroidDebugNotifier(
          service,
          verificationProcessRunner: (exe, args, {workingDirectory}) async {
            return ProcessResult(
              102,
              1,
              '''
   error • Undefined name 'brokenSymbolAfterPatch' • lib/core/theme/app_theme.dart:18:10 • undefined_identifier
   error • Expected ';' after this • lib/core/theme/app_theme.dart:24:1 • expected_token
''',
              '',
            );
          },
        );
        addTearDown(notifier.dispose);

        await _triggerBuildDiagnostic(notifier, proc, tempProj.path);

        final applyResult = await notifier.applyDiagnosticPatches(
          projectPath: tempProj.path,
        );

        expect(applyResult.isSuccess, isTrue);
        expect(notifier.state.isApplyingBuildFix, isFalse);
        expect(notifier.state.buildDiagnostic?.lastAppliedBackupDir, isNotNull);

        final errorLogs = notifier.state.logs.where(
          (entry) => entry.message.contains('flutter analyze reportou'),
        );
        expect(errorLogs, hasLength(1));
        final errLog = errorLogs.single;
        expect(
          errLog.message,
          equals(
            "⚠️ flutter analyze reportou 2 erro(s) após o patch: lib/core/theme/app_theme.dart:18: Undefined name 'brokenSymbolAfterPatch' — use Reverter Patches se necessário.",
          ),
        );
        expect(errLog.isError, isTrue);
        expect(errLog.isResolution, isFalse);

        // User can immediately revert the faulty patch via the preserved backup
        final reverted = await notifier.revertLastDiagnosticPatches(
          projectPath: tempProj.path,
        );
        expect(reverted, isTrue);
        expect(appThemeFile.readAsStringSync(), equals(_brokenAppThemeDart));
      },
    );

    test(
      'verifies multiple modified Dart files and reports exact file count',
      () async {
        final tempProj = await _createSampleProject();
        final fileA = File(p.join(tempProj.path, 'lib', 'a.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('const int a = 1;\n');
        final fileB = File(p.join(tempProj.path, 'lib', 'b.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('const int b = 2;\n');
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );

        final verifyCalls = <_RecordedVerifyCall>[];
        final notifier = AndroidDebugNotifier(
          service,
          verificationProcessRunner: (exe, args, {workingDirectory}) async {
            verifyCalls.add(
              _RecordedVerifyCall(
                executable: exe,
                arguments: List<String>.from(args),
                workingDirectory: workingDirectory,
              ),
            );
            return ProcessResult(103, 0, 'No issues found!', '');
          },
        );
        addTearDown(notifier.dispose);

        await _triggerBuildDiagnostic(notifier, proc, tempProj.path);

        final applyResult = await notifier.applyDiagnosticPatches(
          projectPath: tempProj.path,
          selectedPatches: const [
            DiagnosticFilePatch(
              relativePath: 'lib/a.dart',
              description: 'Update a.dart',
              searchText: 'const int a = 1;',
              replaceText: 'const int a = 10;',
            ),
            DiagnosticFilePatch(
              relativePath: 'lib/b.dart',
              description: 'Update b.dart',
              searchText: 'const int b = 2;',
              replaceText: 'const int b = 20;',
            ),
          ],
        );

        expect(applyResult.isSuccess, isTrue);
        expect(fileA.readAsStringSync(), contains('a = 10'));
        expect(fileB.readAsStringSync(), contains('b = 20'));
        expect(verifyCalls, hasLength(1));
        expect(
          verifyCalls.single.arguments,
          equals(['analyze', '--no-fatal-infos', 'lib/a.dart', 'lib/b.dart']),
        );
        expect(
          notifier.state.logs.any(
            (e) =>
                e.message ==
                '✅ Verificação flutter analyze aprovada em 2 arquivo(s) Dart.',
          ),
          isTrue,
        );
      },
    );

    test(
      'skips DartVerificationService when only non-Dart files are modified',
      () async {
        final tempProj = await _createSampleProject();
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );

        var verifyInvoked = false;
        final notifier = AndroidDebugNotifier(
          service,
          verificationProcessRunner: (exe, args, {workingDirectory}) async {
            verifyInvoked = true;
            return ProcessResult(104, 0, 'No issues found!', '');
          },
        );
        addTearDown(notifier.dispose);

        await _triggerBuildDiagnostic(notifier, proc, tempProj.path);

        final gradlePatch = notifier.state.buildDiagnostic!.suggestedPatches
            .firstWhere((patch) => patch.relativePath.endsWith('.kts'));

        final applyResult = await notifier.applyDiagnosticPatches(
          projectPath: tempProj.path,
          selectedPatches: [gradlePatch],
        );

        expect(applyResult.isSuccess, isTrue);
        expect(verifyInvoked, isFalse);
        expect(
          notifier.state.logs.any(
            (e) => e.message.contains('flutter analyze'),
          ),
          isFalse,
        );
      },
    );

    test(
      'skips subprocess inside FLUTTER_TEST when verificationProcessRunner is null',
      () async {
        final tempProj = await _createSampleProject();
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );

        // Default verificationProcessRunner is null
        final notifier = AndroidDebugNotifier(service);
        addTearDown(notifier.dispose);

        await _triggerBuildDiagnostic(notifier, proc, tempProj.path);

        final applyResult = await notifier.applyDiagnosticPatches(
          projectPath: tempProj.path,
        );

        expect(applyResult.isSuccess, isTrue);
        expect(notifier.state.isApplyingBuildFix, isFalse);
        expect(
          notifier.state.logs.any(
            (e) => e.message.contains('flutter analyze'),
          ),
          isFalse,
        );
      },
    );

    test(
      'supports Riverpod override via diagnosticVerificationProcessRunnerProvider',
      () async {
        final tempProj = await _createSampleProject();
        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
        );

        final container = ProviderContainer(
          overrides: [
            androidDeviceRunnerServiceProvider.overrideWithValue(service),
            diagnosticVerificationProcessRunnerProvider.overrideWithValue(
              (exe, args, {workingDirectory}) async => ProcessResult(
                105,
                1,
                "lib/core/theme/app_theme.dart:12:3: Error: Undefined name 'x'.",
                '',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(androidDebugProvider.notifier);
        await _triggerBuildDiagnostic(notifier, proc, tempProj.path);

        final applyResult = await notifier.applyDiagnosticPatches(
          projectPath: tempProj.path,
        );
        expect(applyResult.isSuccess, isTrue);

        final state = container.read(androidDebugProvider);
        expect(
          state.logs.any(
            (e) =>
                e.isError &&
                e.message ==
                    "⚠️ flutter analyze reportou 1 erro(s) após o patch: lib/core/theme/app_theme.dart:12: Undefined name 'x'. — use Reverter Patches se necessário.",
          ),
          isTrue,
        );
      },
    );
  });
}
