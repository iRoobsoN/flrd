import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flrd/features/generator/presets/preset_file_helper.dart';
import 'package:flrd/features/studio/models/connected_device.dart';
import 'package:flrd/features/studio/presentation/widgets/android_debug_controls.dart';
import 'package:flrd/features/studio/providers/android_debug_provider.dart';
import 'package:flrd/features/studio/services/android_device_runner_service.dart';
import 'package:flrd/features/studio/services/diagnostic_code_fix_service.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flutter/material.dart';
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
  int get pid => 91919;

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

const List<String> _realReportedFailureLogs = <String>[
  'Launching lib\\main.dart on SM S938B in debug mode...',
  "Running Gradle task 'assembleDebug'...",
  'Warning: The plugin permission_handler_android requires Android SDK version 37 or higher.',
  'For more information about build configuration, see https://flutter.dev/to/review-gradle-config.',
  'Your project is configured to compile against Android SDK 36, but the following plugin(s) require to be compiled against a higher Android SDK version:',
  '- permission_handler_android compiles against Android SDK 37',
  r'Add the following to C:\Projects\minha_massagem_teste\android\app\build.gradle.kts:',
  '    android {',
  '        compileSdk = 37',
  '        ...',
  '    }',
  "lib/core/theme/app_theme.dart:18:73: Error: The argument type 'TextTheme/*1*/' can't be assigned to the parameter type 'TextTheme/*2*/?'.",
  " - 'TextTheme/*1*/' is from 'package:flutter/src/material/text_theme.dart' ('/C:/src/flutter/packages/flutter/lib/src/material/text_theme.dart').",
  " - 'TextTheme/*2*/' is from 'package:material_ui/src/text_theme.dart' ('/C:/Users/Rob/AppData/Local/Pub/Cache/hosted/pub.dev/material_ui-1.11.1/lib/src/text_theme.dart').",
  '      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme),',
  '                                                                        ^',
  "lib/core/theme/app_theme.dart:37:72: Error: The argument type 'TextTheme/*1*/' can't be assigned to the parameter type 'TextTheme/*2*/?'.",
  " - 'TextTheme/*1*/' is from 'package:flutter/src/material/text_theme.dart' ('/C:/src/flutter/packages/flutter/lib/src/material/text_theme.dart').",
  " - 'TextTheme/*2*/' is from 'package:material_ui/src/text_theme.dart' ('/C:/Users/Rob/AppData/Local/Pub/Cache/hosted/pub.dev/material_ui-1.11.1/lib/src/text_theme.dart').",
  '      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),',
  '                                                                       ^',
  'Target kernel_snapshot_program failed: Exception',
  "Execution failed for task ':app:compileFlutterBuildDebug'.",
  'BUILD FAILED in 3m 21s',
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

void main() {
  group('Dart compile & Gradle compileSdk diagnostics', () {
    test(
      'diagnoses google_fonts TextTheme conflict + compileSdk 37 requirement and creates valid multi-file patches with backup/revert',
      () async {
        final tempProj = Directory.systemTemp.createTempSync('flrd_diag_fix_');
        addTearDown(() {
          if (tempProj.existsSync()) {
            tempProj.deleteSync(recursive: true);
          }
        });

        final appThemeFile = File(
          p.join(tempProj.path, 'lib', 'core', 'theme', 'app_theme.dart'),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync(_brokenAppThemeDart);

        const originalGradleKts = '''
android {
    namespace = "com.example.app"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        minSdk = 24
        targetSdk = 36
    }
}
''';
        final gradleKtsFile = File(
          p.join(tempProj.path, 'android', 'app', 'build.gradle.kts'),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync(originalGradleKts);

        final runner = AndroidDeviceRunnerService();
        final baseDiagnostic = runner.classifyBuildFailureLogs(
          _realReportedFailureLogs,
        );
        expect(baseDiagnostic, isNotNull);
        expect(
          baseDiagnostic!.issueType,
          AndroidBuildIssueType.dartCompileError,
        );
        expect(baseDiagnostic.affectedLocation, contains('app_theme.dart'));
        expect(baseDiagnostic.explanation, contains('compileSdk = 37'));
        expect(
          baseDiagnostic.steps.any((s) => s.contains('fontFamily')),
          isTrue,
        );

        final enriched =
            DiagnosticCodeFixService.enrichDiagnosticWithLocalAnalysis(
          baseDiagnostic,
          projectPath: tempProj.path,
          crashLogs: _realReportedFailureLogs,
        );

        expect(enriched.suggestedPatches.length, 3);
        expect(
          enriched.suggestedPatches
              .where((patch) => patch.relativePath == 'lib/core/theme/app_theme.dart')
              .length,
          2,
        );
        expect(
          enriched.suggestedPatches.any(
            (patch) =>
                patch.relativePath == 'android/app/build.gradle.kts' &&
                patch.replaceText.contains('compileSdk = 37'),
          ),
          isTrue,
        );

        final terminalLines =
            DiagnosticCodeFixService.formatTerminalResolutionLines(enriched);
        expect(
          terminalLines.any((l) => l.contains('SUGESTÃO DE RESOLUÇÃO')),
          isTrue,
        );
        expect(
          terminalLines.any(
            (l) => l.contains('Patches prontos para aplicar (3)'),
          ),
          isTrue,
        );

        final applyResult = await DiagnosticCodeFixService.applyPatches(
          projectPath: tempProj.path,
          patches: enriched.suggestedPatches,
        );
        expect(applyResult.errorMessage, isNull);
        expect(applyResult.appliedCount, 2);
        expect(applyResult.backupDir, isNotNull);

        final patchedTheme = appThemeFile.readAsStringSync();
        expect(patchedTheme, isNot(contains('plusJakartaSansTextTheme')));
        expect(
          RegExp(r'fontFamily: GoogleFonts\.plusJakartaSans\(\)\.fontFamily,')
              .allMatches(patchedTheme)
              .length,
          2,
        );

        final patchedGradle = gradleKtsFile.readAsStringSync();
        expect(patchedGradle, contains('compileSdk = 37'));
        expect(patchedGradle, isNot(contains('flutter.compileSdkVersion')));

        final restored = await DiagnosticCodeFixService.revertBackup(
          projectPath: tempProj.path,
          backupDir: applyResult.backupDir!,
        );
        expect(restored.length, 2);
        expect(appThemeFile.readAsStringSync(), _brokenAppThemeDart);
        expect(gradleKtsFile.readAsStringSync(), originalGradleKts);
      },
    );

    test(
      'handles identical GoogleFonts.interTextTheme() calls and ThemeData.copyWith safely',
      () async {
        final tempProj = Directory.systemTemp.createTempSync('flrd_dup_theme_');
        addTearDown(() {
          if (tempProj.existsSync()) {
            tempProj.deleteSync(recursive: true);
          }
        });

        const identicalAndCopyWithTheme = '''
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        textTheme: GoogleFonts.interTextTheme(),
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        textTheme: GoogleFonts.interTextTheme(),
      );

  static ThemeData get copied => ThemeData.light().copyWith(
        textTheme: GoogleFonts.robotoTextTheme(ThemeData.light().textTheme),
      );
}
''';
        final themeFile = File(
          p.join(tempProj.path, 'lib', 'core', 'theme', 'app_theme.dart'),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync(identicalAndCopyWithTheme);

        final logs = <String>[
          "lib/core/theme/app_theme.dart:7:20: Error: The argument type 'TextTheme/*1*/' can't be assigned to the parameter type 'TextTheme/*2*/?'.",
          " - 'TextTheme/*2*/' is from 'package:material_ui/src/text_theme.dart'",
          '      textTheme: GoogleFonts.interTextTheme(),',
        ];

        final analysis = DiagnosticCodeFixService.analyzeProjectLocally(
          projectPath: tempProj.path,
          issueTitle: 'Erro GoogleFonts TextTheme',
          crashLogs: logs,
          affectedLocation: 'lib/core/theme/app_theme.dart:7',
        );

        expect(analysis.patches.length, 3);
        final valid = DiagnosticCodeFixService.filterValidPatches(
          projectPath: tempProj.path,
          patches: analysis.patches,
        );
        expect(valid.length, 3);

        final applied = await DiagnosticCodeFixService.applyPatches(
          projectPath: tempProj.path,
          patches: valid,
        );
        expect(applied.errorMessage, isNull);

        final updated = themeFile.readAsStringSync();
        expect(updated, isNot(contains('interTextTheme')));
        expect(updated, isNot(contains('robotoTextTheme')));
        expect(
          RegExp(r'fontFamily: GoogleFonts\.inter\(\)\.fontFamily,')
              .allMatches(updated)
              .length,
          2,
        );
        expect(
          updated,
          contains(
            'textTheme: (ThemeData.light().textTheme).apply(fontFamily: GoogleFonts.roboto().fontFamily),',
          ),
        );
      },
    );

    test(
      'classifies standalone Groovy compileSdkVersion mismatch and generates patch',
      () async {
        final tempProj = Directory.systemTemp.createTempSync('flrd_groovy_sdk_');
        addTearDown(() {
          if (tempProj.existsSync()) {
            tempProj.deleteSync(recursive: true);
          }
        });

        final gradleFile = File(
          p.join(tempProj.path, 'android', 'app', 'build.gradle'),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync('''
android {
    compileSdkVersion 35
    defaultConfig {
        minSdkVersion 24
    }
}
''');

        const logs = <String>[
          'Warning: The plugin permission_handler_android requires Android SDK version 37 or higher.',
          'Your project is configured to compile against Android SDK 35, but the following plugin(s) require to be compiled against a higher Android SDK version:',
          '- permission_handler_android compiles against Android SDK 37',
          'FAILURE: Build failed with an exception.',
        ];

        final runner = AndroidDeviceRunnerService();
        final base = runner.classifyBuildFailureLogs(logs);
        expect(base, isNotNull);
        expect(base!.issueType, AndroidBuildIssueType.androidCompileSdkTooLow);
        expect(base.title, contains('37'));
        expect(base.explanation, contains('permission_handler_android'));

        final enriched =
            DiagnosticCodeFixService.enrichDiagnosticWithLocalAnalysis(
          base,
          projectPath: tempProj.path,
          crashLogs: logs,
        );
        expect(enriched.suggestedPatches.length, 1);

        final apply = await DiagnosticCodeFixService.applyPatches(
          projectPath: tempProj.path,
          patches: enriched.suggestedPatches,
        );
        expect(apply.appliedCount, 1);
        expect(gradleFile.readAsStringSync(), contains('compileSdkVersion 37'));
      },
    );

    test(
      'classifies general Dart compile errors with exact file and message',
      () {
        const logs = <String>[
          "lib/screens/home_screen.dart:42:11: Error: Undefined name 'missingSymbol'.",
          'Target kernel_snapshot_program failed: Exception',
          "Execution failed for task ':app:compileFlutterBuildDebug'.",
          'BUILD FAILED in 12s',
        ];

        final runner = AndroidDeviceRunnerService();
        final diagnostic = runner.classifyBuildFailureLogs(logs);
        expect(diagnostic, isNotNull);
        expect(diagnostic!.issueType, AndroidBuildIssueType.dartCompileError);
        expect(diagnostic.affectedLocation, 'lib/screens/home_screen.dart:42');
        expect(diagnostic.explanation, contains('missingSymbol'));

        final resolutionLines =
            DiagnosticCodeFixService.formatTerminalResolutionLines(diagnostic);
        expect(
          resolutionLines.any((l) => l.contains('home_screen.dart')),
          isTrue,
        );
      },
    );

    test(
      'PresetFileHelper.writeAppTheme emits fontFamily without GoogleFonts TextTheme helper',
      () async {
        final tempProj = Directory.systemTemp.createTempSync('flrd_preset_theme_');
        addTearDown(() {
          if (tempProj.existsSync()) {
            tempProj.deleteSync(recursive: true);
          }
        });

        await PresetFileHelper.writeAppTheme(
          targetPath: tempProj.path,
          config: const ProjectConfig(enableDarkTheme: true),
        );

        final generated = File(
          p.join(tempProj.path, 'lib', 'core', 'theme', 'app_theme.dart'),
        ).readAsStringSync();
        expect(generated, isNot(contains('plusJakartaSansTextTheme')));
        expect(
          RegExp(r'fontFamily: GoogleFonts\.plusJakartaSans\(\)\.fontFamily,')
              .allMatches(generated)
              .length,
          2,
        );
      },
    );

    testWidgets(
      'AndroidDebugConsolePanel surfaces Dart + compileSdk diagnostic card and applies all 3 patches on click',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final tempProj = Directory.systemTemp.createTempSync('flrd_widget_diag_');
        addTearDown(() {
          if (tempProj.existsSync()) {
            tempProj.deleteSync(recursive: true);
          }
        });

        File(p.join(tempProj.path, 'pubspec.yaml'))
          ..createSync(recursive: true)
          ..writeAsStringSync('name: sample_app\n');

        final appThemeFile = File(
          p.join(tempProj.path, 'lib', 'core', 'theme', 'app_theme.dart'),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync(_brokenAppThemeDart);

        final gradleFile = File(
          p.join(tempProj.path, 'android', 'app', 'build.gradle.kts'),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync('''
android {
    compileSdk = 36
}
''');

        final proc = _FakeProcess();
        addTearDown(() async {
          await proc.disposeStreams();
        });

        final service = AndroidDeviceRunnerService(
          processStarter: (exe, args, {workingDirectory, runInShell = true}) async =>
              proc,
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

        for (final line in _realReportedFailureLogs) {
          proc.emitStdoutLine(line);
        }
        proc.completeExit(1);

        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        final debugState = container.read(androidDebugProvider);
        expect(debugState.buildDiagnostic, isNotNull);
        expect(
          debugState.buildDiagnostic!.issueType,
          AndroidBuildIssueType.dartCompileError,
        );
        expect(debugState.buildDiagnostic!.suggestedPatches.length, 3);
        expect(
          debugState.logs.any(
            (l) => l.isResolution && l.message.contains('SUGESTÃO DE RESOLUÇÃO'),
          ),
          isTrue,
        );

        expect(
          find.byKey(const ValueKey('android_build_diagnostic_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('android_apply_patches_button')),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('android_apply_patches_button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('android_apply_patches_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('android_patch_preview_dialog')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('confirm_apply_patches_button')),
        );
        await tester.pumpAndSettle();

        expect(
          appThemeFile.readAsStringSync(),
          isNot(contains('plusJakartaSansTextTheme')),
        );
        expect(gradleFile.readAsStringSync(), contains('compileSdk = 37'));
        expect(
          find.byKey(const ValueKey('android_applied_fix_badge')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('android_revert_patches_button')),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}
