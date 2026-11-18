import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../projects/models/registered_project.dart';
import '../../domain/screen_material.dart';
import '../../domain/widget_variation.dart';
import '../../models/route_node.dart';
import '../../providers/android_debug_provider.dart';
import '../../providers/studio_provider.dart';
import '../../services/dart_widget_injector_service.dart';
import '../../../ai/models/ai_execution_plan.dart';
import '../../../ai/providers/ai_settings_provider.dart';
import '../../../ai/services/gemini_ai_service.dart';
import '../../../ai/services/project_context_snapshot_service.dart';
import 'ai_screen_generator_dialog.dart';

/// Interactive AI visual builder panel displaying widgets currently in a screen,
/// Plan-First Gemini 2.5 widget creation with explicit Plan -> Preview -> Execute workflow,
/// honest BYOK controls, per-component notes & prompts, focused widget AI refinement,
/// and full-screen AI elevation.
class ScreenMaterialsBuilder extends StatefulWidget {
  final RouteNode node;
  final RegisteredProject project;
  final String currentCode;
  final ValueChanged<String> onCodeChanged;
  final List<RouteNode>? existingRoutes;
  final WidgetRef? ref;
  final http.Client? aiHttpClient;
  final ValueChanged<DartWidgetInjectionResult>? onWidgetInjected;

  const ScreenMaterialsBuilder({
    super.key,
    required this.node,
    required this.project,
    required this.currentCode,
    required this.onCodeChanged,
    this.existingRoutes,
    this.ref,
    this.aiHttpClient,
    this.onWidgetInjected,
  });

  @override
  State<ScreenMaterialsBuilder> createState() => _ScreenMaterialsBuilderState();
}

class _ScreenMaterialsBuilderState extends State<ScreenMaterialsBuilder> {
  final Map<String, String> _localNotes = {};

  late final TextEditingController _widgetPromptController;
  late final TextEditingController _placementController;
  late final TextEditingController _apiKeyController;
  late final FocusNode _promptFocusNode;
  late final FocusNode _apiKeyFocusNode;

  ProviderContainer? _observedContainer;
  ProviderSubscription<AiSettingsState>? _aiSettingsSubscription;
  AiSettingsState _fallbackAiSettings = const AiSettingsState();

  bool _isPlanning = false;
  bool _isGeneratingFromPlan = false;
  bool _isInjecting = false;
  bool _isEditingApiKey = false;
  bool _obscureApiKey = true;

  AiExecutionPlan? _activePlan;
  String? _planModelUsed;
  bool _planApproved = false;
  ProjectContextSnapshot? _capturedContext;
  List<WidgetVariation> _variations = [];
  final Set<int> _expandedCodeIndices = {};
  String? _aiErrorBannerMessage;
  bool _aiErrorIsKeyWarning = false;
  DartWidgetInjectionResult? _lastInjectionResult;

  @override
  void initState() {
    super.initState();
    _widgetPromptController = TextEditingController()
      ..addListener(() => setState(() {}));
    _placementController = TextEditingController()
      ..addListener(() => setState(() {}));
    _apiKeyController = TextEditingController();
    _promptFocusNode = FocusNode();
    _apiKeyFocusNode = FocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindAiSettingsSubscription();
  }

