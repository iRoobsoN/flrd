import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../studio/models/connected_device.dart';
import '../../studio/services/diagnostic_code_fix_service.dart';
import 'gemini_ai_service.dart';

/// Process execution signature for running `flutter analyze`, injectable in tests.
typedef VerificationProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

const Object _verificationUnset = Object();

/// Structured diagnostic item parsed from `flutter analyze` / `dart analyze`.
@immutable
class DartVerificationIssue {
  /// Severity level: `'error'`, `'warning'`, or `'info'`.
  final String severity;
  final String message;
  final String? filePath;
  final int? line;
  final int? column;
  final String? code;

  const DartVerificationIssue({
    required this.severity,
    required this.message,
    this.filePath,
    this.line,
    this.column,
    this.code,
  });

  bool get isError => severity.toLowerCase() == 'error';
  bool get isWarning => severity.toLowerCase() == 'warning';
  bool get isInfo => severity.toLowerCase() == 'info';

  /// Formats this issue as a CFE/compiler-style line understood by
  /// [DiagnosticCodeFixService] context collectors and local analyzers.
  String toDiagnosticLine() {
    final label = isError
        ? 'Error'
        : isWarning
            ? 'Warning'
            : 'Info';
    final loc = (filePath != null && filePath!.trim().isNotEmpty)
        ? '${filePath!.trim()}:${line ?? 1}:${column ?? 1}: '
        : '';
    final codeSuffix =
        (code != null && code!.trim().isNotEmpty) ? ' (${code!.trim()})' : '';
    return '$loc$label: $message$codeSuffix';
  }

  DartVerificationIssue copyWith({
    String? severity,
    String? message,
    Object? filePath = _verificationUnset,
    Object? line = _verificationUnset,
    Object? column = _verificationUnset,
    Object? code = _verificationUnset,
  }) {
    return DartVerificationIssue(
      severity: severity ?? this.severity,
      message: message ?? this.message,
      filePath: identical(filePath, _verificationUnset)
          ? this.filePath
          : filePath as String?,
      line: identical(line, _verificationUnset) ? this.line : line as int?,
      column:
          identical(column, _verificationUnset) ? this.column : column as int?,
      code: identical(code, _verificationUnset) ? this.code : code as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DartVerificationIssue &&
        other.severity == severity &&
        other.message == message &&
        other.filePath == filePath &&
        other.line == line &&
        other.column == column &&
        other.code == code;
  }

  @override
  int get hashCode =>
      Object.hash(severity, message, filePath, line, column, code);

  @override
  String toString() =>
      'DartVerificationIssue(severity: $severity, filePath: $filePath, line: $line, column: $column, code: $code, message: $message)';
}

/// Outcome of running static Dart/Flutter verification (and optional auto-repair
/// or backup rollback) against a generated or modified Flutter project.
@immutable
class DartVerificationResult {
  final bool passed;
  final bool skipped;
  final List<DartVerificationIssue> errors;
  final List<DartVerificationIssue> warnings;
  final List<DartVerificationIssue> infos;
  final String rawOutput;
  final int? repairPatchesApplied;
  final bool rolledBack;
  final String? errorSummary;
  final String? backupDir;

