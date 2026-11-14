import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

import '../../wizard/models/project_config.dart';
import '../models/registered_project.dart';
import '../../studio/models/route_node.dart';

/// Result produced after analyzing an existing Flutter project directory.
class AnalyzedProjectResult {
  final RegisteredProject project;
  final List<RouteNode> routeNodes;

  const AnalyzedProjectResult({
    required this.project,
    required this.routeNodes,
  });

  @override
  String toString() =>
      'AnalyzedProjectResult(project: ${project.name}, routeNodes: ${routeNodes.length})';
}

/// Service responsible for scanning and analyzing existing Flutter projects,
/// extracting their architecture preset, permissions, UI routes, and metadata,
/// and synchronizing the `.flrd/manifest.json` descriptor.
class ProjectAnalyzerService {
  ProjectAnalyzerService._();

  /// Analyzes a Flutter project directory located at [projectPath].
  ///
  /// Throws an [Exception] if [projectPath] does not contain a valid `pubspec.yaml`.
  static Future<AnalyzedProjectResult> analyzeProject(String projectPath) async {
    var cleanPath = projectPath.trim();
    if ((cleanPath.startsWith('"') && cleanPath.endsWith('"')) ||
        (cleanPath.startsWith("'") && cleanPath.endsWith("'"))) {
      cleanPath = cleanPath.substring(1, cleanPath.length - 1).trim();
    }
    cleanPath = p.normalize(cleanPath);
    if (FileSystemEntity.isFileSync(cleanPath) &&
        p.basename(cleanPath).toLowerCase() == 'pubspec.yaml') {
      cleanPath = p.dirname(cleanPath);
    }

    final pubspecFile = File(p.join(cleanPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) {
      throw Exception('No pubspec.yaml found at "$cleanPath". Please specify a valid Flutter project root.');
    }

    // 1. Parse pubspec.yaml
    final pubspecContent = await pubspecFile.readAsString();
    final dynamic yamlMap;
    try {
      yamlMap = loadYaml(pubspecContent);
    } catch (e) {
      throw Exception('Failed to parse pubspec.yaml at "$cleanPath": $e');
    }

    if (yamlMap is! YamlMap) {
      throw Exception('Invalid pubspec.yaml structure at "$cleanPath". Expected a YAML map.');
    }

    final rawName = yamlMap['name'];
    final projectName = (rawName is String && rawName.trim().isNotEmpty)
        ? rawName.trim()
        : p.basename(p.normalize(cleanPath));

    final dependencies = <String>{};
    final deps = yamlMap['dependencies'];
    if (deps is YamlMap) {
      dependencies.addAll(deps.keys.map((k) => k.toString()));
    } else if (deps is Map) {
      dependencies.addAll(deps.keys.map((k) => k.toString()));
    }

    // 2. Detect PresetType
    final PresetType preset = _detectPreset(dependencies);

    // 3. Detect DevicePermissions (Android + iOS)
    final detectedPermissions = await _detectPermissions(cleanPath);

    // 4. Detect Organization Identifier (orgId)
    final orgId = await _detectOrgId(cleanPath, projectName);

    // 5. Scan lib/ for Screens/Pages/Views and build RouteNodes
    final routeNodes = await _scanRouteNodes(cleanPath, detectedPermissions);

    // 6. Navigation Style (detect or default)
    final navigationStyle = await _detectNavigationStyle(cleanPath);

    // 7. Write or update .flrd/manifest.json
    await _writeOrUpdateManifest(
      projectPath: cleanPath,
      projectName: projectName,
      orgId: orgId,
      preset: preset,
      navigationStyle: navigationStyle,
      permissions: detectedPermissions,
      routeNodes: routeNodes,
    );

    // 8. Construct RegisteredProject
    final lastModified = pubspecFile.existsSync()
        ? pubspecFile.lastModifiedSync()
        : DateTime.now();

    final project = RegisteredProject(
      id: projectName.toLowerCase().replaceAll(' ', '_'),
      name: projectName,
      orgId: orgId,
      path: cleanPath,
      preset: preset,
      navigationStyle: navigationStyle,
      permissions: detectedPermissions,
      lastModified: lastModified,
      routeCount: routeNodes.length,
    );

    return AnalyzedProjectResult(
      project: project,
      routeNodes: routeNodes,
    );
  }

  /// Detects the project's architectural preset based on dependencies.
  static PresetType _detectPreset(Set<String> dependencies) {
    if (dependencies.contains('flutter_riverpod') || dependencies.contains('riverpod')) {
      return PresetType.saas;
    }
    if (dependencies.contains('flutter_bloc') || dependencies.contains('bloc')) {
      return PresetType.cleanLite;
    }
    if (dependencies.contains('sqflite') ||
        dependencies.contains('drift') ||
        dependencies.contains('isar') ||
        dependencies.contains('hive')) {
      return PresetType.offline;
    }
    return PresetType.saas;
  }

  /// Detects native permissions configured in AndroidManifest.xml and Info.plist.
  static Future<Set<DevicePermission>> _detectPermissions(String projectPath) async {
    final permissions = <DevicePermission>{};

    // Android Manifest inspection
    final manifestFile = File(p.join(
      projectPath,
      'android',
      'app',
      'src',
      'main',
      'AndroidManifest.xml',
    ));

    if (await manifestFile.exists()) {
      try {
        final content = await manifestFile.readAsString();
        final document = XmlDocument.parse(content);
        final manifestTags = document
            .findAllElements('uses-permission')
            .map((el) => el.getAttribute('android:name') ?? el.getAttribute('name') ?? '')
            .where((s) => s.isNotEmpty)
            .toSet();

        for (final perm in DevicePermission.values) {
          if (manifestTags.contains(perm.androidTag) ||
              _matchesAndroidAlternative(perm, manifestTags, content)) {
            permissions.add(perm);
          }
        }
      } catch (_) {
        // Fallback to substring scanning if XML parsing fails
        try {
          final content = await manifestFile.readAsString();
          for (final perm in DevicePermission.values) {
            if (content.contains(perm.androidTag)) {
              permissions.add(perm);
            }
          }
        } catch (_) {}
      }
    }

    // iOS Info.plist inspection
    final plistFile = File(p.join(projectPath, 'ios', 'Runner', 'Info.plist'));
    if (await plistFile.exists()) {
      try {
        final content = await plistFile.readAsString();
        final document = XmlDocument.parse(content);
        final keys = document
            .findAllElements('key')
            .map((el) => el.innerText.trim())
            .toSet();

        for (final perm in DevicePermission.values) {
          if (keys.contains(perm.iosKey) ||
              _matchesIosAlternative(perm, keys, content)) {
            permissions.add(perm);
          }
        }
      } catch (_) {
        // Fallback to substring check
        try {
          final content = await plistFile.readAsString();
          for (final perm in DevicePermission.values) {
            if (content.contains(perm.iosKey)) {
              permissions.add(perm);
            }
          }
        } catch (_) {}
      }
    }

    return permissions;
  }

  static bool _matchesAndroidAlternative(
    DevicePermission perm,
    Set<String> tags,
    String content,
  ) {
    switch (perm) {
      case DevicePermission.camera:
        return tags.contains('android.permission.CAMERA') ||
            content.contains('android.permission.CAMERA');
      case DevicePermission.location:
        return tags.contains('android.permission.ACCESS_FINE_LOCATION') ||
            tags.contains('android.permission.ACCESS_COARSE_LOCATION') ||
            content.contains('ACCESS_FINE_LOCATION') ||
            content.contains('ACCESS_COARSE_LOCATION');
      case DevicePermission.notifications:
        return tags.contains('android.permission.POST_NOTIFICATIONS') ||
            content.contains('POST_NOTIFICATIONS');
      case DevicePermission.photoLibrary:
        return tags.contains('android.permission.READ_MEDIA_IMAGES') ||
            tags.contains('android.permission.READ_EXTERNAL_STORAGE') ||
            content.contains('READ_MEDIA_IMAGES') ||
            content.contains('READ_EXTERNAL_STORAGE');
      case DevicePermission.biometrics:
        return tags.contains('android.permission.USE_BIOMETRIC') ||
            tags.contains('android.permission.USE_FINGERPRINT') ||
            content.contains('USE_BIOMETRIC') ||
            content.contains('USE_FINGERPRINT');
    }
  }

  static bool _matchesIosAlternative(
    DevicePermission perm,
    Set<String> keys,
    String content,
  ) {
    switch (perm) {
      case DevicePermission.camera:
        return keys.contains('NSCameraUsageDescription') ||
            content.contains('NSCameraUsageDescription');
      case DevicePermission.location:
        return keys.contains('NSLocationWhenInUseUsageDescription') ||
            keys.contains('NSLocationAlwaysUsageDescription') ||
            keys.contains('NSLocationAlwaysAndWhenInUseUsageDescription') ||
            content.contains('NSLocationWhenInUseUsageDescription') ||
            content.contains('NSLocationAlwaysAndWhenInUseUsageDescription');
      case DevicePermission.notifications:
        return keys.contains('NSPushNotificationUsageDescription') ||
            content.contains('NSPushNotificationUsageDescription');
      case DevicePermission.photoLibrary:
        return keys.contains('NSPhotoLibraryUsageDescription') ||
            keys.contains('NSPhotoLibraryAddUsageDescription') ||
            content.contains('NSPhotoLibraryUsageDescription');
      case DevicePermission.biometrics:
        return keys.contains('NSFaceIDUsageDescription') ||
            content.contains('NSFaceIDUsageDescription');
    }
  }

  /// Scans lib/ recursively for Flutter screens across single-screen files
  /// (*_screen.dart, *_page.dart, *_view.dart) and multi-screen files
  /// (e.g. lib/screens.dart, lib/main.dart), builds RouteNodes and parent links.
  static Future<List<RouteNode>> _scanRouteNodes(
    String projectPath,
    Set<DevicePermission> projectPermissions,
  ) async {
    const rootNode = RouteNode(
      id: 'root',
      path: '/',
      title: 'Root / Entry',
      subtitle: 'App initial route & shell navigation',
      icon: Icons.alt_route_rounded,
      isProtected: false,
      position: Offset(50, 220),
      filePath: 'lib/main.dart',
      parentRouteId: null,
    );

    final libDir = Directory(p.join(projectPath, 'lib'));
    if (!await libDir.exists()) {
      return [rootNode];
    }

    final dartFiles = <File>[];
    await for (final entity in libDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final baseName = p.basename(entity.path).toLowerCase();
      if (!baseName.endsWith('.dart')) continue;
      if (_isGeneratedDartFile(baseName)) continue;
      dartFiles.add(entity);
    }

    // Sort deterministically by relative path so tests and layout order are stable.
    dartFiles.sort((a, b) => a.path.compareTo(b.path));

    final fileContents = <String, String>{};
    for (final file in dartFiles) {
      try {
        fileContents[file.path] = await file.readAsString();
      } catch (_) {}
    }

    // Collect explicit route declarations (GoRoute and MaterialApp routes map) across lib/.
    final explicitRoutes = _extractExplicitRoutePaths(fileContents.values);
    final screenFilePattern =
        RegExp(r'(_screen|_page|_view)\.dart$', caseSensitive: false);

    final candidates = <_DiscoveredScreenCandidate>[];
    final appShellBlocks = <String>[];

    for (final file in dartFiles) {
      final fileName = p.basename(file.path);
      final relPath = p.relative(file.path, from: projectPath).replaceAll('\\', '/');
      final content = fileContents[file.path] ?? '';
      final isExplicitScreenFile = screenFilePattern.hasMatch(fileName);

      final extractedFromFile = _discoverScreensInFile(
        fileName: fileName,
        relPath: relPath,
        content: content,
        isExplicitScreenFile: isExplicitScreenFile,
        explicitRoutes: explicitRoutes,
        appShellBlocks: appShellBlocks,
      );
      candidates.addAll(extractedFromFile);
    }

    if (candidates.isEmpty) {
      return [rootNode];
    }

    // Deduplicate candidate IDs deterministically while preserving `'root'` for rootNode.
    final usedIds = <String>{'root'};
    for (final c in candidates) {
      final baseId = _toSnakeCaseId(c.title);
      var uniqueId = baseId;
      var suffix = 2;
      while (usedIds.contains(uniqueId)) {
        uniqueId = '${baseId}_$suffix';
        suffix++;
      }
      usedIds.add(uniqueId);
      c.assignedId = uniqueId;
    }

    // Infer parent-child relationships from AppShell home:/routes: and TabBarView / Navigator calls.
    _assignParentRelationships(
      candidates: candidates,
      appShellBlocks: appShellBlocks,
    );

    // Position discovered nodes cleanly in a left-to-right tree starting after root at X=50.
    _assignTreePositions(candidates);

    // Count how many discovered screens share each file for contextual subtitles.
    final countByFile = <String, int>{};
    for (final c in candidates) {
      countByFile[c.relPath] = (countByFile[c.relPath] ?? 0) + 1;
    }

    final routeNodes = <RouteNode>[rootNode];
    for (final c in candidates) {
      final sharedCount = countByFile[c.relPath] ?? 1;
      final subtitle = sharedCount > 1
          ? 'Auto-detected in ${c.fileName}'
          : 'Auto-detected route: ${c.title}';

      final requiredPermissions = _detectScreenPermissionsFromSource(
        c.scopedSource,
        projectPermissions,
      );

      routeNodes.add(
        RouteNode(
          id: c.assignedId,
          path: c.routePath,
          title: c.title,
          subtitle: subtitle,
          icon: _guessScreenIcon(c.title),
          isProtected: _isProtectedScreen(c.title, c.fileName),
          requiredPermissions: requiredPermissions,
          position: c.position,
          filePath: c.relPath,
          parentRouteId: c.parentRouteId,
        ),
      );
    }

    return routeNodes;
  }

  static bool _isGeneratedDartFile(String lowerBaseName) {
    return lowerBaseName.endsWith('.g.dart') ||
        lowerBaseName.endsWith('.freezed.dart') ||
        lowerBaseName.endsWith('.gr.dart') ||
        lowerBaseName.endsWith('.mocks.dart') ||
        lowerBaseName == 'generated_plugin_registrant.dart';
  }

  static Map<String, String> _extractExplicitRoutePaths(
    Iterable<String> contents,
  ) {
    final map = <String, String>{};
    final goRouteRegex = RegExp(
      r'''GoRoute\s*\([\s\S]{0,500}?path:\s*['"]([^'"]+)['"][\s\S]{0,500}?builder:\s*[^=]*=>\s*(?:const\s+)?([A-Z][A-Za-z0-9_]*)\s*\(''',
    );
    final routeTableRegex = RegExp(
      r'''['"](/[^'"]*)['"]\s*:\s*\([^)]*\)\s*(?:=>\s*(?:const\s+)?|\{[\s\S]{0,120}?return\s+(?:const\s+)?)([A-Z][A-Za-z0-9_]*)\s*\(''',
    );

    for (final content in contents) {
      for (final match in goRouteRegex.allMatches(content)) {
        final path = match.group(1);
        final cls = match.group(2);
        if (path != null && cls != null) {
          map.putIfAbsent(cls, () => path);
        }
      }
      for (final match in routeTableRegex.allMatches(content)) {
        final path = match.group(1);
        final cls = match.group(2);
        if (path != null && cls != null && path != '/') {
          map.putIfAbsent(cls, () => path);
        }
      }
    }
    return map;
  }

  static List<_DiscoveredScreenCandidate> _discoverScreensInFile({
    required String fileName,
    required String relPath,
    required String content,
    required bool isExplicitScreenFile,
    required Map<String, String> explicitRoutes,
    required List<String> appShellBlocks,
  }) {
    final widgetClassRegex = RegExp(
      r'^\s*class\s+([A-Z][A-Za-z0-9_]*)\s+extends\s+(?:StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|HookWidget|HookConsumerWidget|GetView(?:<[^>]+>)?|GetWidget(?:<[^>]+>)?)\b',
      multiLine: true,
    );
    final materialAppRegex = RegExp(
      r'\b(?:MaterialApp|CupertinoApp|GetMaterialApp)(?:\.router)?\s*\(',
    );
    final scaffoldRegex = RegExp(
      r'\b(?:Scaffold|CupertinoPageScaffold)\s*\(',
    );

    final discovered = <_DiscoveredScreenCandidate>[];
    final seenClassNames = <String>{};

    for (final match in widgetClassRegex.allMatches(content)) {
      final className = match.group(1);
      if (className == null || !seenClassNames.add(className)) continue;

      final scopedSource = extractWidgetClassAndStateScope(content, className);
      final effectiveScope = scopedSource ?? content;

      // App root wrappers (MaterialApp/CupertinoApp) represent '/' already covered by Root / Entry.
      if (materialAppRegex.hasMatch(effectiveScope)) {
        appShellBlocks.add(effectiveScope);
        continue;
      }

      final hasScreenName = className.endsWith('Screen') ||
          className.endsWith('Page') ||
          className.endsWith('View');
      final buildsScaffold = scaffoldRegex.hasMatch(effectiveScope);
      final isExplicitRouteTarget = explicitRoutes.containsKey(className);

      // Inside *_screen.dart / *_page.dart / *_view.dart, accept public Widget classes even if stubbed;
      // across other .dart files (e.g. lib/screens.dart, lib/main.dart), match Screen/Page/View or Scaffold builders.
      final shouldInclude = isExplicitScreenFile
          ? (hasScreenName || buildsScaffold || isExplicitRouteTarget || discovered.isEmpty)
          : (hasScreenName || buildsScaffold || isExplicitRouteTarget);

      if (!shouldInclude) continue;

      final routePath = explicitRoutes[className] ??
          _generateRoutePathForClass(className);

      discovered.add(
        _DiscoveredScreenCandidate(
          title: className,
          fileName: fileName,
          relPath: relPath,
          routePath: routePath,
          scopedSource: effectiveScope,
        ),
      );
    }

    // Fallback when a traditional *_screen.dart / *_page.dart / *_view.dart uses a custom base widget.
    if (discovered.isEmpty && isExplicitScreenFile) {
      final title = _formatFilenameAsTitle(fileName);
      discovered.add(
        _DiscoveredScreenCandidate(
          title: title,
          fileName: fileName,
          relPath: relPath,
          routePath: _generateRoutePath(fileName, title),
          scopedSource: content,
        ),
      );
    }

    return discovered;
  }

  /// Extracts [className]'s declaration block plus its companion `State` class block (if any).
  static String? extractWidgetClassAndStateScope(
    String content,
    String className,
  ) {
    final blocks = <String>[];
    final mainBlock = _extractSingleClassBlock(content, className);
    if (mainBlock == null) return null;
    blocks.add(mainBlock);

    for (final stateName in ['_${className}State', '${className}State']) {
      final stateBlock = _extractSingleClassBlock(content, stateName);
      if (stateBlock != null) {
        blocks.add(stateBlock);
      }
    }
    return blocks.join('\n\n');
  }

  static String? _extractSingleClassBlock(String content, String exactClassName) {
    final escaped = RegExp.escape(exactClassName);
    final classStartRegex = RegExp(
      'class\\s+$escaped\\b[^{;]*\\{',
      multiLine: true,
    );
    final match = classStartRegex.firstMatch(content);
    if (match == null) return null;

    final openBraceIndex = match.end - 1;
    final closeBraceIndex = _findMatchingBrace(content, openBraceIndex);
    if (closeBraceIndex == -1) return null;
    return content.substring(match.start, closeBraceIndex + 1);
  }

  /// Finds matching `}` while ignoring Dart strings and comments cleanly.
  static int _findMatchingBrace(String code, int openBraceIndex) {
    var depth = 0;
    var i = openBraceIndex;
    final len = code.length;

    while (i < len) {
      final ch = code[i];

      // Line comment
      if (ch == '/' && i + 1 < len && code[i + 1] == '/') {
        i += 2;
        while (i < len && code[i] != '\n') {
          i++;
        }
        continue;
      }

      // Block comment
      if (ch == '/' && i + 1 < len && code[i + 1] == '*') {
        i += 2;
        while (i + 1 < len && !(code[i] == '*' && code[i + 1] == '/')) {
          i++;
        }
        i += 2;
        continue;
      }

      // Triple or single string literals
      if (ch == '\'' || ch == '"') {
        final isTriple = i + 2 < len && code[i + 1] == ch && code[i + 2] == ch;
        if (isTriple) {
          i += 3;
          while (i + 2 < len) {
            if (code[i] == '\\') {
              i += 2;
              continue;
            }
            if (code[i] == ch && code[i + 1] == ch && code[i + 2] == ch) {
              i += 3;
              break;
            }
            i++;
          }
          continue;
        } else {
          i++;
          while (i < len) {
            if (code[i] == '\\') {
              i += 2;
              continue;
            }
            if (code[i] == ch || code[i] == '\n') {
              i++;
              break;
            }
            i++;
          }
          continue;
        }
      }

      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }

    return -1;
  }

  static void _assignParentRelationships({
    required List<_DiscoveredScreenCandidate> candidates,
    required List<String> appShellBlocks,
  }) {
    final byClass = <String, _DiscoveredScreenCandidate>{
      for (final c in candidates) c.title: c,
    };
    final byId = <String, _DiscoveredScreenCandidate>{
      for (final c in candidates) c.assignedId: c,
    };

    // Any screen explicitly set as `home:` inside MaterialApp/CupertinoApp hooks straight to `root`.
    final rootTargets = <String>{};
    for (final shell in appShellBlocks) {
      final homeMatch = RegExp(
        r'home:\s*(?:const\s+)?([A-Z][A-Za-z0-9_]*)\s*\(',
      ).firstMatch(shell);
      final target = homeMatch?.group(1);
      if (target != null && byClass.containsKey(target)) {
        rootTargets.add(target);
        byClass[target]!.parentRouteId = 'root';
      }
    }

    bool wouldCreateCycle(String childId, String proposedParentId) {
      var cursor = proposedParentId;
      final visited = <String>{childId};
      while (cursor != 'root') {
        if (!visited.add(cursor)) return true;
        final node = byId[cursor];
        if (node == null || node.parentRouteId == null) break;
        cursor = node.parentRouteId!;
      }
      return false;
    }

    // Link screens instantiated inside another screen's TabBarView / IndexedStack / Navigator calls.
    for (final parent in candidates) {
      for (final child in candidates) {
        if (identical(parent, child)) continue;
        if (rootTargets.contains(child.title)) continue;
        if (child.parentRouteId != null && child.parentRouteId != 'root') {
          continue;
        }

        final refRegex = RegExp('\\b${RegExp.escape(child.title)}\\s*\\(');
        if (refRegex.hasMatch(parent.scopedSource) &&
            !wouldCreateCycle(child.assignedId, parent.assignedId)) {
          child.parentRouteId = parent.assignedId;
        }
      }
    }

    for (final c in candidates) {
      c.parentRouteId ??= 'root';
    }
  }

  static void _assignTreePositions(List<_DiscoveredScreenCandidate> candidates) {
    final byId = <String, _DiscoveredScreenCandidate>{
      for (final c in candidates) c.assignedId: c,
    };

    int computeDepth(_DiscoveredScreenCandidate node) {
      var depth = 1;
      var parentId = node.parentRouteId ?? 'root';
      final visited = <String>{node.assignedId};
      while (parentId != 'root') {
        if (!visited.add(parentId)) break;
        depth++;
        final parent = byId[parentId];
        if (parent == null) break;
        parentId = parent.parentRouteId ?? 'root';
      }
      return depth;
    }

    final byDepth = <int, List<_DiscoveredScreenCandidate>>{};
    for (final c in candidates) {
      final d = computeDepth(c);
      byDepth.putIfAbsent(d, () => []).add(c);
    }

    var currentColOffset = 0;
    final depths = byDepth.keys.toList()..sort();
    for (final depth in depths) {
      final layer = byDepth[depth]!;
      final baseX = 380.0 + ((depth - 1 + currentColOffset) * 330.0);

      if (layer.length <= 5) {
        for (var i = 0; i < layer.length; i++) {
          final y = layer.length == 1 ? 220.0 : 80.0 + (i * 155.0);
          layer[i].position = Offset(baseX, y);
        }
      } else {
        for (var i = 0; i < layer.length; i++) {
          final subCol = i ~/ 4;
          final row = i % 4;
          layer[i].position = Offset(baseX + (subCol * 330.0), 80.0 + (row * 155.0));
        }
        currentColOffset += (layer.length - 1) ~/ 4;
      }
    }
  }

  static String _formatFilenameAsTitle(String fileName) {
    final withoutExt =
        fileName.replaceAll(RegExp(r'\.dart$', caseSensitive: false), '');
    final words = withoutExt.split(RegExp(r'[_ -]+'));
    final formatted = words.where((w) => w.isNotEmpty).map((w) {
      if (w.length == 1) return w.toUpperCase();
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join('');
    return formatted.isNotEmpty ? formatted : 'Screen';
  }

  static String _generateRoutePathForClass(String className) {
    var base = className.replaceFirst(RegExp(r'(Screen|Page|View)$'), '');
    if (base.isEmpty) base = className;
    final kebab = base
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)}-${m.group(2)}',
        )
        .toLowerCase();
    return '/$kebab';
  }

