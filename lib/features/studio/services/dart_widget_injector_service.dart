import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../ai/models/ai_execution_plan.dart';
import '../domain/screen_material.dart';
import '../domain/widget_variation.dart';

/// Result returned by [DartWidgetInjectorService.injectWidget], describing the
/// files modified or created, backup directory, resolved AST anchor, or failure.
@immutable
class DartWidgetInjectionResult {
  final bool success;
  final String? backupDir;
  final List<String> modifiedFiles;
  final List<String> createdFiles;
  final String? resolvedAnchorDescription;
  final String? errorMessage;
  final String? updatedScreenCode;

  const DartWidgetInjectionResult({
    required this.success,
    this.backupDir,
    this.modifiedFiles = const [],
    this.createdFiles = const [],
    this.resolvedAnchorDescription,
    this.errorMessage,
    this.updatedScreenCode,
  });

  @override
  String toString() =>
      'DartWidgetInjectionResult(success: $success, backupDir: $backupDir, modifiedFiles: $modifiedFiles, createdFiles: $createdFiles, anchor: $resolvedAnchorDescription, errorMessage: $errorMessage)';
}

enum _AnchorKind {
  topOfBody,
  bottomOfColumn,
  afterText,
  beforeText,
  centerBody,
}

/// AST-lite, backup-safe Dart widget injector for Sprint 2 Plan-First codegen.
///
/// Validates project boundaries, creates `.flrd/backups/widget_<stamp>/`
/// snapshots before modifying existing files, handles separate widget extraction
/// or inline top-level class appending, resolves insertion anchors inside
/// `build()`, strips blocking `const` qualifiers on `children: const [` or
/// enclosing containers, and refuses to report `success: true` on unplaceable
/// targets.
class DartWidgetInjectorService {
  const DartWidgetInjectorService._();

  static const String _customStartMarker = '// FLRD:CUSTOM_WIDGET_START';
  static const String _customEndMarker = '// FLRD:CUSTOM_WIDGET_END';

