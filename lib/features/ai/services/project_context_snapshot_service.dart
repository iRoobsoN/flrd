import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const _snapshotSentinel = Object();

/// Immutable snapshot of an existing Flutter project's packages, theme, router,
/// `.flrd/manifest.json` rules, widget layout, and target screen source.
@immutable
class ProjectContextSnapshot {
  final String projectPath;
  final String projectName;
  final Map<String, dynamic> manifestRules;
  final List<String> aiPromptRules;
  final Set<String> dependencies;
  final bool hasAppColors;
  final bool hasGoRouter;
  final String? themeExcerpt;
  final String? routerExcerpt;
  final String? targetScreenPath;
  final String? targetScreenSource;
  final List<String> existingWidgetFiles;

  const ProjectContextSnapshot({
    required this.projectPath,
    required this.projectName,
    this.manifestRules = const {},
    this.aiPromptRules = const [],
    this.dependencies = const {},
    this.hasAppColors = false,
    this.hasGoRouter = false,
    this.themeExcerpt,
    this.routerExcerpt,
    this.targetScreenPath,
    this.targetScreenSource,
    this.existingWidgetFiles = const [],
  });

  /// Captures a [ProjectContextSnapshot] from [projectPath].
  static Future<ProjectContextSnapshot> capture({
    required String projectPath,
    String? targetScreenPath,
  }) {
    return ProjectContextSnapshotService.capture(
      projectPath: projectPath,
      targetScreenPath: targetScreenPath,
    );
  }

  /// Formats a concise, structured prompt context section for AI planning and codegen.
  String toPromptSummary({int maxTargetSourceChars = 12000}) {
    final buffer = StringBuffer();
    buffer.writeln('=== PROJECT CONTEXT SNAPSHOT ===');
    buffer.writeln(
      'Project Name: ${projectName.isNotEmpty ? projectName : "(unknown)"}',
    );
    if (projectPath.isNotEmpty) {
      buffer.writeln('Project Path: ${projectPath.replaceAll('\\', '/')}');
    }

    // 1. Installed packages
    buffer.writeln();
    buffer.writeln('1. INSTALLED PACKAGES (pubspec.yaml):');
    if (dependencies.isEmpty) {
      buffer.writeln('- None detected.');
    } else {
      final sortedDeps = dependencies.toList()..sort();
      buffer.writeln('- Installed dependencies: ${sortedDeps.join(', ')}');
    }
    buffer.writeln(
      '- Rule: Only import packages listed above (plus dart:* and package:flutter/*) unless declared in requiredPackages.',
    );

    // 2. Theme & AppColors rule
    buffer.writeln();
    buffer.writeln('2. THEME & STYLING RULES:');
    if (hasAppColors) {
      buffer.writeln(
        '- AppColors IS AVAILABLE (hasAppColors == true). You may use AppColors tokens defined in the theme excerpt below, or Theme.of(context).colorScheme / Theme.of(context).textTheme.',
      );
    } else {
      buffer.writeln(
        '- STRICT RULE: AppColors is NOT present in this project (hasAppColors == false). Only use AppColors if hasAppColors == true; NEVER reference AppColors here. Always use Theme.of(context).colorScheme and Theme.of(context).textTheme.',
      );
    }

    // 3. Routing & GoRouter rule
    buffer.writeln();
    buffer.writeln('3. ROUTING & NAVIGATION RULES:');
    if (hasGoRouter) {
      buffer.writeln(
        '- go_router IS INSTALLED (hasGoRouter == true). You may use context.go(...) / context.push(...) matching the router configuration below.',
      );
    } else {
      buffer.writeln(
        '- STRICT RULE: go_router is NOT installed in this project (hasGoRouter == false). Only use context.go / context.push if hasGoRouter == true; NEVER call context.go or context.push here. Always use Navigator (e.g. Navigator.of(context).push(...)).',
      );
    }

    // 4. Manifest rules & aiPromptRules
    buffer.writeln();
    buffer.writeln('4. MANIFEST RULES (.flrd/manifest.json):');
    final metadataKeys = [
      'presetName',
      'preset',
      'designSystem',
      'stateManagement',
      'routingPattern',
      'navigationStyle',
    ];
    for (final key in metadataKeys) {
      final value = manifestRules[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        buffer.writeln('- $key: ${value.toString().trim()}');
      }
    }
    if (aiPromptRules.isEmpty) {
      buffer.writeln('- aiPromptRules: (none specified)');
    } else {
      buffer.writeln('- aiPromptRules:');
      for (final rule in aiPromptRules) {
        buffer.writeln('  * $rule');
      }
    }

    // 5. Theme excerpt
    if (themeExcerpt != null && themeExcerpt!.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('5. THEME EXCERPT:');
      buffer.writeln('```dart');
      buffer.writeln(themeExcerpt!.trimRight());
      buffer.writeln('```');
    }

    // 6. Router excerpt
    if (routerExcerpt != null && routerExcerpt!.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('6. ROUTER EXCERPT:');
      buffer.writeln('```dart');
      buffer.writeln(routerExcerpt!.trimRight());
      buffer.writeln('```');
    }

    // 7. Existing widget files
    buffer.writeln();
    buffer.writeln('7. EXISTING WIDGET FILES:');
    if (existingWidgetFiles.isEmpty) {
      buffer.writeln('- (none detected)');
    } else {
      for (final widgetFile in existingWidgetFiles) {
        buffer.writeln('- $widgetFile');
      }
    }

    // 8. Target screen source for natural-language slot placement
    buffer.writeln();
    buffer.writeln(
      '8. TARGET SCREEN SOURCE${targetScreenPath != null ? ' ($targetScreenPath)' : ''}:',
    );
    if (targetScreenSource == null || targetScreenSource!.trim().isEmpty) {
      buffer.writeln('- (no target screen source loaded)');
    } else {
      final source = targetScreenSource!;
      final boundedSource = source.length <= maxTargetSourceChars
          ? source.trimRight()
          : '${source.substring(0, maxTargetSourceChars).trimRight()}\n// ... [truncated ${source.length - maxTargetSourceChars} chars]';
      buffer.writeln(
        'Inspect the widget tree slots below so visualAnchorDescription and insertionAnchorHint match real anchors in this screen:',
      );
      buffer.writeln('```dart');
      buffer.writeln(boundedSource);
      buffer.writeln('```');
    }

    return buffer.toString().trimRight();
  }

