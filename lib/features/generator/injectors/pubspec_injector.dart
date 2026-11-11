import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Semantic AST injector for `pubspec.yaml` using `yaml_edit`.
///
/// Preserves existing formatting, comments, indentation, and structure while
/// safely handling malformed YAML edge cases (missing parent keys, null scalar
/// sections, irregular indentation, CRLF/LF line endings, and empty files).
class PubspecInjector {
  PubspecInjector._();

  /// Safely injects one or more dependencies into the target project's `pubspec.yaml`.
  ///
  /// If [isDev] is true, dependencies are injected under `dev_dependencies`.
  /// Handles missing `dependencies` / `dev_dependencies` maps and null scalars gracefully.
  static Future<bool> injectDependencies({
    required String projectRoot,
    required Map<String, String> dependencies,
    bool isDev = false,
  }) async {
    if (dependencies.isEmpty) return true;

    final pubspecFile = File(
      p.normalize(p.join(projectRoot.isEmpty ? '.' : projectRoot, 'pubspec.yaml')),
    );

    if (!await pubspecFile.exists()) {
      return false;
    }

    try {
      final rawContent = await pubspecFile.readAsString();
      final normalizedContent = _normalizeLineEndings(rawContent);

      final editor = YamlEditor(
        normalizedContent.trim().isEmpty ? 'name: flrd_project\n' : normalizedContent,
      );

      final rootNode = editor.parseAt([]);
      final targetKey = isDev ? 'dev_dependencies' : 'dependencies';

      // 1. Ensure target section exists as a map
      _ensureMapKey(editor, rootNode, targetKey);

      // Re-fetch root node after potential structural modification
      final updatedRoot = editor.parseAt([]);
      final sectionNode = updatedRoot is YamlMap ? updatedRoot[targetKey] : null;
      final existingKeys = sectionNode is YamlMap
          ? sectionNode.nodes.keys.map((k) => k.toString()).toSet()
          : <String>{};

      // 2. Inject each package dependency safely
      for (final entry in dependencies.entries) {
        if (!existingKeys.contains(entry.key)) {
          editor.update([targetKey, entry.key], entry.value);
        }
      }

      await pubspecFile.writeAsString(editor.toString());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Safely injects asset directories or files under the `flutter: assets:` node.
  ///
  /// Avoids duplicate asset paths, creates `flutter:` and `assets:` maps if missing,
  /// and gracefully handles commented-out or malformed sections.
  static Future<bool> injectAssets({
    required String projectRoot,
    required List<String> assets,
  }) async {
    if (assets.isEmpty) return true;

    final pubspecFile = File(
      p.normalize(p.join(projectRoot.isEmpty ? '.' : projectRoot, 'pubspec.yaml')),
    );

    if (!await pubspecFile.exists()) {
      return false;
    }

    try {
      final rawContent = await pubspecFile.readAsString();
      final normalizedContent = _normalizeLineEndings(rawContent);

      final editor = YamlEditor(
        normalizedContent.trim().isEmpty ? 'name: flrd_project\n' : normalizedContent,
      );

      final rootNode = editor.parseAt([]);

      // 1. Ensure `flutter` map exists
      _ensureMapKey(editor, rootNode, 'flutter');

      // 2. Ensure `assets` list exists under `flutter`
      final updatedRoot = editor.parseAt([]);
      final flutterNode = updatedRoot is YamlMap ? updatedRoot['flutter'] : null;

      final existingAssets = <String>[];
      if (flutterNode is YamlMap && flutterNode['assets'] is YamlList) {
        final list = flutterNode['assets'] as YamlList;
        for (final item in list) {
          if (item != null) {
            existingAssets.add(item.toString());
          }
        }
      }

      final mergedAssets = [...existingAssets];
      for (final asset in assets) {
        final normalizedAsset = asset.trim();
        if (normalizedAsset.isNotEmpty && !mergedAssets.contains(normalizedAsset)) {
          mergedAssets.add(normalizedAsset);
        }
      }

      editor.update(['flutter', 'assets'], mergedAssets);

      await pubspecFile.writeAsString(editor.toString());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ensures a key exists in the YAML root as a Map.
  /// Handles cases where key is completely absent, or present as a null scalar (`key:`).
  static void _ensureMapKey(YamlEditor editor, dynamic rootNode, String key) {
    if (rootNode is! YamlMap || !rootNode.containsKey(key)) {
      editor.update([key], <String, dynamic>{});
      return;
    }

    final value = rootNode[key];
    if (value == null || value is! YamlMap) {
      editor.update([key], <String, dynamic>{});
    }
  }

  /// Normalizes CRLF (Windows) and CR to LF for consistent AST offsets.
  static String _normalizeLineEndings(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }
}