  /// Injects [variation] (guided by [plan] / `variation.plan`) into [screenFilePath]
  /// inside [projectPath], optionally extracting a separate widget file and
  /// creating timestamped backups before writing atomically.
  static Future<DartWidgetInjectionResult> injectWidget({
    required String projectPath,
    required String screenFilePath,
    required WidgetVariation variation,
    AiExecutionPlan? plan,
    String? currentScreenCode,
  }) async {
    final cleanRoot = projectPath.trim();
    if (cleanRoot.isEmpty) {
      return const DartWidgetInjectionResult(
        success: false,
        errorMessage: 'Caminho do projeto não informado.',
      );
    }

    final canonicalRoot = p.normalize(p.absolute(cleanRoot));
    if (!Directory(canonicalRoot).existsSync()) {
      return DartWidgetInjectionResult(
        success: false,
        errorMessage: 'Pasta do projeto não encontrada: $projectPath',
      );
    }

    final trimmedScreen = screenFilePath.trim();
    if (trimmedScreen.isEmpty) {
      return const DartWidgetInjectionResult(
        success: false,
        errorMessage: 'Caminho do arquivo de tela não informado.',
      );
    }

    final resolvedScreenPath = p.isAbsolute(trimmedScreen)
        ? p.normalize(p.absolute(trimmedScreen))
        : p.normalize(p.absolute(p.join(canonicalRoot, trimmedScreen)));
    if (!p.isWithin(canonicalRoot, resolvedScreenPath)) {
      return DartWidgetInjectionResult(
        success: false,
        errorMessage:
            'Caminho da tela fora do diretório do projeto: $screenFilePath',
      );
    }

    final screenFile = File(resolvedScreenPath);
    final screenExists = screenFile.existsSync();
    if (!screenExists && currentScreenCode == null) {
      return DartWidgetInjectionResult(
        success: false,
        errorMessage: 'Arquivo de tela não encontrado: $resolvedScreenPath',
      );
    }

    final String originalScreenCode;
    try {
      originalScreenCode = currentScreenCode ?? screenFile.readAsStringSync();
    } catch (e) {
      return DartWidgetInjectionResult(
        success: false,
        errorMessage: 'Falha ao ler arquivo de tela: $e',
      );
    }

    if (originalScreenCode.trim().isEmpty) {
      return DartWidgetInjectionResult(
        success: false,
        errorMessage:
            'Arquivo de tela vazio: nenhum ponto de inserção Dart válido encontrado em $screenFilePath.',
      );
    }

    final effectivePlan = plan ?? variation.plan;
    final rawExtractedCode = _resolveExtractedWidgetCode(variation);
    final widgetClassName = _resolveWidgetClassName(
      extractedWidgetCode: rawExtractedCode,
      plan: effectivePlan,
      variation: variation,
    );

    final placement = effectivePlan?.placementStrategy ??
        AiPlanPlacementStrategy.separateWidgetFile;
    final isSeparateWidget = rawExtractedCode != null &&
        placement != AiPlanPlacementStrategy.inlineInScreen;
    final isInlineWidgetClass = rawExtractedCode != null &&
        placement == AiPlanPlacementStrategy.inlineInScreen;

    String? resolvedWidgetPath;
    String? preparedWidgetFileContent;
    String? extractedWidgetImport;
    final inlineExtractedImports = <String>[];
    String? inlineClassBody;

    if (isSeparateWidget) {
      final pathResolution = _resolveExtractedWidgetTargetPath(
        canonicalRoot: canonicalRoot,
        resolvedScreenPath: resolvedScreenPath,
        widgetClassName: widgetClassName,
        requestedPath: effectivePlan?.extractedWidgetFilePath,
      );
      if (pathResolution.error != null) {
        return DartWidgetInjectionResult(
          success: false,
          errorMessage: pathResolution.error,
        );
      }
      resolvedWidgetPath = pathResolution.targetPath!;

      final split = _splitImportsAndBody(rawExtractedCode);
      final widgetImports = <String>[
        'package:flutter/material.dart',
        ...split.imports,
        ...variation.requiredImports,
        ...(effectivePlan?.requiredImports ?? const <String>[]),
      ];
      preparedWidgetFileContent = _composeDartFile(
        imports: widgetImports,
        body: split.body,
      );

      final projectName = _readProjectName(canonicalRoot);
      extractedWidgetImport = _computeImportUri(
        canonicalRoot: canonicalRoot,
        projectName: projectName,
        fromScreenPath: resolvedScreenPath,
        targetWidgetPath: resolvedWidgetPath,
      );
    } else if (isInlineWidgetClass) {
      final split = _splitImportsAndBody(rawExtractedCode);
      inlineExtractedImports.addAll(split.imports);
      inlineClassBody = split.body.trim();
    }

    final callSite = _resolveCallSiteSnippet(
      variation: variation,
      extractedWidgetCode: rawExtractedCode,
      widgetClassName: widgetClassName,
    );
    if (callSite.isEmpty) {
      return const DartWidgetInjectionResult(
        success: false,
        errorMessage:
            'O widget gerado não possui callSiteSnippet nem dartCode válido para inserção.',
      );
    }

    // 1. Insert call-site at resolved anchor inside build() in memory first.
    final anchorResult = _insertCallSiteIntoScreen(
      screenCode: originalScreenCode,
      callSite: callSite,
      plan: effectivePlan,
      screenFilePath: screenFilePath,
    );
    if (!anchorResult.success || anchorResult.updatedCode == null) {
      return DartWidgetInjectionResult(
        success: false,
        errorMessage: anchorResult.errorMessage ??
            'Não foi possível encontrar um ponto de inserção válido em $screenFilePath.',
      );
    }

    var workingScreenCode = anchorResult.updatedCode!;

    // 2. Append inline widget class cleanly after all top-level classes.
    if (isInlineWidgetClass &&
        inlineClassBody != null &&
        inlineClassBody.isNotEmpty) {
      workingScreenCode = _appendTopLevelClassIfAbsent(
        screenCode: workingScreenCode,
        widgetClassName: widgetClassName,
        classBlock: inlineClassBody,
      );
    }

    // 3. Insert deduplicated requiredImports at the top of the screen file.
    final screenImports = <String>[
      ...variation.requiredImports,
      ...(effectivePlan?.requiredImports ?? const <String>[]),
      ...inlineExtractedImports,
      if (extractedWidgetImport != null) extractedWidgetImport,
    ];
    workingScreenCode = _insertImportsAtTop(
      screenCode: workingScreenCode,
      canonicalRoot: canonicalRoot,
      screenPath: resolvedScreenPath,
      importsToAdd: screenImports,
    );

    if (workingScreenCode == originalScreenCode) {
      return DartWidgetInjectionResult(
        success: false,
        errorMessage:
            'Nenhuma alteração aplicável foi produzida para $screenFilePath.',
      );
    }

    // 4. Create backups for every existing file about to be modified, then write atomically.
    final stamp = _createUniqueBackupStamp(canonicalRoot);
    final backupRoot =
        p.join(canonicalRoot, '.flrd', 'backups', 'widget_$stamp');
    String? usedBackupDir;
    final modifiedFiles = <String>[];
    final createdFiles = <String>[];

    try {
      if (screenExists) {
        final relScreen =
            p.relative(resolvedScreenPath, from: canonicalRoot).replaceAll('\\', '/');
        _writeBackup(
          backupRoot: backupRoot,
          relativePath: relScreen,
          originalContent: screenFile.readAsStringSync(),
        );
        usedBackupDir = backupRoot;
      }

      if (isSeparateWidget &&
          resolvedWidgetPath != null &&
          preparedWidgetFileContent != null) {
        final widgetFile = File(resolvedWidgetPath);
        final widgetExisted = widgetFile.existsSync();
        final relWidget =
            p.relative(resolvedWidgetPath, from: canonicalRoot).replaceAll('\\', '/');
        if (widgetExisted) {
          _writeBackup(
            backupRoot: backupRoot,
            relativePath: relWidget,
            originalContent: widgetFile.readAsStringSync(),
          );
          usedBackupDir = backupRoot;
          modifiedFiles.add(relWidget);
        } else {
          createdFiles.add(relWidget);
        }
        _atomicWriteFile(widgetFile, preparedWidgetFileContent);
      }

      final relScreen =
          p.relative(resolvedScreenPath, from: canonicalRoot).replaceAll('\\', '/');
      if (screenExists) {
        modifiedFiles.add(relScreen);
      } else {
        createdFiles.add(relScreen);
      }
      _atomicWriteFile(screenFile, workingScreenCode);
    } catch (e) {
      return DartWidgetInjectionResult(
        success: false,
        backupDir: usedBackupDir,
        errorMessage: 'Erro ao gravar arquivos modificados: $e',
      );
    }

    return DartWidgetInjectionResult(
      success: true,
      backupDir: usedBackupDir,
      modifiedFiles: List<String>.unmodifiable(modifiedFiles),
      createdFiles: List<String>.unmodifiable(createdFiles),
      resolvedAnchorDescription: anchorResult.anchorDescription,
      updatedScreenCode: workingScreenCode,
    );
  }

  // ---------------------------------------------------------------------------
  // EXTRACTED WIDGET & IMPORT HELPERS
  // ---------------------------------------------------------------------------

  static String? _resolveExtractedWidgetCode(WidgetVariation variation) {
    final explicit = variation.extractedWidgetCode?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final dart = variation.dartCode.trim();
    if (dart.isNotEmpty &&
        RegExp(
          r'(?:^|\n)\s*(?:abstract\s+)?class\s+[A-Za-z_][A-Za-z0-9_]*\s+extends\s+(?:StatefulWidget|StatelessWidget|ConsumerWidget|ConsumerStatefulWidget)\b',
        ).hasMatch(dart)) {
      return dart;
    }
    return null;
  }

  static String _resolveWidgetClassName({
    required String? extractedWidgetCode,
    required AiExecutionPlan? plan,
    required WidgetVariation variation,
  }) {
    if (extractedWidgetCode != null) {
      final m = RegExp(
        r'\bclass\s+([A-Z][A-Za-z0-9_]*)\s+extends\s+(?:StatefulWidget|StatelessWidget|ConsumerWidget|ConsumerStatefulWidget)\b',
      ).firstMatch(extractedWidgetCode);
      if (m != null) {
        return m.group(1)!;
      }
    }
    if (plan != null && plan.sanitizedWidgetName.isNotEmpty) {
      return plan.sanitizedWidgetName;
    }
    return AiExecutionPlan.sanitizeWidgetName(variation.title);
  }