  static String _toSnakeCaseId(String input) {
    return input
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toLowerCase();
  }

  /// Generates a clean route path from the screen filename.
  static String _generateRoutePath(String fileName, String title) {
    var cleaned = fileName
        .replaceAll(RegExp(r'\.dart$', caseSensitive: false), '')
        .replaceAll(RegExp(r'(_screen|_page|_view)$', caseSensitive: false), '');
    cleaned = cleaned.replaceAll('_', '-').trim();
    if (cleaned.isEmpty) {
      cleaned = title.toLowerCase().replaceAll(' ', '-');
    }
    return '/$cleaned';
  }

  /// Determines an appropriate icon based on the screen's title or purpose.
  static IconData _guessScreenIcon(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('main') || lower.contains('shell')) {
      return Icons.view_carousel_rounded;
    }
    if (lower.contains('home')) return Icons.home_rounded;
    if (lower.contains('login') || lower.contains('auth') || lower.contains('signin')) {
      return Icons.lock_outline_rounded;
    }
    if (lower.contains('register') || lower.contains('signup')) {
      return Icons.person_add_alt_1_rounded;
    }
    if (lower.contains('dashboard') || lower.contains('analytic') || lower.contains('metric')) {
      return Icons.space_dashboard_rounded;
    }
    if (lower.contains('explore') || lower.contains('feed')) {
      return Icons.explore_rounded;
    }
    if (lower.contains('gallery') || lower.contains('history') || lower.contains('photo') || lower.contains('img')) {
      return Icons.photo_library_rounded;
    }
    if (lower.contains('inpaint') || lower.contains('paint') || lower.contains('draw') || lower.contains('txt')) {
      return Icons.auto_fix_high_rounded;
    }
    if (lower.contains('profile') || lower.contains('user') || lower.contains('account')) {
      return Icons.account_circle_rounded;
    }
    if (lower.contains('setting') || lower.contains('config') || lower.contains('preference') || lower.contains('model')) {
      return Icons.settings_rounded;
    }
    if (lower.contains('payment') || lower.contains('checkout') || lower.contains('wallet') || lower.contains('pix')) {
      return Icons.payment_rounded;
    }
    if (lower.contains('notification') || lower.contains('alert')) {
      return Icons.notifications_rounded;
    }
    if (lower.contains('search')) {
      return Icons.search_rounded;
    }
    return Icons.widgets_rounded;
  }

  /// Infers whether a route should be guarded or public.
  static bool _isProtectedScreen(String title, String fileName) {
    final lower = '$title $fileName'.toLowerCase();
    if (lower.contains('login') ||
        lower.contains('auth') ||
        lower.contains('register') ||
        lower.contains('signup') ||
        lower.contains('splash') ||
        lower.contains('welcome') ||
        lower.contains('onboarding')) {
      return false;
    }
    return true;
  }

  /// Detects specific device permissions invoked in a given screen's Dart source.
  static List<DevicePermission> _detectScreenPermissionsFromSource(
    String rawSource,
    Set<DevicePermission> projectPermissions,
  ) {
    try {
      final content = rawSource.toLowerCase();
      final needed = <DevicePermission>[];
      for (final perm in projectPermissions) {
        switch (perm) {
          case DevicePermission.camera:
            if (content.contains('camera') ||
                content.contains('imagepicker') ||
                content.contains('qr')) {
              needed.add(perm);
            }
            break;
          case DevicePermission.location:
            if (content.contains('location') ||
                content.contains('geolocator') ||
                content.contains('gps')) {
              needed.add(perm);
            }
            break;
          case DevicePermission.notifications:
            if (content.contains('notification') || content.contains('fcm')) {
              needed.add(perm);
            }
            break;
          case DevicePermission.photoLibrary:
            if (content.contains('photo') ||
                content.contains('gallery') ||
                content.contains('galeria') ||
                content.contains('image_picker') ||
                content.contains('gal.')) {
              needed.add(perm);
            }
            break;
          case DevicePermission.biometrics:
            if (content.contains('biometric') ||
                content.contains('faceid') ||
                content.contains('fingerprint')) {
              needed.add(perm);
            }
            break;
        }
      }
      return needed;
    } catch (_) {
      return const [];
    }
  }

  /// Detects the organization id from build scripts or Android manifest.
  static Future<String> _detectOrgId(String projectPath, String projectName) async {
    // 1. Try reading from existing manifest.json
    final manifestFile = File(p.join(projectPath, '.flrd', 'manifest.json'));
    if (await manifestFile.exists()) {
      try {
        final content = await manifestFile.readAsString();
        final data = jsonDecode(content);
        if (data is Map && data['orgId'] is String && (data['orgId'] as String).isNotEmpty) {
          return data['orgId'] as String;
        }
      } catch (_) {}
    }

    // 2. Try android/app/build.gradle or build.gradle.kts
    for (final gradleName in ['android/app/build.gradle', 'android/app/build.gradle.kts']) {
      final gradleFile = File(p.join(projectPath, gradleName));
      if (await gradleFile.exists()) {
        try {
          final content = await gradleFile.readAsString();
          final appMatch = RegExp(r'(?:applicationId|namespace)\s*=?\s*["'']([^"'']+)["'']')
              .firstMatch(content);
          if (appMatch != null) {
            final fullId = appMatch.group(1);
            if (fullId != null && fullId.isNotEmpty) {
              final parts = fullId.split('.');
              if (parts.length > 1) {
                return parts.sublist(0, parts.length - 1).join('.');
              }
              return fullId;
            }
          }
        } catch (_) {}
      }
    }

    // 3. Fallback to standard default
    return 'com.example';
  }

  /// Detects navigation style preference from existing configuration or code.
  static Future<NavigationStyle> _detectNavigationStyle(String projectPath) async {
    final manifestFile = File(p.join(projectPath, '.flrd', 'manifest.json'));
    if (await manifestFile.exists()) {
      try {
        final content = await manifestFile.readAsString();
        final data = jsonDecode(content);
        if (data is Map && data['navigationStyle'] is String) {
          final styleName = data['navigationStyle'] as String;
          for (final style in NavigationStyle.values) {
            if (style.name == styleName) {
              return style;
            }
          }
        }
      } catch (_) {}
    }

    return NavigationStyle.tabs;
  }

  /// Writes or updates `.flrd/manifest.json` in the target project root.
  static Future<void> _writeOrUpdateManifest({
    required String projectPath,
    required String projectName,
    required String orgId,
    required PresetType preset,
    required NavigationStyle navigationStyle,
    required Set<DevicePermission> permissions,
    required List<RouteNode> routeNodes,
  }) async {
    final flrdDir = Directory(p.join(projectPath, '.flrd'));
    if (!await flrdDir.exists()) {
      await flrdDir.create(recursive: true);
    }

    final manifestFile = File(p.join(flrdDir.path, 'manifest.json'));
    Map<String, dynamic> manifestData = {};

    if (await manifestFile.exists()) {
      try {
        final content = await manifestFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          manifestData = decoded;
        }
      } catch (_) {
        manifestData = {};
      }
    }

    manifestData['name'] = projectName;
    manifestData['orgId'] = manifestData['orgId'] ?? orgId;
    manifestData['preset'] = _presetToIdentifier(preset);
    manifestData['presetName'] = preset.name;
    manifestData['stateManagement'] =
        manifestData['stateManagement'] ?? _defaultStateManagementForPreset(preset);
    manifestData['designSystem'] =
        manifestData['designSystem'] ?? 'Obsidian Glass Dark (Material 3 AAA)';
    manifestData['routingPattern'] =
        manifestData['routingPattern'] ?? 'GoRouter ShellRoute with Guards';
    manifestData['navigationStyle'] = navigationStyle.name;
    manifestData['permissions'] = permissions.map((p) => p.name).toList();
    manifestData['screenNames'] = routeNodes.map((n) => n.title).toList();
    manifestData['routes'] = routeNodes
        .map((n) => {
              'id': n.id,
              'path': n.path,
              'title': n.title,
              'subtitle': n.subtitle,
              'isProtected': n.isProtected,
              'position': {
                'x': n.position.dx,
                'y': n.position.dy,
              },
              'filePath': n.filePath,
              if (n.parentRouteId != null) 'parentRouteId': n.parentRouteId,
              'permissions': n.requiredPermissions.map((p) => p.name).toList(),
            })
        .toList();
    manifestData['aiPromptRules'] = manifestData['aiPromptRules'] ??
        'Todas as novas telas devem respeitar o design system Obsidian Glass e a arquitetura ${preset.name}.';
    manifestData['lastAnalyzed'] = DateTime.now().toIso8601String();

    const encoder = JsonEncoder.withIndent('  ');
    await manifestFile.writeAsString(encoder.convert(manifestData));
  }

  static String _presetToIdentifier(PresetType preset) {
    switch (preset) {
      case PresetType.saas:
        return 'saas';
      case PresetType.cleanLite:
        return 'cleanLite';
      case PresetType.offline:
        return 'offline';
    }
  }

  static String _defaultStateManagementForPreset(PresetType preset) {
    switch (preset) {
      case PresetType.saas:
        return 'Riverpod 2.5 + AsyncNotifier';
      case PresetType.cleanLite:
        return 'BLoC + Dio + GetIt';
      case PresetType.offline:
        return 'Drift / Isar + Provider';
    }
  }
}

class _DiscoveredScreenCandidate {
  final String title;
  final String fileName;
  final String relPath;
  final String routePath;
  final String scopedSource;
  String assignedId = '';
  String? parentRouteId;
  Offset position = Offset.zero;

  _DiscoveredScreenCandidate({
    required this.title,
    required this.fileName,
    required this.relPath,
    required this.routePath,
    required this.scopedSource,
  });
}