  const DartVerificationResult({
    required this.passed,
    this.skipped = false,
    this.errors = const [],
    this.warnings = const [],
    this.infos = const [],
    this.rawOutput = '',
    this.repairPatchesApplied,
    this.rolledBack = false,
    this.errorSummary,
    this.backupDir,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;

  List<DartVerificationIssue> get allIssues =>
      List<DartVerificationIssue>.unmodifiable([...errors, ...warnings, ...infos]);

  DartVerificationResult copyWith({
    bool? passed,
    bool? skipped,
    List<DartVerificationIssue>? errors,
    List<DartVerificationIssue>? warnings,
    List<DartVerificationIssue>? infos,
    String? rawOutput,
    Object? repairPatchesApplied = _verificationUnset,
    bool? rolledBack,
    Object? errorSummary = _verificationUnset,
    Object? backupDir = _verificationUnset,
  }) {
    return DartVerificationResult(
      passed: passed ?? this.passed,
      skipped: skipped ?? this.skipped,
      errors: errors ?? this.errors,
      warnings: warnings ?? this.warnings,
      infos: infos ?? this.infos,
      rawOutput: rawOutput ?? this.rawOutput,
      repairPatchesApplied:
          identical(repairPatchesApplied, _verificationUnset)
              ? this.repairPatchesApplied
              : repairPatchesApplied as int?,
      rolledBack: rolledBack ?? this.rolledBack,
      errorSummary: identical(errorSummary, _verificationUnset)
          ? this.errorSummary
          : errorSummary as String?,
      backupDir: identical(backupDir, _verificationUnset)
          ? this.backupDir
          : backupDir as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DartVerificationResult &&
        other.passed == passed &&
        other.skipped == skipped &&
        listEquals(other.errors, errors) &&
        listEquals(other.warnings, warnings) &&
        listEquals(other.infos, infos) &&
        other.rawOutput == rawOutput &&
        other.repairPatchesApplied == repairPatchesApplied &&
        other.rolledBack == rolledBack &&
        other.errorSummary == errorSummary &&
        other.backupDir == backupDir;
  }

  @override
  int get hashCode => Object.hash(
        passed,
        skipped,
        Object.hashAll(errors),
        Object.hashAll(warnings),
        Object.hashAll(infos),
        rawOutput,
        repairPatchesApplied,
        rolledBack,
        errorSummary,
        backupDir,
      );

  @override
  String toString() =>
      'DartVerificationResult(passed: $passed, skipped: $skipped, errors: ${errors.length}, warnings: ${warnings.length}, repairPatchesApplied: $repairPatchesApplied, rolledBack: $rolledBack, backupDir: $backupDir)';
}

/// Executes static `flutter analyze` verification on generated/edited Dart
/// files and orchestrates deterministic + Gemini auto-repair or backup rollback.
class DartVerificationService {
  const DartVerificationService._();

  static final RegExp _ansiEscapeRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
  static final RegExp _bulletPrefixRegex = RegExp(
    r'^(error|warning|info)\s+•\s+',
    caseSensitive: false,
  );
  static final RegExp _dashFormatRegex = RegExp(
    r'^(error|warning|info)\s+-\s+(.+?):(\d+)(?::(\d+))?\s+-\s+(.+?)(?:\s+-\s+([a-z][a-z0-9_]*))?$',
    caseSensitive: false,
  );
  static final RegExp _shortFormatRegex = RegExp(
    r'^(.+?):(\d+)(?::(\d+))?:\s*(Error|Warning|Info)\s*:\s*(.+)$',
    caseSensitive: false,
  );
  static final RegExp _lintCodeRegex = RegExp(r'^[a-z][a-z0-9_]*$');
  static final RegExp _locLineColRegex = RegExp(r'^(.+?):(\d+):(\d+)$');
  static final RegExp _locLineOnlyRegex = RegExp(r'^(.+?):(\d+)$');

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: !kIsWeb && Platform.isWindows,
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );
  }

  /// Resolves the Flutter CLI binary across Windows, macOS, and Linux, or
  /// returns `null` when unavailable on the host system.
  static Future<String?> resolveFlutterExecutable({
    String? flutterExecutablePath,
    bool allowProcessLocator = true,
    bool probeCommonPaths = true,
    bool fallbackToBareCommand = false,
    Map<String, String>? environment,
    bool? isWindowsOverride,
  }) async {
    if (kIsWeb && !fallbackToBareCommand) {
      return null;
    }

    final isWindows = isWindowsOverride ?? (!kIsWeb && Platform.isWindows);
    final env = environment ?? (!kIsWeb ? Platform.environment : const {});

    final explicit = flutterExecutablePath?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      if (fallbackToBareCommand) {
        return explicit;
      }
      final looksLikePath = explicit.contains('/') || explicit.contains('\\');
      if (looksLikePath) {
        return File(explicit).existsSync() ? explicit : null;
      }
      if (!allowProcessLocator) {
        return explicit;
      }
      final fromPath = _findExecutableInDirectories(
        _splitPathEnv(env['PATH'], isWindows: isWindows),
        [explicit],
      );
      if (fromPath != null) return fromPath;
      final located = await _runLocatorCommand(explicit, isWindows: isWindows);
      return located;
    }

    final binaryNames = isWindows
        ? const ['flutter.bat', 'flutter.exe', 'flutter']
        : const ['flutter'];

    // 1. Check FLUTTER_ROOT environment variable
    final flutterRoot = env['FLUTTER_ROOT']?.trim();
    if (flutterRoot != null && flutterRoot.isNotEmpty) {
      final found = _findExecutableInDirectories(
        [p.join(flutterRoot, 'bin')],
        binaryNames,
      );
      if (found != null) return found;
    }

    // 2. Check PATH directories directly (avoids spawning processes unnecessarily)
    final pathFound = _findExecutableInDirectories(
      _splitPathEnv(env['PATH'], isWindows: isWindows),
      binaryNames,
    );
    if (pathFound != null) return pathFound;

    // 3. Check sibling of Dart/Flutter tester binary inside a Flutter SDK cache
    if (probeCommonPaths && !kIsWeb) {
      final resolvedExe = Platform.resolvedExecutable;
      if (resolvedExe.isNotEmpty &&
          (resolvedExe.contains('dart-sdk') ||
              resolvedExe.contains('flutter_tester'))) {
        final exeDir = p.dirname(resolvedExe);
        final sdkBins = <String>[
          p.normalize(p.join(exeDir, '..', '..', '..')),
          p.normalize(p.join(exeDir, '..', '..', '..', '..')),
        ];
        final sdkFound = _findExecutableInDirectories(sdkBins, binaryNames);
        if (sdkFound != null) return sdkFound;
      }
    }

    // 4. Probe common installation directories
    if (probeCommonPaths) {
      final commonDirs = _commonFlutterBinDirs(env, isWindows: isWindows);
      final commonFound = _findExecutableInDirectories(commonDirs, binaryNames);
      if (commonFound != null) return commonFound;
    }

    // 5. System locator (`where.exe` on Windows, `which` on POSIX)
    if (allowProcessLocator && !kIsWeb) {
      final located = await _runLocatorCommand('flutter', isWindows: isWindows);
      if (located != null) return located;
    }

    return fallbackToBareCommand ? 'flutter' : null;
  }