  ProjectContextSnapshot copyWith({
    String? projectPath,
    String? projectName,
    Map<String, dynamic>? manifestRules,
    List<String>? aiPromptRules,
    Set<String>? dependencies,
    bool? hasAppColors,
    bool? hasGoRouter,
    Object? themeExcerpt = _snapshotSentinel,
    Object? routerExcerpt = _snapshotSentinel,
    Object? targetScreenPath = _snapshotSentinel,
    Object? targetScreenSource = _snapshotSentinel,
    List<String>? existingWidgetFiles,
  }) {
    return ProjectContextSnapshot(
      projectPath: projectPath ?? this.projectPath,
      projectName: projectName ?? this.projectName,
      manifestRules: manifestRules != null
          ? Map<String, dynamic>.unmodifiable(manifestRules)
          : this.manifestRules,
      aiPromptRules: aiPromptRules != null
          ? List<String>.unmodifiable(aiPromptRules)
          : this.aiPromptRules,
      dependencies: dependencies != null
          ? Set<String>.unmodifiable(dependencies)
          : this.dependencies,
      hasAppColors: hasAppColors ?? this.hasAppColors,
      hasGoRouter: hasGoRouter ?? this.hasGoRouter,
      themeExcerpt: identical(themeExcerpt, _snapshotSentinel)
          ? this.themeExcerpt
          : themeExcerpt as String?,
      routerExcerpt: identical(routerExcerpt, _snapshotSentinel)
          ? this.routerExcerpt
          : routerExcerpt as String?,
      targetScreenPath: identical(targetScreenPath, _snapshotSentinel)
          ? this.targetScreenPath
          : targetScreenPath as String?,
      targetScreenSource: identical(targetScreenSource, _snapshotSentinel)
          ? this.targetScreenSource
          : targetScreenSource as String?,
      existingWidgetFiles: existingWidgetFiles != null
          ? List<String>.unmodifiable(existingWidgetFiles)
          : this.existingWidgetFiles,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectContextSnapshot &&
        other.projectPath == projectPath &&
        other.projectName == projectName &&
        mapEquals(other.manifestRules, manifestRules) &&
        listEquals(other.aiPromptRules, aiPromptRules) &&
        setEquals(other.dependencies, dependencies) &&
        other.hasAppColors == hasAppColors &&
        other.hasGoRouter == hasGoRouter &&
        other.themeExcerpt == themeExcerpt &&
        other.routerExcerpt == routerExcerpt &&
        other.targetScreenPath == targetScreenPath &&
        other.targetScreenSource == targetScreenSource &&
        listEquals(other.existingWidgetFiles, existingWidgetFiles);
  }

  @override
  int get hashCode => Object.hash(
        projectPath,
        projectName,
        Object.hashAll(manifestRules.keys),
        Object.hashAll(aiPromptRules),
        Object.hashAll(dependencies),
        hasAppColors,
        hasGoRouter,
        themeExcerpt,
        routerExcerpt,
        targetScreenPath,
        targetScreenSource,
        Object.hashAll(existingWidgetFiles),
      );

  @override
  String toString() =>
      'ProjectContextSnapshot(projectName: $projectName, deps: ${dependencies.length}, hasAppColors: $hasAppColors, hasGoRouter: $hasGoRouter, aiPromptRules: ${aiPromptRules.length}, existingWidgetFiles: ${existingWidgetFiles.length})';
}

/// Captures grounded project context from `pubspec.yaml`, `.flrd/manifest.json`,
/// theme/router files, widget files, and the active target screen.
class ProjectContextSnapshotService {
  ProjectContextSnapshotService._();

