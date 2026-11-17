import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Provider allowing tests to inject a fake [http.Client] for pub.dev requests.
final pubDevHttpClientProvider = Provider<http.Client?>((ref) => null);

/// Supported sorting options on the pub.dev search API.
enum PubDevSort {
  top('top', 'Relevância'),
  like('like', 'Mais Curtidas'),
  points('points', 'Maior Pontuação');

  final String apiValue;
  final String label;
  const PubDevSort(this.apiValue, this.label);
}

/// Package metadata and pub.dev quality metrics.
@immutable
class PubDevPackageInfo {
  final String name;
  final String latestVersion;
  final String description;
  final int grantedPoints;
  final int maxPoints;
  final int likeCount;
  final int downloadCount30Days;
  final bool isFlutterFavorite;
  final bool supportsFlutter;
  final String? publisher;

  const PubDevPackageInfo({
    required this.name,
    required this.latestVersion,
    this.description = '',
    this.grantedPoints = 0,
    this.maxPoints = 160,
    this.likeCount = 0,
    this.downloadCount30Days = 0,
    this.isFlutterFavorite = false,
    this.supportsFlutter = true,
    this.publisher,
  });

  String get versionConstraint =>
      latestVersion.isNotEmpty ? '^$latestVersion' : 'any';

  String get pubDevUrl => 'https://pub.dev/packages/$name';

  bool get isHighRated =>
      isFlutterFavorite ||
      (maxPoints > 0 && (grantedPoints / maxPoints) >= 0.75) ||
      likeCount >= 200;

  String get formattedLikes {
    if (likeCount >= 1000) {
      return '${(likeCount / 1000).toStringAsFixed(1)}k';
    }
    return '$likeCount';
  }
}

/// Search response returned by [PubDevService.searchPackages].
@immutable
class PubDevSearchResult {
  final List<PubDevPackageInfo> packages;
  final bool fromOfflineFallback;
  final String? errorMessage;

  const PubDevSearchResult({
    required this.packages,
    this.fromOfflineFallback = false,
    this.errorMessage,
  });
}

/// Queries the official `pub.dev` REST API for well-rated packages and provides
/// curated offline fallback recommendations when unreachable.
class PubDevService {
  PubDevService._();

  static const Duration _timeout = Duration(seconds: 7);
  static const int _maxFetchedResults = 10;

  static const List<PubDevPackageInfo> _curatedFallbackPackages = [
    PubDevPackageInfo(
      name: 'flutter_riverpod',
      latestVersion: '2.6.1',
      description: 'A reactive caching and data-binding framework for Flutter.',
      grantedPoints: 160,
      maxPoints: 160,
      likeCount: 4045,
      isFlutterFavorite: true,
      publisher: 'dash-overflow.net',
    ),
    PubDevPackageInfo(
      name: 'dio',
      latestVersion: '5.8.0+1',
      description: 'Powerful HTTP networking client for Dart & Flutter with interceptors.',
      grantedPoints: 160,
      maxPoints: 160,
      likeCount: 6500,
      isFlutterFavorite: true,
      publisher: 'cfug.dev',
    ),
    PubDevPackageInfo(
      name: 'go_router',
      latestVersion: '14.8.1',
      description: 'Declarative router package for Flutter using Navigator 2.0.',
      grantedPoints: 160,
      maxPoints: 160,
      likeCount: 3800,
      isFlutterFavorite: true,
      publisher: 'flutter.dev',
    ),
    PubDevPackageInfo(
      name: 'shared_preferences',
      latestVersion: '2.5.2',
      description: 'Wraps platform-specific persistent storage for simple data.',
      grantedPoints: 160,
      maxPoints: 160,
      likeCount: 5100,
      isFlutterFavorite: true,
      publisher: 'flutter.dev',
    ),
    PubDevPackageInfo(
      name: 'image_picker',
      latestVersion: '1.1.2',
      description: 'Flutter plugin for selecting images from gallery or camera.',
      grantedPoints: 160,
      maxPoints: 160,
      likeCount: 4700,
      isFlutterFavorite: true,
      publisher: 'flutter.dev',
    ),
    PubDevPackageInfo(
      name: 'permission_handler',
      latestVersion: '11.4.0',
      description: 'Cross-platform API to request and check runtime permissions.',
      grantedPoints: 150,
      maxPoints: 160,
      likeCount: 3600,
      isFlutterFavorite: true,
      publisher: 'baseflow.com',
    ),
    PubDevPackageInfo(
      name: 'cached_network_image',
      latestVersion: '3.4.1',
      description: 'Flutter library to load and cache network images efficiently.',
      grantedPoints: 150,
      maxPoints: 160,
      likeCount: 5300,
      isFlutterFavorite: true,
    ),
    PubDevPackageInfo(
      name: 'http',
      latestVersion: '1.3.0',
      description: 'Composable, multi-platform, Future-based API for HTTP requests.',
      grantedPoints: 160,
      maxPoints: 160,
      likeCount: 3100,
      publisher: 'dart.dev',
    ),
    PubDevPackageInfo(
      name: 'flutter_bloc',
      latestVersion: '9.1.0',
      description: 'Flutter widgets that make it easy to implement the BLoC pattern.',
      grantedPoints: 160,
      maxPoints: 160,
      likeCount: 6200,
      isFlutterFavorite: true,
      publisher: 'bloclibrary.dev',
    ),
    PubDevPackageInfo(
      name: 'path_provider',
      latestVersion: '2.1.5',
      description: 'Flutter plugin for finding commonly used filesystem locations.',
      grantedPoints: 160,
      maxPoints: 160,
      likeCount: 3400,
      isFlutterFavorite: true,
      publisher: 'flutter.dev',
    ),
  ];

