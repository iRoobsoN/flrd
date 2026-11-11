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

  /// Scans lib/ recursively for Dart files ending in _screen.dart, _page.dart, _view.dart,
  /// builds RouteNode models, and ensures the root route is always present.
  static Future<List<RouteNode>> _scanRouteNodes(
    String projectPath,
    Set<DevicePermission> projectPermissions,
  ) async {
    final routeNodes = <RouteNode>[];

    // Always ensure a root '/' node at Offset(50, 220)
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
    routeNodes.add(rootNode);

    final libDir = Directory(p.join(projectPath, 'lib'));
    if (!await libDir.exists()) {
      return routeNodes;
    }

    final screenPattern = RegExp(r'(_screen|_page|_view)\.dart$', caseSensitive: false);
    final screenFiles = <File>[];

    await for (final entity in libDir.list(recursive: true, followLinks: false)) {
      if (entity is File && screenPattern.hasMatch(p.basename(entity.path))) {
        screenFiles.add(entity);
      }
    }

    // Sort deterministically by relative path
    screenFiles.sort((a, b) => a.path.compareTo(b.path));

    for (var i = 0; i < screenFiles.length; i++) {
      final file = screenFiles[i];
      final fileName = p.basename(file.path);
      final relPath = p.relative(file.path, from: projectPath).replaceAll('\\', '/');

      final title = _extractScreenTitle(file, fileName);
      final routePath = _generateRoutePath(fileName, title);
      final nodeId = title.toLowerCase().replaceAll(' ', '_');
      final icon = _guessScreenIcon(title);
      final isProtected = _isProtectedScreen(title, fileName);
      final requiredPermissions = _detectScreenPermissions(file, projectPermissions);

      // Grid coordinate calculation (columns to the right of root at X=50)
      final col = i ~/ 3;
      final row = i % 3;
      final x = 380.0 + (col * 330.0);
      final y = 80.0 + (row * 160.0);

      routeNodes.add(
        RouteNode(
          id: nodeId,
          path: routePath,
          title: title,
          subtitle: 'Auto-detected route: $title',
          icon: icon,
          isProtected: isProtected,
          requiredPermissions: requiredPermissions,
          position: Offset(x, y),
          filePath: relPath,
          parentRouteId: 'root',
        ),
      );
    }

    return routeNodes;
  }

  /// Extracts the screen title in PascalCase from the file name and Dart widget class.
  static String _extractScreenTitle(File file, String fileName) {
    // 1. Try extracting actual class name extending Widget from file content
    try {
      final content = file.readAsStringSync();
      final classRegex = RegExp(
        r'class\s+([A-Za-z0-9_]+)\s+extends\s+(?:StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|HookWidget)',
      );
      final matches = classRegex.allMatches(content);
      for (final m in matches) {
        final className = m.group(1);
        if (className != null &&
            (className.endsWith('Screen') ||
                className.endsWith('Page') ||
                className.endsWith('View'))) {
          return className;
        }
      }
    } catch (_) {}

    // 2. Fallback to formatting filename: e.g. home_screen.dart -> HomeScreen
    final withoutExt = fileName.replaceAll(RegExp(r'\.dart$', caseSensitive: false), '');
    final words = withoutExt.split(RegExp(r'[_ -]+'));
    final formatted = words.where((w) => w.isNotEmpty).map((w) {
      if (w.length == 1) return w.toUpperCase();
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join('');

    return formatted.isNotEmpty ? formatted : 'Screen';
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
    if (lower.contains('profile') || lower.contains('user') || lower.contains('account')) {
      return Icons.account_circle_rounded;
    }
    if (lower.contains('setting') || lower.contains('config') || lower.contains('preference')) {
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
  static List<DevicePermission> _detectScreenPermissions(
    File file,
    Set<DevicePermission> projectPermissions,
  ) {
    try {
      final content = file.readAsStringSync().toLowerCase();
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
                content.contains('image_picker')) {
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
