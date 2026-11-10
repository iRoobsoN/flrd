import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../controllers/wizard_controller.dart';

class ProjectInfoTab extends ConsumerStatefulWidget {
  const ProjectInfoTab({super.key});

  @override
  ConsumerState<ProjectInfoTab> createState() => _ProjectInfoTabState();
}

class _ProjectInfoTabState extends ConsumerState<ProjectInfoTab> {
  late TextEditingController _nameController;
  late TextEditingController _orgController;
  late TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    final config = ref.read(wizardProvider).config;
    _nameController = TextEditingController(text: config.projectName);
    _orgController = TextEditingController(text: config.orgId);
    
    final initialPath = config.outputPath.isNotEmpty
        ? config.outputPath
        : (kIsWeb ? 'C:/Projects' : '');
    _pathController = TextEditingController(text: initialPath);

    if (config.outputPath.isEmpty && initialPath.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(wizardProvider.notifier).updateConfig((c) => c.copyWith(outputPath: initialPath));
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orgController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.surfaceCard,
            duration: Duration(seconds: 4),
            content: Text(
              'No navegador (Chrome), selecione um dos atalhos abaixo ou digite o caminho (ex: C:/Projects). A janela nativa de pastas funciona no app Desktop.',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        );
      }
      return;
    }

    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Project Parent Directory',
      );
      if (result != null) {
        _pathController.text = result;
        ref.read(wizardProvider.notifier).updateConfig(
              (c) => c.copyWith(outputPath: result),
            );
      }
    } catch (_) {
      // Gracefully ignored on platforms without directory picker
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(wizardProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Project Setup',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Define your application identity, namespace, and local directory.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 32),

          // Project Name Input
          _FormField(
            label: 'PROJECT NAME',
            hint: 'e.g. my_saas_app',
            helperText: 'Use lowercase letters and underscores (standard Flutter naming).',
            controller: _nameController,
            onChanged: (val) {
              notifier.updateConfig((c) => c.copyWith(projectName: val.trim()));
            },
          ),
          const SizedBox(height: 24),

          // Organization / Bundle ID Input
          _FormField(
            label: 'ORGANIZATION / BUNDLE IDENTIFIER',
            hint: 'e.g. com.company, dev.robson',
            helperText: 'Your reverse domain name used for Android package and iOS bundle.',
            controller: _orgController,
            onChanged: (val) {
              notifier.updateConfig((c) => c.copyWith(orgId: val.trim()));
            },
          ),
          const SizedBox(height: 24),

          // Output Directory Selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DESTINATION DIRECTORY',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'C:/Users/You/Projects',
                        prefixIcon: Icon(Icons.folder_open_rounded, size: 18, color: AppColors.textMuted),
                      ),
                      onChanged: (val) {
                        notifier.updateConfig((c) => c.copyWith(outputPath: val.trim()));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _pickFolder,
                    icon: const Icon(Icons.drive_folder_upload_rounded, size: 16),
                    label: const Text('Browse'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceHover,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'A new subfolder with your project name will be created in this location.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('C:/Projects'),
                    avatar: const Icon(Icons.flash_on_rounded, size: 14, color: AppColors.secondary),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    onPressed: () {
                      _pathController.text = 'C:/Projects';
                      notifier.updateConfig((c) => c.copyWith(outputPath: 'C:/Projects'));
                    },
                  ),
                  ActionChip(
                    label: const Text('C:/Users/Rob/Desktop'),
                    avatar: const Icon(Icons.desktop_windows_rounded, size: 14, color: AppColors.primary),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    onPressed: () {
                      _pathController.text = 'C:/Users/Rob/Desktop';
                      notifier.updateConfig((c) => c.copyWith(outputPath: 'C:/Users/Rob/Desktop'));
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final String hint;
  final String helperText;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _FormField({
    required this.label,
    required this.hint,
    required this.helperText,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(hintText: hint),
          onChanged: onChanged,
        ),
        const SizedBox(height: 6),
        Text(
          helperText,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}