  /// Runs `flutter analyze --no-fatal-infos` on [projectPath] (optionally
  /// scoped to [targetFiles] inside [projectPath]) and parses diagnostics.
  static Future<DartVerificationResult> verifyDartFiles({
    required String projectPath,
    List<String> targetFiles = const [],
    VerificationProcessRunner? processRunner,
    String? flutterExecutablePath,
  }) async {
    if (kIsWeb && processRunner == null) {
      return const DartVerificationResult(
        passed: false,
        skipped: true,
        errorSummary: 'Verificação Dart via CLI indisponível no ambiente Web.',
      );
    }

    final cleanRoot = projectPath.trim();
    if (cleanRoot.isEmpty) {
      return const DartVerificationResult(
        passed: false,
        skipped: true,
        errorSummary: 'Caminho do projeto não informado.',
      );
    }

    final canonicalRoot = p.normalize(p.absolute(cleanRoot));
    if (!Directory(canonicalRoot).existsSync()) {
      return DartVerificationResult(
        passed: false,
        skipped: true,
        errorSummary: 'Pasta do projeto não encontrada: $projectPath',
      );
    }

    final pubspecFile = File(p.join(canonicalRoot, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return DartVerificationResult(
        passed: false,
        skipped: true,
        errorSummary: 'pubspec.yaml não encontrado em $canonicalRoot',
      );
    }

    final relativeTargets = <String>[];
    if (targetFiles.isNotEmpty) {
      final seenTargets = <String>{};
      for (final rawTarget in targetFiles) {
        final trimmed = rawTarget.trim();
        if (trimmed.isEmpty) continue;

        final resolvedTarget = p.isAbsolute(trimmed)
            ? p.normalize(p.absolute(trimmed))
            : p.normalize(
                p.absolute(
                  p.joinAll([
                    canonicalRoot,
                    ...trimmed
                        .replaceAll('\\', '/')
                        .split('/')
                        .where((segment) => segment.isNotEmpty),
                  ]),
                ),
              );

        if (!p.isWithin(canonicalRoot, resolvedTarget)) continue;
        if (!resolvedTarget.toLowerCase().endsWith('.dart')) continue;
        if (!File(resolvedTarget).existsSync()) continue;

        final relPosix =
            p.relative(resolvedTarget, from: canonicalRoot).replaceAll('\\', '/');
        if (seenTargets.add(relPosix.toLowerCase())) {
          relativeTargets.add(relPosix);
        }
      }

      if (relativeTargets.isEmpty) {
        return const DartVerificationResult(
          passed: false,
          skipped: true,
          errorSummary:
              'Nenhum arquivo .dart válido encontrado dentro do projeto para verificação.',
        );
      }
    }

    final hasCustomRunner = processRunner != null;
    final executable = await resolveFlutterExecutable(
      flutterExecutablePath: flutterExecutablePath,
      allowProcessLocator: !hasCustomRunner,
      fallbackToBareCommand: hasCustomRunner,
    );

    if (executable == null || executable.trim().isEmpty) {
      return const DartVerificationResult(
        passed: false,
        skipped: true,
        errorSummary:
            'Flutter SDK não encontrado no PATH do sistema. Verificação estática ignorada.',
      );
    }

    final runner = processRunner ?? _defaultProcessRunner;
    final args = <String>[
      'analyze',
      '--no-fatal-infos',
      ...relativeTargets,
    ];

    final ProcessResult processResult;
    try {
      processResult = await runner(
        executable,
        args,
        workingDirectory: canonicalRoot,
      );
    } on ProcessException catch (e) {
      return DartVerificationResult(
        passed: false,
        skipped: true,
        errorSummary: 'Falha ao executar Flutter SDK ($executable): ${e.message}',
      );
    } catch (e) {
      return DartVerificationResult(
        passed: false,
        skipped: true,
        errorSummary: 'Erro inesperado ao executar flutter analyze: $e',
      );
    }

    final stdoutText = processResult.stdout?.toString() ?? '';
    final stderrText = processResult.stderr?.toString() ?? '';
    final combinedOutput = [
      if (stdoutText.trim().isNotEmpty) stdoutText.trimRight(),
      if (stderrText.trim().isNotEmpty) stderrText.trimRight(),
    ].join('\n');

    if (!hasCustomRunner &&
        processResult.exitCode != 0 &&
        _looksLikeMissingCommandOutput(combinedOutput)) {
      return DartVerificationResult(
        passed: false,
        skipped: true,
        rawOutput: combinedOutput,
        errorSummary:
            'Executável Flutter indisponível ($executable): $combinedOutput',
      );
    }

    final parsed = parseAnalyzerOutput(
      combinedOutput,
      projectPath: canonicalRoot,
    );

    final passed = processResult.exitCode == 0 && parsed.errors.isEmpty;
    final errorSummary = passed
        ? null
        : _buildErrorSummary(
            errors: parsed.errors,
            rawOutput: combinedOutput,
            exitCode: processResult.exitCode,
          );

    return DartVerificationResult(
      passed: passed,
      skipped: false,
      errors: parsed.errors,
      warnings: parsed.warnings,
      infos: parsed.infos,
      rawOutput: combinedOutput,
      errorSummary: errorSummary,
    );
  }

  /// Verifies Dart files, attempts local deterministic + optional Gemini AI
  /// repair when errors are found, re-verifies, and optionally rolls back to
  /// [backupDir] if errors persist.
  static Future<DartVerificationResult> verifyAndAutoRepairOrRollback({
    required String projectPath,
    List<String> targetFiles = const [],
    String? backupDir,
    String? apiKey,
    String preferredModel = 'gemini-2.5-flash',
    bool autoRollbackOnFailure = false,
    VerificationProcessRunner? processRunner,
    http.Client? aiHttpClient,
    String? flutterExecutablePath,
  }) async {
    final initialResult = await verifyDartFiles(
      projectPath: projectPath,
      targetFiles: targetFiles,
      processRunner: processRunner,
      flutterExecutablePath: flutterExecutablePath,
    );

    if (initialResult.passed || initialResult.skipped) {
      return initialResult;
    }

    final canonicalRoot = p.normalize(p.absolute(projectPath.trim()));
    final resolvedBackupDir = _resolveProjectBackupDir(
      canonicalRoot: canonicalRoot,
      backupDir: backupDir,
    );

    var appliedPatchesCount = 0;
    String? repairBackupDir;
    var latestResult = initialResult;

    final shouldAttemptRepair = initialResult.errors.isNotEmpty ||
        (initialResult.warnings.isEmpty &&
            initialResult.rawOutput.trim().isNotEmpty);

    if (shouldAttemptRepair) {
      final syntheticCrashLines = _buildSyntheticCrashLines(initialResult);
      final affectedLocation = _firstAffectedLocation(initialResult.errors);
      final issueTitle = initialResult.errors.isNotEmpty
          ? (initialResult.errors.length == 1
              ? 'Erro de análise Dart: ${initialResult.errors.first.message}'
              : 'Erros de análise Dart (${initialResult.errors.length}): ${initialResult.errors.first.message}')
          : 'Falha na verificação estática Dart (flutter analyze)';

      final baseDiagnostic = AndroidBuildDiagnostic(
        issueType: AndroidBuildIssueType.dartCompileError,
        title: issueTitle,
        explanation: initialResult.errorSummary ?? issueTitle,
        affectedLocation: affectedLocation,
        relevantLogLines: syntheticCrashLines,
      );

      final locallyEnriched =
          DiagnosticCodeFixService.enrichDiagnosticWithLocalAnalysis(
        baseDiagnostic,
        projectPath: canonicalRoot,
        crashLogs: syntheticCrashLines,
      );

      var candidatePatches = locallyEnriched.suggestedPatches;

      if (candidatePatches.isEmpty && _hasValidApiKey(apiKey)) {
        // preferredModel is accepted for API parity with GeminiAiService;
        // diagnostic fix analysis uses GeminiAiService.analyzeAndBuildAppFix.
        assert(preferredModel.isNotEmpty);
        final aiFix = await GeminiAiService.analyzeAndBuildAppFix(
          projectPath: canonicalRoot,
          issueTitle: issueTitle,
          crashLogs: syntheticCrashLines,
          affectedLocation: affectedLocation,
          apiKey: apiKey,
          httpClient: aiHttpClient,
        );
        candidatePatches = aiFix.patches;
      }

      final validPatches = DiagnosticCodeFixService.filterValidPatches(
        projectPath: canonicalRoot,
        patches: candidatePatches,
      );

      if (validPatches.isNotEmpty) {
        final applyResult = await DiagnosticCodeFixService.applyPatches(
          projectPath: canonicalRoot,
          patches: validPatches,
        );
        appliedPatchesCount = applyResult.appliedCount;
        repairBackupDir = applyResult.backupDir;

        if (appliedPatchesCount > 0) {
          latestResult = await verifyDartFiles(
            projectPath: projectPath,
            targetFiles: targetFiles,
            processRunner: processRunner,
            flutterExecutablePath: flutterExecutablePath,
          );
        }
      }
    }

    if (latestResult.passed) {
      return latestResult.copyWith(
        repairPatchesApplied: appliedPatchesCount,
        rolledBack: false,
        backupDir: resolvedBackupDir ?? repairBackupDir,
      );
    }

    if (!latestResult.skipped &&
        autoRollbackOnFailure &&
        resolvedBackupDir != null) {
      if (repairBackupDir != null &&
          repairBackupDir.isNotEmpty &&
          !p.equals(repairBackupDir, resolvedBackupDir)) {
        await DiagnosticCodeFixService.revertBackup(
          projectPath: canonicalRoot,
          backupDir: repairBackupDir,
        );
      }

      final restoredFiles = await DiagnosticCodeFixService.revertBackup(
        projectPath: canonicalRoot,
        backupDir: resolvedBackupDir,
      );

      return latestResult.copyWith(
        repairPatchesApplied: appliedPatchesCount,
        rolledBack: restoredFiles.isNotEmpty,
        backupDir: resolvedBackupDir,
      );
    }

    return latestResult.copyWith(
      repairPatchesApplied: appliedPatchesCount,
      rolledBack: false,
      backupDir: resolvedBackupDir ?? repairBackupDir,
    );
  }

  /// Parses `flutter analyze` / `dart analyze` output across bullet (`•`),
  /// dash (`-`), and CFE/Windows short (`file:line:col: Error: ...`) formats.
  static ({
    List<DartVerificationIssue> errors,
    List<DartVerificationIssue> warnings,
    List<DartVerificationIssue> infos,
  }) parseAnalyzerOutput(
    String rawOutput, {
    String? projectPath,
  }) {
    if (rawOutput.trim().isEmpty) {
      return const (
        errors: <DartVerificationIssue>[],
        warnings: <DartVerificationIssue>[],
        infos: <DartVerificationIssue>[],
      );
    }

    final canonicalRoot = (projectPath != null && projectPath.trim().isNotEmpty)
        ? p.normalize(p.absolute(projectPath.trim()))
        : null;

    final errors = <DartVerificationIssue>[];
    final warnings = <DartVerificationIssue>[];
    final infos = <DartVerificationIssue>[];
    final seen = <DartVerificationIssue>{};

    for (final rawLine in rawOutput.split(RegExp(r'\r?\n'))) {
      final cleanLine = rawLine.replaceAll(_ansiEscapeRegex, '').trim();
      if (cleanLine.isEmpty) continue;

      final issue = _parseSingleAnalyzerLine(
        cleanLine,
        canonicalRoot: canonicalRoot,
      );
      if (issue == null || !seen.add(issue)) continue;

      if (issue.isError) {
        errors.add(issue);
      } else if (issue.isWarning) {
        warnings.add(issue);
      } else {
        infos.add(issue);
      }
    }

    return (
      errors: List<DartVerificationIssue>.unmodifiable(errors),
      warnings: List<DartVerificationIssue>.unmodifiable(warnings),
      infos: List<DartVerificationIssue>.unmodifiable(infos),
    );
  }

  static DartVerificationIssue? _parseSingleAnalyzerLine(
    String line, {
    String? canonicalRoot,
  }) {
    // 1. Standard Flutter bullet format:
    //    error • Undefined name 'AppColors' • lib/screens/home.dart:14:9 • undefined_identifier
    if (_bulletPrefixRegex.hasMatch(line)) {
      final parts = line.split(RegExp(r'\s+•\s+'));
      if (parts.length >= 3) {
        final severity = parts.first.trim().toLowerCase();
        final lastPart = parts.last.trim();
        final hasCode = parts.length >= 4 && _lintCodeRegex.hasMatch(lastPart);

        final code = hasCode ? lastPart : null;
        final locationPart =
            hasCode ? parts[parts.length - 2].trim() : lastPart;
        final messageParts = hasCode
            ? parts.sublist(1, parts.length - 2)
            : parts.sublist(1, parts.length - 1);
        final message = messageParts.join(' • ').trim();

        final loc = _parseLocation(locationPart, canonicalRoot: canonicalRoot);
        if (message.isNotEmpty) {
          return DartVerificationIssue(
            severity: severity,
            message: message,
            filePath: loc.filePath,
            line: loc.line,
            column: loc.column,
            code: code,
          );
        }
      }
    }

    // 2. Dart `dart analyze` dash format:
    //    error - lib/screens/home.dart:14:9 - Undefined name 'AppColors'. - undefined_identifier
    final dashMatch = _dashFormatRegex.firstMatch(line);
    if (dashMatch != null) {
      final severity = dashMatch.group(1)!.toLowerCase();
      final normalizedPath = _normalizeIssuePath(
        dashMatch.group(2)!,
        canonicalRoot: canonicalRoot,
      );
      final lineNum = int.tryParse(dashMatch.group(3) ?? '');
      final colNum = int.tryParse(dashMatch.group(4) ?? '');
      final message = dashMatch.group(5)!.trim();
      final code = dashMatch.group(6)?.trim();
      if (message.isNotEmpty) {
        return DartVerificationIssue(
          severity: severity,
          message: message,
          filePath: normalizedPath,
          line: lineNum,
          column: colNum,
          code: (code != null && code.isNotEmpty) ? code : null,
        );
      }
    }

    // 3. CFE / Windows / short compiler format:
    //    lib/screens/home.dart:14:9: Error: Undefined name 'AppColors'.
    final shortMatch = _shortFormatRegex.firstMatch(line);
    if (shortMatch != null) {
      final rawPath = shortMatch.group(1)!.trim();
      final lineNum = int.tryParse(shortMatch.group(2) ?? '');
      final colNum = int.tryParse(shortMatch.group(3) ?? '');
      final severity = shortMatch.group(4)!.toLowerCase();
      final message = shortMatch.group(5)!.trim();
      if (rawPath.isNotEmpty && message.isNotEmpty) {
        return DartVerificationIssue(
          severity: severity,
          message: message,
          filePath: _normalizeIssuePath(rawPath, canonicalRoot: canonicalRoot),
          line: lineNum,
          column: colNum,
        );
      }
    }

    return null;
  }

  static ({String? filePath, int? line, int? column}) _parseLocation(
    String rawLocation, {
    String? canonicalRoot,
  }) {
    final trimmed = rawLocation.trim();
    if (trimmed.isEmpty) {
      return const (filePath: null, line: null, column: null);
    }

    final lineColMatch = _locLineColRegex.firstMatch(trimmed);
    if (lineColMatch != null) {
      return (
        filePath: _normalizeIssuePath(
          lineColMatch.group(1)!,
          canonicalRoot: canonicalRoot,
        ),
        line: int.tryParse(lineColMatch.group(2)!),
        column: int.tryParse(lineColMatch.group(3)!),
      );
    }

    final lineOnlyMatch = _locLineOnlyRegex.firstMatch(trimmed);
    if (lineOnlyMatch != null) {
      return (
        filePath: _normalizeIssuePath(
          lineOnlyMatch.group(1)!,
          canonicalRoot: canonicalRoot,
        ),
        line: int.tryParse(lineOnlyMatch.group(2)!),
        column: null,
      );
    }

    return (
      filePath: _normalizeIssuePath(trimmed, canonicalRoot: canonicalRoot),
      line: null,
      column: null,
    );
  }

  static String _normalizeIssuePath(
    String rawPath, {
    String? canonicalRoot,
  }) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return trimmed;
    if (canonicalRoot != null && p.isAbsolute(trimmed)) {
      final normalizedAbs = p.normalize(p.absolute(trimmed));
      if (p.isWithin(canonicalRoot, normalizedAbs)) {
        return p.relative(normalizedAbs, from: canonicalRoot).replaceAll('\\', '/');
      }
    }
    return trimmed.replaceAll('\\', '/');
  }

