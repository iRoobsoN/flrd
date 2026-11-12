import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../projects/models/registered_project.dart';
import '../../domain/screen_material.dart';
import '../../domain/widget_variation.dart';
import '../../models/route_node.dart';
import '../../providers/android_debug_provider.dart';
import '../../providers/studio_provider.dart';
import '../../../ai/providers/ai_settings_provider.dart';
import '../../../ai/services/gemini_ai_service.dart';
import 'ai_screen_generator_dialog.dart';

/// Interactive AI visual builder panel displaying widgets currently in a screen,
/// prompt-based AI widget synthesis with variations gallery, inline provider/BYOK controls,
/// per-component notes & prompts, focused widget AI refinement, and full-screen AI elevation.
class ScreenMaterialsBuilder extends StatefulWidget {
  final RouteNode node;
  final RegisteredProject project;
  final String currentCode;
  final ValueChanged<String> onCodeChanged;
  final List<RouteNode>? existingRoutes;
  final WidgetRef? ref;

  const ScreenMaterialsBuilder({
    super.key,
    required this.node,
    required this.project,
    required this.currentCode,
    required this.onCodeChanged,
    this.existingRoutes,
    this.ref,
  });

  @override
  State<ScreenMaterialsBuilder> createState() => _ScreenMaterialsBuilderState();
}

class _ScreenMaterialsBuilderState extends State<ScreenMaterialsBuilder> {
  final Map<String, String> _localNotes = {};

