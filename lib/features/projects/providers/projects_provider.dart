import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wizard/models/project_config.dart';
import '../models/registered_project.dart';
import '../services/project_analyzer_service.dart';
import '../services/workspace_projects_service.dart';

const _projectsSentinel = Object();

class ProjectsState {
  final List<RegisteredProject> projects;
  final bool isScanning;
  final String? selectedProjectId;

  const ProjectsState({
    this.projects = const [],
    this.isScanning = false,
    this.selectedProjectId,
  });

  ProjectsState copyWith({
    List<RegisteredProject>? projects,
    bool? isScanning,
    Object? selectedProjectId = _projectsSentinel,
  }) {
    return ProjectsState(
      projects: projects ?? this.projects,
      isScanning: isScanning ?? this.isScanning,
      selectedProjectId: identical(selectedProjectId, _projectsSentinel)
          ? this.selectedProjectId
          : selectedProjectId as String?,
    );
  }
}

/// Manages the user's real Flutter projects on disk, persisting valid project
/// paths and discovering real `pubspec.yaml` workspaces without mockup data.
class ProjectsNotifier extends StateNotifier<ProjectsState> {
  final String? _storageFilePath;
  final List<String>? _workspaceScanRoots;
  final bool _enableDiskSync;

  ProjectsNotifier({
    String? storageFilePath,
    List<String>? workspaceScanRoots,
    bool? enableDiskSync,
    bool autoInitialize = true,
  })  : _storageFilePath = storageFilePath,
        _workspaceScanRoots = workspaceScanRoots,
        _enableDiskSync = enableDiskSync ?? _resolveDefaultDiskSync(),
        super(const ProjectsState()) {
    if (autoInitialize && _enableDiskSync) {
      Future<void>.microtask(_initializeFromDisk);
    }
  }

  static bool _resolveDefaultDiskSync() {
    if (kIsWeb) return false;
    try {
      return !Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  Future<void> _initializeFromDisk() async {
    if (!mounted || kIsWeb) return;
    final loaded = WorkspaceProjectsService.loadPersistedProjectPaths(
      storageFilePath: _storageFilePath,
    );

    if (!loaded.hasStorageFile) {
      await scanWorkspace();
      return;
    }

    if (loaded.paths.isEmpty) {
      return;
    }

    state = state.copyWith(isScanning: true);
    final analyzed = await _analyzeValidDirectories(loaded.paths);
    if (!mounted) return;

    state = state.copyWith(
      projects: analyzed,
      isScanning: false,
    );
    await WorkspaceProjectsService.savePersistedProjectPaths(
      analyzed.map((p) => p.path).toList(growable: false),
      storageFilePath: _storageFilePath,
    );
  }

  void addProject({
    required String name,
    required String orgId,
    required String path,
    required PresetType preset,
    required NavigationStyle navigationStyle,
    required Set<DevicePermission> permissions,
    int routeCount = 5,
  }) {
    final normalizedPath =
        WorkspaceProjectsService.normalizeProjectPath(path);
    final newProject = RegisteredProject(
      id: name.toLowerCase().replaceAll(' ', '_'),
      name: name,
      orgId: orgId,
      path: normalizedPath.isNotEmpty ? normalizedPath : path,
      preset: preset,
      navigationStyle: navigationStyle,
      permissions: permissions,
      lastModified: DateTime.now(),
      routeCount: routeCount,
    );

    registerProject(newProject);
  }

  void registerProject(RegisteredProject project) {
    final normalizedPath =
        WorkspaceProjectsService.normalizeProjectPath(project.path);
    final normalizedProject = normalizedPath.isNotEmpty
        ? project.copyWith(path: normalizedPath)
        : project;
    final targetKey =
        WorkspaceProjectsService.canonicalCompareKey(normalizedProject.path);

    final updated = <RegisteredProject>[];
    var replaced = false;
    for (final existing in state.projects) {
      final existingKey =
          WorkspaceProjectsService.canonicalCompareKey(existing.path);
      final isSameProject =
          existing.id == normalizedProject.id ||
          (targetKey.isNotEmpty && existingKey == targetKey);
      if (isSameProject) {
        if (!replaced) {
          updated.add(normalizedProject);
          replaced = true;
        }
      } else {
        updated.add(existing);
      }
    }
    if (!replaced) {
      updated.insert(0, normalizedProject);
    }

    state = state.copyWith(projects: updated);
    _persistCurrentPaths();
  }

  void removeProject(String id) {
    state = state.copyWith(
      projects: state.projects.where((p) => p.id != id).toList(),
      selectedProjectId:
          state.selectedProjectId == id ? null : state.selectedProjectId,
    );
    _persistCurrentPaths();
  }

  void selectProject(String? id) {
    state = state.copyWith(selectedProjectId: id);
  }

  Future<void> scanWorkspace({List<String>? extraRoots}) async {
    if (!mounted) return;
    if (kIsWeb) {
      state = state.copyWith(isScanning: false);
      return;
    }

    state = state.copyWith(isScanning: true);
    try {
      final roots = <String>[
        ...?_workspaceScanRoots,
        if (_workspaceScanRoots == null && _enableDiskSync)
          ...WorkspaceProjectsService.defaultScanRoots(),
        ...?extraRoots,
      ];

      final discovered = await WorkspaceProjectsService.discoverProjectDirs(
        roots,
      );

      final seenKeys = <String>{};
      final validPaths = <String>[];

      void addIfValid(String rawPath) {
        final normalized =
            WorkspaceProjectsService.normalizeProjectPath(rawPath);
        if (!WorkspaceProjectsService.isValidFlutterProjectDir(normalized)) {
          return;
        }
        final key = WorkspaceProjectsService.canonicalCompareKey(normalized);
        if (seenKeys.add(key)) {
          validPaths.add(normalized);
        }
      }

      for (final existing in state.projects) {
        addIfValid(existing.path);
      }
      for (final path in discovered) {
        addIfValid(path);
      }

      final analyzed = await _analyzeValidDirectories(validPaths);
      if (!mounted) return;

      final validIds = analyzed.map((p) => p.id).toSet();
      final nextSelected = (state.selectedProjectId != null &&
              validIds.contains(state.selectedProjectId))
          ? state.selectedProjectId
          : null;

      state = state.copyWith(
        projects: analyzed,
        isScanning: false,
        selectedProjectId: nextSelected,
      );

      if (_enableDiskSync || _storageFilePath != null) {
        await WorkspaceProjectsService.savePersistedProjectPaths(
          analyzed.map((p) => p.path).toList(growable: false),
          storageFilePath: _storageFilePath,
        );
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(isScanning: false);
      }
    }
  }

  Future<List<RegisteredProject>> _analyzeValidDirectories(
    List<String> paths,
  ) async {
    final analyzed = <RegisteredProject>[];
    for (final dirPath in paths) {
      if (!WorkspaceProjectsService.isValidFlutterProjectDir(dirPath)) {
        continue;
      }
      try {
        final result = await ProjectAnalyzerService.analyzeProject(dirPath);
        analyzed.add(result.project);
      } catch (_) {
        // Ignore folders with unreadable or malformed pubspec.yaml.
      }
    }
    analyzed.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return analyzed;
  }

  void _persistCurrentPaths() {
    if (!_enableDiskSync && _storageFilePath == null) return;
    WorkspaceProjectsService.savePersistedProjectPaths(
      state.projects.map((p) => p.path).toList(growable: false),
      storageFilePath: _storageFilePath,
    );
  }
}

final projectsProvider =
    StateNotifierProvider<ProjectsNotifier, ProjectsState>((ref) {
  return ProjectsNotifier();
});