  /// Searches packages directly on `https://pub.dev/api/search`, enriches them
  /// with `/api/packages/<pkg>` and `/api/packages/<pkg>/score`, and filters
  /// by quality criteria when requested.
  static Future<PubDevSearchResult> searchPackages(
    String query, {
    PubDevSort sort = PubDevSort.top,
    bool highRatedOnly = true,
    bool favoritesOnly = false,
    http.Client? httpClient,
  }) async {
    final trimmed = query.trim();
    final effectiveQuery = trimmed.isEmpty
        ? (favoritesOnly ? 'is:flutter-favorite' : 'sdk:flutter')
        : trimmed;

    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;

    try {
      final searchUri = Uri.https('pub.dev', '/api/search', {
        'q': effectiveQuery,
        'sort': sort.apiValue,
      });

      final searchResp = await client.get(searchUri).timeout(_timeout);
      if (searchResp.statusCode != 200) {
        return _offlineFallback(
          query: trimmed,
          highRatedOnly: highRatedOnly,
          favoritesOnly: favoritesOnly,
          error: 'pub.dev retornou HTTP ${searchResp.statusCode}. Exibindo catálogo curado.',
        );
      }

      final decoded = jsonDecode(searchResp.body);
      final rawList = (decoded is Map<String, dynamic> ? decoded['packages'] : null);
      if (rawList is! List) {
        return const PubDevSearchResult(packages: []);
      }

      final names = <String>[];
      for (final item in rawList) {
        if (item is Map && item['package'] is String) {
          final name = (item['package'] as String).trim();
          if (name.isNotEmpty) {
            names.add(name);
            if (names.length >= _maxFetchedResults) break;
          }
        }
      }

      final fetched = await Future.wait(
        names.map((name) => _fetchPackageWithScore(client, name)),
      );

      final valid = fetched.whereType<PubDevPackageInfo>().toList();
      final filtered = _applyQualityFilters(
        valid,
        highRatedOnly: highRatedOnly,
        favoritesOnly: favoritesOnly,
      );

      return PubDevSearchResult(
        packages: filtered,
        fromOfflineFallback: false,
      );
    } catch (e) {
      return _offlineFallback(
        query: trimmed,
        highRatedOnly: highRatedOnly,
        favoritesOnly: favoritesOnly,
        error: 'Sem conexão com pub.dev no momento (${e.runtimeType}). Exibindo recomendações offline.',
      );
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }

  static Future<PubDevPackageInfo?> _fetchPackageWithScore(
    http.Client client,
    String packageName,
  ) async {
    try {
      final pkgUri = Uri.https('pub.dev', '/api/packages/$packageName');
      final scoreUri = Uri.https('pub.dev', '/api/packages/$packageName/score');

      final responses = await Future.wait([
        client.get(pkgUri).timeout(_timeout),
        client.get(scoreUri).timeout(_timeout),
      ]);

      final pkgResp = responses[0];
      if (pkgResp.statusCode != 200) return null;

      final pkgJson = jsonDecode(pkgResp.body);
      if (pkgJson is! Map<String, dynamic>) return null;

      final latest = pkgJson['latest'];
      String latestVersion = '';
      String description = '';
      if (latest is Map<String, dynamic>) {
        latestVersion = (latest['version'] as String?)?.trim() ?? '';
        final pubspec = latest['pubspec'];
        if (pubspec is Map<String, dynamic>) {
          description = (pubspec['description'] as String?)?.trim() ?? '';
        }
      }

      int grantedPoints = 0;
      int maxPoints = 160;
      int likeCount = 0;
      int downloads = 0;
      bool isFavorite = false;
      bool supportsFlutter = true;
      String? publisher;

      final scoreResp = responses[1];
      if (scoreResp.statusCode == 200) {
        final scoreJson = jsonDecode(scoreResp.body);
        if (scoreJson is Map<String, dynamic>) {
          grantedPoints = (scoreJson['grantedPoints'] as num?)?.toInt() ?? 0;
          maxPoints = (scoreJson['maxPoints'] as num?)?.toInt() ?? 160;
          likeCount = (scoreJson['likeCount'] as num?)?.toInt() ?? 0;
          downloads = (scoreJson['downloadCount30Days'] as num?)?.toInt() ?? 0;
          final tags = scoreJson['tags'];
          if (tags is List) {
            for (final rawTag in tags) {
              final tag = rawTag.toString();
              if (tag == 'is:flutter-favorite') isFavorite = true;
              if (tag.startsWith('publisher:')) {
                publisher = tag.substring('publisher:'.length);
              }
              if (tag == 'sdk:dart' && !tags.contains('sdk:flutter')) {
                // Keep compatible, just note tag metadata accurately.
                supportsFlutter = true;
              }
            }
          }
        }
      }

      return PubDevPackageInfo(
        name: packageName,
        latestVersion: latestVersion,
        description: description.replaceAll('\n', ' ').trim(),
        grantedPoints: grantedPoints,
        maxPoints: maxPoints > 0 ? maxPoints : 160,
        likeCount: likeCount,
        downloadCount30Days: downloads,
        isFlutterFavorite: isFavorite,
        supportsFlutter: supportsFlutter,
        publisher: publisher,
      );
    } catch (_) {
      return null;
    }
  }

  static List<PubDevPackageInfo> _applyQualityFilters(
    List<PubDevPackageInfo> items, {
    required bool highRatedOnly,
    required bool favoritesOnly,
  }) {
    var result = items.where((pkg) {
      if (favoritesOnly && !pkg.isFlutterFavorite) return false;
      if (highRatedOnly && !pkg.isHighRated) return false;
      return true;
    }).toList();

    // If strict filter filtered out everything on a very specific search, fall
    // back to unfiltered list sorted by score so the user still sees results.
    if (result.isEmpty && items.isNotEmpty && !favoritesOnly) {
      result = List<PubDevPackageInfo>.from(items);
    }

    result.sort((a, b) {
      if (a.isFlutterFavorite != b.isFlutterFavorite) {
        return a.isFlutterFavorite ? -1 : 1;
      }
      final pointCmp = b.grantedPoints.compareTo(a.grantedPoints);
      if (pointCmp != 0) return pointCmp;
      return b.likeCount.compareTo(a.likeCount);
    });

    return result;
  }

  static PubDevSearchResult _offlineFallback({
    required String query,
    required bool highRatedOnly,
    required bool favoritesOnly,
    required String error,
  }) {
    final lower = query.toLowerCase();
    final matched = _curatedFallbackPackages.where((pkg) {
      if (lower.isEmpty) return true;
      return pkg.name.toLowerCase().contains(lower) ||
          pkg.description.toLowerCase().contains(lower);
    }).toList();

    return PubDevSearchResult(
      packages: _applyQualityFilters(
        matched,
        highRatedOnly: highRatedOnly,
        favoritesOnly: favoritesOnly,
      ),
      fromOfflineFallback: true,
      errorMessage: error,
    );
  }
}

/// Represents a single entry under `dependencies` or `dev_dependencies`.
@immutable
class PubspecDependencyEntry {
  final String name;
  final String constraint;
  final bool isDev;
  final String sourceType; // 'pub', 'sdk', 'path', 'git'

