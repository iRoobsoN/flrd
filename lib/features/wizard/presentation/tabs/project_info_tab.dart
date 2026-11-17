import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../models/project_name_validator.dart';
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
        if (!mounted) return;
        ref
            .read(wizardProvider.notifier)
            .updateConfig((c) => c.copyWith(outputPath: initialPath));
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

  List<({String label, String path, IconData icon, Color color})>
      _suggestedFolders() {
    final shortcuts =
        <({String label, String path, IconData icon, Color color})>[
      (
        label: 'C:/Projects',
        path: 'C:/Projects',
        icon: Icons.flash_on_rounded,
        color: AppColors.secondary,
      ),
    ];

    if (!kIsWeb) {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      if (home.isNotEmpty) {
        final desktop = p.join(home, 'Desktop').replaceAll('\\', '/');
        final docs = p.join(home, 'Documents').replaceAll('\\', '/');
        shortcuts.add((
          label: 'Desktop',
          path: desktop,
          icon: Icons.desktop_windows_rounded,
          color: AppColors.primary,
        ));
        shortcuts.add((
          label: 'Documents',
          path: docs,
          icon: Icons.folder_special_rounded,
          color: AppColors.success,
        ));
      }
    }
    return shortcuts;
  }

  void _applyOutputPath(String path) {
    final cleaned = path.trim();
    setState(() {
      _pathController.text = cleaned;
    });
    ref
        .read(wizardProvider.notifier)
        .updateConfig((c) => c.copyWith(outputPath: cleaned));
  }

  Future<void> _pickFolder() async {
    if (kIsWeb) {
      if (mounted) {
        AppToast.info(
          context,
          'No navegador, use os atalhos abaixo ou digite um caminho (ex.: C:/Projects).',
          duration: const Duration(seconds: 4),
        );
      }
      return;
    }

    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Selecione a pasta onde criar o projeto',
      );
      if (result != null && result.trim().isNotEmpty) {
        _applyOutputPath(result);
      }
    } catch (_) {
      // Gracefully ignored on platforms without directory picker
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(wizardProvider.notifier);
    final trimmedPath = _pathController.text.trim();
    final trimmedName = _nameController.text.trim();
    final pathError =
        trimmedPath.isEmpty ? 'Escolha ou digite uma pasta de destino.' : null;
    final previewFullPath = trimmedPath.isNotEmpty
        ? p.join(trimmedPath, trimmedName.isEmpty ? 'meu_app' : trimmedName)
            .replaceAll('\\', '/')
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Etapa 1 • Identidade do Projeto',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Defina o nome interno do pacote, o identificador da empresa e onde a pasta do projeto será criada no seu computador.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),

          // Project Name Input
          _FormField(
            fieldKey: const ValueKey('wizard_project_name_input'),
            label: 'NOME DO PROJETO (SNAKE_CASE)',
            hint: 'ex.: meu_app_delivery',
            helperText:
                'Use letras minúsculas, números e underline (padrão oficial Dart/Flutter).',
            errorText: ProjectNameValidator.validate(_nameController.text),
            controller: _nameController,
            onChanged: (val) {
              setState(() {});
              notifier.updateConfig((c) => c.copyWith(projectName: val.trim()));
            },
          ),
          const SizedBox(height: 22),

          // Organization / Bundle ID Input
          _FormField(
            fieldKey: const ValueKey('wizard_org_id_input'),
            label: 'ORGANIZAÇÃO / APPLICATION ID (DOMÍNIO REVERSO)',
            hint: 'ex.: com.suaempresa, dev.seuapp',
            helperText:
                'Identificador único usado na Play Store (Android) e App Store (iOS).',
            errorText: OrgIdValidator.validate(_orgController.text),
            controller: _orgController,
            onChanged: (val) {
              setState(() {});
              notifier.updateConfig((c) => c.copyWith(orgId: val.trim()));
            },
          ),
          const SizedBox(height: 22),

          // Output Directory Selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PASTA DE DESTINO (OBRIGATÓRIO)',
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
                      key: const ValueKey('wizard_output_path_input'),
                      controller: _pathController,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: 'C:/Projects',
                        prefixIcon: const Icon(
                          Icons.folder_open_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        errorText: pathError,
                      ),
                      onChanged: (val) {
                        setState(() {});
                        notifier.updateConfig(
                          (c) => c.copyWith(outputPath: val.trim()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _pickFolder,
                    icon: const Icon(Icons.drive_folder_upload_rounded, size: 16),
                    label: const Text('Escolher Pasta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceHover,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                previewFullPath != null
                    ? 'Será criado em: $previewFullPath'
                    : 'Uma subpasta com o nome do projeto será criada dentro dessa pasta.',
                style: TextStyle(
                  color: previewFullPath != null
                      ? AppColors.secondary
                      : AppColors.textMuted,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _suggestedFolders()
                    .map(
                      (s) => ActionChip(
                        label: Text(s.label),
                        avatar: Icon(s.icon, size: 14, color: s.color),
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.border),
                        labelStyle: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        onPressed: () => _applyOutputPath(s.path),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final Key? fieldKey;
  final String label;
  final String hint;
  final String helperText;
  final String? errorText;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _FormField({
    this.fieldKey,
    required this.label,
    required this.hint,
    required this.helperText,
    this.errorText,
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
          key: fieldKey,
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
          ),
          onChanged: onChanged,
        ),
        if (errorText == null) ...[
          const SizedBox(height: 6),
          Text(
            helperText,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