  static const int _maxExcerptChars = 4000;

  static final RegExp _appColorsDeclarationRegex = RegExp(
    r'^\s*(?:abstract\s+)?(?:final\s+|base\s+|sealed\s+)?class\s+AppColors\b',
    multiLine: true,
  );
  static final RegExp _goRouterImportRegex = RegExp(
    r'''import\s+['"]package:go_router/''',
  );
  static final RegExp _widgetFileSuffixRegex = RegExp(
    r'(_widget|_card|_badge|_banner|_tile|_panel|_dialog|_modal|_sheet)\.dart$',
    caseSensitive: false,
  );

  /// Inspects [projectPath] (and optional [targetScreenPath]) without throwing on missing files.
  static Future<ProjectContextSnapshot> capture({
    required String projectPath,
    String? targetScreenPath,
  }) async {
    final cleanPath = _normalizeProjectPath(projectPath);
    if (cleanPath.isEmpty) {
      return ProjectContextSnapshot(
        projectPath: '',
        projectName: '',
        targetScreenPath: _cleanOptionalTargetPath(targetScreenPath),
      );
    }

    // 1. Parse pubspec.yaml
    final pubspecResult = await _readPubspec(cleanPath);
    final projectName = pubspecResult.projectName;
    final dependencies = pubspecResult.dependencies;

    // 2. Parse .flrd/manifest.json
    final manifestResult = await _readManifest(cleanPath);

    // 3. Scan lib/ for theme, router, GoRouter/AppColors usage, and existing widget files
    final libScan = await _scanLibDirectory(cleanPath);

    final hasAppColors = libScan.hasAppColors;
    final hasGoRouter =
        dependencies.contains('go_router') || libScan.hasGoRouterImport;

    // 4. Read target screen if supplied
    final targetResult = await _readTargetScreen(
      projectPath: cleanPath,
      targetScreenPath: targetScreenPath,
    );

    return ProjectContextSnapshot(
      projectPath: cleanPath,
      projectName: projectName,
      manifestRules: manifestResult.manifestRules,
      aiPromptRules: manifestResult.aiPromptRules,
      dependencies: Set<String>.unmodifiable(dependencies),
      hasAppColors: hasAppColors,
      hasGoRouter: hasGoRouter,
      themeExcerpt: libScan.themeExcerpt,
      routerExcerpt: libScan.routerExcerpt,
      targetScreenPath: targetResult.normalizedPath,
      targetScreenSource: targetResult.source,
      existingWidgetFiles: List<String>.unmodifiable(libScan.widgetFiles),
    );
  }

  static String _normalizeProjectPath(String rawPath) {
    var clean = rawPath.trim();
    if ((clean.startsWith('"') && clean.endsWith('"')) ||
        (clean.startsWith("'") && clean.endsWith("'"))) {
      clean = clean.substring(1, clean.length - 1).trim();
    }
    if (clean.isEmpty) return '';
    final normalized = p.normalize(clean);
    if (p.basename(normalized).toLowerCase() == 'pubspec.yaml' &&
        FileSystemEntity.isFileSync(normalized)) {
      return p.dirname(normalized);
    }
    return normalized;
  }

  static String? _cleanOptionalTargetPath(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim().replaceAll('\\', '/');
    return trimmed.isEmpty ? null : trimmed;
  }

  static Future<({String projectName, Set<String> dependencies})> _readPubspec(
    String projectPath,
  ) async {
    final fallbackName = p.basename(projectPath);
    final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) {
      return (projectName: fallbackName, dependencies: <String>{});
    }