  const PubspecDependencyEntry({
    required this.name,
    required this.constraint,
    required this.isDev,
    this.sourceType = 'pub',
  });

  bool get isRemovable => name != 'flutter' && name != 'flutter_test';
  bool get isEditableVersion => sourceType == 'pub';
}

/// Snapshot of real dependencies parsed from a project's `pubspec.yaml`.
@immutable
class PubspecDependenciesSnapshot {
  final bool exists;
  final String? projectName;
  final List<PubspecDependencyEntry> dependencies;
  final List<PubspecDependencyEntry> devDependencies;
  final String? errorMessage;

  const PubspecDependenciesSnapshot({
    required this.exists,
    this.projectName,
    this.dependencies = const [],
    this.devDependencies = const [],
    this.errorMessage,
  });

  Set<String> get allPackageNames => {
        for (final d in dependencies) d.name,
        for (final d in devDependencies) d.name,
      };
}

/// Reads, adds, updates, and removes real dependencies inside `pubspec.yaml`
/// while preserving comments and formatting via `yaml_edit`.
class PubspecDependenciesService {
  PubspecDependenciesService._();

  static final RegExp validPackageNameRegex = RegExp(r'^[a-z][a-z0-9_]*$');

  static PubspecDependenciesSnapshot readDependencies(String projectRoot) {
    if (kIsWeb || projectRoot.trim().isEmpty) {
      return const PubspecDependenciesSnapshot(
        exists: false,
        errorMessage: 'Caminho do projeto indisponível.',
      );
    }

    final file = File(p.join(p.normalize(projectRoot), 'pubspec.yaml'));
    if (!file.existsSync()) {
      return const PubspecDependenciesSnapshot(
        exists: false,
        errorMessage: 'Arquivo pubspec.yaml não encontrado na pasta do projeto.',
      );
    }

    try {
      final raw = file.readAsStringSync();
      final doc = loadYaml(raw);
      if (doc is! YamlMap) {
        return const PubspecDependenciesSnapshot(
          exists: true,
          errorMessage: 'Estrutura do pubspec.yaml inválida.',
        );
      }

      final projectName = doc['name']?.toString();
      final deps = _parseSection(doc['dependencies'], isDev: false);
      final devDeps = _parseSection(doc['dev_dependencies'], isDev: true);

      return PubspecDependenciesSnapshot(
        exists: true,
        projectName: projectName,
        dependencies: deps,
        devDependencies: devDeps,
      );
    } catch (e) {
      return PubspecDependenciesSnapshot(
        exists: true,
        errorMessage: 'Erro ao ler pubspec.yaml: $e',
      );
    }
  }