  late final TextEditingController _widgetPromptController;
  late final TextEditingController _apiKeyController;
  bool _isGeneratingVariations = false;
  List<WidgetVariation> _variations = [];
  final Set<int> _expandedCodeIndices = {};
  bool _isByokSelected = false;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    _widgetPromptController = TextEditingController();
    _widgetPromptController.addListener(() {
      setState(() {});
    });
    _apiKeyController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_apiKeyController.text.isEmpty) {
      String? existingKey;
      if (widget.ref != null) {
        try {
          existingKey = widget.ref!.read(aiSettingsProvider).apiKey;
        } catch (_) {}
      }
      if (existingKey == null) {
        try {
          existingKey = ProviderScope.containerOf(context, listen: false)
              .read(aiSettingsProvider)
              .apiKey;
        } catch (_) {}
      }
      if (existingKey != null && existingKey.isNotEmpty) {
        _apiKeyController.text = existingKey;
        _isByokSelected = true;
      }
    }
  }

  @override
  void dispose() {
    _widgetPromptController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _onApiKeyChanged(String val) {
    final clean = val.trim();
    if (widget.ref != null) {
      try {
        widget.ref!.read(aiSettingsProvider.notifier).setApiKey(clean.isEmpty ? null : clean);
      } catch (_) {}
    }
    try {
      ProviderScope.containerOf(context, listen: false)
          .read(aiSettingsProvider.notifier)
          .setApiKey(clean.isEmpty ? null : clean);
    } catch (_) {}
    setState(() {});
  }

  bool get _hasApiKey => _apiKeyController.text.trim().isNotEmpty;

  String get _statusIndicatorText {
    if (_isByokSelected) {
      return _hasApiKey ? '🟢 Gemini 1.5 Flash Ativo' : '⚡ Motor Neural Local';
    } else {
      return '🟢 Gemini 1.5 Flash Ativo';
    }
  }

  Future<void> _generateVariations() async {
    final prompt = _widgetPromptController.text.trim();
    if (prompt.isEmpty) {
      AppToast.warning(
        context,
        'Por favor, digite uma ideia de widget.',
        duration: const Duration(seconds: 2),
      );
      return;
    }

    setState(() {
      _isGeneratingVariations = true;
      _expandedCodeIndices.clear();
    });

    String? apiKey;
    if (_isByokSelected) {
      apiKey = _apiKeyController.text.trim();
      if (apiKey.isEmpty) apiKey = null;
    } else {
      if (widget.ref != null) {
        try {
          apiKey = widget.ref!.read(aiSettingsProvider).apiKey;
        } catch (_) {}
      }
      if (apiKey == null) {
        try {
          apiKey = ProviderScope.containerOf(context, listen: false)
              .read(aiSettingsProvider)
              .apiKey;
        } catch (_) {}
      }
    }

    try {
      final results = await GeminiAiService.generateWidgetVariations(
        prompt: prompt,
        preset: widget.project.preset,
        routeNode: widget.node,
        apiKey: apiKey,
      );

      if (mounted) {
        setState(() {
          _variations = results;
          _isGeneratingVariations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGeneratingVariations = false;
        });
        AppToast.error(context, 'Erro ao gerar variações: $e');
      }
    }
  }

  void _insertVariation(WidgetVariation variation) {
    final updatedCode = ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode(
      _effectiveCode,
      variation.dartCode,
    );

    _saveAndNotify(updatedCode);

    if (mounted) {
      AppToast.success(
        context,
        'Widget "${variation.title}" inserido na tela com sucesso!',
        duration: const Duration(seconds: 3),
      );
    }
  }

  List<RouteNode>? get _effectiveExistingRoutes {
    if (widget.existingRoutes != null) return widget.existingRoutes;
    if (widget.ref != null) {
      try {
        return widget.ref!.read(studioProvider).nodes;
      } catch (_) {}
    }
    try {
      if (context.findAncestorWidgetOfExactType<ProviderScope>() != null) {
        return ProviderScope.containerOf(context, listen: false).read(studioProvider).nodes;
      }
    } catch (_) {}
    return null;
  }

  String get _effectiveCode {
    if (widget.currentCode.trim().isNotEmpty) {
      return widget.currentCode;
    }
    try {
      final filePath = p.isAbsolute(widget.node.filePath)
          ? p.normalize(widget.node.filePath)
          : p.normalize(p.join(widget.project.path, widget.node.filePath));
      final file = File(filePath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.trim().isNotEmpty) {
          return content;
        }
      }
    } catch (_) {}
    return '';
  }

  List<ScreenMaterialItem> get _materials {
    final list = ScreenMaterialParser.extractMaterialsFromCode(
      _effectiveCode,
      widget.node.title,
    );
    return list.asMap().entries.map((entry) {
      final idx = entry.key;
      final it = entry.value;
      final note = _getEffectiveNote(it, idx);
      return it.copyWith(note: note);
    }).toList();
  }

  String? _getEffectiveNote(ScreenMaterialItem item, int index) {
    if (_localNotes.containsKey(item.id)) {
      final note = _localNotes[item.id];
      return (note != null && note.isNotEmpty) ? note : null;
    }
    if (_localNotes.containsKey('$index')) {
      final note = _localNotes['$index'];
      return (note != null && note.isNotEmpty) ? note : null;
    }
    return item.note;
  }

  void _removeMaterial(int index) {
    _localNotes.remove('$index');
    final updatedCode = ScreenMaterialCodeUpdater.removeMaterialAtIndexInCode(
      currentCode: _effectiveCode,
      index: index,
      screenClassName: widget.node.title,
      routePath: widget.node.path,
      routeTitle: widget.node.title,
      isProtected: widget.node.isProtected,
    );
    _saveAndNotify(updatedCode);
  }

  void _reorderMaterial(int oldIndex, int newIndex) {
    final updatedCode = ScreenMaterialCodeUpdater.reorderMaterialsInCode(
      currentCode: _effectiveCode,
      oldIndex: oldIndex,
      newIndex: newIndex,
      screenClassName: widget.node.title,
      routePath: widget.node.path,
      routeTitle: widget.node.title,
      isProtected: widget.node.isProtected,
    );
    _saveAndNotify(updatedCode);
  }

  void _updateMaterialNote(ScreenMaterialItem item, int index, String? newNote) {
    final cleanNote = (newNote != null && newNote.trim().isNotEmpty) ? newNote.trim() : null;
    setState(() {
      if (cleanNote != null) {
        _localNotes[item.id] = cleanNote;
        _localNotes['$index'] = cleanNote;
      } else {
        _localNotes.remove(item.id);
        _localNotes.remove('$index');
      }
    });

    final updatedCode = ScreenMaterialCodeUpdater.updateMaterialNoteInCode(
      currentCode: _effectiveCode,
      materialId: item.id,
      note: cleanNote,
      screenClassName: widget.node.title,
      routePath: widget.node.path,
      routeTitle: widget.node.title,
      isProtected: widget.node.isProtected,
    );
    _saveAndNotify(updatedCode);
  }

  void _handleRefineWidgetWithAi(ScreenMaterialItem material, int index) {
    final note = _getEffectiveNote(material, index);
    final targetMat = material.copyWith(note: note);
    AiScreenGeneratorDialog.show(
      context,
      widget.project,
      initialRoutePath: widget.node.path,
      initialScreenTitle: widget.node.title,
      targetMaterial: targetMat,
    );
  }

  void _saveAndNotify(String newCode) {
    widget.onCodeChanged(newCode);

    try {
      final filePath = p.isAbsolute(widget.node.filePath)
          ? p.normalize(widget.node.filePath)
          : p.normalize(p.join(widget.project.path, widget.node.filePath));
      final file = File(filePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsStringSync(newCode, flush: true);
      _notifyAndroidHotReload();
    } catch (e) {
      debugPrint('ScreenMaterialsBuilder error saving to file: $e');
    }
  }

  void _notifyAndroidHotReload() {
    if (widget.ref != null) {
      try {
        widget.ref!.read(androidDebugProvider.notifier).onCodeSaved(widget.project.path);
        return;
      } catch (_) {}
    }
    if (!mounted) return;
    try {
      ProviderScope.containerOf(context, listen: false)
          .read(androidDebugProvider.notifier)
          .onCodeSaved(widget.project.path);
    } catch (_) {}
  }

  void _handleAiEnhance(List<ScreenMaterialItem> materials) {
    final annotatedMaterials = materials.asMap().entries.map((entry) {
      final idx = entry.key;
      final it = entry.value;
      final note = _getEffectiveNote(it, idx);
      return it.copyWith(note: note);
    }).toList();

    final prompt = ScreenMaterialCodeUpdater.generateAiEnhancePrompt(
      widget.node,
      annotatedMaterials,
      existingRoutes: _effectiveExistingRoutes,
      preset: widget.project.preset,
    );
    AiScreenGeneratorDialog.show(
      context,
      widget.project,
      initialPrompt: prompt,
      initialRoutePath: widget.node.path,
      initialScreenTitle: widget.node.title,
      initialMaterials: annotatedMaterials,
    );
  }

  Future<void> _showEditNoteDialog(ScreenMaterialItem item, int index) async {
    final currentNote = _getEffectiveNote(item, index) ?? '';
    final controller = TextEditingController(text: currentNote);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.borderSubtle),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: item.type.accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon ?? item.type.defaultIcon,
                  size: 16,
                  color: item.type.accentColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Anotação / Prompt do Widget',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.displayName,
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Descreva como este componente deve se comportar, estilos visuais, interações ou estados com IA:',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('material_note_text_field'),
                controller: controller,
                maxLines: 4,
                autofocus: true,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  hintText: 'Ex: Botão azul que troca de cor quando toco nele...',
                  hintStyle: TextStyle(
                    color: AppColors.textMuted.withOpacity(0.6),
                    fontSize: 11.5,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          actions: [
            if (currentNote.isNotEmpty)
              TextButton.icon(
                key: const ValueKey('material_note_dialog_clear'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _updateMaterialNote(item, index, null);
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.danger),
                label: const Text(
                  'Remover Nota',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            TextButton(
              key: const ValueKey('material_note_dialog_cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            ElevatedButton(
              key: const ValueKey('material_note_dialog_save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: () {
                final newText = controller.text.trim();
                Navigator.of(dialogContext).pop();
                _updateMaterialNote(item, index, newText.isEmpty ? null : newText);
              },
              child: const Text(
                'Salvar Nota',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final materials = _materials;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // =====================================================================
        // TOP: CRIADOR DE WIDGETS COM IA
        // =====================================================================
        _buildWidgetCreatorSection(),

        const SizedBox(height: 16),
        const Divider(color: AppColors.borderSubtle, height: 1),
        const SizedBox(height: 16),

        // =====================================================================
        // BOTTOM: WIDGETS NESTA TELA (N)
        // =====================================================================
        // Header: Title & Materials Count Badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.layers_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Widgets nesta Tela (${materials.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Text(
                '${materials.length}',
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Prominent Button: ✨ Refinar Tela Inteira com IA
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              key: const ValueKey('ai_enhance_materials_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => _handleAiEnhance(materials),
              icon: const Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: Colors.white,
              ),
              label: const Text(
                '✨ Refinar Tela Inteira com IA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // List of widgets in screen
        if (materials.isEmpty)
          _buildEmptyMaterialsView()
        else
          ListView.separated(
            key: const ValueKey('screen_materials_list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: materials.length,
            separatorBuilder: (context, index) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = materials[index];
              return _buildMaterialItemCard(
                item: item,
                index: index,
                totalCount: materials.length,
              );
            },
          ),
      ],
    );
  }

  Widget _buildEmptyMaterialsView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: const [
          Icon(
            Icons.dashboard_customize_outlined,
            size: 28,
            color: AppColors.textMuted,
          ),
          SizedBox(height: 8),
          Text(
            'Nenhum widget nesta tela ainda',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Descreva sua ideia no Criador com IA acima para gerar e inserir widgets!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetCreatorSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Title "Criador de Widgets com IA" + active count badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Criador de Widgets com IA',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _variations.isNotEmpty
                      ? AppColors.secondary.withOpacity(0.15)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _variations.isNotEmpty
                        ? AppColors.secondary.withOpacity(0.4)
                        : AppColors.borderSubtle,
                  ),
                ),
                child: Text(
                  _variations.isNotEmpty
                      ? '${_variations.length} variações ativas'
                      : '3 Variações',
                  style: TextStyle(
                    color: _variations.isNotEmpty
                        ? AppColors.secondary
                        : AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Idea prompt input field with clear button
          TextField(
            key: const ValueKey('widget_creator_prompt_input'),
            controller: _widgetPromptController,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText:
                  'Descreva sua ideia de widget (ex: Uma bola que fica pingando, Foto de perfil com moldura oval, Card de faturamento mensal e lucro)...',
              hintStyle: TextStyle(
                color: AppColors.textMuted.withOpacity(0.65),
                fontSize: 11.5,
              ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: _widgetPromptController.text.isNotEmpty
                  ? IconButton(
                      key: const ValueKey('widget_creator_prompt_clear'),
                      icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                      onPressed: () {
                        setState(() {
                          _widgetPromptController.clear();
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Quick inspiration chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildInspirationChip(
                  label: '👤 Foto de Perfil & Boas-Vindas',
                  prompt:
                      'foto de perfil do usuário logado com moldura oval e boas-vindas',
                ),
                const SizedBox(width: 6),
                _buildInspirationChip(
                  label: '📊 Faturamento & Lucro',
                  prompt: 'Card de faturamento mensal e lucro',
                ),
                const SizedBox(width: 6),
                _buildInspirationChip(
                  label: '⚽ Bola Pingando (Física/Animação)',
                  prompt: 'Uma bola que fica pingando com física e animação',
                ),
                const SizedBox(width: 6),
                _buildInspirationChip(
                  label: '💳 Seletor Pix/Cartão',
                  prompt: 'Seletor de pagamento rápido com chave Pix e cartão',
                ),
                const SizedBox(width: 6),
                _buildInspirationChip(
                  label: '🔍 Busca com Filtro',
                  prompt: 'Barra de busca moderna com filtro e chips rápidos',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // AI Provider & Key control: Segmented switcher & status indicator
          _buildAiProviderControl(),
          const SizedBox(height: 10),

          // Button [✨ Gerar 3 Variações de Widgets com IA]
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const ValueKey('generate_widget_variations_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _isGeneratingVariations ? null : _generateVariations,
              child: _isGeneratingVariations
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Gerando variações...',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  : const Text(
                      '✨ Gerar 3 Variações de Widgets com IA',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
            ),
          ),

          // Variations Gallery
          if (_variations.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_motion_rounded,
                  size: 13,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Variações Geradas (${_variations.length}):',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _variations.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final variation = _variations[index];
                return _buildVariationCard(variation, index);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiProviderControl() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const ValueKey('widget_creator_provider_cloud'),
                  onTap: () => setState(() => _isByokSelected = false),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                    decoration: BoxDecoration(
                      color: !_isByokSelected
                          ? AppColors.primary.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !_isByokSelected
                            ? AppColors.primary
                            : AppColors.borderSubtle,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '⚡ FLRD Pro Cloud',
                        style: TextStyle(
                          color: !_isByokSelected
                              ? Colors.white
                              : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: !_isByokSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  key: const ValueKey('widget_creator_provider_byok'),
                  onTap: () => setState(() => _isByokSelected = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _isByokSelected
                          ? AppColors.primary.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isByokSelected
                            ? AppColors.primary
                            : AppColors.borderSubtle,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '🔑 BYOK (Chave Gemini)',
                        style: TextStyle(
                          color: _isByokSelected
                              ? Colors.white
                              : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: _isByokSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isByokSelected) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('widget_creator_api_key_input'),
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              onChanged: _onApiKeyChanged,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11.5,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                labelText: 'Chave Gemini API',
                labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                hintText: 'AIzaSy...',
                hintStyle: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.6),
                  fontSize: 11,
                ),
                filled: true,
                fillColor: AppColors.surfaceCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureApiKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                key: const ValueKey('widget_creator_status_indicator'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (_statusIndicatorText.contains('🟢'))
                      ? const Color(0xFF10B981).withOpacity(0.12)
                      : const Color(0xFFF59E0B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (_statusIndicatorText.contains('🟢'))
                        ? const Color(0xFF10B981).withOpacity(0.3)
                        : const Color(0xFFF59E0B).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  _statusIndicatorText,
                  style: TextStyle(
                    color: (_statusIndicatorText.contains('🟢'))
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInspirationChip({
    required String label,
    required String prompt,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _widgetPromptController.text = prompt;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildVariationCard(WidgetVariation variation, int index) {
    final isCodeExpanded = _expandedCodeIndices.contains(index);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Style tag pill & tech approach badge
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                ),
                child: Text(
                  variation.styleTag,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.code_rounded,
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        variation.techApproach,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Title
          Text(
            variation.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),

          // Description
          Text(
            variation.description,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),

          // Code viewer toggle & Choose button
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  setState(() {
                    if (isCodeExpanded) {
                      _expandedCodeIndices.remove(index);
                    } else {
                      _expandedCodeIndices.add(index);
                    }
                  });
                },
                child: Text(
                  isCodeExpanded ? '👁️ Ocultar Código' : '👁️ Ver Código',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              ElevatedButton(
                key: ValueKey('choose_variation_button_$index'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: () => _insertVariation(variation),
                child: const Text(
                  '✅ Escolher este Widget / Inserir na Tela',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          // Code Viewer
          if (isCodeExpanded) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF090D16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  variation.dartCode,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFFE2E8F0),
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaterialItemCard({
    required ScreenMaterialItem item,
    required int index,
    required int totalCount,
  }) {
    final accentColor = item.type.accentColor;
    final iconData = item.icon ?? item.type.defaultIcon;
    final effectiveNote = _getEffectiveNote(item, index);
    final hasNote = effectiveNote != null && effectiveNote.trim().isNotEmpty;

    return Container(
      key: ValueKey('material_item_$index'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasNote
              ? AppColors.primary.withOpacity(0.4)
              : AppColors.borderSubtle,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Color-coded icon pill
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  iconData,
                  size: 15,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 10),

              // Title & Description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.hint ?? item.type.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Note button [💬 Nota] (when note does NOT exist)
              if (!hasNote) ...[
                InkWell(
                  key: ValueKey('material_note_button_$index'),
                  onTap: () => _showEditNoteDialog(item, index),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 11,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 3),
                        Text(
                          '💬 Nota',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],

              // Up Arrow Button
              IconButton(
                key: ValueKey('material_up_$index'),
                tooltip: 'Mover para cima',
                icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                color: index > 0
                    ? AppColors.textSecondary
                    : AppColors.textMuted.withOpacity(0.3),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: index > 0 ? () => _reorderMaterial(index, index - 1) : null,
              ),

              // Down Arrow Button
              IconButton(
                key: ValueKey('material_down_$index'),
                tooltip: 'Mover para baixo',
                icon: const Icon(Icons.arrow_downward_rounded, size: 14),
                color: index < totalCount - 1
                    ? AppColors.textSecondary
                    : AppColors.textMuted.withOpacity(0.3),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: index < totalCount - 1
                    ? () => _reorderMaterial(index, index + 1)
                    : null,
              ),

              const SizedBox(width: 4),

              // Delete Button (Trash icon)
              IconButton(
                key: ValueKey('material_delete_$index'),
                tooltip: 'Remover da tela',
                icon: const Icon(Icons.delete_outline_rounded, size: 14),
                color: AppColors.danger.withOpacity(0.85),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => _removeMaterial(index),
              ),
            ],
          ),

          // Elegant Italic Card/Chip when note exists
          if (hasNote) ...[
            const SizedBox(height: 6),
            Container(
              key: ValueKey('material_note_card_$index'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B4B).withOpacity(0.4),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '💬 ',
                        style: TextStyle(fontSize: 10),
                      ),
                      Expanded(
                        child: Text(
                          '"$effectiveNote"',
                          style: const TextStyle(
                            color: Color(0xFFE0E7FF),
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Edit note button
                      InkWell(
                        key: ValueKey('material_note_edit_$index'),
                        onTap: () => _showEditNoteDialog(item, index),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 13,
                            color: AppColors.primary.withOpacity(0.9),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      // Clear note button
                      InkWell(
                        key: ValueKey('material_note_clear_$index'),
                        onTap: () => _updateMaterialNote(item, index, null),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: AppColors.textMuted.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // [✨ Refinar este Widget com IA] Button
                  SizedBox(
                    width: double.infinity,
                    child: InkWell(
                      key: ValueKey('material_ai_refine_$index'),
                      onTap: () => _handleRefineWidgetWithAi(item, index),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 11,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '✨ Refinar este Widget com IA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