  static List<String> _buildSyntheticCrashLines(DartVerificationResult result) {
    final lines = <String>[];
    final seen = <String>{};

    void addLine(String value) {
      final clean = value.trim();
      if (clean.isNotEmpty && seen.add(clean)) {
        lines.add(clean);
      }
    }

    for (final issue in result.errors) {
      addLine(issue.toDiagnosticLine());
    }

    final rawLines = result.rawOutput.split(RegExp(r'\r?\n'));
    final cappedRaw =
        rawLines.length > 80 ? rawLines.sublist(rawLines.length - 80) : rawLines;
    for (final line in cappedRaw) {
      addLine(line);
    }

    return lines;
  }

  static String? _firstAffectedLocation(List<DartVerificationIssue> errors) {
    for (final issue in errors) {
      final path = issue.filePath?.trim();
      if (path != null && path.isNotEmpty) {
        return issue.line != null ? '$path:${issue.line}' : path;
      }
    }
    return null;
  }

  static String _buildErrorSummary({
    required List<DartVerificationIssue> errors,
    required String rawOutput,
    required int exitCode,
  }) {
    if (errors.isNotEmpty) {
      final first = errors.first;
      final loc = (first.filePath != null && first.filePath!.isNotEmpty)
          ? '${first.filePath}${first.line != null ? ':${first.line}' : ''}: '
          : '';
      if (errors.length == 1) {
        return '$loc${first.message}';
      }
      return '${errors.length} erro(s) Dart encontrados — $loc${first.message}';
    }

    final firstLine = rawOutput
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isNotEmpty) {
      return '$firstLine (exitCode=$exitCode)';
    }
    return 'flutter analyze falhou com código de saída $exitCode.';
  }

