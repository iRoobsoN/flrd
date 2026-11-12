import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/app_colors.dart';
import '../../../ai/providers/ai_settings_provider.dart';
import '../../../ai/services/gemini_ai_service.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../projects/models/registered_project.dart';
import '../../../settings/presentation/settings_and_billing_dialog.dart';
import '../../domain/screen_material.dart';
import '../../models/route_node.dart';
import '../../providers/studio_provider.dart';

class AiScreenGeneratorDialog extends ConsumerStatefulWidget {
  final RegisteredProject project;
  final String? initialPrompt;
  final String? initialRoutePath;
  final String? initialScreenTitle;
  final ScreenMaterialItem? targetMaterial;
  final List<ScreenMaterialItem>? initialMaterials;
  final http.Client? httpClient;

  const AiScreenGeneratorDialog({
    super.key,
    required this.project,
    this.initialPrompt,
    this.initialRoutePath,
    this.initialScreenTitle,
    this.targetMaterial,
    this.initialMaterials,
    this.httpClient,
  });

  static Future<void> show(
    BuildContext context,
    RegisteredProject project, {
    String? initialPrompt,
    String? initialRoutePath,
    String? initialScreenTitle,
    ScreenMaterialItem? targetMaterial,
    List<ScreenMaterialItem>? initialMaterials,
    http.Client? httpClient,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AiScreenGeneratorDialog(
        project: project,
        initialPrompt: initialPrompt,
        initialRoutePath: initialRoutePath,
        initialScreenTitle: initialScreenTitle,
        targetMaterial: targetMaterial,
        initialMaterials: initialMaterials,
        httpClient: httpClient,
      ),
    );
  }

  /// Resolves the active Gemini API key to use based on mode selection and available credentials.
  /// In Pro Cloud mode (selectedMode == 0), passes `aiSettings.apiKey` if a key is stored.
  static String? resolveActiveApiKey({
    required int selectedMode,
    required AiSettingsState aiSettings,
    required String byokInputKey,
  }) {
    return (selectedMode == 0)
        ? ((aiSettings.apiKey != null && aiSettings.apiKey!.trim().isNotEmpty)
            ? aiSettings.apiKey!.trim()
            : null)
        : (byokInputKey.trim().isNotEmpty
            ? byokInputKey.trim()
            : (aiSettings.apiKey != null && aiSettings.apiKey!.trim().isNotEmpty
                ? aiSettings.apiKey!.trim()
                : null));
  }

  @override
  ConsumerState<AiScreenGeneratorDialog> createState() =>
      _AiScreenGeneratorDialogState();
}

