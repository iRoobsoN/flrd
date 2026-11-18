import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../ai/models/ai_execution_plan.dart';
import '../../../ai/providers/ai_settings_provider.dart';
import '../../../ai/services/dart_verification_service.dart';
import '../../../ai/services/gemini_ai_service.dart';
import '../../../ai/services/project_context_snapshot_service.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../projects/models/registered_project.dart';
import '../../../settings/presentation/settings_and_billing_dialog.dart';
import '../../domain/screen_material.dart';
import '../../domain/widget_variation.dart';
import '../../models/route_node.dart';
import '../../providers/android_debug_provider.dart';
import '../../providers/studio_provider.dart';
import '../../services/dart_widget_injector_service.dart';
import '../../services/diagnostic_code_fix_service.dart';

/// Modal dialog for Plan-First AI screen generation and focused widget refinement
/// using honest BYOK Google Gemini 2.5 credentials, `.flrd/backups/` snapshots,
/// and `flutter analyze` verification + 1-click rollback.
class AiScreenGeneratorDialog extends ConsumerStatefulWidget {
  final RegisteredProject project;
  final String? initialPrompt;
  final String? initialRoutePath;
  final String? initialScreenTitle;
  final ScreenMaterialItem? targetMaterial;
  final List<ScreenMaterialItem>? initialMaterials;
  final String? targetScreenFilePath;
  final String? currentScreenCode;
  final ValueChanged<String>? onCodeChanged;
  final http.Client? httpClient;
  final http.Client? aiHttpClient;
  final VerificationProcessRunner? verificationProcessRunner;

  const AiScreenGeneratorDialog({
    super.key,
    required this.project,
    this.initialPrompt,
    this.initialRoutePath,
    this.initialScreenTitle,
    this.targetMaterial,
    this.initialMaterials,
    this.targetScreenFilePath,
    this.currentScreenCode,
    this.onCodeChanged,
    this.httpClient,
    this.aiHttpClient,
    this.verificationProcessRunner,
  });

  http.Client? get _effectiveHttpClient => aiHttpClient ?? httpClient;

  static Future<void> show(
    BuildContext context,
    RegisteredProject project, {
    String? initialPrompt,
    String? initialRoutePath,
    String? initialScreenTitle,
    ScreenMaterialItem? targetMaterial,
    List<ScreenMaterialItem>? initialMaterials,
    String? targetScreenFilePath,
    String? currentScreenCode,
    ValueChanged<String>? onCodeChanged,
    http.Client? httpClient,
    http.Client? aiHttpClient,
    VerificationProcessRunner? verificationProcessRunner,
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
        targetScreenFilePath: targetScreenFilePath,
        currentScreenCode: currentScreenCode,
        onCodeChanged: onCodeChanged,
        httpClient: httpClient,
        aiHttpClient: aiHttpClient,
        verificationProcessRunner: verificationProcessRunner,
      ),
    );
  }

  /// Resolves the active BYOK Gemini API key from [byokInputKey] or stored
  /// [aiSettings]. Never falls back to a fake cloud proxy.
  static String? resolveActiveApiKey({
    int selectedMode = 1,
    required AiSettingsState aiSettings,
    String byokInputKey = '',
  }) {
    final trimmedInput = byokInputKey.trim();
    if (trimmedInput.isNotEmpty) {
      return trimmedInput;
    }
    final stored = aiSettings.apiKey?.trim();
    return (stored != null && stored.isNotEmpty) ? stored : null;
  }

  @override
  ConsumerState<AiScreenGeneratorDialog> createState() =>
      _AiScreenGeneratorDialogState();
}