  static String? _resolveProjectBackupDir({
    required String canonicalRoot,
    required String? backupDir,
  }) {
    final trimmed = backupDir?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final resolved = p.isAbsolute(trimmed)
        ? p.normalize(p.absolute(trimmed))
        : p.normalize(
            p.absolute(
              p.joinAll([
                canonicalRoot,
                ...trimmed
                    .replaceAll('\\', '/')
                    .split('/')
                    .where((segment) => segment.isNotEmpty),
              ]),
            ),
          );
    return p.isWithin(canonicalRoot, resolved) ? resolved : null;
  }

  static bool _hasValidApiKey(String? apiKey) {
    if (apiKey == null) return false;
    final trimmed = apiKey.trim();
    return trimmed.isNotEmpty && trimmed != 'null' && trimmed != 'undefined';
  }

  static bool _looksLikeMissingCommandOutput(String output) {
    final lower = output.toLowerCase();
    return lower.contains('is not recognized as an internal or external command') ||
        lower.contains('não é reconhecido como um comando interno') ||
        lower.contains('command not found') ||
        lower.contains('no such file or directory');
  }

  static List<String> _splitPathEnv(String? pathEnv, {required bool isWindows}) {
    if (pathEnv == null || pathEnv.trim().isEmpty) return const [];
    final separator = isWindows ? ';' : ':';
    return pathEnv
        .split(separator)
        .map((segment) => segment.trim().replaceAll('"', ''))
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _commonFlutterBinDirs(
    Map<String, String> env, {
    required bool isWindows,
  }) {
    if (isWindows) {
      final userProfile = env['USERPROFILE']?.trim() ?? '';
      final localAppData = env['LOCALAPPDATA']?.trim() ?? '';
      return <String>[
        r'C:\src\flutter\bin',
        r'C:\flutter\bin',
        if (userProfile.isNotEmpty) p.join(userProfile, 'flutter', 'bin'),
        if (localAppData.isNotEmpty) p.join(localAppData, 'flutter', 'bin'),
      ];
    }

    final home = env['HOME']?.trim() ?? '';
    return <String>[
      if (home.isNotEmpty) p.join(home, 'flutter', 'bin'),
      if (home.isNotEmpty) p.join(home, 'development', 'flutter', 'bin'),
      '/opt/flutter/bin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
    ];
  }

  static String? _findExecutableInDirectories(
    List<String> directories,
    List<String> binaryNames,
  ) {
    for (final dir in directories) {
      for (final name in binaryNames) {
        final candidate = p.join(dir, name);
        try {
          if (File(candidate).existsSync()) {
            return candidate;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  static Future<String?> _runLocatorCommand(
    String binaryName, {
    required bool isWindows,
  }) async {
    final locator = isWindows ? 'where.exe' : 'which';
    try {
      final result = await Process.run(
        locator,
        [binaryName],
        runInShell: isWindows,
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      );
      if (result.exitCode != 0) return null;
      final candidates = result.stdout
          .toString()
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (candidates.isEmpty) return null;

      if (isWindows) {
        for (final candidate in candidates) {
          final lower = candidate.toLowerCase();
          if (lower.endsWith('.bat') || lower.endsWith('.exe')) {
            return candidate;
          }
        }
      }
      return candidates.first;
    } catch (_) {
      return null;
    }
  }
}
