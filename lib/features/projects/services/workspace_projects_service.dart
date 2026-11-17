import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Result of loading persisted project paths from local storage.
class PersistedProjectsLoad {
  final List<String> paths;
  final bool hasStorageFile;

  const PersistedProjectsLoad({
    required this.paths,
    required this.hasStorageFile,
  });
}

/// Discovers, validates, and persists real Flutter projects on the user's disk.
///
/// Ensures FLRD only stores and lists real project directories containing a valid
/// `pubspec.yaml`, filtering out deleted or placeholder folders automatically.
class WorkspaceProjectsService {
  WorkspaceProjectsService._();

  static const int _maxVisitedDirectories = 450;
  static const int _maxDiscoveredProjects = 30;

  static const Set<String> _ignoredDirNames = {
    'build',
    'node_modules',
    'android',
    'ios',
    'linux',
    'macos',
    'windows',
    'web',
    'ephemeral',
    'pods',
    'symlinks',
    'assets',
    'test',
    'integration_test',
    'lib',
    'bin',
    'appdata',
    '\$recycle.bin',
    'system volume information',
  };

  /// Normalizes a filesystem directory path for consistent display & storage.
  static String normalizeProjectPath(String dirPath) {
    var cleaned = dirPath.trim();
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    if (cleaned.isEmpty) return '';
    return p.normalize(cleaned);
  }

  /// Canonical key used to deduplicate project paths across separators/case.
  static String canonicalCompareKey(String dirPath) {
    final normalized = normalizeProjectPath(dirPath);
    if (!kIsWeb && Platform.isWindows) {
      return normalized.toLowerCase();
    }
    return normalized;
  }

  /// Returns `true` when [dirPath] exists on disk and contains `pubspec.yaml`.
  static bool isValidFlutterProjectDir(String dirPath) {
    if (kIsWeb) return false;
    final normalized = normalizeProjectPath(dirPath);
    if (normalized.isEmpty) return false;
    try {
      final dir = Directory(normalized);
      if (!dir.existsSync()) return false;
      final pubspec = File(p.join(normalized, 'pubspec.yaml'));
      return pubspec.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Default path where FLRD stores the user's real project list JSON.
  static String? defaultStorageFilePath() {
    if (kIsWeb) return null;
    try {
      final String? baseDir;
      if (Platform.isWindows) {
        baseDir = Platform.environment['LOCALAPPDATA'] ??
            Platform.environment['APPDATA'] ??
            Platform.environment['USERPROFILE'];
      } else {
        baseDir = Platform.environment['XDG_CONFIG_HOME'] ??
            (Platform.environment['HOME'] != null
                ? p.join(Platform.environment['HOME']!, '.config')
                : null);
      }
      if (baseDir == null || baseDir.trim().isEmpty) return null;
      return p.join(baseDir.trim(), 'flrd', 'registered_projects.json');
    } catch (_) {
      return null;
    }
  }

  /// Common existing workspace folders on the user's machine to scan for real projects.
  static List<String> defaultScanRoots() {
    if (kIsWeb) return const [];
    final candidates = <String>[];

    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      final trimmedHome = home.trim();
      for (final child in const [
        'Desktop',
        'Downloads',
        'Documents',
        'Projects',
        'StudioProjects',
        'AndroidStudioProjects',
        'IdeaProjects',
        'dev',
        'src',
      ]) {
        candidates.add(p.join(trimmedHome, child));
      }
    }

    if (Platform.isWindows) {
      candidates.add('C:/Projects');
      candidates.add('D:/Projects');
    }

    try {
      final cwd = Directory.current.path;
      if (isValidFlutterProjectDir(cwd)) {
        candidates.add(cwd);
      }
    } catch (_) {}

    final seen = <String>{};
    final existing = <String>[];
    for (final raw in candidates) {
      final normalized = normalizeProjectPath(raw);
      if (normalized.isEmpty) continue;
      final key = canonicalCompareKey(normalized);
      if (!seen.add(key)) continue;
      try {
        if (Directory(normalized).existsSync()) {
          existing.add(normalized);
        }
      } catch (_) {}
    }
    return existing;
  }

  /// Loads persisted project directories, dropping any path that does not exist
  /// or does not contain `pubspec.yaml`.
  static PersistedProjectsLoad loadPersistedProjectPaths({
    String? storageFilePath,
  }) {
    if (kIsWeb) {
      return const PersistedProjectsLoad(paths: [], hasStorageFile: false);
    }
    final targetPath = storageFilePath ?? defaultStorageFilePath();
    if (targetPath == null || targetPath.trim().isEmpty) {
      return const PersistedProjectsLoad(paths: [], hasStorageFile: false);
    }

    final file = File(targetPath);
    if (!file.existsSync()) {
      return const PersistedProjectsLoad(paths: [], hasStorageFile: false);
    }

    try {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const PersistedProjectsLoad(paths: [], hasStorageFile: true);
      }
      final rawPaths = decoded['paths'];
      if (rawPaths is! List) {
        return const PersistedProjectsLoad(paths: [], hasStorageFile: true);
      }

      final seen = <String>{};
      final validPaths = <String>[];
      for (final item in rawPaths) {
        if (item is! String) continue;
        final normalized = normalizeProjectPath(item);
        if (!isValidFlutterProjectDir(normalized)) continue;
        final key = canonicalCompareKey(normalized);
        if (seen.add(key)) {
          validPaths.add(normalized);
        }
      }
      return PersistedProjectsLoad(paths: validPaths, hasStorageFile: true);
    } catch (_) {
      return const PersistedProjectsLoad(paths: [], hasStorageFile: true);
    }
  }