class _AiScreenGeneratorDialogState
    extends ConsumerState<AiScreenGeneratorDialog> {
  static int _backupCounter = 0;

  late final TextEditingController _pathController;
  late final TextEditingController _titleController;
  late final TextEditingController _promptController;
  late final TextEditingController _apiKeyController;
  late final FocusNode _apiKeyFocusNode;

  String _parentRouteId = 'dashboard';
  bool _isGenerating = false;
  bool _isApplying = false;
  bool _isRevertingBackup = false;
  bool _isEditingApiKey = false;
  bool _obscureApiKey = true;
  bool _showCodePreview = true;

  String? _errorBannerMessage;
  bool _errorIsKeyWarning = false;

  ProjectContextSnapshot? _capturedContext;
  AiExecutionPlan? _executionPlan;
  WidgetVariation? _refinedVariation;
  String? _generatedScreenCode;
  String? _plannedTargetRelativePath;
  String? _modelUsed;

  DartVerificationResult? _verificationResult;
  String? _activeBackupDir;
  List<String> _createdFilesForRollback = const [];
  bool _wasRolledBack = false;

  bool get _isWidgetRefinement => widget.targetMaterial != null;

  bool get _shouldSkipLiveVerification {
    if (widget.verificationProcessRunner != null) return false;
    if (kIsWeb) return false;
    try {
      final value = Platform.environment['FLUTTER_TEST'];
      return value != null && value.toLowerCase() != 'false' && value != '0';
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    final defaultPath = _isWidgetRefinement
        ? '/components/${widget.targetMaterial!.type.name}'
        : '/checkout/payment';
    final defaultTitle = _isWidgetRefinement
        ? '${widget.targetMaterial!.displayName.replaceAll(RegExp(r'\s+'), '')}Widget'
        : 'PaymentScreen';

    _pathController = TextEditingController(
      text: widget.initialRoutePath ?? defaultPath,
    );
    _titleController = TextEditingController(
      text: widget.initialScreenTitle ?? defaultTitle,
    );

    final existingNodes = ref.read(studioProvider).nodes;
    final matchingRoute = _findMatchingRouteNode(existingNodes);
    var promptText = widget.initialPrompt ?? '';
    if (promptText.isEmpty) {
      if (_isWidgetRefinement) {
        promptText = ScreenMaterialCodeUpdater.generateWidgetSpecificPrompt(
          widget.targetMaterial!,
          routeNode: matchingRoute,
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
    _apiKeyFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _titleController.dispose();
    _promptController.dispose();
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    super.dispose();
  }

  RouteNode? _findMatchingRouteNode(List<RouteNode> nodes) {
    final targetPath = (widget.initialRoutePath ?? _pathController.text).trim();
    final targetTitle =
        (widget.initialScreenTitle ?? _titleController.text).trim();
    for (final node in nodes) {
      if (targetPath.isNotEmpty && node.path == targetPath) {
        return node;
      }
    }
    for (final node in nodes) {
      if (targetTitle.isNotEmpty && node.title == targetTitle) {
        return node;
      }
    }
    return null;
  }

  String? _resolveTargetScreenRelativePath() {
    final canonicalRoot = p.normalize(p.absolute(widget.project.path.trim()));
    final explicit = widget.targetScreenFilePath?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return _normalizeToRelativeOrOriginal(canonicalRoot, explicit);
    }
    final matchingNode = _findMatchingRouteNode(ref.read(studioProvider).nodes);
    if (matchingNode != null && matchingNode.filePath.trim().isNotEmpty) {
      return _normalizeToRelativeOrOriginal(
        canonicalRoot,
        matchingNode.filePath.trim(),
      );
    }
    return null;
  }

  String _normalizeToRelativeOrOriginal(String canonicalRoot, String rawPath) {
    if (canonicalRoot.isEmpty) return rawPath.replaceAll('\\', '/');
    final abs = p.isAbsolute(rawPath)
        ? p.normalize(p.absolute(rawPath))
        : p.normalize(p.absolute(p.join(canonicalRoot, rawPath)));
    if (p.isWithin(canonicalRoot, abs)) {
      return p.relative(abs, from: canonicalRoot).replaceAll('\\', '/');
    }
    return rawPath.replaceAll('\\', '/');
  }

  String _computeNewScreenRelativePath(String rawClassName) {
    final explicit = widget.targetScreenFilePath?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      final canonicalRoot = p.normalize(p.absolute(widget.project.path.trim()));
      return _normalizeToRelativeOrOriginal(canonicalRoot, explicit);
    }
    final sanitized = rawClassName.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    final effective = sanitized.isEmpty ? 'GeneratedScreen' : sanitized;
    var featureFolder = effective.toLowerCase().replaceAll('screen', '');
    if (featureFolder.isEmpty) {
      featureFolder = effective.toLowerCase();
    }
    return 'lib/features/$featureFolder/presentation/${effective.toLowerCase()}.dart';
  }

  String? _ensureConfiguredByokKey() {
    final aiSettings = ref.read(aiSettingsProvider);
    final typedKey = _apiKeyController.text.trim();
    if (!aiSettings.hasApiKey && typedKey.isNotEmpty) {
      ref.read(aiSettingsProvider.notifier).setApiKey(typedKey);
    }

    final resolved = AiScreenGeneratorDialog.resolveActiveApiKey(
      aiSettings: ref.read(aiSettingsProvider),
      byokInputKey: _apiKeyController.text,
    );
    if (resolved == null || resolved.isEmpty) {
      const msg =
          'Chave Gemini (BYOK) necessária. Configure e salve sua chave API antes de continuar.';
      setState(() {
        _isEditingApiKey = true;
        _errorBannerMessage = msg;
        _errorIsKeyWarning = true;
      });
      _apiKeyFocusNode.requestFocus();
      AppToast.error(context, msg);
      return null;
    }
    return resolved;
  }

  void _saveInlineApiKey() {
    final trimmed = _apiKeyController.text.trim();
    if (trimmed.isEmpty) {
      ref.read(aiSettingsProvider.notifier).clearApiKey();
      const msg = 'Informe uma chave Gemini API válida para ativar o modo BYOK.';
      setState(() {
        _isEditingApiKey = true;
        _errorBannerMessage = msg;
        _errorIsKeyWarning = true;
      });
      _apiKeyFocusNode.requestFocus();
      AppToast.warning(context, msg);
      return;
    }

    ref.read(aiSettingsProvider.notifier).setApiKey(trimmed);
    setState(() {
      _isEditingApiKey = false;
      if (_errorIsKeyWarning) {
        _errorBannerMessage = null;
        _errorIsKeyWarning = false;
      }
    });
    AppToast.success(context, 'Chave Gemini (BYOK) salva com sucesso.');
  }

  void _clearInlineApiKey() {
    _apiKeyController.clear();
    ref.read(aiSettingsProvider.notifier).clearApiKey();
    setState(() {
      _isEditingApiKey = true;
      _errorBannerMessage = null;
      _errorIsKeyWarning = false;
    });
    _apiKeyFocusNode.requestFocus();
  }

  void _selectModel(String model) {
    ref.read(aiSettingsProvider.notifier).setSelectedModel(model);
  }

  String _modelDisplayLabel(String modelId) {
    return AiSettingsState.normalizeModel(modelId) ==
            AiSettingsState.geminiProModel
        ? 'Gemini 2.5 Pro'
        : 'Gemini 2.5 Flash';
  }

  String _maskApiKey(String key) {
    final clean = key.trim();
    if (clean.length <= 8) return '••••••••';
    return '${clean.substring(0, 4)}••••${clean.substring(clean.length - 4)}';
  }

  String? _readFileIfExists(String path) {
    if (path.trim().isEmpty) return null;
    try {
      final canonicalRoot = p.normalize(p.absolute(widget.project.path.trim()));
      final abs = p.isAbsolute(path)
          ? p.normalize(p.absolute(path))
          : p.normalize(p.absolute(p.join(canonicalRoot, path)));
      final file = File(abs);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.trim().isNotEmpty) {
          return content;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _planAndGenerateWidgetRefinement() async {
    final activeApiKey = _ensureConfiguredByokKey();
    if (activeApiKey == null) return false;

    final promptText = _promptController.text.trim();
    if (promptText.isEmpty) {
      const msg = 'Descreva o refinamento do widget antes de continuar.';
      setState(() {
        _errorBannerMessage = msg;
        _errorIsKeyWarning = false;
      });
      AppToast.error(context, msg);
      return false;
    }

    setState(() {
      _isGenerating = true;
      _errorBannerMessage = null;
      _errorIsKeyWarning = false;
      _verificationResult = null;
      _wasRolledBack = false;
    });

    final targetScreenRel = _resolveTargetScreenRelativePath();
    final existingNodes = ref.read(studioProvider).nodes;
    final matchingRoute = _findMatchingRouteNode(existingNodes);
    final aiSettings = ref.read(aiSettingsProvider);

    var snapshot = await ProjectContextSnapshotService.capture(
      projectPath: widget.project.path,
      targetScreenPath: targetScreenRel,
    );
    final liveCode = widget.currentScreenCode?.trim();
    if (liveCode != null && liveCode.isNotEmpty) {
      snapshot = snapshot.copyWith(
        targetScreenPath: snapshot.targetScreenPath ?? targetScreenRel,
        targetScreenSource: liveCode,
      );
    }

    final materialLabel = widget.targetMaterial!.displayName;
    final placementHint =
        'Atualizar/inserir componente "$materialLabel" na tela existente';
    final planPrompt = '$promptText\n\n'
        'RESTRIÇÃO ESTRITA: Refine apenas o componente "$materialLabel" para injeção dentro da tela existente. '
        'NÃO gere Scaffold nem MaterialApp nem uma nova rota.';

    final planOutcome = await GeminiAiService.planWidgetCreation(
      prompt: planPrompt,
      userPlacementHint: placementHint,
      preset: widget.project.preset,
      routeNode: matchingRoute,
      projectContext: snapshot,
      apiKey: activeApiKey,
      preferredModel: aiSettings.selectedModel,
      client: widget._effectiveHttpClient,
    );

    if (!mounted) return false;

    if (!planOutcome.isSuccess || planOutcome.data == null) {
      final isKeyMissing = planOutcome.source == AiResultSource.unconfiguredKey;
      final message = planOutcome.errorMessage ??
          'Não foi possível gerar o plano de refinamento com Gemini.';
      setState(() {
        _isGenerating = false;
        _isEditingApiKey = isKeyMissing ? true : _isEditingApiKey;
        _errorBannerMessage = message;
        _errorIsKeyWarning = isKeyMissing;
      });
      AppToast.error(context, message);
      return false;
    }

    var effectivePlan = planOutcome.data!;
    if (effectivePlan.architectureType == 'fullScreen') {
      effectivePlan = effectivePlan.copyWith(
        architectureType: 'statefulWidgetClass',
      );
    }
    if ((effectivePlan.targetFilePath == null ||
            effectivePlan.targetFilePath!.trim().isEmpty) &&
        targetScreenRel != null) {
      effectivePlan = effectivePlan.copyWith(targetFilePath: targetScreenRel);
    }

    final widgetOutcome = await GeminiAiService.generateWidgetFromPlan(
      plan: effectivePlan,
      originalPrompt: planPrompt,
      userPlacementHint: placementHint,
      preset: widget.project.preset,
      routeNode: matchingRoute,
      projectContext: snapshot,
      apiKey: activeApiKey,
      preferredModel: aiSettings.selectedModel,
      client: widget._effectiveHttpClient,
    );

    if (!mounted) return false;

    if (!widgetOutcome.isSuccess || widgetOutcome.data == null) {
      final isKeyMissing = widgetOutcome.source == AiResultSource.unconfiguredKey;
      final message = widgetOutcome.errorMessage ??
          'Falha ao gerar o widget refinado pelo plano.';
      setState(() {
        _isGenerating = false;
        _capturedContext = snapshot;
        _executionPlan = effectivePlan;
        _modelUsed = widgetOutcome.modelUsed ?? planOutcome.modelUsed;
        _isEditingApiKey = isKeyMissing ? true : _isEditingApiKey;
        _errorBannerMessage = message;
        _errorIsKeyWarning = isKeyMissing;
      });
      AppToast.error(context, message);
      return false;
    }

    final generatedSnippet = widgetOutcome.data!.extractedWidgetCode ??
        widgetOutcome.data!.dartCode;
    if (RegExp(r'\bScaffold\s*\(').hasMatch(generatedSnippet)) {
      const msg =
          'O refinamento gerou um Scaffold completo em vez de um widget componente. Tente ajustar o prompt e replanejar.';
      setState(() {
        _isGenerating = false;
        _capturedContext = snapshot;
        _executionPlan = effectivePlan;
        _errorBannerMessage = msg;
        _errorIsKeyWarning = false;
      });
      AppToast.error(context, msg);
      return false;
    }

    setState(() {
      _isGenerating = false;
      _capturedContext = snapshot;
      _executionPlan = effectivePlan;
      _refinedVariation = widgetOutcome.data!;
      _modelUsed =
          widgetOutcome.modelUsed ?? planOutcome.modelUsed ?? aiSettings.selectedModel;
      _plannedTargetRelativePath = targetScreenRel;
      _errorBannerMessage = null;
      _errorIsKeyWarning = false;
    });
    return true;
  }

  Future<void> _refineAndInjectWidget() async {
    if (_isGenerating || _isApplying) return;

    if (_refinedVariation == null) {
      final plannedOk = await _planAndGenerateWidgetRefinement();
      if (!plannedOk || !mounted || _refinedVariation == null) return;
    }

    final targetScreenPath =
        _plannedTargetRelativePath ?? _resolveTargetScreenRelativePath() ?? '';
    if (targetScreenPath.isEmpty) {
      const msg =
          'Arquivo da tela alvo não encontrado para injeção do widget refinado.';
      setState(() {
        _errorBannerMessage = msg;
        _errorIsKeyWarning = false;
      });
      AppToast.error(context, msg);
      return;
    }

    setState(() {
      _isApplying = true;
      _errorBannerMessage = null;
      _errorIsKeyWarning = false;
      _wasRolledBack = false;
    });

    final injectResult = await DartWidgetInjectorService.injectWidget(
      projectPath: widget.project.path,
      screenFilePath: targetScreenPath,
      variation: _refinedVariation!,
      plan: _executionPlan ?? _refinedVariation!.plan,
      currentScreenCode: widget.currentScreenCode,
    );

    if (!mounted) return;

    if (!injectResult.success || injectResult.updatedScreenCode == null) {
      final errMsg = injectResult.errorMessage ??
          'Não foi possível injetar o widget refinado na tela.';
      setState(() {
        _isApplying = false;
        _errorBannerMessage = errMsg;
        _errorIsKeyWarning = false;
      });
      AppToast.error(context, errMsg);
      return;
    }

    final aiSettings = ref.read(aiSettingsProvider);
    final activeApiKey = AiScreenGeneratorDialog.resolveActiveApiKey(
      aiSettings: aiSettings,
      byokInputKey: _apiKeyController.text,
    );
    final targetFiles = <String>[
      ...injectResult.createdFiles,
      ...injectResult.modifiedFiles,
    ];

    final DartVerificationResult verificationResult;
    if (_shouldSkipLiveVerification) {
      verificationResult = DartVerificationResult(
        passed: false,
        skipped: true,
        backupDir: injectResult.backupDir,
      );
    } else {
      verificationResult =
          await DartVerificationService.verifyAndAutoRepairOrRollback(
        projectPath: widget.project.path,
        targetFiles: targetFiles,
        backupDir: injectResult.backupDir,
        apiKey: activeApiKey,
        preferredModel: aiSettings.selectedModel,
        processRunner: widget.verificationProcessRunner,
        aiHttpClient: widget._effectiveHttpClient,
      );
    }

    if (!mounted) return;

    final latestCode = _readFileIfExists(targetScreenPath) ??
        injectResult.updatedScreenCode!;
    widget.onCodeChanged?.call(latestCode);

    final verificationClean =
        !verificationResult.rolledBack && verificationResult.errors.isEmpty;
    final canFinishCleanly = verificationClean &&
        (verificationResult.passed || verificationResult.skipped);

    if (canFinishCleanly) {
      ref.read(androidDebugProvider.notifier).onCodeSaved(widget.project.path);
      final materialName = widget.targetMaterial!.displayName;
      Navigator.of(context).pop();
      AppToast.success(
        context,
        'Widget "$materialName" refinado com IA e injetado com sucesso! ($targetScreenPath)',
        duration: const Duration(seconds: 4),
      );
      return;
    }

    setState(() {
      _isApplying = false;
      _verificationResult = verificationResult;
      _activeBackupDir = verificationResult.backupDir ?? injectResult.backupDir;
      _createdFilesForRollback = injectResult.createdFiles;
    });

    final errCount = verificationResult.errors.isNotEmpty
        ? verificationResult.errors.length
        : 1;
    AppToast.warning(
      context,
      'Analyzer encontrou $errCount erro(s). Use "Reverter Alterações" se necessário.',
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _planAndPreviewNewScreen() async {
    final activeApiKey = _ensureConfiguredByokKey();
    if (activeApiKey == null) return;

    final promptText = _promptController.text.trim();
    if (promptText.isEmpty) {
      const msg = 'Descreva a tela antes de gerar código com IA.';
      setState(() {
        _errorBannerMessage = msg;
        _errorIsKeyWarning = false;
      });
      AppToast.error(context, msg);
      return;
    }

    final cleanTitle = _titleController.text.trim().isEmpty
        ? 'GeneratedScreen'
        : _titleController.text.trim();
    final rawRoute = _pathController.text.trim().isEmpty
        ? '/generated'
        : _pathController.text.trim();
    final routePath = rawRoute.startsWith('/') ? rawRoute : '/$rawRoute';
    final relativeFilePath = _computeNewScreenRelativePath(cleanTitle);

    setState(() {
      _isGenerating = true;
      _errorBannerMessage = null;
      _errorIsKeyWarning = false;
      _verificationResult = null;
      _wasRolledBack = false;
    });

    final existingNodes = ref.read(studioProvider).nodes;
    final existingRoutes =
        existingNodes.map((n) => '${n.title} (${n.path})').toList();

    var snapshot = await ProjectContextSnapshotService.capture(
      projectPath: widget.project.path,
      targetScreenPath: relativeFilePath,
    );
    final liveCode = widget.currentScreenCode?.trim();
    if (liveCode != null && liveCode.isNotEmpty) {
      snapshot = snapshot.copyWith(
        targetScreenPath: snapshot.targetScreenPath ?? relativeFilePath,
        targetScreenSource: liveCode,
      );
    }

    final aiSettings = ref.read(aiSettingsProvider);
    final previewRouteNode = RouteNode(
      id: cleanTitle.toLowerCase(),
      path: routePath,
      title: cleanTitle,
      subtitle: promptText,
      icon: Icons.auto_awesome_rounded,
      position: Offset.zero,
      filePath: relativeFilePath,
      isProtected: true,
      isAIGenerated: true,
    );

    final outcome = await GeminiAiService.generateScreenWithOutcome(
      prompt: 'Screen class name: $cleanTitle\n'
          'Route path: $routePath\n\n'
          '$promptText',
      preset: widget.project.preset,
      routeNode: previewRouteNode,
      projectContext: snapshot,
      existingRoutes: existingRoutes,
      apiKey: activeApiKey,
      preferredModel: aiSettings.selectedModel,
      client: widget._effectiveHttpClient,
    );

    if (!mounted) return;

    if (!outcome.isSuccess || outcome.data == null) {
      final isKeyMissing = outcome.source == AiResultSource.unconfiguredKey;
      final message = outcome.errorMessage ??
          'Não foi possível gerar a tela com Gemini.';
      setState(() {
        _isGenerating = false;
        _isEditingApiKey = isKeyMissing ? true : _isEditingApiKey;
        _errorBannerMessage = message;
        _errorIsKeyWarning = isKeyMissing;
      });
      AppToast.error(context, message);
      return;
    }

    setState(() {
      _isGenerating = false;
      _capturedContext = snapshot;
      _generatedScreenCode = outcome.data!;
      _plannedTargetRelativePath = relativeFilePath;
      _modelUsed = outcome.modelUsed ?? aiSettings.selectedModel;
      _errorBannerMessage = null;
      _errorIsKeyWarning = false;
    });
  }

  Future<void> _saveAndVerifyNewScreen() async {
    final code = _generatedScreenCode;
    final relativeFilePath = _plannedTargetRelativePath;
    if (code == null ||
        code.trim().isEmpty ||
        relativeFilePath == null ||
        relativeFilePath.trim().isEmpty) {
      return;
    }

    final cleanRoot = widget.project.path.trim();
    if (cleanRoot.isEmpty) {
      const msg = 'Caminho do projeto não informado.';
      setState(() => _errorBannerMessage = msg);
      AppToast.error(context, msg);
      return;
    }

    final canonicalRoot = p.normalize(p.absolute(cleanRoot));
    final targetAbsPath = p.normalize(
      p.absolute(
        p.joinAll([
          canonicalRoot,
          ...relativeFilePath
              .replaceAll('\\', '/')
              .split('/')
              .where((s) => s.isNotEmpty),
        ]),
      ),
    );
    if (!p.isWithin(canonicalRoot, targetAbsPath)) {
      final msg = 'Caminho de saída fora do projeto: $relativeFilePath';
      setState(() => _errorBannerMessage = msg);
      AppToast.error(context, msg);
      return;
    }

    setState(() {
      _isApplying = true;
      _errorBannerMessage = null;
      _errorIsKeyWarning = false;
      _wasRolledBack = false;
    });

    final stamp = _nextBackupStamp();
    final backupDir = p.join(canonicalRoot, '.flrd', 'backups', 'screen_$stamp');
    final targetFile = File(targetAbsPath);
    final existedBefore = targetFile.existsSync();

    try {
      Directory(backupDir).createSync(recursive: true);
      if (existedBefore) {
        final backupFile = File(p.join(backupDir, relativeFilePath));
        backupFile.parent.createSync(recursive: true);
        backupFile.writeAsStringSync(targetFile.readAsStringSync(), flush: true);
      }

      if (!targetFile.parent.existsSync()) {
        targetFile.parent.createSync(recursive: true);
      }
      _atomicWriteFile(targetFile, code);
    } catch (e) {
      if (!mounted) return;
      final msg = 'Erro ao gravar arquivo gerado com backup: $e';
      setState(() {
        _isApplying = false;
        _errorBannerMessage = msg;
      });
      AppToast.error(context, msg);
      return;
    }

    final aiSettings = ref.read(aiSettingsProvider);
    final activeApiKey = AiScreenGeneratorDialog.resolveActiveApiKey(
      aiSettings: aiSettings,
      byokInputKey: _apiKeyController.text,
    );

    final DartVerificationResult verificationResult;
    if (_shouldSkipLiveVerification) {
      verificationResult = DartVerificationResult(
        passed: false,
        skipped: true,
        backupDir: backupDir,
      );
    } else {
      verificationResult =
          await DartVerificationService.verifyAndAutoRepairOrRollback(
        projectPath: canonicalRoot,
        targetFiles: [relativeFilePath],
        backupDir: backupDir,
        apiKey: activeApiKey,
        preferredModel: aiSettings.selectedModel,
        processRunner: widget.verificationProcessRunner,
        aiHttpClient: widget._effectiveHttpClient,
      );
    }

    if (!mounted) return;

    final latestCode = _readFileIfExists(targetAbsPath) ?? code;
    final verificationClean =
        !verificationResult.rolledBack && verificationResult.errors.isEmpty;
    final canFinishCleanly = verificationClean &&
        (verificationResult.passed || verificationResult.skipped);

    if (canFinishCleanly) {
      ref.read(androidDebugProvider.notifier).onCodeSaved(widget.project.path);
      widget.onCodeChanged?.call(latestCode);

      final cleanTitle = _titleController.text.trim().isEmpty
          ? 'GeneratedScreen'
          : _titleController.text.trim();
      final rawRoute = _pathController.text.trim().isEmpty
          ? '/generated'
          : _pathController.text.trim();
      final routePath = rawRoute.startsWith('/') ? rawRoute : '/$rawRoute';

      final studio = ref.read(studioProvider.notifier);
      final currentNodes = ref.read(studioProvider).nodes;
      final routeExists = currentNodes.any((n) => n.path == routePath);

      if (!routeExists && widget.targetScreenFilePath == null) {
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
          path: routePath,
          title: cleanTitle,
          subtitle: _promptController.text.trim(),
          icon: Icons.auto_awesome_rounded,
          isProtected: true,
          isAIGenerated: true,
          position: newPos,
          parentRouteId: _parentRouteId,
          filePath: relativeFilePath,
        );
      }

      Navigator.of(context).pop();
      AppToast.success(
        context,
        'Tela "$cleanTitle" gerada via IA e injetada no Fluxograma! ($relativeFilePath)',
        duration: const Duration(seconds: 4),
      );
      return;
    }

    setState(() {
      _isApplying = false;
      _generatedScreenCode = latestCode;
      _verificationResult = verificationResult;
      _activeBackupDir = verificationResult.backupDir ?? backupDir;
      _createdFilesForRollback =
          existedBefore ? const [] : <String>[relativeFilePath];
    });

    final errCount = verificationResult.errors.isNotEmpty
        ? verificationResult.errors.length
        : 1;
    AppToast.warning(
      context,
      'Analyzer encontrou $errCount erro(s). Use "Reverter Alterações" se necessário.',
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _revertAppliedChanges() async {
    final backupDir = _activeBackupDir;
    if (_isRevertingBackup || backupDir == null || backupDir.trim().isEmpty) {
      return;
    }

    setState(() => _isRevertingBackup = true);

    final canonicalRoot = p.normalize(p.absolute(widget.project.path.trim()));
    final restored = await DiagnosticCodeFixService.revertBackup(
      projectPath: canonicalRoot,
      backupDir: backupDir,
    );

    final restoredNormalized =
        restored.map((item) => item.replaceAll('\\', '/').toLowerCase()).toSet();
    for (final rawRel in _createdFilesForRollback) {
      final relPosix = rawRel.replaceAll('\\', '/').trim();
      if (relPosix.isEmpty ||
          restoredNormalized.contains(relPosix.toLowerCase())) {
        continue;
      }
      final candidateAbs =
          p.normalize(p.absolute(p.join(canonicalRoot, relPosix)));
      if (!p.isWithin(canonicalRoot, candidateAbs)) continue;
      try {
        final createdFile = File(candidateAbs);
        if (createdFile.existsSync()) {
          createdFile.deleteSync();
        }
      } catch (_) {}
    }

    if (!mounted) return;

    if (_isWidgetRefinement && widget.onCodeChanged != null) {
      final targetScreenPath =
          _plannedTargetRelativePath ?? _resolveTargetScreenRelativePath() ?? '';
      final restoredScreen = _readFileIfExists(targetScreenPath);
      if (restoredScreen != null) {
        widget.onCodeChanged!(restoredScreen);
      }
    }

    setState(() {
      _isRevertingBackup = false;
      _wasRolledBack = true;
      _verificationResult = _verificationResult?.copyWith(rolledBack: true);
    });

    AppToast.info(
      context,
      'Alterações revertidas a partir do backup em .flrd/backups/.',
      duration: const Duration(seconds: 3),
    );
  }

  String _nextBackupStamp() {
    _backupCounter++;
    final now = DateTime.now().toUtc();
    final base = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return '${base}_$_backupCounter';
  }

  void _atomicWriteFile(File targetFile, String content) {
    final tempPath =
        '${targetFile.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}';
    final tempFile = File(tempPath);
    try {
      tempFile.writeAsStringSync(content, flush: true);
      tempFile.renameSync(targetFile.path);
    } finally {
      try {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(studioProvider).nodes;
    final auth = ref.watch(authProvider);
    final aiSettings = ref.watch(aiSettingsProvider);

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

    final effectiveParentId = nodes.any((n) => n.id == _parentRouteId)
        ? _parentRouteId
        : (nodes.isNotEmpty ? nodes.first.id : null);
    final targetScreenRel = _resolveTargetScreenRelativePath();

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
              _isWidgetRefinement
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
                  _isWidgetRefinement
                      ? 'Refinar Widget com IA: ${widget.targetMaterial!.displayName}'
                      : 'Gerador de Telas com IA',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _isWidgetRefinement
                      ? 'FLRD Widget Studio • Plan-First Gemini 2.5 (BYOK)'
                      : 'FLRD AI Screen Studio • Plan-First Gemini 2.5 (BYOK)',
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
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Plan Status & Honest BYOK Quota Header
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: planColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border:
                                Border.all(color: planColor.withOpacity(0.35)),
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
                        InkWell(
                          key: const Key('manage_plan_button'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            SettingsAndBillingDialog.show(
                              context,
                              initialTabIndex: 1,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.secondary.withOpacity(0.3),
                              ),
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
                    const Text(
                      'Cota Ilimitada / BYOK Livre',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (auth.user != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Créditos FLRD preservados (${auth.creditsRemaining} / ${auth.creditsTotal}) — execução direta via sua chave Gemini.',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 2. Architecture Context / Target Screen Pill
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
                        _isWidgetRefinement
                            ? 'Widget Focus: ${widget.targetMaterial!.displayName} (${widget.targetMaterial!.type.shortChipLabel})'
                                '${targetScreenRel != null ? ' • Tela: $targetScreenRel' : ''}'
                            : 'Project Context: ${widget.project.preset.name.toUpperCase()} • Plan-First & Verify',
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
              const SizedBox(height: 14),

              // 3. Route Path & Class Name (for new screens; read-only summary when refining a widget)
              if (!_isWidgetRefinement) ...[
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
                          ? const [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text('Nenhuma rota existente'),
                              ),
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
              ],

              // 4. AI Prompt
              Text(
                _isWidgetRefinement
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
                  hintText: _isWidgetRefinement
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
              const SizedBox(height: 14),

              // 5. Honest BYOK Gemini 2.5 Controls
              _buildHonestByokControl(aiSettings),

              if (_errorBannerMessage != null &&
                  _errorBannerMessage!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildErrorBanner(),
              ],

              // 6. Plan / Preview Summary + Generated Code (New Screen or Refined Widget)
              if (_isWidgetRefinement &&
                  (_executionPlan != null || _refinedVariation != null)) ...[
                const SizedBox(height: 12),
                _buildWidgetPlanPreviewCard(),
              ],

              if (!_isWidgetRefinement && _generatedScreenCode != null) ...[
                const SizedBox(height: 12),
                _buildScreenPlanPreviewCard(),
              ],

              // 7. Verification Status & 1-click Rollback Card
              if (_verificationResult != null || _wasRolledBack) ...[
                const SizedBox(height: 12),
                _buildVerificationCard(),
              ],
            ],
          ),
        ),
      ),
      actions: _buildActions(),
    );
  }

  List<Widget> _buildActions() {
    final busy = _isGenerating || _isApplying || _isRevertingBackup;

    if (_isWidgetRefinement) {
      return [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancelar',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        OutlinedButton.icon(
          key: const Key('dialog_plan_widget_button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: busy ? null : _planAndGenerateWidgetRefinement,
          icon: const Icon(Icons.architecture_rounded, size: 15),
          label: const Text(
            '📋 Ver Plano',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
          onPressed: busy ? null : _refineAndInjectWidget,
          icon: (_isGenerating || _isApplying)
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
                ? 'Planejando Widget...'
                : _isApplying
                    ? 'Injetando & Verificando...'
                    : '✨ Refinar e Injetar Widget',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ];
    }

    final hasScreenPreview = _generatedScreenCode != null;
    return [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: const Text(
          'Cancelar',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
      if (hasScreenPreview) ...[
        OutlinedButton.icon(
          key: const Key('dialog_regenerate_screen_button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: busy ? null : _planAndPreviewNewScreen,
          icon: const Icon(Icons.refresh_rounded, size: 15),
          label: const Text(
            'Gerar Novamente',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton.icon(
          key: const Key('dialog_apply_and_verify_screen_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: busy ? null : _saveAndVerifyNewScreen,
          icon: _isApplying
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.verified_rounded, size: 16),
          label: Text(
            _isApplying
                ? 'Salvando & Verificando...'
                : '✅ Salvar, Injetar e Verificar',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ] else
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
          onPressed: busy ? null : _planAndPreviewNewScreen,
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
                ? 'Gerando com Gemini 2.5...'
                : 'Gerar e Injetar Tela',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
    ];
  }

  Widget _buildHonestByokControl(AiSettingsState settings) {
    final hasKey = settings.hasApiKey;
    final showInlineInput = !hasKey || _isEditingApiKey;
    final selectedModel = AiSettingsState.normalizeModel(settings.selectedModel);
    final statusColor =
        hasKey ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final statusText = hasKey
        ? '⚡ BYOK Ativo · ${_modelDisplayLabel(selectedModel)}'
        : '🔑 Chave Gemini (BYOK) necessária';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasKey
              ? AppColors.borderSubtle
              : const Color(0xFFF59E0B).withOpacity(0.4),
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
                key: const ValueKey('dialog_ai_status_indicator'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withOpacity(0.35)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildModelBadge(
                    key: const ValueKey('dialog_model_flash'),
                    label: 'Gemini 2.5 Flash',
                    isSelected:
                        selectedModel == AiSettingsState.geminiFlashModel,
                    onTap: () => _selectModel(AiSettingsState.geminiFlashModel),
                  ),
                  _buildModelBadge(
                    key: const ValueKey('dialog_model_pro'),
                    label: 'Gemini 2.5 Pro',
                    isSelected: selectedModel == AiSettingsState.geminiProModel,
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
              runSpacing: 4,
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
                  key: const ValueKey('dialog_api_key_edit_button'),
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
                  key: const ValueKey('dialog_api_key_clear_button'),
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
              key: const ValueKey('dialog_api_key_input'),
              controller: _apiKeyController,
              focusNode: _apiKeyFocusNode,
              obscureText: _obscureApiKey,
              onSubmitted: (_) => _saveInlineApiKey(),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Chave de API Google Gemini (BYOK)',
                labelStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
                hintText: 'Cole sua Gemini API Key (ex: AIzaSy...)',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                prefixIcon: const Icon(
                  Icons.key_rounded,
                  size: 16,
                  color: AppColors.success,
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
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ElevatedButton.icon(
                  key: const ValueKey('dialog_api_key_save_button'),
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
                    key: const ValueKey('dialog_api_key_cancel_button'),
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
              : AppColors.surface,
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

  Widget _buildErrorBanner() {
    final color = _errorIsKeyWarning ? AppColors.warning : AppColors.danger;
    return Container(
      key: const ValueKey('dialog_ai_error_banner'),
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
            _errorIsKeyWarning
                ? Icons.vpn_key_outlined
                : Icons.error_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorBannerMessage ?? '',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() {
              _errorBannerMessage = null;
              _errorIsKeyWarning = false;
            }),
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetPlanPreviewCard() {
    final plan = _executionPlan;
    final variation = _refinedVariation;
    final previewCode = variation != null
        ? (variation.extractedWidgetCode?.trim().isNotEmpty == true
            ? variation.extractedWidgetCode!.trim()
            : variation.dartCode.trim())
        : '';

    return Container(
      key: const ValueKey('dialog_plan_preview_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '📋 Plano de Refinamento',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (plan != null)
                Text(
                  plan.sanitizedWidgetName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              if (_modelUsed != null)
                Text(
                  _modelUsed!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
          if (plan != null && plan.goalSummary.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              plan.goalSummary,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
          if (previewCode.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildCodePreviewBox(previewCode),
          ],
        ],
      ),
    );
  }

  Widget _buildScreenPlanPreviewCard() {
    final snapshot = _capturedContext;
    final code = _generatedScreenCode ?? '';
    final targetPath = _plannedTargetRelativePath ?? '';

    return Container(
      key: const ValueKey('dialog_plan_preview_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '📋 Plano e Prévia da Tela',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_modelUsed != null)
                Text(
                  _modelUsed!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () =>
                    setState(() => _showCodePreview = !_showCodePreview),
                child: Text(
                  _showCodePreview ? '👁️ Ocultar Código' : '👁️ Ver Código',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Destino: $targetPath',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10.5,
              fontFamily: 'monospace',
            ),
          ),
          if (snapshot != null) ...[
            const SizedBox(height: 4),
            Text(
              'Contexto: ${snapshot.hasAppColors ? 'AppColors ativo' : 'Theme.of(context)'} · '
              '${snapshot.hasGoRouter ? 'go_router' : 'Navigator'} · '
              '${snapshot.dependencies.length} pacote(s)',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
              ),
            ),
          ],
          if (_showCodePreview && code.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildCodePreviewBox(code),
          ],
        ],
      ),
    );
  }

  Widget _buildCodePreviewBox(String code) {
    return Container(
      key: const ValueKey('dialog_screen_code_preview'),
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 200),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5,
              color: Color(0xFFE2E8F0),
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationCard() {
    final verification = _verificationResult;
    final isReverted = _wasRolledBack || (verification?.rolledBack ?? false);
    final hasFailure = !isReverted &&
        verification != null &&
        !verification.passed &&
        !verification.skipped;
    final errCount = verification != null
        ? (verification.errors.isNotEmpty
            ? verification.errors.length
            : (hasFailure ? 1 : 0))
        : 0;
    final color = isReverted
        ? AppColors.warning
        : hasFailure
            ? AppColors.danger
            : AppColors.success;

    return Container(
      key: const ValueKey('dialog_verification_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const ValueKey('dialog_verification_status_badge'),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isReverted
                  ? '↩️ Alterações revertidas via backup'
                  : hasFailure
                      ? '⚠️ Analyzer encontrou $errCount erro(s)'
                      : '✅ Verificado (flutter analyze)',
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (verification != null &&
              hasFailure &&
              verification.errors.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final issue in verification.errors.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• ${issue.toDiagnosticLine()}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ] else if (verification != null &&
              hasFailure &&
              verification.errorSummary != null &&
              verification.errorSummary!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              verification.errorSummary!,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
              ),
            ),
          ],
          if (hasFailure &&
              _activeBackupDir != null &&
              _activeBackupDir!.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('dialog_rollback_button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: BorderSide(color: AppColors.warning.withOpacity(0.6)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: _isRevertingBackup ? null : _revertAppliedChanges,
              icon: _isRevertingBackup
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.warning,
                      ),
                    )
                  : const Icon(Icons.undo_rounded, size: 13),
              label: Text(
                _isRevertingBackup ? 'Revertendo...' : '↩️ Reverter Alterações',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