  static List<PubspecDependencyEntry> _parseSection(
    dynamic section, {
    required bool isDev,
  }) {
    if (section is! YamlMap) return const [];
    final list = <PubspecDependencyEntry>[];

    for (final key in section.keys) {
      final name = key.toString().trim();
      if (name.isEmpty) continue;
      final value = section[key];

      String constraint;
      String sourceType = 'pub';

      if (value == null) {
        constraint = 'any';
      } else if (value is YamlMap) {
        if (value.containsKey('sdk')) {
          sourceType = 'sdk';
          constraint = 'sdk: ${value['sdk']}';
        } else if (value.containsKey('path')) {
          sourceType = 'path';
          constraint = 'path: ${value['path']}';
        } else if (value.containsKey('git')) {
          sourceType = 'git';
          constraint = 'git';
        } else {
          constraint = value.toString();
        }
      } else {
        constraint = value.toString().trim();
        if (constraint.isEmpty) constraint = 'any';
      }

      list.add(
        PubspecDependencyEntry(
          name: name,
          constraint: constraint,
          isDev: isDev,
          sourceType: sourceType,
        ),
      );
    }

    list.sort((a, b) {
      if (a.name == 'flutter' || a.name == 'flutter_test') return -1;
      if (b.name == 'flutter' || b.name == 'flutter_test') return 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// Adds or updates [packageName] in `pubspec.yaml` preserving formatting.
  static Future<bool> addOrUpdateDependency({
    required String projectRoot,
    required String packageName,
    String versionConstraint = 'any',
    bool isDev = false,
  }) async {
    final cleanName = packageName.trim().toLowerCase();
    if (!validPackageNameRegex.hasMatch(cleanName)) return false;

    final cleanVersion =
        versionConstraint.trim().isEmpty ? 'any' : versionConstraint.trim();

    final file = File(p.join(p.normalize(projectRoot), 'pubspec.yaml'));
    if (!file.existsSync()) return false;

    try {
      final raw = file.readAsStringSync();
      final isCrlf = raw.contains('\r\n');
      final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final editor = YamlEditor(
        normalized.trim().isEmpty ? 'name: flrd_project\n' : normalized,
      );

      final rootNode = editor.parseAt([]);
      final targetKey = isDev ? 'dev_dependencies' : 'dependencies';
      if (rootNode is! YamlMap ||
          !rootNode.containsKey(targetKey) ||
          rootNode[targetKey] is! YamlMap) {
        editor.update([targetKey], <String, dynamic>{});
      }

      editor.update([targetKey, cleanName], cleanVersion);

      var output = editor.toString();
      if (isCrlf) {
        output = output.replaceAll('\n', '\r\n');
      }
      file.writeAsStringSync(output);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes [packageName] from `dependencies` or `dev_dependencies`.
  static Future<bool> removeDependency({
    required String projectRoot,
    required String packageName,
    bool isDev = false,
  }) async {
    final cleanName = packageName.trim();
    if (cleanName.isEmpty ||
        cleanName == 'flutter' ||
        cleanName == 'flutter_test') {
      return false;
    }

    final file = File(p.join(p.normalize(projectRoot), 'pubspec.yaml'));
    if (!file.existsSync()) return false;

    try {
      final raw = file.readAsStringSync();
      final isCrlf = raw.contains('\r\n');
      final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final editor = YamlEditor(normalized);
      final targetKey = isDev ? 'dev_dependencies' : 'dependencies';
      final rootNode = editor.parseAt([]);
      if (rootNode is! YamlMap) return false;

      final section = rootNode[targetKey];
      if (section is! YamlMap || !section.containsKey(cleanName)) {
        return false;
      }

      editor.remove([targetKey, cleanName]);
      var output = editor.toString();
      if (isCrlf) {
        output = output.replaceAll('\n', '\r\n');
      }
      file.writeAsStringSync(output);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Runs `flutter pub get` inside [projectRoot].
  static Future<({bool success, String output})> runPubGet(
    String projectRoot, {
    Future<ProcessResult> Function(
      String exe,
      List<String> args, {
      String? workingDirectory,
      bool runInShell,
    })? processRunner,
  }) async {
    if (kIsWeb || projectRoot.trim().isEmpty) {
      return (success: false, output: 'Execução disponível apenas no Desktop.');
    }

    final runner = processRunner ??
        (String exe, List<String> args,
                {String? workingDirectory, bool runInShell = true}) =>
            Process.run(
              exe,
              args,
              workingDirectory: workingDirectory,
              runInShell: runInShell,
              stdoutEncoding: const Utf8Codec(allowMalformed: true),
              stderrEncoding: const Utf8Codec(allowMalformed: true),
            );

    try {
      final res = await runner(
        'flutter',
        ['pub', 'get'],
        workingDirectory: p.normalize(projectRoot),
        runInShell: true,
      );
      final text =
          '${res.stdout ?? ''}\n${res.stderr ?? ''}'.trim();
      return (success: res.exitCode == 0, output: text);
    } catch (e) {
      return (success: false, output: 'Falha ao executar flutter pub get: $e');
    }
  }
}