    try {
      final raw = await pubspecFile.readAsString();
      final doc = loadYaml(raw);
      if (doc is! YamlMap) {
        return (projectName: fallbackName, dependencies: <String>{});
      }

      final rawName = doc['name']?.toString().trim();
      final projectName =
          (rawName != null && rawName.isNotEmpty) ? rawName : fallbackName;

      final dependencies = <String>{};
      final rawDeps = doc['dependencies'];
      if (rawDeps is YamlMap) {
        for (final key in rawDeps.keys) {
          final name = key.toString().trim();
          if (name.isNotEmpty) dependencies.add(name);
        }
      } else if (rawDeps is Map) {
        for (final key in rawDeps.keys) {
          final name = key.toString().trim();
          if (name.isNotEmpty) dependencies.add(name);
        }
      }

      return (projectName: projectName, dependencies: dependencies);
    } catch (_) {
      return (projectName: fallbackName, dependencies: <String>{});
    }
  }

  static Future<
      ({
        Map<String, dynamic> manifestRules,
        List<String> aiPromptRules,
      })> _readManifest(String projectPath) async {
    final manifestFile = File(p.join(projectPath, '.flrd', 'manifest.json'));
    if (!await manifestFile.exists()) {
      return (
        manifestRules: const <String, dynamic>{},
        aiPromptRules: const <String>[],
      );
    }

    try {
      final raw = await manifestFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return (
          manifestRules: const <String, dynamic>{},
          aiPromptRules: const <String>[],
        );
      }

      final rulesMap = Map<String, dynamic>.from(decoded);
      final rawPromptRules =
          rulesMap['aiPromptRules'] ?? rulesMap['ai_prompt_rules'];
      final promptRules = _extractAiPromptRules(rawPromptRules);

      return (
        manifestRules: Map<String, dynamic>.unmodifiable(rulesMap),
        aiPromptRules: List<String>.unmodifiable(promptRules),
      );
    } catch (_) {
      return (
        manifestRules: const <String, dynamic>{},
        aiPromptRules: const <String>[],
      );
    }
  }

  static List<String> _extractAiPromptRules(dynamic raw) {
    if (raw == null) return const [];
    if (raw is Iterable) {
      return raw
          .where((item) => item != null)
          .map((item) => item.toString().trim())
          .where((line) => line.isNotEmpty)
          .toList();
    }
    if (raw is String) {
      return raw
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static Future<
      ({
        bool hasAppColors,
        bool hasGoRouterImport,
        String? themeExcerpt,
        String? routerExcerpt,
        List<String> widgetFiles,
      })> _scanLibDirectory(String projectPath) async {
    final libDir = Directory(p.join(projectPath, 'lib'));
    if (!await libDir.exists()) {
      return (
        hasAppColors: false,
        hasGoRouterImport: false,
        themeExcerpt: null,
        routerExcerpt: null,
        widgetFiles: const <String>[],
      );
    }

    final dartFiles = <({File file, String relPath})>[];
    try {
      await for (final entity
          in libDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final baseName = p.basename(entity.path).toLowerCase();
        if (!baseName.endsWith('.dart')) continue;
        if (_isGeneratedDartFile(baseName)) continue;
        final relPath =
            p.relative(entity.path, from: projectPath).replaceAll('\\', '/');
        dartFiles.add((file: entity, relPath: relPath));
      }
    } catch (_) {
      return (
        hasAppColors: false,
        hasGoRouterImport: false,
        themeExcerpt: null,
        routerExcerpt: null,
        widgetFiles: const <String>[],
      );
    }

    dartFiles.sort((a, b) => a.relPath.compareTo(b.relPath));

    var hasAppColors = false;
    var hasGoRouterImport = false;
    final themeEntries = <({String relPath, String content})>[];
    final routerEntries = <({String relPath, String content})>[];
    final widgetFiles = <String>[];

    for (final entry in dartFiles) {
      final relPath = entry.relPath;
      final lowerRel = relPath.toLowerCase();
      final baseName = p.basename(lowerRel);

      if (_isWidgetFile(lowerRel, baseName)) {
        widgetFiles.add(relPath);
      }

      if (baseName == 'app_colors.dart') {
        hasAppColors = true;
      }

      String content;
      try {
        content = await entry.file.readAsString();
      } catch (_) {
        continue;
      }

      if (!hasAppColors && _appColorsDeclarationRegex.hasMatch(content)) {
        hasAppColors = true;
      }
      if (!hasGoRouterImport && _goRouterImportRegex.hasMatch(content)) {
        hasGoRouterImport = true;
      }

      if (_isThemeFile(lowerRel, baseName)) {
        themeEntries.add((relPath: relPath, content: content));
      }
      if (_isRouterFile(lowerRel, baseName)) {
        routerEntries.add((relPath: relPath, content: content));
      }
    }

    return (
      hasAppColors: hasAppColors,
      hasGoRouterImport: hasGoRouterImport,
      themeExcerpt: _buildCombinedExcerpt(themeEntries),
      routerExcerpt: _buildCombinedExcerpt(routerEntries),
      widgetFiles: widgetFiles,
    );
  }

  static bool _isGeneratedDartFile(String lowerBaseName) {
    return lowerBaseName.endsWith('.g.dart') ||
        lowerBaseName.endsWith('.freezed.dart') ||
        lowerBaseName.endsWith('.gr.dart') ||
        lowerBaseName.endsWith('.mocks.dart') ||
        lowerBaseName == 'generated_plugin_registrant.dart';
  }

  static bool _isThemeFile(String lowerRelPath, String lowerBaseName) {
    return lowerBaseName == 'app_theme.dart' ||
        lowerBaseName == 'app_colors.dart' ||
        lowerBaseName.endsWith('_theme.dart') ||
        lowerRelPath.contains('/theme/') && lowerBaseName.endsWith('.dart');
  }

  static bool _isRouterFile(String lowerRelPath, String lowerBaseName) {
    return lowerBaseName == 'app_router.dart' ||
        lowerBaseName.endsWith('_router.dart') ||
        lowerBaseName == 'routes.dart' ||
        (lowerRelPath.contains('/router/') && lowerBaseName.endsWith('.dart'));
  }

  static bool _isWidgetFile(String lowerRelPath, String lowerBaseName) {
    if (lowerRelPath.contains('/widgets/')) return true;
    return _widgetFileSuffixRegex.hasMatch(lowerBaseName);
  }

  static String? _buildCombinedExcerpt(
    List<({String relPath, String content})> entries,
  ) {
    if (entries.isEmpty) return null;

    final sorted = List<({String relPath, String content})>.from(entries)
      ..sort((a, b) {
        final aScore = a.relPath.startsWith('lib/core/') ? 0 : 1;
        final bScore = b.relPath.startsWith('lib/core/') ? 0 : 1;
        if (aScore != bScore) return aScore.compareTo(bScore);
        return a.relPath.compareTo(b.relPath);
      });

    final buffer = StringBuffer();
    var remaining = _maxExcerptChars;

    for (final item in sorted) {
      if (remaining <= 0) break;
      final header = '// ${item.relPath}\n';
      final body = item.content.trimRight();
      if (body.isEmpty) continue;

      final block = '$header$body\n\n';
      if (block.length <= remaining) {
        buffer.write(block);
        remaining -= block.length;
      } else {
        final allowedBodyChars = remaining - header.length - 32;
        if (allowedBodyChars > 0) {
          buffer.write(header);
          buffer.write(body.substring(0, allowedBodyChars).trimRight());
          buffer.writeln('\n// ... [truncated]');
        }
        remaining = 0;
      }
    }

    final result = buffer.toString().trimRight();
    return result.isEmpty ? null : result;
  }

  static Future<({String? normalizedPath, String? source})> _readTargetScreen({
    required String projectPath,
    required String? targetScreenPath,
  }) async {
    final cleaned = _cleanOptionalTargetPath(targetScreenPath);
    if (cleaned == null) {
      return (normalizedPath: null, source: null);
    }

    final resolvedFilePath = p.isAbsolute(cleaned)
        ? p.normalize(cleaned)
        : p.normalize(p.join(projectPath, cleaned));

    String normalizedDisplayPath = cleaned;
    if (p.isAbsolute(cleaned) && p.isWithin(projectPath, resolvedFilePath)) {
      normalizedDisplayPath =
          p.relative(resolvedFilePath, from: projectPath).replaceAll('\\', '/');
    }

    final targetFile = File(resolvedFilePath);
    if (!await targetFile.exists()) {
      return (normalizedPath: normalizedDisplayPath, source: null);
    }

    try {
      final source = await targetFile.readAsString();
      return (normalizedPath: normalizedDisplayPath, source: source);
    } catch (_) {
      return (normalizedPath: normalizedDisplayPath, source: null);
    }
  }
}
