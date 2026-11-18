import 'dart:convert';
import 'dart:io';

import 'package:flrd/features/ai/services/dart_verification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class _MockAiHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  _MockAiHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final httpRequest = request as http.Request;
    final response = await handler(httpRequest);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

Directory _createTempFlutterProject({String name = 'sample_app'}) {
  final dir = Directory.systemTemp.createTempSync('flrd_verify_test_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $name
description: Test project
version: 1.0.0
environment:
  sdk: ">=3.2.0 <4.0.0"
''');
  return dir;
}

void main() {
  group('DartVerificationService.parseAnalyzerOutput & verifyDartFiles', () {
    test('clean "No issues found!" output returns passed=true and empty errors',
        () async {
      final projectDir = _createTempFlutterProject();
      File(p.join(projectDir.path, 'lib', 'main.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}\n');

      String? capturedExecutable;
      List<String>? capturedArgs;
      String? capturedWorkingDir;

      final result = await DartVerificationService.verifyDartFiles(
        projectPath: projectDir.path,
        flutterExecutablePath: '/custom/bin/flutter',
        processRunner: (executable, arguments, {workingDirectory}) async {
          capturedExecutable = executable;
          capturedArgs = arguments;
          capturedWorkingDir = workingDirectory;
          return ProcessResult(
            101,
            0,
            'Analyzing sample_app...\nNo issues found! (ran in 1.1s)\n',
            '',
          );
        },
      );

      expect(capturedExecutable, '/custom/bin/flutter');
      expect(capturedArgs, equals(['analyze', '--no-fatal-infos']));
      expect(
        capturedWorkingDir,
        p.normalize(p.absolute(projectDir.path)),
      );
      expect(result.passed, isTrue);
      expect(result.skipped, isFalse);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.infos, isEmpty);
      expect(result.errorSummary, isNull);
      expect(result.rawOutput, contains('No issues found!'));
    });

    test(
        'parses real Flutter analyzer error output into structured DartVerificationIssue',
        () async {
      final projectDir = _createTempFlutterProject();
      const analyzerOutput = '''
Analyzing sample_app...

  error • Undefined name 'AppColors' • lib/screens/home.dart:14:9 • undefined_identifier

1 issue found. (ran in 0.9s)
''';

      final result = await DartVerificationService.verifyDartFiles(
        projectPath: projectDir.path,
        processRunner: (executable, arguments, {workingDirectory}) async {
          return ProcessResult(102, 1, analyzerOutput, '');
        },
      );

      expect(result.passed, isFalse);
      expect(result.skipped, isFalse);
      expect(result.errors, hasLength(1));
      expect(result.warnings, isEmpty);

      final issue = result.errors.single;
      expect(issue.severity, 'error');
      expect(issue.message, "Undefined name 'AppColors'");
      expect(issue.filePath, 'lib/screens/home.dart');
      expect(issue.line, 14);
      expect(issue.column, 9);
      expect(issue.code, 'undefined_identifier');
      expect(result.errorSummary, contains('lib/screens/home.dart:14'));
      expect(result.errorSummary, contains("Undefined name 'AppColors'"));
    });

    test(
        'parses Windows/short compiler format, dash format, warnings, and infos accurately',
        () async {
      final projectDir = _createTempFlutterProject();
      final absMainPath = p.normalize(
        p.join(p.absolute(projectDir.path), 'lib', 'main.dart'),
      );
      final mixedOutput = '''
\x1B[31mlib\\screens\\home.dart:14:9: Error: Undefined name 'AppColors'.\x1B[0m
$absMainPath:5: Warning: Unused helper reference
  error - lib\\screens\\profile.dart:21:4 - Missing return statement. - missing_return
warning • Unused import: 'dart:math' • lib/main.dart:2:8 • unused_import
   info • Prefer const with constant constructors • lib/main.dart:8:5 • prefer_const_constructors
''';

      final result = await DartVerificationService.verifyDartFiles(
        projectPath: projectDir.path,
        processRunner: (executable, arguments, {workingDirectory}) async {
          return ProcessResult(103, 1, mixedOutput, '');
        },
      );

      expect(result.passed, isFalse);
      expect(result.errors, hasLength(2));
      expect(result.errors[0].severity, 'error');
      expect(result.errors[0].filePath, 'lib/screens/home.dart');
      expect(result.errors[0].line, 14);
      expect(result.errors[0].column, 9);
      expect(result.errors[0].message, "Undefined name 'AppColors'.");

      expect(result.errors[1].severity, 'error');
      expect(result.errors[1].filePath, 'lib/screens/profile.dart');
      expect(result.errors[1].line, 21);
      expect(result.errors[1].column, 4);
      expect(result.errors[1].message, 'Missing return statement.');
      expect(result.errors[1].code, 'missing_return');

      expect(result.warnings, hasLength(2));
      expect(result.warnings[0].filePath, 'lib/main.dart');
      expect(result.warnings[0].line, 5);
      expect(result.warnings[1].code, 'unused_import');

      expect(result.infos, hasLength(1));
      expect(result.infos[0].severity, 'info');
      expect(result.infos[0].code, 'prefer_const_constructors');
    });

    test('passed is true only when exitCode == 0 and errors is empty', () async {
      final projectDir = _createTempFlutterProject();

      final warningPass = await DartVerificationService.verifyDartFiles(
        projectPath: projectDir.path,
        processRunner: (executable, arguments, {workingDirectory}) async {
          return ProcessResult(
            1,
            0,
            "warning • Unused import: 'dart:math' • lib/main.dart:1:8 • unused_import\n",
            '',
          );
        },
      );
      expect(warningPass.passed, isTrue);
      expect(warningPass.warnings, hasLength(1));
      expect(warningPass.errors, isEmpty);

      final nonZeroFail = await DartVerificationService.verifyDartFiles(
        projectPath: projectDir.path,
        processRunner: (executable, arguments, {workingDirectory}) async {
          return ProcessResult(
            2,
            2,
            '',
            'Pub failed to resolve dependencies.\n',
          );
        },
      );
      expect(nonZeroFail.passed, isFalse);
      expect(nonZeroFail.skipped, isFalse);
      expect(nonZeroFail.errors, isEmpty);
      expect(nonZeroFail.errorSummary, contains('exitCode=2'));
    });

    test(
        'filters targetFiles to existing .dart files strictly inside projectPath',
        () async {
      final projectDir = _createTempFlutterProject();
      final homeFile = File(p.join(projectDir.path, 'lib', 'screens', 'home.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('class Home {}\n');
      File(p.join(projectDir.path, 'README.md')).writeAsStringSync('# Readme');

      final outsideDir = Directory.systemTemp.createTempSync('flrd_outside_');
      addTearDown(() {
        if (outsideDir.existsSync()) outsideDir.deleteSync(recursive: true);
      });
      final outsideDart = File(p.join(outsideDir.path, 'outside.dart'))
        ..writeAsStringSync('void hack() {}\n');

      List<String>? capturedArgs;
      final result = await DartVerificationService.verifyDartFiles(
        projectPath: projectDir.path,
        targetFiles: [
          'lib/screens/home.dart',
          homeFile.path, // duplicate in absolute form -> deduplicated
          '../outside.dart',
          outsideDart.path,
          'lib/screens/does_not_exist.dart',
          'README.md',
        ],
        processRunner: (executable, arguments, {workingDirectory}) async {
          capturedArgs = arguments;
          return ProcessResult(10, 0, 'No issues found!', '');
        },
      );

      expect(result.passed, isTrue);
      expect(
        capturedArgs,
        equals(['analyze', '--no-fatal-infos', 'lib/screens/home.dart']),
      );
    });

    test(
        'returns skipped=true cleanly when project, pubspec.yaml, targetFiles, or Flutter SDK is missing',
        () async {
      var runnerCalled = false;
      Future<ProcessResult> failIfCalled(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        runnerCalled = true;
        return ProcessResult(0, 0, '', '');
      }

      // 1. Missing project directory
      final missingDirResult = await DartVerificationService.verifyDartFiles(
        projectPath: p.join(Directory.systemTemp.path, 'flrd_missing_dir_xyz'),
        processRunner: failIfCalled,
      );
      expect(missingDirResult.skipped, isTrue);
      expect(missingDirResult.passed, isFalse);
      expect(runnerCalled, isFalse);

      // 2. Missing pubspec.yaml
      final noPubspecDir = Directory.systemTemp.createTempSync('flrd_nopub_');
      addTearDown(() {
        if (noPubspecDir.existsSync()) noPubspecDir.deleteSync(recursive: true);
      });
      final noPubspecResult = await DartVerificationService.verifyDartFiles(
        projectPath: noPubspecDir.path,
        processRunner: failIfCalled,
      );
      expect(noPubspecResult.skipped, isTrue);
      expect(noPubspecResult.passed, isFalse);
      expect(noPubspecResult.errorSummary, contains('pubspec.yaml'));
      expect(runnerCalled, isFalse);

      // 3. Valid project, but all targetFiles invalid/traversal/missing
      final projectDir = _createTempFlutterProject();
      final noValidTargets = await DartVerificationService.verifyDartFiles(
        projectPath: projectDir.path,
        targetFiles: ['../outside.dart', 'lib/nonexistent.dart', 'notes.txt'],
        processRunner: failIfCalled,
      );
      expect(noValidTargets.skipped, isTrue);
      expect(noValidTargets.passed, isFalse);
      expect(runnerCalled, isFalse);

      // 4. Missing Flutter SDK executable (explicit nonexistent path, no mock runner)
      final missingSdkResult = await DartVerificationService.verifyDartFiles(
        projectPath: projectDir.path,
        flutterExecutablePath: p.join(projectDir.path, 'missing_bin', 'flutter'),
      );
      expect(missingSdkResult.skipped, isTrue);
      expect(missingSdkResult.passed, isFalse);

      // 5. ProcessException from runner returns skipped=true without crashing
      final processExceptionResult =
          await DartVerificationService.verifyDartFiles(
        projectPath: projectDir.path,
        processRunner: (exe, args, {workingDirectory}) async {
          throw ProcessException(exe, args, 'Executable not found', 2);
        },
      );
      expect(processExceptionResult.skipped, isTrue);
      expect(processExceptionResult.passed, isFalse);
      expect(processExceptionResult.errorSummary, contains('Executable not found'));
    });

    test('resolveFlutterExecutable locates flutter.bat on Windows PATH and flutter on POSIX PATH',
        () async {
      final sdkDir = Directory.systemTemp.createTempSync('flrd_sdk_probe_');
      addTearDown(() {
        if (sdkDir.existsSync()) sdkDir.deleteSync(recursive: true);
      });

      final binDir = Directory(p.join(sdkDir.path, 'bin'))..createSync();
      final winBat = File(p.join(binDir.path, 'flutter.bat'))
        ..writeAsStringSync('@echo off');
      final posixExe = File(p.join(binDir.path, 'flutter'))
        ..writeAsStringSync('#!/bin/sh');

      final resolvedWin = await DartVerificationService.resolveFlutterExecutable(
        environment: {'PATH': binDir.path},
        isWindowsOverride: true,
        allowProcessLocator: false,
        probeCommonPaths: false,
      );
      expect(resolvedWin, equals(winBat.path));

      final resolvedPosix =
          await DartVerificationService.resolveFlutterExecutable(
        environment: {'FLUTTER_ROOT': sdkDir.path},
        isWindowsOverride: false,
        allowProcessLocator: false,
        probeCommonPaths: false,
      );
      expect(resolvedPosix, equals(posixExe.path));

      final resolvedMissing =
          await DartVerificationService.resolveFlutterExecutable(
        environment: const {},
        isWindowsOverride: false,
        allowProcessLocator: false,
        probeCommonPaths: false,
      );
      expect(resolvedMissing, isNull);
    });
  });

  group('DartVerificationService.verifyAndAutoRepairOrRollback', () {
    test('returns immediately when initial verification passes or is skipped',
        () async {
      final projectDir = _createTempFlutterProject();
      var processCalls = 0;
      var httpCalls = 0;

      final passResult =
          await DartVerificationService.verifyAndAutoRepairOrRollback(
        projectPath: projectDir.path,
        apiKey: 'fake-key',
        processRunner: (exe, args, {workingDirectory}) async {
          processCalls++;
          return ProcessResult(1, 0, 'No issues found!', '');
        },
        aiHttpClient: _MockAiHttpClient((req) async {
          httpCalls++;
          return http.Response('{}', 200);
        }),
      );

      expect(passResult.passed, isTrue);
      expect(passResult.skipped, isFalse);
      expect(passResult.rolledBack, isFalse);
      expect(passResult.repairPatchesApplied, isNull);
      expect(processCalls, 1);
      expect(httpCalls, 0);

      final skippedResult =
          await DartVerificationService.verifyAndAutoRepairOrRollback(
        projectPath: p.join(projectDir.path, 'does_not_exist'),
        autoRollbackOnFailure: true,
        backupDir: '.flrd/backups/fake',
      );
      expect(skippedResult.skipped, isTrue);
      expect(skippedResult.passed, isFalse);
      expect(skippedResult.rolledBack, isFalse);
    });

    test(
        'auto-repair loop with mocked processRunner & mock AI patch fixes error and passes on 2nd run',
        () async {
      final projectDir = _createTempFlutterProject();
      final homeFile =
          File(p.join(projectDir.path, 'lib', 'screens', 'home.dart'))
            ..createSync(recursive: true)
            ..writeAsStringSync('''
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      child: const Text('Home'),
    );
  }
}
''');

      var analyzeAttempt = 0;
      final aiRequests = <String>[];

      final result =
          await DartVerificationService.verifyAndAutoRepairOrRollback(
        projectPath: projectDir.path,
        targetFiles: const ['lib/screens/home.dart'],
        apiKey: 'test-gemini-key',
        preferredModel: 'gemini-2.5-flash',
        autoRollbackOnFailure: true,
        processRunner: (exe, args, {workingDirectory}) async {
          analyzeAttempt++;
          if (analyzeAttempt == 1) {
            return ProcessResult(
              201,
              1,
              "  error • Undefined name 'AppColors' • lib/screens/home.dart:9:14 • undefined_identifier\n",
              '',
            );
          }
          return ProcessResult(
            202,
            0,
            'Analyzing lib/screens/home.dart...\nNo issues found!\n',
            '',
          );
        },
        aiHttpClient: _MockAiHttpClient((request) async {
          aiRequests.add(request.body);
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text': '''
### Correção
Substituído `AppColors.primary` por `Theme.of(context).colorScheme.primary`.

```json
{
  "patches": [
    {
      "relativePath": "lib/screens/home.dart",
      "description": "Use Material 3 ColorScheme instead of undefined AppColors",
      "searchText": "      color: AppColors.primary,",
      "replaceText": "      color: Theme.of(context).colorScheme.primary,"
    }
  ]
}
```
''',
                      }
                    ]
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      expect(analyzeAttempt, 2);
      expect(aiRequests, hasLength(1));
      expect(aiRequests.single, contains('lib/screens/home.dart'));
      expect(aiRequests.single, contains("Undefined name 'AppColors'"));

      expect(result.passed, isTrue);
      expect(result.skipped, isFalse);
      expect(result.repairPatchesApplied, greaterThan(0));
      expect(result.repairPatchesApplied, 1);
      expect(result.rolledBack, isFalse);
      expect(result.errors, isEmpty);
      expect(
        homeFile.readAsStringSync(),
        contains('Theme.of(context).colorScheme.primary'),
      );
      expect(
        homeFile.readAsStringSync(),
        isNot(contains('AppColors.primary')),
      );
    });

    test(
        'auto-repair loop applies local deterministic GoogleFonts TextTheme patch offline without AI',
        () async {
      final projectDir = _createTempFlutterProject();
      final themeFile =
          File(p.join(projectDir.path, 'lib', 'core', 'theme', 'app_theme.dart'))
            ..createSync(recursive: true)
            ..writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme),
      );
}
''');

      var attempt = 0;
      final result =
          await DartVerificationService.verifyAndAutoRepairOrRollback(
        projectPath: projectDir.path,
        targetFiles: const ['lib/core/theme/app_theme.dart'],
        processRunner: (exe, args, {workingDirectory}) async {
          attempt++;
          if (attempt == 1) {
            return ProcessResult(
              301,
              1,
              "  error • The argument type 'TextTheme/*1*/' can't be assigned to the parameter type 'TextTheme/*2*/?'. • lib/core/theme/app_theme.dart:6:20 • argument_type_not_assignable\n",
              '',
            );
          }
          return ProcessResult(302, 0, 'No issues found!\n', '');
        },
      );

      expect(attempt, 2);
      expect(result.passed, isTrue);
      expect(result.repairPatchesApplied, 1);
      expect(result.rolledBack, isFalse);
      expect(
        themeFile.readAsStringSync(),
        contains('fontFamily: GoogleFonts.plusJakartaSans().fontFamily'),
      );
    });

    test(
        'rolls back modified files from .flrd/backups/ on unfixable error when autoRollbackOnFailure=true',
        () async {
      final projectDir = _createTempFlutterProject();
      const originalHomeCode = '''
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Text('Original Clean Screen');
}
''';
      const brokenHomeCode = '''
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Text(UnknownBrokenSymbol.value);
}
''';

      final homeFile =
          File(p.join(projectDir.path, 'lib', 'screens', 'home.dart'))
            ..createSync(recursive: true)
            ..writeAsStringSync(brokenHomeCode);

      final backupDir = p.join(
        projectDir.path,
        '.flrd',
        'backups',
        'widget_2026-11-18T18-00-00',
      );
      File(p.join(backupDir, 'lib', 'screens', 'home.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(originalHomeCode);

      var attempts = 0;
      final result =
          await DartVerificationService.verifyAndAutoRepairOrRollback(
        projectPath: projectDir.path,
        targetFiles: const ['lib/screens/home.dart'],
        backupDir: backupDir,
        autoRollbackOnFailure: true,
        processRunner: (exe, args, {workingDirectory}) async {
          attempts++;
          return ProcessResult(
            401,
            1,
            "  error • Undefined name 'UnknownBrokenSymbol' • lib/screens/home.dart:6:46 • undefined_identifier\n",
            '',
          );
        },
      );

      expect(attempts, 1);
      expect(result.passed, isFalse);
      expect(result.rolledBack, isTrue);
      expect(result.backupDir, p.normalize(p.absolute(backupDir)));
      expect(result.repairPatchesApplied, 0);
      expect(homeFile.readAsStringSync(), equals(originalHomeCode));
    });

    test(
        'rolls back both failed repair patch and caller backup when 2nd verification still fails',
        () async {
      final projectDir = _createTempFlutterProject();
      const originalCode = "const String label = 'Original';\n";
      const injectedBrokenCode = "final String label = MissingOne.x;\n";

      final targetFile = File(p.join(projectDir.path, 'lib', 'widget.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(injectedBrokenCode);

      const relativeBackupDir = '.flrd/backups/widget_rel_test';
      File(p.join(projectDir.path, relativeBackupDir, 'lib', 'widget.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(originalCode);

      var attempts = 0;
      final result =
          await DartVerificationService.verifyAndAutoRepairOrRollback(
        projectPath: projectDir.path,
        targetFiles: const ['lib/widget.dart'],
        backupDir: relativeBackupDir,
        apiKey: 'test-key',
        autoRollbackOnFailure: true,
        processRunner: (exe, args, {workingDirectory}) async {
          attempts++;
          return ProcessResult(
            500 + attempts,
            1,
            "  error • Undefined name 'MissingOne' • lib/widget.dart:1:22 • undefined_identifier\n",
            '',
          );
        },
        aiHttpClient: _MockAiHttpClient((req) async {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text': '''
```json
{
  "patches": [
    {
      "relativePath": "lib/widget.dart",
      "description": "Attempted patch that still fails verification",
      "searchText": "final String label = MissingOne.x;",
      "replaceText": "final String label = StillMissingTwo.y;"
    }
  ]
}
```
''',
                      }
                    ]
                  }
                }
              ]
            }),
            200,
          );
        }),
      );

      expect(attempts, 2);
      expect(result.passed, isFalse);
      expect(result.repairPatchesApplied, 1);
      expect(result.rolledBack, isTrue);
      expect(
        result.backupDir,
        p.normalize(p.absolute(p.join(projectDir.path, relativeBackupDir))),
      );
      expect(targetFile.readAsStringSync(), equals(originalCode));
    });

    test('does not roll back when autoRollbackOnFailure is false', () async {
      final projectDir = _createTempFlutterProject();
      const originalCode = "const String label = 'Original';\n";
      const brokenCode = "final String label = Broken.x;\n";

      final targetFile = File(p.join(projectDir.path, 'lib', 'widget.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(brokenCode);

      final backupDir = p.join(projectDir.path, '.flrd', 'backups', 'widget_no_rb');
      File(p.join(backupDir, 'lib', 'widget.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(originalCode);

      final result =
          await DartVerificationService.verifyAndAutoRepairOrRollback(
        projectPath: projectDir.path,
        targetFiles: const ['lib/widget.dart'],
        backupDir: backupDir,
        autoRollbackOnFailure: false,
        processRunner: (exe, args, {workingDirectory}) async {
          return ProcessResult(
            601,
            1,
            "  error • Undefined name 'Broken' • lib/widget.dart:1:22 • undefined_identifier\n",
            '',
          );
        },
      );

      expect(result.passed, isFalse);
      expect(result.rolledBack, isFalse);
      expect(targetFile.readAsStringSync(), equals(brokenCode));
    });
  });
}
