import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/localization/language_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../projects/models/registered_project.dart';
import '../../../projects/presentation/widgets/import_project_dialog.dart';
import '../../../projects/providers/projects_provider.dart';
import '../../../projects/services/project_analyzer_service.dart';
import '../../../projects/services/workspace_projects_service.dart';
import '../../../studio/presentation/app_studio_screen.dart';
import '../../../studio/providers/studio_provider.dart';
import '../../../wizard/presentation/wizard_screen.dart';

class ProjectsGridView extends ConsumerWidget {
  const ProjectsGridView({super.key});

  Future<void> _openVsCode(BuildContext context, String path) async {
    if (kIsWeb) {
      AppToast.info(context, 'Abra no terminal local: code "$path"');
      return;
    }
    try {
      await Process.run('code', [path], runInShell: true);
    } catch (_) {}
  }

  Future<void> _openDirectory(String path) async {
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path.replaceAll('/', '\\')]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectsProvider);
    final strings = ref.watch(appStringsProvider);
    final projects = state.projects;

    if (projects.isEmpty) {
      return Container(
        key: const ValueKey('empty_projects_state'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                size: 28,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              strings.noProjectsTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                strings.noProjectsSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  key: const ValueKey('empty_create_project_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WizardScreen()),
                    );
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    strings.newProjectTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('empty_import_project_button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => ImportProjectDialog.show(context),
                  icon: const Icon(
                    Icons.folder_open_rounded,
                    size: 16,
                    color: AppColors.secondary,
                  ),
                  label: Text(
                    strings.language.code == 'pt'
                        ? 'Abrir Pasta do PC'
                        : 'Open Local Folder',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('empty_scan_projects_button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: state.isScanning
                      ? null
                      : () =>
                          ref.read(projectsProvider.notifier).scanWorkspace(),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    strings.language.code == 'pt'
                        ? 'Buscar no Computador'
                        : 'Scan Machine',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 220,
          ),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];
            return _ProjectCard(
              project: project,
              onOpenStudio: () async {
                var targetProject = project;
                final navigator = Navigator.of(context);
                if (!kIsWeb &&
                    !WorkspaceProjectsService.isValidFlutterProjectDir(
                      project.path,
                    )) {
                  ref.read(projectsProvider.notifier).removeProject(project.id);
                  if (!context.mounted) return;
                  AppToast.error(
                    context,
                    'Projeto real não encontrado em "${project.path}". Removido da lista.',
                  );
                  return;
                }
                if (!kIsWeb &&
                    File(p.join(project.path, 'pubspec.yaml')).existsSync()) {
                  final projectsNotifier = ref.read(projectsProvider.notifier);
                  final studioNotifier = ref.read(studioProvider.notifier);
                  try {
                    final analyzed =
                        await ProjectAnalyzerService.analyzeProject(
                      project.path,
                    );
                    targetProject = analyzed.project;
                    projectsNotifier.registerProject(analyzed.project);
                    studioNotifier.setNodes(analyzed.routeNodes);
                  } catch (_) {
                    // Fall back to opening the existing project record if re-analysis fails.
                  }
                }
                if (!context.mounted) return;
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => AppStudioScreen(project: targetProject),
                  ),
                );
              },
              onOpenVsCode: () => _openVsCode(context, project.path),
              onOpenDirectory: () => _openDirectory(project.path),
              onRemove: () {
                ref.read(projectsProvider.notifier).removeProject(project.id);
                AppToast.info(
                  context,
                  'Projeto "${project.name}" removido da lista do FLRD.',
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ProjectCard extends StatefulWidget {
  final RegisteredProject project;
  final VoidCallback onOpenStudio;
  final VoidCallback onOpenVsCode;
  final VoidCallback onOpenDirectory;
  final VoidCallback onRemove;

  const _ProjectCard({
    required this.project,
    required this.onOpenStudio,
    required this.onOpenVsCode,
    required this.onOpenDirectory,
    required this.onRemove,
  });

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.project;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onOpenStudio,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered ? AppColors.surfaceHover : AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isHovered
                  ? AppColors.primary.withOpacity(0.7)
                  : AppColors.border,
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Icon + Name + Preset Tag
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.flutter_dash_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          p.orgId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p.preset.name.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Remover da lista',
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: ValueKey('remove_project_${p.id}'),
                        onTap: widget.onRemove,
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // File Path snippet
              Text(
                p.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: AppColors.textMuted.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 10),

              // Route Count & Permission Chips
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.alt_route_rounded,
                          size: 11,
                          color: AppColors.secondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${p.routeCount} Rotas',
                          style: const TextStyle(
                            color: AppColors.secondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (p.permissions.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Text(
                        '${p.permissions.length} Permissões',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const Spacer(),

              // Bottom Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: widget.onOpenStudio,
                      icon: const Icon(Icons.alt_route_rounded, size: 13),
                      label: const Text(
                        'Fluxograma',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Abrir no VS Code',
                    icon: const Icon(Icons.code_rounded, size: 15),
                    color: AppColors.textSecondary,
                    onPressed: widget.onOpenVsCode,
                  ),
                  IconButton(
                    tooltip: 'Abrir Pasta',
                    icon: const Icon(Icons.folder_open_rounded, size: 15),
                    color: AppColors.textSecondary,
                    onPressed: widget.onOpenDirectory,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