  static ({String? targetPath, String? error}) _resolveExtractedWidgetTargetPath({
    required String canonicalRoot,
    required String resolvedScreenPath,
    required String widgetClassName,
    required String? requestedPath,
  }) {
    final trimmed = requestedPath?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      final candidate = p.isAbsolute(trimmed)
          ? p.normalize(p.absolute(trimmed))
          : p.normalize(p.absolute(p.join(canonicalRoot, trimmed)));
      if (!p.isWithin(canonicalRoot, candidate)) {
        return (
          targetPath: null,
          error: 'Caminho do widget fora do projeto: $trimmed',
        );
      }
      if (!p.equals(candidate, resolvedScreenPath)) {
        return (targetPath: candidate, error: null);
      }
    }

    final featureDir = _resolveFeatureDir(canonicalRoot, resolvedScreenPath);
    final snake = _toSnakeCase(widgetClassName);
    final derived = p.normalize(p.join(featureDir, 'widgets', '$snake.dart'));
    if (!p.isWithin(canonicalRoot, derived)) {
      return (
        targetPath: null,
        error: 'Caminho derivado do widget fora do projeto: $derived',
      );
    }
    return (targetPath: derived, error: null);
  }

  static String _resolveFeatureDir(
    String canonicalRoot,
    String resolvedScreenPath,
  ) {
    final screenDir = p.dirname(resolvedScreenPath);
    final dirName = p.basename(screenDir).toLowerCase();
    final parentDir = p.dirname(screenDir);

    if ((dirName == 'screens' || dirName == 'pages' || dirName == 'views') &&
        p.isWithin(canonicalRoot, parentDir)) {
      return parentDir;
    }

    if (dirName == 'presentation' &&
        p.isWithin(canonicalRoot, parentDir) &&
        Directory(p.join(parentDir, 'widgets')).existsSync() &&
        !Directory(p.join(screenDir, 'widgets')).existsSync()) {
      return parentDir;
    }

    return screenDir;
  }

  static String _toSnakeCase(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return 'generated_widget';
    final snake = clean
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toLowerCase();
    return snake.isEmpty ? 'generated_widget' : snake;
  }

  static ({List<String> imports, String body}) _splitImportsAndBody(String code) {
    final directives = DartSyntaxScanner.findImportDirectives(code);
    if (directives.isEmpty) {
      return (imports: const [], body: code.trim());
    }

    final imports = <String>[];
    var working = code;
    for (int i = directives.length - 1; i >= 0; i--) {
      final d = directives[i];
      imports.insert(0, d.rawStatement);
      var lineEnd = d.end;
      if (lineEnd < working.length && working[lineEnd] == '\r') lineEnd++;
      if (lineEnd < working.length && working[lineEnd] == '\n') lineEnd++;
      final lineStart = working.lastIndexOf('\n', max(0, d.start - 1)) + 1;
      final prefix = working.substring(lineStart, d.start);
      final removeFrom = prefix.trim().isEmpty ? lineStart : d.start;
      working = working.replaceRange(removeFrom, lineEnd, '');
    }

    return (imports: imports, body: working.trim());
  }

  static String _composeDartFile({
    required List<String> imports,
    required String body,
  }) {
    final ordered = _deduplicateAndSortImports(imports);
    final importBlock = ordered.join('\n');
    if (importBlock.isEmpty) {
      return '${body.trim()}\n';
    }
    return '$importBlock\n\n${body.trim()}\n';
  }

  static List<String> _deduplicateAndSortImports(List<String> rawImports) {
    final seenUris = <String>{};
    final dartImports = <String>[];
    final flutterImports = <String>[];
    final packageImports = <String>[];
    final relativeImports = <String>[];

    for (final raw in rawImports) {
      final uri = DartSyntaxScanner.normalizeImportUri(raw);
      final directive = DartSyntaxScanner.formatImportDirective(raw);
      if (uri.isEmpty || directive.isEmpty) continue;
      if (!seenUris.add(uri)) continue;

      if (uri.startsWith('dart:')) {
        dartImports.add(directive);
      } else if (uri.startsWith('package:flutter/')) {
        flutterImports.add(directive);
      } else if (uri.startsWith('package:')) {
        packageImports.add(directive);
      } else {
        relativeImports.add(directive);
      }
    }

    return [
      ...dartImports,
      ...flutterImports,
      ...packageImports,
      ...relativeImports,
    ];
  }

  static String? _readProjectName(String canonicalRoot) {
    final pubspecFile = File(p.join(canonicalRoot, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) return null;
    try {
      final doc = loadYaml(pubspecFile.readAsStringSync());
      if (doc is YamlMap) {
        final name = doc['name']?.toString().trim();
        if (name != null &&
            name.isNotEmpty &&
            RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) {
          return name;
        }
      }
    } catch (_) {}
    return null;
  }

  static String _computeImportUri({
    required String canonicalRoot,
    required String? projectName,
    required String fromScreenPath,
    required String targetWidgetPath,
  }) {
    final libRoot = p.normalize(p.join(canonicalRoot, 'lib'));
    if (projectName != null &&
        projectName.isNotEmpty &&
        p.isWithin(libRoot, targetWidgetPath)) {
      final relFromLib =
          p.relative(targetWidgetPath, from: libRoot).replaceAll('\\', '/');
      return 'package:$projectName/$relFromLib';
    }
    return p
        .relative(targetWidgetPath, from: p.dirname(fromScreenPath))
        .replaceAll('\\', '/');
  }

  static String _insertImportsAtTop({
    required String screenCode,
    required String canonicalRoot,
    required String screenPath,
    required List<String> importsToAdd,
  }) {
    if (importsToAdd.isEmpty) return screenCode;

    final existing = DartSyntaxScanner.findImportDirectives(screenCode);
    final existingUris = <String>{};
    final existingResolvedPaths = <String>{};
    final projectName = _readProjectName(canonicalRoot);
    final libRoot = p.normalize(p.join(canonicalRoot, 'lib'));
    final screenDir = p.dirname(screenPath);

    void registerUri(String uri) {
      existingUris.add(uri);
      if (projectName != null && uri.startsWith('package:$projectName/')) {
        final sub = uri.substring('package:$projectName/'.length);
        existingResolvedPaths.add(p.normalize(p.join(libRoot, sub)));
      } else if (!uri.startsWith('dart:') && !uri.startsWith('package:')) {
        existingResolvedPaths.add(p.normalize(p.join(screenDir, uri)));
      }
    }

    for (final imp in existing) {
      registerUri(imp.uri);
    }

    final toInsert = <String>[];
    for (final raw in importsToAdd) {
      final uri = DartSyntaxScanner.normalizeImportUri(raw);
      final directive = DartSyntaxScanner.formatImportDirective(raw);
      if (uri.isEmpty || directive.isEmpty) continue;

      String? resolvedTarget;
      if (projectName != null && uri.startsWith('package:$projectName/')) {
        resolvedTarget = p.normalize(
          p.join(libRoot, uri.substring('package:$projectName/'.length)),
        );
      } else if (!uri.startsWith('dart:') && !uri.startsWith('package:')) {
        resolvedTarget = p.normalize(p.join(screenDir, uri));
      }

      if (existingUris.contains(uri)) continue;
      if (resolvedTarget != null &&
          existingResolvedPaths.any((e) => p.equals(e, resolvedTarget!))) {
        continue;
      }

      registerUri(uri);
      toInsert.add(directive);
    }

    if (toInsert.isEmpty) return screenCode;

    final sortedToInsert = _deduplicateAndSortImports(toInsert);
    final block = sortedToInsert.join('\n');

    if (existing.isNotEmpty) {
      final last = existing.last;
      final insertPos = last.end;
      return '${screenCode.substring(0, insertPos)}\n$block${screenCode.substring(insertPos)}';
    }

    // No imports yet: place after optional `library ...;` or leading comments.
    final libMatch = RegExp(r'^\s*library\s+[^;]+;', multiLine: true)
        .firstMatch(screenCode);
    if (libMatch != null) {
      final insertPos = libMatch.end;
      return '${screenCode.substring(0, insertPos)}\n\n$block${screenCode.substring(insertPos)}';
    }

    return '$block\n\n$screenCode';
  }

  static String _appendTopLevelClassIfAbsent({
    required String screenCode,
    required String widgetClassName,
    required String classBlock,
  }) {
    final decls = DartSyntaxScanner.findTopLevelDeclarations(screenCode);
    if (decls.any((d) => d.name == widgetClassName)) {
      return screenCode;
    }

    if (decls.isNotEmpty) {
      final lastEnd = decls.last.end;
      final prefix = screenCode.substring(0, lastEnd).trimRight();
      final suffix = screenCode.substring(lastEnd).trim();
      if (suffix.isEmpty) {
        return '$prefix\n\n$classBlock\n';
      }
      return '$prefix\n\n$classBlock\n\n$suffix\n';
    }

    return '${screenCode.trimRight()}\n\n$classBlock\n';
  }

  // ---------------------------------------------------------------------------
  // CALL-SITE & ANCHOR RESOLUTION
  // ---------------------------------------------------------------------------

  static String _resolveCallSiteSnippet({
    required WidgetVariation variation,
    required String? extractedWidgetCode,
    required String widgetClassName,
  }) {
    final explicit = variation.callSiteSnippet?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return _stripTrailingSeparator(explicit);
    }
    if (extractedWidgetCode != null && extractedWidgetCode.isNotEmpty) {
      final hasZeroArgConst = RegExp(
        r'\bconst\s+' +
            RegExp.escape(widgetClassName) +
            r'\s*\(\s*(?:\{[^}]*\})?\s*\)',
      ).hasMatch(extractedWidgetCode);
      return hasZeroArgConst ? 'const $widgetClassName()' : '$widgetClassName()';
    }
    return _stripTrailingSeparator(variation.dartCode.trim());
  }

  static String _stripTrailingSeparator(String expr) {
    var trimmed = expr.trim();
    while (trimmed.endsWith(';') || trimmed.endsWith(',')) {
      trimmed = trimmed.substring(0, trimmed.length - 1).trimRight();
    }
    return trimmed;
  }

  static String _wrapCallSite(String callSite, String indent) {
    if (callSite.contains(_customStartMarker)) {
      return _indentSnippet(callSite, indent);
    }
    final cleanExpr = _stripTrailingSeparator(callSite);
    final indentedExpr = _indentSnippet(cleanExpr, indent);
    return '$indent$_customStartMarker\n$indentedExpr,\n$indent$_customEndMarker';
  }

  static ({_AnchorKind kind, String? needle}) _parseAnchorDirective(
    AiExecutionPlan? plan,
  ) {
    final rawHint = plan?.insertionAnchorHint.trim() ?? '';
    final visual = plan?.visualAnchorDescription.trim() ?? '';

    final explicit = _matchStructuredHint(rawHint);
    if (explicit != null) return explicit;

    if (rawHint.isNotEmpty) {
      final naturalFromHint = _matchNaturalLanguageHint(rawHint);
      if (naturalFromHint != null) return naturalFromHint;
    }

    if (visual.isNotEmpty &&
        (rawHint.isEmpty ||
            rawHint.toLowerCase() == 'bottom_of_column')) {
      final naturalFromVisual = _matchNaturalLanguageHint(visual);
      if (naturalFromVisual != null) return naturalFromVisual;
    }

    return (kind: _AnchorKind.bottomOfColumn, needle: null);
  }

  static ({_AnchorKind kind, String? needle})? _matchStructuredHint(String raw) {
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();

    if (lower.startsWith('after_text:')) {
      final needle = raw.substring('after_text:'.length).trim();
      if (needle.isNotEmpty) {
        return (kind: _AnchorKind.afterText, needle: needle);
      }
    }
    if (lower.startsWith('after:')) {
      final needle = raw.substring('after:'.length).trim();
      if (needle.isNotEmpty) {
        return (kind: _AnchorKind.afterText, needle: needle);
      }
    }
    if (lower.startsWith('before_text:')) {
      final needle = raw.substring('before_text:'.length).trim();
      if (needle.isNotEmpty) {
        return (kind: _AnchorKind.beforeText, needle: needle);
      }
    }
    if (lower.startsWith('before:')) {
      final needle = raw.substring('before:'.length).trim();
      if (needle.isNotEmpty) {
        return (kind: _AnchorKind.beforeText, needle: needle);
      }
    }

    if (lower == 'top_of_body' ||
        lower == 'top_of_column' ||
        lower == 'start_of_column' ||
        lower == 'top') {
      return (kind: _AnchorKind.topOfBody, needle: null);
    }

    if (lower == 'bottom_of_column' ||
        lower == 'bottom_of_body' ||
        lower == 'end_of_column' ||
        lower == 'bottom') {
      return (kind: _AnchorKind.bottomOfColumn, needle: null);
    }

    if (lower == 'center_body' || lower == 'center') {
      return (kind: _AnchorKind.centerBody, needle: null);
    }

    return null;
  }

  static ({_AnchorKind kind, String? needle})? _matchNaturalLanguageHint(
    String raw,
  ) {
    final lower = raw.toLowerCase();
    final quotedMatch = RegExp(r'''['"]([^'"]+)['"]''').firstMatch(raw);
    if (quotedMatch != null) {
      final needle = quotedMatch.group(1)!.trim();
      if (needle.isNotEmpty) {
        if (RegExp(r'\b(before|above|antes|acima)\b').hasMatch(lower)) {
          return (kind: _AnchorKind.beforeText, needle: needle);
        }
        if (RegExp(r'\b(after|below|under|following|depois|abaixo|após|apos)\b')
            .hasMatch(lower)) {
          return (kind: _AnchorKind.afterText, needle: needle);
        }
      }
    }

    if (RegExp(r'\b(top of|at the top|first child|topo|in[íi]cio|primeiro)\b')
        .hasMatch(lower)) {
      return (kind: _AnchorKind.topOfBody, needle: null);
    }
    if (RegExp(r'\b(center|centered|centro|centralizado)\b').hasMatch(lower)) {
      return (kind: _AnchorKind.centerBody, needle: null);
    }
    if (RegExp(r'\b(bottom|at the end|last child|final)\b').hasMatch(lower)) {
      return (kind: _AnchorKind.bottomOfColumn, needle: null);
    }
    return null;
  }

  static ({
    bool success,
    String? updatedCode,
    String? anchorDescription,
    String? errorMessage,
  }) _insertCallSiteIntoScreen({
    required String screenCode,
    required String callSite,
    required AiExecutionPlan? plan,
    required String screenFilePath,
  }) {
    final primaryScopes = DartSyntaxScanner.findPrimaryScreenScopes(screenCode);
    final buildMethod = DartSyntaxScanner.findBuildMethod(
      screenCode,
      startOffset: primaryScopes.isNotEmpty ? primaryScopes.first[0] : 0,
      endOffset: primaryScopes.isNotEmpty ? primaryScopes.last[1] : null,
    );

    if (buildMethod == null) {
      return (
        success: false,
        updatedCode: null,
        anchorDescription: null,
        errorMessage:
            'Método Widget build(BuildContext context) não encontrado ou com delimitadores inválidos em $screenFilePath.',
      );
    }

    final buildSlice =
        screenCode.substring(buildMethod.bodyStart, buildMethod.bodyEnd);
    final allLists = DartSyntaxScanner.findAllChildrenLists(
      screenCode,
      startOffset: buildMethod.bodyStart,
      endOffset: buildMethod.bodyEnd,
    );

    // Fail explicitly if build() declares `children:` with unbalanced brackets.
    if (allLists.isEmpty &&
        RegExp(r'\bchildren\s*:\s*(?:const\s+)?(?:<[^>]+>\s*)?\[')
            .hasMatch(buildSlice)) {
      return (
        success: false,
        updatedCode: null,
        anchorDescription: null,
        errorMessage:
            'Lista children: [...] desbalanceada ou inválida em $screenFilePath.',
      );
    }

    final bodyArg = DartSyntaxScanner.findScaffoldBodyArg(
      screenCode,
      startOffset: buildMethod.bodyStart,
      endOffset: buildMethod.bodyEnd,
    );

    final bodyLists = bodyArg != null
        ? allLists
            .where((l) =>
                l.matchStart >= bodyArg.valueStart &&
                l.closeBracket <= bodyArg.codeEnd)
            .toList()
        : allLists;
    final orderedLists = _prioritizeChildrenLists(
      screenCode,
      bodyLists.isNotEmpty ? bodyLists : allLists,
      buildMethod.bodyStart,
    );

    final directive = _parseAnchorDirective(plan);

    switch (directive.kind) {
      case _AnchorKind.afterText:
      case _AnchorKind.beforeText:
        final needle = directive.needle!;
        final textMatch = _findChildMatchingNeedle(
          screenCode,
          orderedLists,
          needle,
        );
        if (textMatch != null) {
          final isAfter = directive.kind == _AnchorKind.afterText;
          final updated = _insertAdjacentToChildElement(
            screenCode: screenCode,
            listMatch: textMatch.list,
            elemIndex: textMatch.elemIndex,
            callSite: callSite,
            insertAfter: isAfter,
          );
          return (
            success: true,
            updatedCode: updated,
            anchorDescription:
                '${isAfter ? 'Inserted after' : 'Inserted before'} "$needle"',
            errorMessage: null,
          );
        }

        // Check single body / Center(child: ...) containing the needle.
        if (bodyArg != null &&
            orderedLists.isEmpty &&
            _textMatchesNeedle(
              screenCode.substring(bodyArg.valueStart, bodyArg.codeEnd),
              needle,
            )) {
          final wrapped = _wrapSingleBodyInColumn(
            screenCode: screenCode,
            bodyValueStart: bodyArg.valueStart,
            bodyValueEnd: bodyArg.codeEnd,
            callSite: callSite,
            placeNewFirst: directive.kind == _AnchorKind.beforeText,
          );
          if (wrapped != null) {
            return (
              success: true,
              updatedCode: wrapped,
              anchorDescription:
                  'Wrapped body in Column ${directive.kind == _AnchorKind.beforeText ? 'before' : 'after'} "$needle"',
              errorMessage: null,
            );
          }
        }

        if (orderedLists.isNotEmpty) {
          final updated = _insertAtListBoundary(
            screenCode: screenCode,
            listMatch: orderedLists.first,
            callSite: callSite,
            atStart: false,
          );
          return (
            success: true,
            updatedCode: updated,
            anchorDescription:
                'Anchor "$needle" not found; inserted at bottom of main children list',
            errorMessage: null,
          );
        }
        break;

      case _AnchorKind.topOfBody:
        if (orderedLists.isNotEmpty) {
          final updated = _insertAtListBoundary(
            screenCode: screenCode,
            listMatch: orderedLists.first,
            callSite: callSite,
            atStart: true,
          );
          return (
            success: true,
            updatedCode: updated,
            anchorDescription: 'Inserted as first child of main children list',
            errorMessage: null,
          );
        }
        if (bodyArg != null) {
          final wrapped = _wrapSingleBodyInColumn(
            screenCode: screenCode,
            bodyValueStart: bodyArg.valueStart,
            bodyValueEnd: bodyArg.codeEnd,
            callSite: callSite,
            placeNewFirst: true,
          );
          if (wrapped != null) {
            return (
              success: true,
              updatedCode: wrapped,
              anchorDescription:
                  'Wrapped single body in Column with injected widget at top',
              errorMessage: null,
            );
          }
        }
        break;

      case _AnchorKind.centerBody:
        if (bodyArg != null && orderedLists.isEmpty) {
          final wrapped = _wrapSingleBodyInColumn(
            screenCode: screenCode,
            bodyValueStart: bodyArg.valueStart,
            bodyValueEnd: bodyArg.codeEnd,
            callSite: callSite,
            placeNewFirst: false,
          );
          if (wrapped != null) {
            return (
              success: true,
              updatedCode: wrapped,
              anchorDescription:
                  'Wrapped Center/body child in Column(mainAxisSize: MainAxisSize.min)',
              errorMessage: null,
            );
          }
        }
        if (orderedLists.isNotEmpty) {
          final updated = _insertAtListBoundary(
            screenCode: screenCode,
            listMatch: orderedLists.first,
            callSite: callSite,
            atStart: false,
          );
          return (
            success: true,
            updatedCode: updated,
            anchorDescription: 'Inserted into existing centered children list',
            errorMessage: null,
          );
        }
        final directCenter = _wrapReturnedCenterInBuild(
          screenCode: screenCode,
          buildStart: buildMethod.bodyStart,
          buildEnd: buildMethod.bodyEnd,
          callSite: callSite,
        );
        if (directCenter != null) {
          return (
            success: true,
            updatedCode: directCenter,
            anchorDescription:
                'Wrapped returned Center child in Column(mainAxisSize: MainAxisSize.min)',
            errorMessage: null,
          );
        }
        break;

      case _AnchorKind.bottomOfColumn:
        if (orderedLists.isNotEmpty) {
          final updated = _insertAtListBoundary(
            screenCode: screenCode,
            listMatch: orderedLists.first,
            callSite: callSite,
            atStart: false,
          );
          return (
            success: true,
            updatedCode: updated,
            anchorDescription: 'Inserted at bottom of main children list',
            errorMessage: null,
          );
        }
        if (bodyArg != null) {
          final wrapped = _wrapSingleBodyInColumn(
            screenCode: screenCode,
            bodyValueStart: bodyArg.valueStart,
            bodyValueEnd: bodyArg.codeEnd,
            callSite: callSite,
            placeNewFirst: false,
          );
          if (wrapped != null) {
            return (
              success: true,
              updatedCode: wrapped,
              anchorDescription:
                  'Wrapped single body in Column(mainAxisSize: MainAxisSize.min)',
              errorMessage: null,
            );
          }
        }
        break;
    }

    return (
      success: false,
      updatedCode: null,
      anchorDescription: null,
      errorMessage:
          'Nenhum slot de inserção válido (children: [...] ou Scaffold body:) encontrado em $screenFilePath.',
    );
  }

  static List<DartChildrenListMatch> _prioritizeChildrenLists(
    String code,
    List<DartChildrenListMatch> lists,
    int scopeStart,
  ) {
    if (lists.length <= 1) return lists;
    final layout = <DartChildrenListMatch>[];
    final others = <DartChildrenListMatch>[];

    for (final list in lists) {
      final prefix = code.substring(
        max(scopeStart, list.matchStart - 220),
        list.matchStart,
      );
      if (RegExp(r'\b(?:Column|ListView|CustomScrollView|Wrap|Flex)\s*\([^)]*$')
          .hasMatch(prefix)) {
        layout.add(list);
      } else {
        others.add(list);
      }
    }

    return [...layout, ...others];
  }

  static ({DartChildrenListMatch list, int elemIndex})? _findChildMatchingNeedle(
    String code,
    List<DartChildrenListMatch> lists,
    String needle,
  ) {
    // Pass 1: exact substring; Pass 2: case-insensitive / whitespace-normalized.
    for (final caseSensitive in const [true, false]) {
      for (final list in lists) {
        final elems = DartSyntaxScanner.splitTopLevelElements(
          code,
          list.openBracket,
          list.closeBracket,
        );
        for (int i = 0; i < elems.length; i++) {
          final snippet = code.substring(elems[i].codeStart, elems[i].codeEnd);
          if (_textMatchesNeedle(
            snippet,
            needle,
            caseSensitive: caseSensitive,
          )) {
            return (list: list, elemIndex: i);
          }
        }
      }
    }
    return null;
  }

  static bool _textMatchesNeedle(
    String snippet,
    String needle, {
    bool caseSensitive = false,
  }) {
    final cleanNeedle = needle.trim();
    if (cleanNeedle.isEmpty) return false;
    if (caseSensitive) {
      return snippet.contains(cleanNeedle);
    }
    final normSnippet =
        snippet.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final normNeedle =
        cleanNeedle.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return normSnippet.contains(normNeedle);
  }

  static String _insertAtListBoundary({
    required String screenCode,
    required DartChildrenListMatch listMatch,
    required String callSite,
    required bool atStart,
  }) {
    final strip = _stripConstForList(
      screenCode,
      listMatch,
      stripParentConst: !callSite.trimLeft().startsWith('const '),
    );
    final code = strip.code;
    final openBracket = strip.openBracket;
    final closeBracket = strip.closeBracket;

    final listLineIndent = _lineIndentAt(code, listMatch.matchStart - strip.deltaBeforeList);
    final closingLineStart = code.lastIndexOf('\n', closeBracket);
    var parentIndent = listLineIndent;
    if (closingLineStart != -1) {
      final prefix = code.substring(closingLineStart + 1, closeBracket);
      if (prefix.trim().isEmpty) {
        parentIndent = prefix;
      }
    }
    final childIndent = '$parentIndent  ';
    final wrapped = _wrapCallSite(callSite, childIndent);

    final inside = code.substring(openBracket + 1, closeBracket);
    final trimmedInside = inside.trim();

    if (trimmedInside.isEmpty) {
      return '${code.substring(0, openBracket + 1)}\n'
          '$wrapped\n'
          '$parentIndent${code.substring(closeBracket)}';
    }

    if (atStart) {
      final elems = DartSyntaxScanner.splitTopLevelElements(
        code,
        openBracket,
        closeBracket,
      );
      final firstElem = elems.isNotEmpty ? elems.first : null;
      final elemIndent = firstElem != null &&
              _lineStartAt(code, firstElem.codeStart) > openBracket
          ? _lineIndentAt(code, firstElem.codeStart)
          : childIndent;
      final firstWrapped = _wrapCallSite(callSite, elemIndent);
      final rest = code.substring(openBracket + 1);
      final hasLeadingNewline = RegExp(r'^[ \t]*\r?\n').hasMatch(rest);
      return '${code.substring(0, openBracket + 1)}\n'
          '$firstWrapped'
          '${hasLeadingNewline ? rest : '\n$elemIndent${rest.trimLeft()}'}';
    }

    final elems = DartSyntaxScanner.splitTopLevelElements(
      code,
      openBracket,
      closeBracket,
    );
    final lastElem = elems.isNotEmpty ? elems.last : null;
    if (lastElem != null) {
      final elemIndent = _lineStartAt(code, lastElem.codeStart) > openBracket
          ? _lineIndentAt(code, lastElem.codeStart)
          : childIndent;
      final bottomWrapped = _wrapCallSite(callSite, elemIndent);
      if (lastElem.commaIndex != null) {
        final afterComma = lastElem.commaIndex! + 1;
        final rest = code.substring(afterComma);
        final hasLeadingNewline = RegExp(r'^[ \t]*\r?\n').hasMatch(rest);
        return '${code.substring(0, afterComma)}\n'
            '$bottomWrapped'
            '${hasLeadingNewline ? rest : '\n$parentIndent${rest.trimLeft()}'}';
      }
      final rest = code.substring(lastElem.codeEnd);
      final hasLeadingNewline = RegExp(r'^[ \t]*\r?\n').hasMatch(rest);
      return '${code.substring(0, lastElem.codeEnd)},\n'
          '$bottomWrapped'
          '${hasLeadingNewline ? rest : '\n$parentIndent${rest.trimLeft()}'}';
    }

    final needsComma = !trimmedInside.endsWith(',');
    return '${code.substring(0, closeBracket)}'
        '${needsComma ? ',' : ''}\n'
        '$wrapped\n'
        '$parentIndent${code.substring(closeBracket)}';
  }

  static String _insertAdjacentToChildElement({
    required String screenCode,
    required DartChildrenListMatch listMatch,
    required int elemIndex,
    required String callSite,
    required bool insertAfter,
  }) {
    final strip = _stripConstForList(
      screenCode,
      listMatch,
      stripParentConst: !callSite.trimLeft().startsWith('const '),
    );
    final code = strip.code;
    final elems = DartSyntaxScanner.splitTopLevelElements(
      code,
      strip.openBracket,
      strip.closeBracket,
    );
    if (elemIndex < 0 || elemIndex >= elems.length) {
      return _insertAtListBoundary(
        screenCode: screenCode,
        listMatch: listMatch,
        callSite: callSite,
        atStart: !insertAfter,
      );
    }

    final target = elems[elemIndex];
    final listIndent = _lineIndentAt(code, listMatch.matchStart - strip.deltaBeforeList);
    final onOwnLine = _lineStartAt(code, target.codeStart) > strip.openBracket;
    final elemIndent = onOwnLine
        ? _lineIndentAt(code, target.codeStart)
        : '$listIndent  ';
    final wrapped = _wrapCallSite(callSite, elemIndent);

    if (!insertAfter) {
      final anchorLineStart = _lineStartAt(code, target.fullStart);
      if (anchorLineStart > strip.openBracket) {
        return '${code.substring(0, anchorLineStart)}'
            '$wrapped\n'
            '${code.substring(anchorLineStart)}';
      }
      final insertPos = max(strip.openBracket + 1, target.fullStart);
      return '${code.substring(0, insertPos)}\n'
          '$wrapped\n'
          '$elemIndent${code.substring(insertPos)}';
    }

    if (target.commaIndex != null) {
      final afterComma = target.commaIndex! + 1;
      final rest = code.substring(afterComma);
      final hasLeadingNewline = RegExp(r'^[ \t]*\r?\n').hasMatch(rest);
      return '${code.substring(0, afterComma)}\n'
          '$wrapped'
          '${hasLeadingNewline ? rest : '\n$elemIndent${rest.trimLeft()}'}';
    }

    final rest = code.substring(target.codeEnd);
    final hasLeadingNewline = RegExp(r'^[ \t]*\r?\n').hasMatch(rest);
    return '${code.substring(0, target.codeEnd)},\n'
        '$wrapped'
        '${hasLeadingNewline ? rest : '\n$listIndent${rest.trimLeft()}'}';
  }

  static String? _wrapSingleBodyInColumn({
    required String screenCode,
    required int bodyValueStart,
    required int bodyValueEnd,
    required String callSite,
    required bool placeNewFirst,
  }) {
    var working = screenCode;
    var valStart = bodyValueStart;
    var valEnd = bodyValueEnd;

    // Strip leading `const ` on wrapping widget (e.g. `const Center(...)` or `const SafeArea(...)`).
    final bodyText = working.substring(valStart, valEnd);
    final leadingConst = RegExp(r'^const\s+').firstMatch(bodyText);
    if (leadingConst != null) {
      working = working.replaceRange(valStart, valStart + leadingConst.end, '');
      valEnd -= leadingConst.end;
    }

    final strippedBody = working.substring(valStart, valEnd);
    final centerMatch = RegExp(r'^Center\s*\(').firstMatch(strippedBody);
    if (centerMatch != null) {
      final centerOpenParen = valStart + centerMatch.end - 1;
      final centerCloseParen =
          DartSyntaxScanner.findMatchingDelimiter(working, centerOpenParen);
      if (centerCloseParen != -1 && centerCloseParen <= valEnd) {
        final args = DartSyntaxScanner.findNamedArguments(
          working,
          centerOpenParen,
          centerCloseParen,
        );
        final childArg = args.where((a) => a.name == 'child').firstOrNull;
        if (childArg != null) {
          return _replaceSingleChildWithColumn(
            code: working,
            childStart: childArg.valueStart,
            childEnd: childArg.codeEnd,
            baseIndent: _lineIndentAt(working, childArg.codeStart),
            callSite: callSite,
            placeNewFirst: placeNewFirst,
          );
        }
      }
    }

    final baseIndent = _lineIndentAt(working, valStart);
    return _replaceSingleChildWithColumn(
      code: working,
      childStart: valStart,
      childEnd: valEnd,
      baseIndent: baseIndent,
      callSite: callSite,
      placeNewFirst: placeNewFirst,
    );
  }

  static String? _wrapReturnedCenterInBuild({
    required String screenCode,
    required int buildStart,
    required int buildEnd,
    required String callSite,
  }) {
    final slice = screenCode.substring(buildStart, buildEnd);
    final m = RegExp(r'\b(const\s+)?Center\s*\(').firstMatch(slice);
    if (m == null) return null;

    var working = screenCode;
    var openParen = buildStart + m.end - 1;
    if (m.group(1) != null) {
      final constStart = buildStart + m.start;
      final constEnd = constStart + m.group(1)!.length;
      working = working.replaceRange(constStart, constEnd, '');
      openParen -= (constEnd - constStart);
    }

    final closeParen = DartSyntaxScanner.findMatchingDelimiter(working, openParen);
    if (closeParen == -1) return null;
    final args = DartSyntaxScanner.findNamedArguments(working, openParen, closeParen);
    final childArg = args.where((a) => a.name == 'child').firstOrNull;
    if (childArg == null) return null;

    return _replaceSingleChildWithColumn(
      code: working,
      childStart: childArg.valueStart,
      childEnd: childArg.codeEnd,
      baseIndent: _lineIndentAt(working, childArg.codeStart),
      callSite: callSite,
      placeNewFirst: false,
    );
  }

  static String _replaceSingleChildWithColumn({
    required String code,
    required int childStart,
    required int childEnd,
    required String baseIndent,
    required String callSite,
    required bool placeNewFirst,
  }) {
    final existingExpr = code.substring(childStart, childEnd).trim();
    final innerIndent = '$baseIndent    ';
    final existingFormatted = '${_indentSnippet(existingExpr, innerIndent)},';
    final newFormatted = _wrapCallSite(callSite, innerIndent);

    final childrenBlock = placeNewFirst
        ? '$newFormatted\n$existingFormatted'
        : '$existingFormatted\n$newFormatted';

    final columnExpr = '''Column(
$baseIndent  mainAxisSize: MainAxisSize.min,
$baseIndent  children: [
$childrenBlock
$baseIndent  ],
$baseIndent)''';

    return code.replaceRange(childStart, childEnd, columnExpr);
  }

  static ({
    String code,
    int openBracket,
    int closeBracket,
    int deltaBeforeList,
  }) _stripConstForList(
    String code,
    DartChildrenListMatch listMatch, {
    required bool stripParentConst,
  }) {
    final edits = <({int start, int end})>[];
    if (listMatch.constStart != null && listMatch.constEnd != null) {
      edits.add((start: listMatch.constStart!, end: listMatch.constEnd!));
    }

    if (stripParentConst) {
      final before = code.substring(0, listMatch.matchStart);
      final enclosing = RegExp(
        r'\b(const\s+)(?:Column|ListView|Wrap|Flex|Center|SafeArea|Padding|SingleChildScrollView)\s*\(',
      ).allMatches(before);
      for (final m in enclosing) {
        final parenIdx = m.end - 1;
        final closeParen = DartSyntaxScanner.findMatchingDelimiter(code, parenIdx);
        if (closeParen != -1 && closeParen > listMatch.closeBracket) {
          edits.add((start: m.start, end: m.start + m.group(1)!.length));
        }
      }
    }

    if (edits.isEmpty) {
      return (
        code: code,
        openBracket: listMatch.openBracket,
        closeBracket: listMatch.closeBracket,
        deltaBeforeList: 0,
      );
    }

    edits.sort((a, b) => a.start.compareTo(b.start));
    var working = code;
    var deltaBeforeList = 0;
    var deltaBeforeOpen = 0;
    var deltaBeforeClose = 0;

    for (int i = edits.length - 1; i >= 0; i--) {
      final e = edits[i];
      final len = e.end - e.start;
      working = working.replaceRange(e.start, e.end, '');
      if (e.end <= listMatch.matchStart) deltaBeforeList += len;
      if (e.end <= listMatch.openBracket) deltaBeforeOpen += len;
      if (e.end <= listMatch.closeBracket) deltaBeforeClose += len;
    }

    return (
      code: working,
      openBracket: listMatch.openBracket - deltaBeforeOpen,
      closeBracket: listMatch.closeBracket - deltaBeforeClose,
      deltaBeforeList: deltaBeforeList,
    );
  }

  // ---------------------------------------------------------------------------
  // BACKUP & ATOMIC FILE I/O HELPERS
  // ---------------------------------------------------------------------------

  static String _createUniqueBackupStamp(String canonicalRoot) {
    final base = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    var candidate = base;
    var counter = 1;
    while (Directory(
      p.join(canonicalRoot, '.flrd', 'backups', 'widget_$candidate'),
    ).existsSync()) {
      candidate = '${base}_$counter';
      counter++;
    }
    return candidate;
  }

  static void _writeBackup({
    required String backupRoot,
    required String relativePath,
    required String originalContent,
  }) {
    final backupFile = File(p.join(backupRoot, relativePath));
    backupFile.parent.createSync(recursive: true);
    backupFile.writeAsStringSync(originalContent, flush: true);
  }

  static void _atomicWriteFile(File targetFile, String content) {
    targetFile.parent.createSync(recursive: true);
    final tmpFile = File(
      '${targetFile.path}.flrd_tmp_${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      tmpFile.writeAsStringSync(content, flush: true);
      tmpFile.renameSync(targetFile.path);
    } catch (_) {
      if (tmpFile.existsSync()) {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
      targetFile.writeAsStringSync(content, flush: true);
    }
  }

  static String _indentSnippet(String snippet, String baseIndent) {
    final lines = snippet.trimRight().split('\n');
    int? minIndent;
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      final match = RegExp(r'^[ \t]*').firstMatch(l);
      final len = match?.group(0)?.length ?? 0;
      if (minIndent == null || len < minIndent) {
        minIndent = len;
      }
    }
    minIndent ??= 0;
    return lines.map((l) {
      if (l.trim().isEmpty) return '';
      final stripped =
          l.length >= minIndent! ? l.substring(minIndent) : l.trimLeft();
      return '$baseIndent$stripped';
    }).join('\n');
  }

  static int _lineStartAt(String code, int offset) {
    if (offset <= 0) return 0;
    final nl = code.lastIndexOf('\n', offset - 1);
    return nl == -1 ? 0 : nl + 1;
  }

  static String _lineIndentAt(String code, int offset) {
    final start = _lineStartAt(code, offset);
    final rest = code.substring(start);
    final match = RegExp(r'^[ \t]*').firstMatch(rest);
    return match?.group(0) ?? '';
  }
}