  @override
  void didUpdateWidget(covariant ScreenMaterialsBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id ||
        oldWidget.project.path != widget.project.path) {
      _localNotes.clear();
      _activePlan = null;
      _planModelUsed = null;
      _planApproved = false;
      _capturedContext = null;
      _variations = [];
      _expandedCodeIndices.clear();
      _aiErrorBannerMessage = null;
      _aiErrorIsKeyWarning = false;
      _lastInjectionResult = null;
    }
  }

  @override
  void dispose() {
    _aiSettingsSubscription?.close();
    _widgetPromptController.dispose();
    _placementController.dispose();
    _apiKeyController.dispose();
    _promptFocusNode.dispose();
    _apiKeyFocusNode.dispose();
    super.dispose();
  }

  void _bindAiSettingsSubscription() {
    ProviderContainer? container;
    try {
      container = ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      container = null;
    }

    if (identical(container, _observedContainer)) {
      return;
    }

    _aiSettingsSubscription?.close();
    _aiSettingsSubscription = null;
    _observedContainer = container;

    if (container != null) {
      final current = container.read(aiSettingsProvider);
      _syncControllerWithSettings(current);
      _aiSettingsSubscription = container.listen<AiSettingsState>(
        aiSettingsProvider,
        (previous, next) {
          if (!mounted) return;
          _syncControllerWithSettings(next);
          setState(() {});
        },
      );
    }
  }

  void _syncControllerWithSettings(AiSettingsState settings) {
    if (_isEditingApiKey) return;
    final key = settings.apiKey ?? '';
    if (_apiKeyController.text != key) {
      _apiKeyController.text = key;
    }
  }

  AiSettingsState get _aiSettings {
    if (widget.ref != null) {
      try {
        return widget.ref!.read(aiSettingsProvider);
      } catch (_) {}
    }
    try {
      return ProviderScope.containerOf(context, listen: false)
          .read(aiSettingsProvider);
    } catch (_) {}
    return _fallbackAiSettings;
  }

  void _persistApiKey(String? rawKey) {
    final clean = rawKey?.trim();
    final normalized = (clean != null && clean.isNotEmpty) ? clean : null;
    var updatedViaProvider = false;
    if (widget.ref != null) {
      try {
        widget.ref!.read(aiSettingsProvider.notifier).setApiKey(normalized);
        updatedViaProvider = true;
      } catch (_) {}
    }
    if (!updatedViaProvider) {
      try {
        ProviderScope.containerOf(context, listen: false)
            .read(aiSettingsProvider.notifier)
            .setApiKey(normalized);
        updatedViaProvider = true;
      } catch (_) {}
    }
    if (!updatedViaProvider) {
      _fallbackAiSettings = _fallbackAiSettings.copyWith(apiKey: normalized);
    }
  }

  void _selectModel(String model) {
    final normalized = AiSettingsState.normalizeModel(model);
    var updatedViaProvider = false;
    if (widget.ref != null) {
      try {
        widget.ref!.read(aiSettingsProvider.notifier).setSelectedModel(normalized);
        updatedViaProvider = true;
      } catch (_) {}
    }
    if (!updatedViaProvider) {
      try {
        ProviderScope.containerOf(context, listen: false)
            .read(aiSettingsProvider.notifier)
            .setSelectedModel(normalized);
        updatedViaProvider = true;
      } catch (_) {}
    }
    if (!updatedViaProvider) {
      _fallbackAiSettings =
          _fallbackAiSettings.copyWith(selectedModel: normalized);
    }
    setState(() {});
  }

  void _saveInlineApiKey() {
    final trimmed = _apiKeyController.text.trim();
    if (trimmed.isEmpty) {
      _persistApiKey(null);
      setState(() {
        _isEditingApiKey = true;
        _aiErrorBannerMessage =
            'Informe uma chave Gemini API válida para ativar o modo BYOK.';
        _aiErrorIsKeyWarning = true;
      });
      _apiKeyFocusNode.requestFocus();
      AppToast.warning(context, 'Digite uma chave Gemini API válida.');
      return;
    }

    _persistApiKey(trimmed);
    setState(() {
      _isEditingApiKey = false;
      if (_aiErrorIsKeyWarning) {
        _aiErrorBannerMessage = null;
        _aiErrorIsKeyWarning = false;
      }
    });
    AppToast.success(context, 'Chave Gemini (BYOK) salva com sucesso.');
  }

  void _clearInlineApiKey() {
    _apiKeyController.clear();
    _persistApiKey(null);
    setState(() {
      _isEditingApiKey = true;
      _aiErrorBannerMessage = null;
      _aiErrorIsKeyWarning = false;
    });
    _apiKeyFocusNode.requestFocus();
  }

  String _modelDisplayLabel(String modelId) {
    return AiSettingsState.normalizeModel(modelId) ==
            AiSettingsState.geminiProModel
        ? 'Gemini 2.5 Pro'
        : 'Gemini 2.5 Flash';
  }

  String _statusIndicatorText(AiSettingsState settings) {
    if (!settings.hasApiKey) {
      return '🔑 Chave Gemini (BYOK) necessária';
    }
    return '⚡ BYOK Ativo · ${_modelDisplayLabel(settings.selectedModel)}';
  }

  String get _resolvedScreenFilePath {
    final raw = widget.node.filePath.trim();
    if (raw.isEmpty) return '';
    if (p.isAbsolute(raw)) {
      return p.normalize(p.absolute(raw));
    }
    return p.normalize(p.absolute(p.join(widget.project.path, raw)));
  }

  Future<void> _planWidget() async {
    final prompt = _widgetPromptController.text.trim();
    if (prompt.isEmpty) {
      AppToast.warning(
        context,
        'Por favor, digite uma ideia de widget.',
        duration: const Duration(seconds: 2),
      );
      _promptFocusNode.requestFocus();
      return;
    }

    final settings = _aiSettings;
    if (!settings.hasApiKey) {
      setState(() {
        _isEditingApiKey = true;
        _activePlan = null;
        _planModelUsed = null;
        _planApproved = false;
        _variations = [];
        _expandedCodeIndices.clear();
        _aiErrorBannerMessage =
            'Chave Gemini (BYOK) necessária. Configure e salve sua chave API acima antes de planejar widgets com IA.';
        _aiErrorIsKeyWarning = true;
      });
      _apiKeyFocusNode.requestFocus();
      AppToast.warning(
        context,
        'Configure sua chave Gemini (BYOK) antes de continuar.',
      );
      return;
    }

    setState(() {
      _isPlanning = true;
      _activePlan = null;
      _planModelUsed = null;
      _planApproved = false;
      _variations = [];
      _expandedCodeIndices.clear();
      _aiErrorBannerMessage = null;
      _aiErrorIsKeyWarning = false;
      _lastInjectionResult = null;
    });

    final placementHint = _placementController.text.trim();
    final targetScreenPath = widget.node.filePath.trim().isNotEmpty
        ? widget.node.filePath.trim()
        : null;

    var snapshot = await ProjectContextSnapshotService.capture(
      projectPath: widget.project.path,
      targetScreenPath: targetScreenPath,
    );
    final liveCode = _effectiveCode;
    if (liveCode.trim().isNotEmpty) {
      snapshot = snapshot.copyWith(
        targetScreenPath: snapshot.targetScreenPath ?? targetScreenPath,
        targetScreenSource: liveCode,
      );
    }

    final outcome = await GeminiAiService.planWidgetCreation(
      prompt: prompt,
      userPlacementHint: placementHint.isEmpty ? null : placementHint,
      preset: widget.project.preset,
      routeNode: widget.node,
      projectContext: snapshot,
      apiKey: settings.apiKey,
      preferredModel: settings.selectedModel,
      client: widget.aiHttpClient,
    );

    if (!mounted) return;

    if (outcome.source != AiResultSource.liveAi || outcome.data == null) {
      final isKeyMissing = outcome.source == AiResultSource.unconfiguredKey;
      final message = outcome.errorMessage ??
          'Não foi possível gerar o plano de execução com Gemini.';
      setState(() {
        _isPlanning = false;
        _isEditingApiKey = isKeyMissing ? true : _isEditingApiKey;
        _activePlan = null;
        _variations = [];
        _aiErrorBannerMessage = message;
        _aiErrorIsKeyWarning = isKeyMissing;
      });
      if (isKeyMissing) {
        _apiKeyFocusNode.requestFocus();
        AppToast.warning(context, message);
      } else {
        AppToast.error(context, message);
      }
      return;
    }

    setState(() {
      _isPlanning = false;
      _capturedContext = snapshot;
      _activePlan = outcome.data;
      _planModelUsed = outcome.modelUsed ?? settings.selectedModel;
      _planApproved = false;
      _aiErrorBannerMessage = null;
      _aiErrorIsKeyWarning = false;
    });
  }

  Future<void> _generateFromPlan() async {
    final plan = _activePlan;
    if (plan == null) return;

    final settings = _aiSettings;
    if (!settings.hasApiKey) {
      setState(() {
        _isEditingApiKey = true;
        _aiErrorBannerMessage =
            'Chave Gemini (BYOK) necessária para gerar o código pelo plano.';
        _aiErrorIsKeyWarning = true;
      });
      _apiKeyFocusNode.requestFocus();
      AppToast.warning(context, 'Configure sua chave Gemini (BYOK) primeiro.');
      return;
    }

    setState(() {
      _isGeneratingFromPlan = true;
      _aiErrorBannerMessage = null;
      _aiErrorIsKeyWarning = false;
      _expandedCodeIndices.clear();
    });

    final placementHint = _placementController.text.trim();
    final outcome = await GeminiAiService.generateWidgetFromPlan(
      plan: plan,
      originalPrompt: _widgetPromptController.text.trim(),
      userPlacementHint: placementHint.isEmpty ? null : placementHint,
      preset: widget.project.preset,
      routeNode: widget.node,
      projectContext: _capturedContext,
      apiKey: settings.apiKey,
      preferredModel: settings.selectedModel,
      client: widget.aiHttpClient,
    );

    if (!mounted) return;

    if (outcome.source != AiResultSource.liveAi || outcome.data == null) {
      final isKeyMissing = outcome.source == AiResultSource.unconfiguredKey;
      final message = outcome.errorMessage ??
          'Falha ao gerar o código do widget a partir do plano.';
      setState(() {
        _isGeneratingFromPlan = false;
        _isEditingApiKey = isKeyMissing ? true : _isEditingApiKey;
        _aiErrorBannerMessage = message;
        _aiErrorIsKeyWarning = isKeyMissing;
      });
      AppToast.error(context, message);
      return;
    }

    setState(() {
      _isGeneratingFromPlan = false;
      _planApproved = true;
      _planModelUsed = outcome.modelUsed ?? _planModelUsed;
      _variations = [outcome.data!];
      _aiErrorBannerMessage = null;
      _aiErrorIsKeyWarning = false;
    });
  }

  void _replanWidget() {
    setState(() {
      _activePlan = null;
      _planModelUsed = null;
      _planApproved = false;
      _variations = [];
      _expandedCodeIndices.clear();
      _aiErrorBannerMessage = null;
      _aiErrorIsKeyWarning = false;
      _lastInjectionResult = null;
    });
    _promptFocusNode.requestFocus();
  }

  Future<void> _insertVariation(WidgetVariation variation) async {
    if (_isInjecting) return;

    setState(() {
      _isInjecting = true;
      _aiErrorBannerMessage = null;
      _aiErrorIsKeyWarning = false;
    });

    final resolvedScreenPath = _resolvedScreenFilePath;
    final result = await DartWidgetInjectorService.injectWidget(
      projectPath: widget.project.path,
      screenFilePath: resolvedScreenPath,
      variation: variation,
      plan: _activePlan ?? variation.plan,
      currentScreenCode: _effectiveCode,
    );

    if (!mounted) return;

    if (!result.success || result.updatedScreenCode == null) {
      final errorMsg = result.errorMessage ??
          'Não foi possível inserir "${variation.title}" na tela.';
      setState(() {
        _isInjecting = false;
        _aiErrorBannerMessage = errorMsg;
        _aiErrorIsKeyWarning = false;
      });
      AppToast.error(context, errorMsg);
      return;
    }

    _saveAndNotify(result.updatedScreenCode!);
    widget.onWidgetInjected?.call(result);

    setState(() {
      _isInjecting = false;
      _lastInjectionResult = result;
      _aiErrorBannerMessage = null;
      _aiErrorIsKeyWarning = false;
    });

    final modifiedInfo = result.modifiedFiles.isNotEmpty
        ? result.modifiedFiles.join(', ')
        : widget.node.filePath;
    final createdInfo = result.createdFiles.isNotEmpty
        ? ' · Criado: ${result.createdFiles.join(', ')}'
        : '';
    final anchorInfo = (result.resolvedAnchorDescription != null &&
            result.resolvedAnchorDescription!.isNotEmpty)
        ? ' (${result.resolvedAnchorDescription})'
        : '';

    AppToast.success(
      context,
      'Widget "${variation.title}" inserido em $modifiedInfo$createdInfo$anchorInfo.',
      duration: const Duration(seconds: 4),
    );
  }

  List<RouteNode>? get _effectiveExistingRoutes {
    if (widget.existingRoutes != null) return widget.existingRoutes;
    if (widget.ref != null) {
      try {
        return widget.ref!.read(studioProvider).nodes;
      } catch (_) {}
    }
    try {
      return ProviderScope.containerOf(context, listen: false)
          .read(studioProvider)
          .nodes;
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
      final filePath = _resolvedScreenFilePath;
      if (filePath.isNotEmpty) {
        final file = File(filePath);
        if (!file.parent.existsSync()) {
          file.parent.createSync(recursive: true);
        }
        file.writeAsStringSync(newCode, flush: true);
      }
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
    final settings = _aiSettings;
    final headerBadgeText = _variations.isNotEmpty
        ? '${_variations.length} pronta${_variations.length > 1 ? 's' : ''}'
        : _activePlan != null
            ? 'Plano Pronto'
            : 'Gemini 2.5 · Plan-First';

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
          // Header: Icon + Title "Criador de Widgets com IA" + Plan-First badge
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (_variations.isNotEmpty || _activePlan != null)
                      ? AppColors.secondary.withOpacity(0.15)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (_variations.isNotEmpty || _activePlan != null)
                        ? AppColors.secondary.withOpacity(0.4)
                        : AppColors.borderSubtle,
                  ),
                ),
                child: Text(
                  headerBadgeText,
                  style: TextStyle(
                    color: (_variations.isNotEmpty || _activePlan != null)
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
            focusNode: _promptFocusNode,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText:
                  'Descreva sua ideia de widget (ex: Relógio digital interativo, Foto de perfil com moldura oval, Card de faturamento mensal)...',
              hintStyle: TextStyle(
                color: AppColors.textMuted.withOpacity(0.65),
                fontSize: 11.5,
              ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: _widgetPromptController.text.isNotEmpty
                  ? IconButton(
                      key: const ValueKey('widget_creator_prompt_clear'),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
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

          // Natural-language widget placement prompt input
          TextField(
            key: const ValueKey('widget_placement_prompt_input'),
            controller: _placementController,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              labelText: 'Onde deseja posicionar na tela? (com suas palavras)',
              labelStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
              hintText:
                  'Ex: logo abaixo do card Welcome, no topo da tela, ou em arquivo separado',
              hintStyle: TextStyle(
                color: AppColors.textMuted.withOpacity(0.65),
                fontSize: 11,
              ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: _placementController.text.isNotEmpty
                  ? IconButton(
                      key: const ValueKey('widget_placement_prompt_clear'),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () {
                        setState(() {
                          _placementController.clear();
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
          const SizedBox(height: 10),

          // Honest BYOK Gemini 2.5 control: status indicator, model badges & inline API key
          _buildAiProviderControl(settings),
          const SizedBox(height: 10),

          // Step 1 Button: Planejar Widget (Gemini 2.5)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const ValueKey('generate_widget_variations_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _isPlanning ? null : _planWidget,
              icon: _isPlanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.architecture_rounded, size: 16),
              label: Text(
                _isPlanning
                    ? 'Planejando com Gemini 2.5...'
                    : 'Planejar Widget (Gemini 2.5)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Honest Error / Key Warning Banner (never replaced by dummy boxes)
          if (_aiErrorBannerMessage != null &&
              _aiErrorBannerMessage!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildAiErrorBanner(),
          ],

          // Step 1/2: Execution Plan Card (stays visible with "✅ Plano Aprovado" once generated)
          if (_activePlan != null) ...[
            const SizedBox(height: 12),
            _buildExecutionPlanCard(_activePlan!),
          ],

          // Step 2 & Step 3: Preview & Execute cards
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
                Expanded(
                  child: Text(
                    _variations.length == 1
                        ? 'Prévia Gerada pelo Plano:'
                        : 'Variações Geradas (${_variations.length}):',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
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

          if (_lastInjectionResult != null && _lastInjectionResult!.success) ...[
            const SizedBox(height: 10),
            _buildInjectionResultBanner(_lastInjectionResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildAiProviderControl(AiSettingsState settings) {
    final hasKey = settings.hasApiKey;
    final showInlineInput = !hasKey || _isEditingApiKey;
    final selectedModel = AiSettingsState.normalizeModel(settings.selectedModel);
    final statusColor =
        hasKey ? const Color(0xFF10B981) : const Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasKey
              ? AppColors.borderSubtle
              : const Color(0xFFF59E0B).withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Container(
                key: const ValueKey('widget_creator_status_indicator'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withOpacity(0.35)),
                ),
                child: Text(
                  _statusIndicatorText(settings),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildModelBadge(
                    key: const ValueKey('widget_creator_model_flash'),
                    label: 'Gemini 2.5 Flash',
                    isSelected:
                        selectedModel == AiSettingsState.geminiFlashModel,
                    onTap: () =>
                        _selectModel(AiSettingsState.geminiFlashModel),
                  ),
                  _buildModelBadge(
                    key: const ValueKey('widget_creator_model_pro'),
                    label: 'Gemini 2.5 Pro',
                    isSelected:
                        selectedModel == AiSettingsState.geminiProModel,
                    onTap: () => _selectModel(AiSettingsState.geminiProModel),
                  ),
                ],
              ),
            ],
          ),
          if (hasKey && !showInlineInput) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Chave salva: ${_maskApiKey(settings.apiKey!)}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('widget_creator_api_key_edit_button'),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    setState(() {
                      _apiKeyController.text = settings.apiKey ?? '';
                      _isEditingApiKey = true;
                    });
                    _apiKeyFocusNode.requestFocus();
                  },
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 13,
                    color: AppColors.secondary,
                  ),
                  label: const Text(
                    'Alterar Chave',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('widget_creator_api_key_clear_button'),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _clearInlineApiKey,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 13,
                    color: AppColors.danger,
                  ),
                  label: const Text(
                    'Remover',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (showInlineInput) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('widget_creator_api_key_input'),
              controller: _apiKeyController,
              focusNode: _apiKeyFocusNode,
              obscureText: _obscureApiKey,
              onSubmitted: (_) => _saveInlineApiKey(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11.5,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                labelText: 'Chave Gemini API (BYOK)',
                labelStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
                hintText: 'AIzaSy...',
                hintStyle: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.6),
                  fontSize: 11,
                ),
                filled: true,
                fillColor: AppColors.surfaceCard,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    _obscureApiKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () =>
                      setState(() => _obscureApiKey = !_obscureApiKey),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ElevatedButton.icon(
                  key: const ValueKey('widget_creator_api_key_save_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: AppColors.background,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: _saveInlineApiKey,
                  icon: const Icon(Icons.save_rounded, size: 13),
                  label: const Text(
                    'Salvar Chave',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                if (hasKey) ...[
                  TextButton(
                    key: const ValueKey('widget_creator_api_key_cancel_button'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() {
                        _apiKeyController.text = settings.apiKey ?? '';
                        _isEditingApiKey = false;
                      });
                    },
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('widget_creator_api_key_clear_button'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _clearInlineApiKey,
                    child: const Text(
                      'Remover',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModelBadge({
    required Key key,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.22)
              : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textMuted,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _maskApiKey(String key) {
    final clean = key.trim();
    if (clean.length <= 8) return '••••••••';
    return '${clean.substring(0, 4)}••••${clean.substring(clean.length - 4)}';
  }

  Widget _buildAiErrorBanner() {
    final color = _aiErrorIsKeyWarning ? AppColors.warning : AppColors.danger;
    return Container(
      key: const ValueKey('widget_ai_error_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _aiErrorIsKeyWarning
                ? Icons.vpn_key_outlined
                : Icons.error_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _aiErrorBannerMessage ?? '',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
          InkWell(
            key: const ValueKey('widget_ai_error_dismiss'),
            onTap: () => setState(() {
              _aiErrorBannerMessage = null;
              _aiErrorIsKeyWarning = false;
            }),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionPlanCard(AiExecutionPlan plan) {
    final isApproved = _planApproved && _variations.isNotEmpty;
    final archLabel = switch (plan.architectureType) {
      'statefulWidgetClass' => 'StatefulWidget',
      'statelessSnippet' => 'StatelessSnippet',
      'fullScreen' => 'FullScreen',
      'codePatch' => 'CodePatch',
      _ => plan.architectureType,
    };
    final placementDescription = plan.visualAnchorDescription.trim().isNotEmpty
        ? plan.visualAnchorDescription.trim()
        : plan.insertionAnchorHint;
    final targetStrategyText =
        plan.placementStrategy == AiPlanPlacementStrategy.inlineInScreen
            ? 'Inline na tela (${plan.targetFilePath ?? widget.node.filePath})'
            : (plan.extractedWidgetFilePath != null &&
                    plan.extractedWidgetFilePath!.trim().isNotEmpty)
                ? plan.extractedWidgetFilePath!
                : 'Arquivo separado (${_previewWidgetFileName(plan)})';

    return Container(
      key: const ValueKey('widget_execution_plan_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isApproved
              ? AppColors.success.withOpacity(0.55)
              : AppColors.primary.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (isApproved ? AppColors.success : AppColors.primary)
                      .withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (isApproved ? AppColors.success : AppColors.primary)
                        .withOpacity(0.45),
                  ),
                ),
                child: Text(
                  isApproved ? '✅ Plano Aprovado' : '📋 Plano de Execução',
                  style: TextStyle(
                    color: isApproved ? AppColors.success : AppColors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Text(
                  archLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_planModelUsed != null && _planModelUsed!.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Text(
                    _planModelUsed!,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            plan.sanitizedWidgetName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          if (plan.goalSummary.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              plan.goalSummary,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Onde será inserido:',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  placementDescription,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Destino: $targetStrategyText · Âncora: ${plan.insertionAnchorHint}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (plan.stateFields.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildPlanChipsGroup(
              title: 'Estado:',
              items: plan.stateFields,
              monospace: true,
            ),
          ],
          if (plan.interactions.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildPlanChipsGroup(
              title: 'Interações:',
              items: plan.interactions,
            ),
          ],
          if (plan.requiredImports.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildPlanChipsGroup(
              title: 'Imports:',
              items: plan.requiredImports,
              monospace: true,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Dependências: ${plan.requiredPackages.isEmpty ? 'Nenhuma externa (Flutter SDK)' : plan.requiredPackages.join(', ')}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('replan_widget_button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: _isGeneratingFromPlan ? null : _replanWidget,
                icon: const Icon(Icons.tune_rounded, size: 13),
                label: const Text(
                  'Ajustar / Replanejar',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton.icon(
                key: const ValueKey('generate_from_plan_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.background,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: (_isGeneratingFromPlan || _isPlanning)
                    ? null
                    : _generateFromPlan,
                icon: _isGeneratingFromPlan
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : const Icon(Icons.code_rounded, size: 14),
                label: Text(
                  _isGeneratingFromPlan
                      ? 'Gerando código...'
                      : 'Gerar Código pelo Plano',
                  style: const TextStyle(
                    fontSize: 11,
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

  Widget _buildPlanChipsGroup({
    required String title,
    required List<String> items,
    bool monospace = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: items
              .map(
                (item) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 10,
                      fontFamily: monospace ? 'monospace' : null,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  String _previewWidgetFileName(AiExecutionPlan plan) {
    final name = plan.sanitizedWidgetName;
    final snake = name
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .toLowerCase();
    return 'widgets/$snake.dart';
  }

  Widget _buildInjectionResultBanner(DartWidgetInjectionResult result) {
    return Container(
      key: const ValueKey('widget_injection_result_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: AppColors.success,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Arquivos atualizados com segurança',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (result.createdFiles.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Criados: ${result.createdFiles.join(', ')}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (result.modifiedFiles.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Modificados: ${result.modifiedFiles.join(', ')}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (result.resolvedAnchorDescription != null &&
              result.resolvedAnchorDescription!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Âncora: ${result.resolvedAnchorDescription}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
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
    final effectivePlan = variation.plan ?? _activePlan;
    final previewCode = _buildVariationCodePreview(variation);

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
          if (effectivePlan != null) ...[
            const SizedBox(height: 6),
            Text(
              'Alinhado ao plano: ${effectivePlan.sanitizedWidgetName} · ${effectivePlan.visualAnchorDescription.isNotEmpty ? effectivePlan.visualAnchorDescription : effectivePlan.insertionAnchorHint}',
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 8),

          // Code viewer toggle & Insert button
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton(
                key: ValueKey('toggle_variation_code_button_$index'),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed:
                    _isInjecting ? null : () => _insertVariation(variation),
                child: Text(
                  _isInjecting
                      ? 'Inserindo na tela...'
                      : '✅ Inserir Widget na Tela',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
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
                  previewCode,
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

  String _buildVariationCodePreview(WidgetVariation variation) {
    final extracted = variation.extractedWidgetCode?.trim();
    final mainCode = (extracted != null && extracted.isNotEmpty)
        ? extracted
        : variation.dartCode.trim();

    final missingImports = <String>[];
    for (final imp in variation.requiredImports) {
      final trimmed = imp.trim();
      if (trimmed.isEmpty) continue;
      final statement =
          trimmed.startsWith('import ') ? trimmed : "import '$trimmed';";
      if (!mainCode.contains(trimmed) && !mainCode.contains(statement)) {
        missingImports.add(statement);
      }
    }

    final buffer = StringBuffer();
    if (missingImports.isNotEmpty) {
      buffer.writeln('// Imports requeridos:');
      for (final statement in missingImports) {
        buffer.writeln(statement);
      }
      buffer.writeln();
    }

    if (mainCode.isNotEmpty) {
      buffer.writeln(mainCode);
    }

    final callSite = variation.callSiteSnippet?.trim();
    if (callSite != null && callSite.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('// Call-site na tela:');
      buffer.writeln(callSite);
    }

    return buffer.toString().trimRight();
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
