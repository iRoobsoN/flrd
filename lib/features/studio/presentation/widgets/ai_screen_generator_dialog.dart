import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../ai/providers/ai_settings_provider.dart';
import '../../../ai/services/gemini_ai_service.dart';
import '../../../projects/models/registered_project.dart';
import '../../providers/studio_provider.dart';

class AiScreenGeneratorDialog extends ConsumerStatefulWidget {
  final RegisteredProject project;

  const AiScreenGeneratorDialog({super.key, required this.project});

  static Future<void> show(BuildContext context, RegisteredProject project) {
    return showDialog(
      context: context,
      builder: (_) => AiScreenGeneratorDialog(project: project),
    );
  }

  @override
  ConsumerState<AiScreenGeneratorDialog> createState() =>
      _AiScreenGeneratorDialogState();
}

class _AiScreenGeneratorDialogState
    extends ConsumerState<AiScreenGeneratorDialog> {
  final _pathController = TextEditingController(text: '/checkout/payment');
  final _titleController = TextEditingController(text: 'PaymentScreen');
  final _promptController = TextEditingController(
    text:
        'Tela de checkout e pagamento com seleção de Pix, Cartão de Crédito e resumo de pedido com gradiente Obsidian.',
  );
  late final TextEditingController _apiKeyController;

  String _parentRouteId = 'dashboard';
  int _selectedMode = 0; // 0 = FLRD Pro Cloud, 1 = BYOK Gemini
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    final initialKey = ref.read(aiSettingsProvider).apiKey ?? '';
    _apiKeyController = TextEditingController(text: initialKey);
  }

  @override
  void dispose() {
    _pathController.dispose();
    _titleController.dispose();
    _promptController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _generateScreen() async {
    setState(() => _isGenerating = true);

    try {
      final cleanTitle = _titleController.text.trim().isEmpty
          ? 'GeneratedScreen'
          : _titleController.text.trim();

      final aiSettings = ref.read(aiSettingsProvider);
      final activeApiKey = (_selectedMode == 1)
          ? (_apiKeyController.text.trim().isNotEmpty
              ? _apiKeyController.text.trim()
              : aiSettings.apiKey)
          : null;

      // Update provider if user typed key in BYOK mode
      if (_selectedMode == 1 && _apiKeyController.text.trim().isNotEmpty) {
        ref.read(aiSettingsProvider.notifier).setApiKey(_apiKeyController.text.trim());
      }

      // 1. Generate code and write physical file via GeminiAiService
      final result = await GeminiAiService.generateScreen(
        projectPath: widget.project.path,
        screenClassName: cleanTitle,
        routePath: _pathController.text.trim(),
        prompt: _promptController.text.trim(),
        preset: widget.project.preset,
        apiKey: activeApiKey,
      );

      if (!mounted) return;

      // 2. Inject RouteNode into Flowchart
      final studio = ref.read(studioProvider.notifier);
      final currentNodes = ref.read(studioProvider).nodes;

      final parent = currentNodes.firstWhere(
        (n) => n.id == _parentRouteId,
        orElse: () => currentNodes.last,
      );

      final newPos = Offset(
        parent.position.dx + 330,
        parent.position.dy + 30,
      );

      studio.addRouteNode(
        path: _pathController.text.trim(),
        title: cleanTitle,
        subtitle: _promptController.text.trim(),
        icon: Icons.auto_awesome_rounded,
        isProtected: true,
        isAIGenerated: true,
        position: newPos,
        parentRouteId: _parentRouteId,
        filePath: result.filePath,
      );

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Tela "$cleanTitle" gerada via IA e injetada no Fluxograma! (${result.filePath})'),
              ),
            ],
          ),
          backgroundColor: AppColors.surfaceSelected,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Falha ao gerar tela com IA: $e'),
              ),
            ],
          ),
          backgroundColor: AppColors.surfaceCard,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(studioProvider).nodes;

    return AlertDialog(
      backgroundColor: AppColors.backgroundSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.secondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gerador de Telas com IA',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'FLRD AI Screen Studio • Clean Architecture Output',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Architecture Context Pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.architecture_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Contexto do Projeto: ${widget.project.preset.name.toUpperCase()} • Riverpod & Tokens',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Route Path & Screen Class Name Fields
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Caminho da Rota',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _pathController,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: AppColors.secondary,
                          ),
                          decoration: InputDecoration(
                            hintText: '/minha-tela',
                            hintStyle:
                                const TextStyle(color: AppColors.textMuted),
                            filled: true,
                            fillColor: AppColors.surfaceCard,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nome da Classe Widget',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _titleController,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'PaymentScreen',
                            hintStyle:
                                const TextStyle(color: AppColors.textMuted),
                            filled: true,
                            fillColor: AppColors.surfaceCard,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Parent Node Selector
              const Text(
                'Conectar a partir de qual Rota (Pai no Fluxograma)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _parentRouteId,
                    dropdownColor: AppColors.surface,
                    isExpanded: true,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                    items: nodes.map((node) {
                      return DropdownMenuItem<String>(
                        value: node.id,
                        child: Text('${node.title} (${node.path})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _parentRouteId = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // AI Prompt
              const Text(
                'Prompt da Tela (Descreva o que a IA deve gerar)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _promptController,
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Ex: Tela de perfil com avatar, bio e estatísticas',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surfaceCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 16),

              // AI Provider Architecture Selector (Security & Monetization model!)
              const Text(
                'Provedor de Execução da IA',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildModeOption(
                      index: 0,
                      title: '⚡ FLRD Pro Cloud',
                      subtitle: 'Proxy Seguro na Nuvem (Chave Secreta Privada)',
                      icon: Icons.cloud_done_rounded,
                      accentColor: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildModeOption(
                      index: 1,
                      title: '🔑 BYOK (Sua Chave)',
                      subtitle: 'Gemini API Gratuita salva localmente no PC',
                      icon: Icons.key_rounded,
                      accentColor: AppColors.success,
                    ),
                  ),
                ],
              ),

              if (_selectedMode == 1) ...[
                const SizedBox(height: 12),
                const Text(
                  'Chave de API Google Gemini (BYOK)',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Cole sua Gemini API Key (ex: AIzaSy...)',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    prefixIcon: const Icon(
                      Icons.key_rounded,
                      size: 16,
                      color: AppColors.success,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (val) {
                    ref.read(aiSettingsProvider.notifier).setApiKey(val);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isGenerating ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancelar',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: AppColors.background,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _isGenerating ? null : _generateScreen,
          icon: _isGenerating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.background,
                  ),
                )
              : const Icon(Icons.auto_awesome_rounded, size: 16),
          label: Text(
            _isGenerating ? 'Gerando com IA...' : 'Gerar e Injetar Tela',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildModeOption({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    final isSelected = _selectedMode == index;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selectedMode = index),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withOpacity(0.12)
              : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accentColor : AppColors.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