  /// Saves only valid existing Flutter project paths to disk.
  static Future<void> savePersistedProjectPaths(
    List<String> paths, {
    String? storageFilePath,
  }) async {
    if (kIsWeb) return;
    final targetPath = storageFilePath ?? defaultStorageFilePath();
    if (targetPath == null || targetPath.trim().isEmpty) return;

    final seen = <String>{};
    final cleanPaths = <String>[];
    for (final raw in paths) {
      final normalized = normalizeProjectPath(raw);
      if (!isValidFlutterProjectDir(normalized)) continue;
      final key = canonicalCompareKey(normalized);
      if (seen.add(key)) {
        cleanPaths.add(normalized);
      }
    }

    try {
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({'paths': cleanPaths}),
      );
    } catch (_) {}
  }

  /// Discovers real Flutter project directories under [roots] up to [maxDepth].
  static Future<List<String>> discoverProjectDirs(
    List<String> roots, {
    int maxDepth = 2,
  }) async {
    if (kIsWeb) return const [];

    final discovered = <String>[];
    final seenProjects = <String>{};
    final visitedDirs = <String>{};
    final queue = <({String path, int depth})>[];

    for (final root in roots) {
      final normalized = normalizeProjectPath(root);
      if (normalized.isEmpty) continue;
      queue.add((path: normalized, depth: 0));
    }

    while (queue.isNotEmpty &&
        visitedDirs.length < _maxVisitedDirectories &&
        discovered.length < _maxDiscoveredProjects) {
      final current = queue.removeAt(0);
      final dirKey = canonicalCompareKey(current.path);
      if (!visitedDirs.add(dirKey)) continue;

      final dir = Directory(current.path);
      try {
        if (!dir.existsSync()) continue;
      } catch (_) {
        continue;
      }

      if (isValidFlutterProjectDir(current.path)) {
        if (seenProjects.add(dirKey)) {
          discovered.add(current.path);
        }
        // Stop descending inside an already-recognized project so sub-packages
        // like `example/` do not clutter the top-level project grid.
        continue;
      }

      if (current.depth >= maxDepth) continue;

      List<FileSystemEntity> children;
      try {
        children = dir.listSync(followLinks: false);
      } catch (_) {
        continue;
      }

      for (final entity in children) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.isEmpty || name.startsWith('.')) continue;
        if (_ignoredDirNames.contains(name.toLowerCase())) continue;
        queue.add((path: normalizeProjectPath(entity.path), depth: current.depth + 1));
      }
    }

    return discovered;
  }
}