class _AiScreenGeneratorDialogState
    extends ConsumerState<AiScreenGeneratorDialog> {
  late final TextEditingController _pathController;
  late final TextEditingController _titleController;
  late final TextEditingController _promptController;
  late final TextEditingController _apiKeyController;

  String _parentRouteId = 'dashboard';
  int _selectedMode = 0; // 0 = FLRD Pro Cloud, 1 = BYOK Gemini
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    final defaultPath = widget.targetMaterial != null
        ? '/components/${widget.targetMaterial!.type.name}'
        : '/checkout/payment';
    final defaultTitle = widget.targetMaterial != null
        ? '${widget.targetMaterial!.displayName.replaceAll(RegExp(r'\s+'), '')}Widget'
        : 'PaymentScreen';

    _pathController = TextEditingController(
      text: widget.initialRoutePath ?? defaultPath,
    );
    _titleController = TextEditingController(
      text: widget.initialScreenTitle ?? defaultTitle,
    );

    final existingNodes = ref.read(studioProvider).nodes;
    String promptText = widget.initialPrompt ?? '';
    if (promptText.isEmpty) {
      if (widget.targetMaterial != null) {
        promptText = ScreenMaterialCodeUpdater.generateWidgetSpecificPrompt(
          widget.targetMaterial!,
          existingRoutes: existingNodes,
          preset: widget.project.preset,
        );
      } else {
        promptText =
            'Tela de checkout e pagamento com seleção de Pix, Cartão de Crédito e resumo de pedido com gradiente Obsidian.';
      }
    }

    _promptController = TextEditingController(text: promptText);
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
      // 1. Credit Deduction when generating with FLRD Pro Cloud (_selectedMode == 0)
      if (_selectedMode == 0) {
        await ref.read(authProvider.notifier).consumeAiCredit();
      }

      final cleanTitle = _titleController.text.trim().isEmpty
          ? (widget.targetMaterial != null
              ? '${widget.targetMaterial!.displayName.replaceAll(RegExp(r'\s+'), '')}Widget'
              : 'GeneratedScreen')
          : _titleController.text.trim();

      final aiSettings = ref.read(aiSettingsProvider);
      final activeApiKey = AiScreenGeneratorDialog.resolveActiveApiKey(
        selectedMode: _selectedMode,
        aiSettings: aiSettings,
        byokInputKey: _apiKeyController.text,
      );

      // Update provider if user typed key in BYOK mode
      if (_selectedMode == 1 && _apiKeyController.text.trim().isNotEmpty) {
        ref.read(aiSettingsProvider.notifier).setApiKey(_apiKeyController.text.trim());
      }

      // 2. Read existing project routes for app navigation context
      final existingNodes = ref.read(studioProvider).nodes;

      // 3. Generate code and write physical file via GeminiAiService
      final result = await GeminiAiService.generateScreen(
        projectPath: widget.project.path,
        screenClassName: cleanTitle,
        routePath: _pathController.text.trim(),
        prompt: _promptController.text.trim(),
        preset: widget.project.preset,
        existingRoutes: existingNodes,
        materials: widget.initialMaterials,
        apiKey: activeApiKey,
        httpClient: widget.httpClient,
      );

      if (!mounted) return;

      // 4. Inject RouteNode into Flowchart
      final studio = ref.read(studioProvider.notifier);
      final currentNodes = ref.read(studioProvider).nodes;

      RouteNode? parent;
      for (final n in currentNodes) {
        if (n.id == _parentRouteId) {
          parent = n;
          break;
        }
      }
      if (parent == null && currentNodes.isNotEmpty) {
        parent = currentNodes.last;
      }

      final newPos = parent != null
          ? Offset(parent.position.dx + 330, parent.position.dy + 30)
          : const Offset(380, 80);

      studio.addRouteNode(
        path: _pathController.text.trim(),
        title: cleanTitle,
        subtitle: widget.targetMaterial != null
            ? 'Widget Refinado: ${widget.targetMaterial!.displayName}'
            : _promptController.text.trim(),
        icon: widget.targetMaterial != null
            ? (widget.targetMaterial!.icon ?? Icons.widgets_rounded)
            : Icons.auto_awesome_rounded,
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
                child: Text(
                  widget.targetMaterial != null
                      ? 'Widget "${widget.targetMaterial!.displayName}" refinado com IA e injetado com sucesso! (${result.filePath})'
                      : 'Tela "$cleanTitle" gerada via IA e injetada no Fluxograma! (${result.filePath})',
                ),
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
    final auth = ref.watch(authProvider);
    final aiSettings = ref.watch(aiSettingsProvider);

    // Current Plan badge
    final String planBadge;
    final Color planColor;
    if (auth.isAuthenticated && auth.user != null) {
      planBadge = auth.user!.subscriptionTier.badgeLabel;
      planColor = auth.user!.isPro ? AppColors.secondary : AppColors.primary;
    } else if (aiSettings.isProActive) {
      planBadge = aiSettings.selectedPlan == 'starter'
          ? '⚡ FLRD Starter'
          : '⭐ FLRD Studio Pro';
      planColor = AppColors.secondary;
    } else {
      planBadge = '🌱 Community Free';
      planColor = AppColors.textMuted;
    }

    // Credits counter
    final String creditsText;
    if (_selectedMode == 1) {
      creditsText = 'Cota Ilimitada / BYOK Livre';
    } else {
      if (auth.user != null) {
        creditsText =
            '⚡ ${auth.creditsRemaining} / ${auth.creditsTotal} Créditos Disponíveis';
      } else if (aiSettings.isProActive) {
        creditsText = '⚡ 185 / 200 Créditos Disponíveis';
      } else {
        creditsText = '⚡ ${auth.creditsRemaining} / 10 Créditos Disponíveis';
      }
    }

    final effectiveParentId = nodes.any((n) => n.id == _parentRouteId)
        ? _parentRouteId
        : (nodes.isNotEmpty ? nodes.first.id : null);

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
            child: Icon(
              widget.targetMaterial != null
                  ? (widget.targetMaterial!.icon ?? Icons.widgets_rounded)
                  : Icons.auto_awesome_rounded,
              color: AppColors.secondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.targetMaterial != null
                      ? 'Refinar Widget com IA: ${widget.targetMaterial!.displayName}'
                      : 'Gerador de Telas com IA',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.targetMaterial != null
                      ? 'FLRD Widget Studio • Refinamento Focado de Componente'
                      : 'FLRD AI Screen Studio • Clean Architecture Output',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Subscription Plan & AI Credits Header Bar
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Plan Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: planColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: planColor.withOpacity(0.35)),
                          ),
                          child: Text(
                            planBadge,
                            style: TextStyle(
                              color: planColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // Manage Plan Link
                        InkWell(
                          key: const Key('manage_plan_button'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            SettingsAndBillingDialog.show(context, initialTabIndex: 1);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
                            ),
                            child: const Text(
                              '⚡ Gerenciar Plano / Inscrição',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Credits Counter
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            creditsText,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

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
                        widget.targetMaterial != null
                            ? 'Widget Focus: ${widget.targetMaterial!.displayName} (${widget.targetMaterial!.type.shortChipLabel}) • Riverpod & Tokens'
                            : 'Project Context: ${widget.project.preset.name.toUpperCase()} • Riverpod & Tokens',
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
                        Text(
                          widget.targetMaterial != null
                              ? 'Nome da Classe do Widget'
                              : 'Nome da Classe Widget',
                          style: const TextStyle(
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
                            hintText: widget.targetMaterial != null
                                ? 'MyCustomWidget'
                                : 'PaymentScreen',
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
                    value: effectiveParentId,
                    dropdownColor: AppColors.surface,
                    isExpanded: true,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                    items: nodes.isEmpty
                        ? [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Nenhuma rota existente'),
                            )
                          ]
                        : nodes.map((node) {
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
              Text(
                widget.targetMaterial != null
                    ? 'Prompt do Widget (Instruções detalhadas para a IA)'
                    : 'Prompt da Tela (Descreva o que a IA deve gerar)',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _promptController,
                maxLines: 4,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: widget.targetMaterial != null
                      ? 'Ex: Botão com estado reativo, borda arredondada e microinterações Obsidian'
                      : 'Ex: Tela de perfil com avatar, bio e estatísticas',
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
          key: const Key('generate_screen_button'),
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
            _isGenerating
                ? (widget.targetMaterial != null
                    ? 'Refinando Widget...'
                    : 'Gerando com IA...')
                : (widget.targetMaterial != null
                    ? '✨ Refinar e Injetar Widget'
                    : 'Gerar e Injetar Tela'),
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
