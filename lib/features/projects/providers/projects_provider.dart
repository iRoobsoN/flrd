import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../wizard/models/project_config.dart';
import '../models/registered_project.dart';

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
    String? selectedProjectId,
  }) {
    return ProjectsState(
      projects: projects ?? this.projects,
      isScanning: isScanning ?? this.isScanning,
      selectedProjectId: selectedProjectId ?? this.selectedProjectId,
    );
  }
}

class ProjectsNotifier extends StateNotifier<ProjectsState> {
  ProjectsNotifier()
      : super(
          ProjectsState(
            projects: [
              RegisteredProject(
                id: 'my_awesome_app',
                name: 'my_awesome_app',
                orgId: 'com.example.awesome',
                path: 'C:/Users/Rob/Desktop/my_awesome_app',
                preset: PresetType.saas,
                navigationStyle: NavigationStyle.tabs,
                permissions: {DevicePermission.camera, DevicePermission.notifications},
                lastModified: DateTime.now().subtract(const Duration(hours: 2)),
                routeCount: 6,
              ),
              RegisteredProject(
                id: 'crypto_clean_wallet',
                name: 'crypto_clean_wallet',
                orgId: 'com.robsondavid.wallet',
                path: 'C:/Projects/crypto_clean_wallet',
                preset: PresetType.cleanLite,
                navigationStyle: NavigationStyle.adaptiveRail,
                permissions: {DevicePermission.biometrics, DevicePermission.photoLibrary},
                lastModified: DateTime.now().subtract(const Duration(days: 1)),
                routeCount: 5,
              ),
              RegisteredProject(
                id: 'notes_offline_vault',
                name: 'notes_offline_vault',
                orgId: 'com.iroobson.vault',
                path: 'C:/Projects/notes_offline_vault',
                preset: PresetType.offline,
                navigationStyle: NavigationStyle.drawer,
                permissions: {DevicePermission.photoLibrary},
                lastModified: DateTime.now().subtract(const Duration(days: 3)),
                routeCount: 4,
              ),
            ],
          ),
        );

  void addProject({
    required String name,
    required String orgId,
    required String path,
    required PresetType preset,
    required NavigationStyle navigationStyle,
    required Set<DevicePermission> permissions,
    int routeCount = 5,
  }) {
    final newProject = RegisteredProject(
      id: name.toLowerCase().replaceAll(' ', '_'),
      name: name,
      orgId: orgId,
      path: path,
      preset: preset,
      navigationStyle: navigationStyle,
      permissions: permissions,
      lastModified: DateTime.now(),
      routeCount: routeCount,
    );

    state = state.copyWith(
      projects: [newProject, ...state.projects],
    );
  }

  void registerProject(RegisteredProject project) {
    final existingIndex = state.projects.indexWhere(
      (p) => p.id == project.id || p.path == project.path,
    );
    if (existingIndex >= 0) {
      final updated = List<RegisteredProject>.from(state.projects);
      updated[existingIndex] = project;
      state = state.copyWith(projects: updated);
    } else {
      state = state.copyWith(
        projects: [project, ...state.projects],
      );
    }
  }

  void removeProject(String id) {
    state = state.copyWith(
      projects: state.projects.where((p) => p.id != id).toList(),
    );
  }

  void selectProject(String id) {
    state = state.copyWith(selectedProjectId: id);
  }

  Future<void> scanWorkspace() async {
    state = state.copyWith(isScanning: true);
    // Simulate filesystem scan with brief feedback
    await Future.delayed(const Duration(milliseconds: 600));
    state = state.copyWith(isScanning: false);
  }
}

final projectsProvider =
    StateNotifierProvider<ProjectsNotifier, ProjectsState>((ref) {
  return ProjectsNotifier();
});
