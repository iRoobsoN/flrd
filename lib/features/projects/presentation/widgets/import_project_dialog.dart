import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../studio/presentation/app_studio_screen.dart';
import '../../../studio/providers/studio_provider.dart';
import '../../providers/projects_provider.dart';
import '../../services/project_analyzer_service.dart';

/// Obsidian Glass dialog for analyzing and importing an existing Flutter project.
class ImportProjectDialog extends ConsumerStatefulWidget {
  const ImportProjectDialog({super.key});

  /// Displays the [ImportProjectDialog].
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => const ImportProjectDialog(),
    );
  }

  @override
  ConsumerState<ImportProjectDialog> createState() =>
      _ImportProjectDialogState();
}

class _ImportProjectDialogState extends ConsumerState<ImportProjectDialog> {
  final TextEditingController _pathController =
      TextEditingController(text: 'C:/Projects');
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    if (kIsWeb) {
      AppToast.info(
        context,
        'A seleção de pastas do sistema está disponível no aplicativo Desktop.',
      );
      return;
    }

    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Selecione o diretório do projeto Flutter',
      );
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        setState(() {
          _pathController.text = selectedDirectory.replaceAll('\\', '/');
          _errorMessage = null;
        });
      }
    } catch (_) {}
  }

  String _sanitizePath(String rawPath) {
    var cleaned = rawPath.trim();
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    return p.normalize(cleaned);
  }

  Future<void> _importProject() async {
    var path = _sanitizePath(_pathController.text);
    if (path.isEmpty) {
      setState(() {
        _errorMessage = 'Por favor, informe o caminho do projeto Flutter.';
      });
      return;
    }

    if (!kIsWeb) {
      if (FileSystemEntity.isFileSync(path)) {
        if (p.basename(path).toLowerCase() == 'pubspec.yaml') {
          path = p.dirname(path);
          _pathController.text = path.replaceAll('\\', '/');
        } else {
          setState(() {
            _errorMessage =
                'O caminho especificado aponta para um arquivo. Selecione a pasta raiz do projeto.';
          });
          return;
        }
      }

      final dir = Directory(path);
      if (!dir.existsSync()) {
        setState(() {
          _errorMessage = 'O diretório informado não foi encontrado: "$path"';
        });
        return;
      }

      final pubspec = File(p.join(path, 'pubspec.yaml'));
      if (!pubspec.existsSync()) {
        setState(() {
          _errorMessage =
              'Nenhum pubspec.yaml encontrado em "$path". Certifique-se de selecionar a raiz de um projeto Flutter válido.';
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ProjectAnalyzerService.analyzeProject(path);

      if (!mounted) return;

      // Register the project in ProjectsNotifier
      ref.read(projectsProvider.notifier).registerProject(result.project);

      // Load extracted route nodes into StudioNotifier
      ref.read(studioProvider.notifier).setNodes(result.routeNodes);

      // Dismiss dialog
      Navigator.of(context).pop();

      // Navigate directly to AppStudioScreen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AppStudioScreen(project: result.project),
        ),
      );

      // Show success feedback
      AppToast.success(
        context,
        'Projeto importado com sucesso! ${result.routeNodes.length} rotas mapeadas.',
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      if (!mounted) return;
      final cleanMessage = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isLoading = false;
        _errorMessage = cleanMessage;
      });

      AppToast.error(
        context,
        'Erro ao importar projeto: $cleanMessage',
        duration: const Duration(seconds: 4),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.backgroundSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.folder_open_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importar Projeto Existente',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Engenharia reversa de arquitetura, rotas e dependências',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.textMuted,
            ),
            splashRadius: 18,
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info description box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Selecione a pasta raiz do projeto Flutter (contendo pubspec.yaml). O FLRD analisará a arquitetura e extrairá o mapa de rotas interativo no Studio.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Caminho do Projeto',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      enabled: !_isLoading,
                      onSubmitted: _isLoading ? null : (_) => _importProject(),
                      onChanged: (val) {
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        }
                      },
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppColors.secondary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'C:/Projects/meu_app',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surfaceCard,
                        prefixIcon: const Icon(
                          Icons.folder_outlined,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _pickFolder,
                    icon: const Icon(
                      Icons.drive_folder_upload_rounded,
                      size: 16,
                    ),
                    label: const Text('Procurar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceHover,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Shortcut Chips
              const Text(
                'Atalhos rápidos:',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('C:/Projects'),
                    avatar: const Icon(
                      Icons.flash_on_rounded,
                      size: 14,
                      color: AppColors.secondary,
                    ),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    onPressed: _isLoading
                        ? null
                        : () => setState(
                              () => _pathController.text = 'C:/Projects',
                            ),
                  ),
                  ActionChip(
                    label: const Text('Desktop'),
                    avatar: const Icon(
                      Icons.desktop_windows_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    onPressed: _isLoading
                        ? null
                        : () {
                            final desktopPath = Platform.isWindows
                                ? '${Platform.environment['USERPROFILE']?.replaceAll('\\', '/') ?? 'C:/Users/Rob'}/Desktop'
                                : '~/Desktop';
                            setState(() => _pathController.text = desktopPath);
                          },
                  ),
                  ActionChip(
                    label: const Text('FLRD Workspace'),
                    avatar: const Icon(
                      Icons.code_rounded,
                      size: 14,
                      color: AppColors.success,
                    ),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    onPressed: _isLoading
                        ? null
                        : () => setState(
                              () => _pathController.text =
                                  'C:/Users/Rob/Desktop/flrd',
                            ),
                  ),
                ],
              ),

              if (_isLoading) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.25),
                    ),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Analisando dependências e rotas do projeto...',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Lendo pubspec.yaml, permissões e componentes de tela...',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_errorMessage != null && !_isLoading) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancelar',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _isLoading ? null : _importProject,
          icon: _isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_awesome_rounded, size: 16),
          label: Text(
            _isLoading ? 'Analisando...' : 'Analisar e Importar',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
