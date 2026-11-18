import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/connected_device.dart';
import 'android_device_runner_service.dart';

/// Combined human-readable root-cause analysis and verified multi-file code
/// patches produced by FLRD's deep diagnostic analyzer or Gemini AI.
@immutable
class AppFixAnalysisResult {
  final String explanationMarkdown;
  final List<DiagnosticFilePatch> patches;
  final List<String> inspectedFiles;

  const AppFixAnalysisResult({
    required this.explanationMarkdown,
    this.patches = const [],
    this.inspectedFiles = const [],
  });
}

/// Result of applying (and backing up) a batch of [DiagnosticFilePatch] edits.
@immutable
class AppPatchApplyResult {
  final int appliedCount;
  final List<String> modifiedFiles;
  final List<String> skippedFiles;
  final String? backupDir;
  final bool clearedCxxCache;
  final String? errorMessage;

  const AppPatchApplyResult({
    required this.appliedCount,
    this.modifiedFiles = const [],
    this.skippedFiles = const [],
    this.backupDir,
    this.clearedCxxCache = false,
    this.errorMessage,
  });

  bool get isSuccess => appliedCount > 0 && errorMessage == null;
}

/// Collected project snippets and resolved paths passed into AI & local analyzers.
class CollectedDiagnosticContext {
  final String formattedContext;
  final List<String> inspectedFiles;
  final Map<String, String> snippetsByPath;
  final List<String> cacheHighlights;

  const CollectedDiagnosticContext({
    required this.formattedContext,
    this.inspectedFiles = const [],
    this.snippetsByPath = const {},
    this.cacheHighlights = const [],
  });
}

/// Deep project context collector, code-aware fix analyzer, terminal resolution
/// formatter, and backup-safe patch applicator for FLRD diagnostics.
class DiagnosticCodeFixService {
  const DiagnosticCodeFixService();

  static const int _maxInspectedFiles = 12;
  static const int _maxPerFileChars = 4200;
  static const int _maxTotalChars = 28000;
  static const int _maxNativeScanFiles = 260;

  static const List<String> _vulkanFocalAnchors = [
    'ggml_vk_load_shaders',
    'c.wait()',
    'c.get()',
    'bindPipeline',
    'ggml_vk_khr_cooperative_matrix_support',
    'GGML_VK_DISABLE_F16',
    'VK_VENDOR_ID_QUALCOMM',
  ];

  /// Formats a structured resolution block printed directly into FLRD's
  /// terminal output (Debug Android and interactive shell tabs).
  static List<String> formatTerminalResolutionLines(
    AndroidBuildDiagnostic diagnostic, {
    String? aiSummary,
  }) {
    final lines = <String>[
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
      '🔧 SUGESTÃO DE RESOLUÇÃO (TERMINAL FLRD)',
      '📌 Problema: ${diagnostic.title}',
    ];

    final loc = diagnostic.affectedLocation?.trim();
    if (loc != null && loc.isNotEmpty) {
      lines.add('📍 Local / Stack: $loc');
    }

    lines.add('🔎 Causa: ${diagnostic.explanation}');

    if (diagnostic.steps.isNotEmpty) {
      lines.add('📋 Passos recomendados:');
      for (var i = 0; i < diagnostic.steps.length; i++) {
        lines.add('   ${i + 1}. ${diagnostic.steps[i]}');
      }
    }

    final cmd = diagnostic.suggestedTerminalCommand?.trim();
    if (cmd != null && cmd.isNotEmpty) {
      lines.add('💻 Comando útil no terminal: $cmd');
    }

    if (diagnostic.hasSuggestedPatches) {
      final files = diagnostic.suggestedPatches
          .map((patch) => patch.relativePath)
          .toSet()
          .join(', ');
      lines.add(
        '🧩 Patches prontos para aplicar (${diagnostic.suggestedPatches.length}): $files — clique em "Aplicar Correções" no banner acima.',
      );
    }

    if (aiSummary != null && aiSummary.trim().isNotEmpty) {
      lines.add('🤖 Análise detalhada (IA):');
      final preview = aiSummary
          .trim()
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .take(12);
      for (final line in preview) {
        lines.add('   $line');
      }
    }

    lines.add('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return lines;
  }

  /// Collects targeted source snippets across Dart, Kotlin/Java, C++/CMake,
  /// nested native submodules (e.g. `ggml-vulkan.cpp`), and `.cxx/CMakeCache.txt`.
  static CollectedDiagnosticContext collectDiagnosticContext(
    String projectPath, {
    required List<String> crashLogs,
    String? affectedLocation,
  }) {
    final cleanRoot = projectPath.trim();
    if (cleanRoot.isEmpty) {
      return const CollectedDiagnosticContext(formattedContext: '');
    }

    final rootDir = Directory(cleanRoot);
    if (!rootDir.existsSync()) {
      return const CollectedDiagnosticContext(formattedContext: '');
    }

    final combinedText = '${affectedLocation ?? ''}\n${crashLogs.join('\n')}';
    final lowerCombined = combinedText.toLowerCase();
    final candidateRelPaths = <({String relPath, int? targetLine, bool deepFocal})>[];
    final seenPaths = <String>{};

    void addCandidate(
      String relPath, {
      int? targetLine,
      bool deepFocal = false,
    }) {
      final norm = relPath.replaceAll('\\', '/').trim();
      if (norm.isEmpty) return;
      final key = norm.toLowerCase();
      if (seenPaths.add(key)) {
        candidateRelPaths.add((
          relPath: norm,
          targetLine: targetLine,
          deepFocal: deepFocal,
        ));
      }
    }

    // 1. Referenced `lib/.../*.dart[:line]` and `package:<pkg>/.../*.dart[:line]`
    for (final m in RegExp(r'(lib[/\\][a-zA-Z0-9_./\\-]+\.dart)(?::(\d+))?')
        .allMatches(combinedText)) {
      addCandidate(
        m.group(1)!.replaceAll('\\', '/'),
        targetLine: int.tryParse(m.group(2) ?? ''),
      );
    }
    if (lowerCombined.contains('googlefonts') ||
        lowerCombined.contains('google_fonts') ||
        lowerCombined.contains('texttheme') ||
        lowerCombined.contains('app_theme.dart')) {
      addCandidate('lib/core/theme/app_theme.dart');
    }
    if (lowerCombined.contains('compilesdk') ||
        lowerCombined.contains('android sdk') ||
        lowerCombined.contains('build.gradle')) {
      addCandidate('android/app/build.gradle.kts');
      addCandidate('android/app/build.gradle');
    }
    for (final m in RegExp(
      r'package:([a-zA-Z0-9_]+)/([a-zA-Z0-9_./-]+\.dart)(?::(\d+))?',
    ).allMatches(combinedText)) {
      final candidate = 'lib/${m.group(2)!}';
      if (File(p.join(cleanRoot, candidate)).existsSync()) {
        addCandidate(candidate, targetLine: int.tryParse(m.group(3) ?? ''));
      }
    }

    // 2. Native / Vulkan / CMake / JNI context
    final isNativeOrBuild = lowerCombined.contains('adrenovk') ||
        lowerCombined.contains('vulkan') ||
        lowerCombined.contains('fatal signal') ||
        lowerCombined.contains('sigsegv') ||
        lowerCombined.contains('sigabrt') ||
        lowerCombined.contains('cmake') ||
        lowerCombined.contains('.so') ||
        lowerCombined.contains('jni') ||
        lowerCombined.contains('bad_alloc') ||
        lowerCombined.contains('outofdevicememory') ||
        lowerCombined.contains('ggml') ||
        lowerCombined.contains('unet') ||
        lowerCombined.contains('pipeline');

    final cacheHighlights = <String>[];
    if (isNativeOrBuild) {
      addCandidate('android/app/src/main/cpp/CMakeLists.txt');

      final cppDir = Directory(
        p.join(cleanRoot, 'android', 'app', 'src', 'main', 'cpp'),
      );
      if (cppDir.existsSync()) {
        try {
          final topCppFiles = cppDir
              .listSync(followLinks: false)
              .whereType<File>()
              .where((f) {
            final lowerName = p.basename(f.path).toLowerCase();
            return lowerName.endsWith('.cpp') ||
                lowerName.endsWith('.cc') ||
                lowerName.endsWith('.c') ||
                lowerName.endsWith('.h') ||
                lowerName.endsWith('.hpp');
          }).toList()
            ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

          for (final file in topCppFiles.take(4)) {
            addCandidate(p.relative(file.path, from: cleanRoot));
          }

          // Deep bounded scan of nested submodules (e.g. ggml-vulkan.cpp, stable-diffusion.h)
          final nestedTargets = _findNestedNativeTargets(
            cleanRoot: cleanRoot,
            cppDir: cppDir,
            lowerLogs: lowerCombined,
          );
          for (final target in nestedTargets) {
            addCandidate(target, deepFocal: true);
          }
        } catch (_) {}
      }

      // MainActivity.kt / MainActivity.java & Gradle ABI/build config
      for (final langDir in const ['kotlin', 'java']) {
        final srcDir = Directory(
          p.join(cleanRoot, 'android', 'app', 'src', 'main', langDir),
        );
        if (!srcDir.existsSync()) continue;
        try {
          for (final entity
              in srcDir.listSync(recursive: true, followLinks: false)) {
            if (entity is File) {
              final name = p.basename(entity.path);
              if (name == 'MainActivity.kt' ||
                  name == 'MainActivity.java' ||
                  combinedText.contains(p.basenameWithoutExtension(name))) {
                addCandidate(p.relative(entity.path, from: cleanRoot));
                break;
              }
            }
          }
        } catch (_) {}
      }

      cacheHighlights.addAll(_readNewestCmakeCacheHighlights(cleanRoot));
    }

    // 3. Flutter entrypoints & service callers
    addCandidate('lib/ai_service.dart');
    addCandidate('lib/main.dart');
    addCandidate('lib/screens.dart');
    addCandidate('android/app/build.gradle.kts');
    addCandidate('android/app/build.gradle');
    addCandidate('pubspec.yaml');

    final inspected = <String>[];
    final snippetsByPath = <String, String>{};
    final contextBuffer = StringBuffer();
    var totalChars = 0;

    if (cacheHighlights.isNotEmpty) {
      contextBuffer
        ..writeln('--- CMakeCache.txt (build nativo atual) ---')
        ..writeln(cacheHighlights.join('\n'))
        ..writeln();
    }

    for (final candidate in candidateRelPaths) {
      if (inspected.length >= _maxInspectedFiles ||
          totalChars >= _maxTotalChars) {
        break;
      }
      final file = File(p.join(cleanRoot, candidate.relPath));
      if (!file.existsSync()) continue;
      try {
        final len = file.lengthSync();
        final sizeCap = candidate.deepFocal ? 2 * 1024 * 1024 : 256 * 1024;
        if (len > sizeCap) continue;
        final raw = file.readAsStringSync();
        if (raw.trim().isEmpty) continue;

        final snippet = candidate.deepFocal && raw.length > _maxPerFileChars
            ? _extractFocalSections(raw, maxChars: _maxPerFileChars)
            : _sliceFileSnippet(
                raw,
                targetLine: candidate.targetLine,
                maxChars: _maxPerFileChars,
              );
        if (totalChars + snippet.length > _maxTotalChars &&
            inspected.isNotEmpty) {
          break;
        }
        inspected.add(candidate.relPath);
        snippetsByPath[candidate.relPath] = snippet;
        contextBuffer
          ..writeln('--- ${candidate.relPath} ---')
          ..writeln(snippet)
          ..writeln();
        totalChars += snippet.length;
      } catch (_) {}
    }

    return CollectedDiagnosticContext(
      formattedContext: contextBuffer.toString().trimRight(),
      inspectedFiles: inspected,
      snippetsByPath: snippetsByPath,
      cacheHighlights: cacheHighlights,
    );
  }

  /// Enriches an existing [AndroidBuildDiagnostic] using local source code
  /// inspection so even pre-AI cards and terminal output show verified root
  /// causes and ready-to-apply patches when deterministic fixes exist.
  static AndroidBuildDiagnostic enrichDiagnosticWithLocalAnalysis(
    AndroidBuildDiagnostic diagnostic, {
    required String? projectPath,
    required List<String> crashLogs,
  }) {
    final cleanRoot = (projectPath ?? '').trim();
    if (cleanRoot.isEmpty || !Directory(cleanRoot).existsSync()) {
      return diagnostic;
    }

    final analysis = analyzeProjectLocally(
      projectPath: cleanRoot,
      issueTitle: diagnostic.title,
      crashLogs: crashLogs.isNotEmpty ? crashLogs : diagnostic.relevantLogLines,
      affectedLocation: diagnostic.affectedLocation,
    );

    if (analysis.patches.isEmpty &&
        diagnostic.issueType != AndroidBuildIssueType.vulkanAdrenoPipelineCrash &&
        diagnostic.issueType !=
            AndroidBuildIssueType.nativeCrashSigsegvOrSigabrt) {
      return diagnostic;
    }

    final mergedPatches = mergeValidatedPatches(
      projectPath: cleanRoot,
      primary: diagnostic.suggestedPatches,
      secondary: analysis.patches,
    );

    final enhancedSteps = List<String>.from(diagnostic.steps);
    if (analysis.patches.isNotEmpty) {
      final patchSummaryStep =
          'Patches verificados prontos no FLRD (${analysis.patches.length} arquivo(s)): '
          '${analysis.patches.map((e) => e.relativePath).toSet().join(", ")}.';
      if (!enhancedSteps.any((s) => s.contains('Patches verificados'))) {
        enhancedSteps.insert(0, patchSummaryStep);
      }
    }

    return diagnostic.copyWith(
      suggestedPatches: mergedPatches,
      steps: enhancedSteps,
    );
  }

  /// Code-aware offline/local engineering analyzer that reads real project
  /// files on disk and produces deep PT-BR guidance plus verified file patches.
  static AppFixAnalysisResult analyzeProjectLocally({
    required String projectPath,
    required String issueTitle,
    required List<String> crashLogs,
    String? affectedLocation,
    CollectedDiagnosticContext? precollectedContext,
  }) {
    final context = precollectedContext ??
        collectDiagnosticContext(
          projectPath,
          crashLogs: crashLogs,
          affectedLocation: affectedLocation,
        );

    final joined = crashLogs.join('\n');
    final lower = '$issueTitle\n$joined\n${affectedLocation ?? ''}'.toLowerCase();
    final filesNote = context.inspectedFiles.isNotEmpty
        ? context.inspectedFiles.map((f) => '`$f`').join(', ')
        : 'nenhum arquivo fonte local lido';

    final buffer = StringBuffer()
      ..writeln('### 🛠️ Diagnóstico de Engenharia (Análise Local do Projeto)')
      ..writeln('**Erro:** $issueTitle');
    if (affectedLocation != null && affectedLocation.trim().isNotEmpty) {
      buffer.writeln('**Local / Stack:** `${affectedLocation.trim()}`');
    }
    buffer.writeln('**Arquivos inspecionados:** $filesNote');
    if (context.cacheHighlights.isNotEmpty) {
      buffer.writeln(
        '**Build CMake ativo:** `${context.cacheHighlights.take(3).join(" | ")}`',
      );
    }
    buffer.writeln();

    final patches = <DiagnosticFilePatch>[];

    final isVulkanAdreno = (lower.contains('adrenovk') ||
            lower.contains('failed to link shaders') ||
            lower.contains('pipeline create failed') ||
            lower.contains('vkcmdbindpipeline') ||
            lower.contains('ggml-vulkan')) &&
        (lower.contains('pipeline') ||
            lower.contains('shader') ||
            lower.contains('vkcmdbindpipeline') ||
            lower.contains('adrenovk'));

    if (isVulkanAdreno) {
      final vulkanReport = _analyzeVulkanAndJniBridge(
        projectPath: projectPath,
        context: context,
        outPatches: patches,
      );
      buffer.write(vulkanReport);
      return AppFixAnalysisResult(
        explanationMarkdown: buffer.toString().trimRight(),
        patches: patches,
        inspectedFiles: context.inspectedFiles,
      );
    }

    if (lower.contains('outofmemoryerror') ||
        lower.contains('std::bad_alloc') ||
        lower.contains('outofdevicememory') ||
        lower.contains('vk_error_out_of_device_memory') ||
        lower.contains('out of device memory')) {
      buffer
        ..writeln('**1. Causa Raiz Provável:**')
        ..writeln(
          'O processo esgotou a memória disponível — seja RAM nativa / VRAM compartilhada do Vulkan '
          '(`std::bad_alloc` / `OutOfDeviceMemory`) ao alocar tensores/modelos de IA, ou heap da JVM (`OutOfMemoryError`) com bitmaps grandes.',
        )
        ..writeln()
        ..writeln('**2. Correções Recomendadas:**')
        ..writeln('• **Libere recursos antes de nova alocação:** Descarregue o contexto/modelo anterior (`free`/`release`) antes de carregar outro modelo ou rodar `img2img`.')
        ..writeln('• **Reduza o consumo de memória:** Diminua resolução (`512x512`), `batch_size = 1`, `n_ctx` menor ou use quantização `Q4_K_M`/`Q4_0`.')
        ..writeln('• **Bitmaps no Android (Kotlin/Java):** Use `BitmapFactory.Options().inSampleSize` para redimensionar antes de enviar buffers via JNI e chame `bitmap.recycle()`.');
      return AppFixAnalysisResult(
        explanationMarkdown: buffer.toString().trimRight(),
        patches: patches,
        inspectedFiles: context.inspectedFiles,
      );
    }

    if (lower.contains('fatal signal') ||
        lower.contains('sigsegv') ||
        lower.contains('sigabrt') ||
        lower.contains('null pointer dereference') ||
        lower.contains('backtrace:')) {
      final hasNullResultReturn = _analyzeNativeBridgeSafety(
        projectPath: projectPath,
        context: context,
        outPatches: patches,
      );
      buffer
        ..writeln('**1. Causa Raiz Provável:**')
        ..writeln(
          lower.contains('sigabrt')
              ? 'Um módulo nativo C/C++ chamou `abort()` (`SIGABRT`) devido a `assert` falho, `GGML_ABORT` ou exceção C++ não tratada antes da fronteira JNI.'
              : 'O código nativo C/C++ tentou ler/escrever memória inválida (`SIGSEGV` — ponteiro nulo, objeto já liberado ou acesso fora dos limites do buffer).',
        );
      if (hasNullResultReturn) {
        buffer.writeln(
          '\n⚠️ Detectado acesso sem validação de `results[0].data == nullptr` na ponte JNI — um patch seguro está disponível.',
        );
      }
      buffer
        ..writeln()
        ..writeln('**2. Correções Recomendadas:**')
        ..writeln('• **Cheque retornos nulos em C++/JNI:** Nunca desreferencie contexto/modelo/pipeline sem validar `if (ctx == nullptr || results[0].data == nullptr) return ...;`.')
        ..writeln('• **Proteja fronteira JNI:** Valide `GetStringUTFChars` / `GetByteArrayElements`, verifique `env->ExceptionCheck()` e capture `std::exception` em `try/catch` antes de retornar ao Kotlin.')
        ..writeln('• **Sincronização de Threads:** Garanta que apenas uma chamada nativa use o mesmo contexto por vez (`std::mutex`) e nunca libere memória enquanto uma worker thread ainda a utiliza.');
      return AppFixAnalysisResult(
        explanationMarkdown: buffer.toString().trimRight(),
        patches: patches,
        inspectedFiles: context.inspectedFiles,
      );
    }

    if (lower.contains('install_failed_')) {
      final codeMatch = RegExp(r'INSTALL_FAILED_[A-Z0-9_]+').firstMatch(joined);
      final code = codeMatch?.group(0) ?? 'INSTALL_FAILED';
      buffer
        ..writeln('**1. Causa Raiz:**')
        ..writeln('O gerenciador de pacotes do Android rejeitou a instalação do APK com `$code`.')
        ..writeln()
        ..writeln('**2. Correções Recomendadas:**')
        ..writeln('• Para `VERSION_DOWNGRADE` ou `UPDATE_INCOMPATIBLE`: execute `adb uninstall <seu.applicationId>` e relance.')
        ..writeln('• Para `INSUFFICIENT_STORAGE`: libere espaço no aparelho e evite embutir modelos gigantes dentro de `assets/` do APK.')
        ..writeln('• Para `NO_MATCHING_ABIS`: confira `ndk { abiFilters "arm64-v8a" }` no `android/app/build.gradle`.');
      return AppFixAnalysisResult(
        explanationMarkdown: buffer.toString().trimRight(),
        patches: patches,
        inspectedFiles: context.inspectedFiles,
      );
    }

    if (lower.contains('not found') && lower.contains('adb') ||
        lower.contains('no devices/emulators found') ||
        lower.contains('device offline')) {
      buffer
        ..writeln('**1. Causa Raiz:**')
        ..writeln('A sessão ADB perdeu comunicação com o dispositivo físico ou emulador durante o deploy/execução.')
        ..writeln()
        ..writeln('**2. Correções Recomendadas:**')
        ..writeln('• Troque para uma porta USB direta (sem hub), verifique o cabo e desbloqueie a tela do celular.')
        ..writeln('• Confirme modo USB **Transferência de arquivos (MTP)** e **Depuração USB** ativa.')
        ..writeln('• Clique em **"Re-detectar & Rodar"** para atualizar o serial ADB e relançar.');
      return AppFixAnalysisResult(
        explanationMarkdown: buffer.toString().trimRight(),
        patches: patches,
        inspectedFiles: context.inspectedFiles,
      );
    }

    if (lower.contains('unhandled exception') ||
        lower.contains('exception caught by')) {
      final dartSnippet = context.snippetsByPath.entries.firstWhere(
        (e) => e.key.toLowerCase().endsWith('.dart'),
        orElse: () => const MapEntry('', ''),
      );
      buffer
        ..writeln('**1. Causa Raiz Provável:**')
        ..writeln(
          'Uma exceção Dart não tratada interrompeu o fluxo ou a renderização do widget'
          '${affectedLocation != null ? " em `$affectedLocation`" : ""}.',
        )
        ..writeln()
        ..writeln('**2. Correções Recomendadas:**')
        ..writeln('• Verifique uso de operador `!` em valores possivelmente nulos, acesso a índices vazios (`RangeError`) ou `setState` após `dispose` (`if (!mounted) return;`).')
        ..writeln('• Envolva chamadas assíncronas externas (I/O, canais nativos `MethodChannel`, HTTP) em blocos `try { ... } catch (e) { ... }` com feedback seguro na UI.');
      if (dartSnippet.key.isNotEmpty) {
        final previewLines = dartSnippet.value.split('\n').take(18).join('\n');
        buffer
          ..writeln()
          ..writeln('**Trecho inspecionado em `${dartSnippet.key}`:**')
          ..writeln('```dart')
          ..writeln(previewLines)
          ..writeln('```');
      }
      return AppFixAnalysisResult(
        explanationMarkdown: buffer.toString().trimRight(),
        patches: patches,
        inspectedFiles: context.inspectedFiles,
      );
    }

    final sdkMismatch =
        AndroidDeviceRunnerService.extractAndroidCompileSdkMismatch(joined);
    final isGoogleFontsTextThemeConflict =
        (lower.contains("the argument type 'texttheme") ||
                lower.contains('texttheme/*1*/')) &&
            (lower.contains('material_ui') ||
                lower.contains('text_theme.dart') ||
                lower.contains('googlefonts') ||
                lower.contains('google_fonts') ||
                lower.contains('app_theme.dart'));
    final dartErrorMatch = RegExp(
      r'([a-zA-Z0-9_./\\-]+\.dart):(\d+)(?::\d+)?:\s*Error:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(joined);
    final isDartCompileError = isGoogleFontsTextThemeConflict ||
        dartErrorMatch != null ||
        lower.contains('target kernel_snapshot_program failed') ||
        lower.contains('compileflutterbuilddebug');

    if (isDartCompileError || sdkMismatch != null) {
      if (isGoogleFontsTextThemeConflict ||
          lower.contains('googlefonts') ||
          lower.contains('texttheme')) {
        _collectGoogleFontsTextThemePatches(
          projectPath: projectPath,
          inspectedFiles: context.inspectedFiles,
          joinedLogs: joined,
          outPatches: patches,
        );
      }
      if (sdkMismatch != null) {
        _collectAndroidCompileSdkPatches(
          projectPath: projectPath,
          sdkMismatch: sdkMismatch,
          outPatches: patches,
        );
      }

      if (isGoogleFontsTextThemeConflict) {
        final dartFile = dartErrorMatch?.group(1)?.replaceAll('\\', '/') ??
            'lib/core/theme/app_theme.dart';
        buffer
          ..writeln('**1. Causa Raiz (Conflito `google_fonts` × `material_ui`):**')
          ..writeln(
            'A compilação Dart falhou em `$dartFile` porque `GoogleFonts.*TextTheme(...)` tentou trocar `TextTheme` entre `package:flutter/src/material/text_theme.dart` (`TextTheme/*1*/`) e `package:material_ui/src/text_theme.dart` (`TextTheme/*2*/`).',
          )
          ..writeln()
          ..writeln('**2. Solução Prática:**')
          ..writeln(
            '• Em `ThemeData(...)`, troque `textTheme: GoogleFonts.<fonte>TextTheme(...)` por `fontFamily: GoogleFonts.<fonte>().fontFamily` (retorna `String?`, eliminando a ambiguidade de `TextTheme`).',
          );
        if (sdkMismatch != null) {
          final pluginNote = sdkMismatch.plugins.isNotEmpty
              ? sdkMismatch.plugins.join(', ')
              : 'plugin Android';
          final currentNote = sdkMismatch.currentSdk != null
              ? ' (atual: `${sdkMismatch.currentSdk}`)'
              : '';
          buffer.writeln(
            '• Também atualize `compileSdk = ${sdkMismatch.requiredSdk}` em `${sdkMismatch.targetGradleFile}`$currentNote exigido por `$pluginNote`.',
          );
        }
      } else if (sdkMismatch != null) {
        final pluginNote = sdkMismatch.plugins.isNotEmpty
            ? sdkMismatch.plugins.join(', ')
            : 'plugin Android';
        final currentNote = sdkMismatch.currentSdk != null
            ? ' enquanto o projeto usa SDK `${sdkMismatch.currentSdk}`'
            : '';
        buffer
          ..writeln('**1. Causa Raiz (`compileSdk` Insuficiente):**')
          ..writeln(
            'O plugin `$pluginNote` exige compilação contra **Android SDK ${sdkMismatch.requiredSdk}**$currentNote.',
          )
          ..writeln()
          ..writeln('**2. Solução Prática:**')
          ..writeln(
            '• Defina `compileSdk = ${sdkMismatch.requiredSdk}` em `${sdkMismatch.targetGradleFile}` (bloco `android { ... }`).',
          )
          ..writeln(
            '• Depois de aplicar o ajuste, rode novamente o app no aparelho ou execute `flutter clean && flutter run`.',
          );
      } else {
        final dartFile = dartErrorMatch?.group(1)?.replaceAll('\\', '/');
        final dartLine = dartErrorMatch?.group(2);
        final dartMsg = dartErrorMatch?.group(3)?.trim();
        buffer
          ..writeln('**1. Causa Raiz (Erro de Compilação Dart):**')
          ..writeln(
            dartFile != null
                ? 'O compilador Dart (`compileFlutterBuildDebug` / `kernel_snapshot_program`) falhou em `$dartFile:${dartLine ?? '1'}`${dartMsg != null && dartMsg.isNotEmpty ? ': `$dartMsg`' : '.'}'
                : 'A tarefa Gradle `:app:compileFlutterBuildDebug` falhou por erro de compilação no código Dart.',
          )
          ..writeln()
          ..writeln('**2. Solução Prática:**')
          ..writeln(
            '• Corrija a assinatura, import ou tipo reportado em `${dartFile ?? filesNote}`.',
          )
          ..writeln(
            '• Rode `flutter pub get` e valide localmente com `flutter analyze` antes de relançar no dispositivo.',
          );
      }

      if (patches.isNotEmpty) {
        final patchedFiles =
            patches.map((e) => '`${e.relativePath}`').toSet().join(', ');
        buffer
          ..writeln()
          ..writeln('**3. Correção Automática Pronta (FLRD):**')
          ..writeln(
            '• ${patches.length} patch(es) validado(s) em $patchedFiles. Clique em **Ver & Aplicar Correções** para aplicar com backup automático em `.flrd/backups/`.',
          );
      }
      return AppFixAnalysisResult(
        explanationMarkdown: buffer.toString().trimRight(),
        patches: patches,
        inspectedFiles: context.inspectedFiles,
      );
    }

    buffer
      ..writeln('**1. Causa Raiz:**')
      ..writeln('Falha detectada durante o ciclo de build/execução Android: `$issueTitle`.')
      ..writeln()
      ..writeln('**2. Passos Recomendados:**')
      ..writeln('• Revise as últimas linhas do console e valide o ambiente (JDK 17, Android SDK, CMake/Ninja/MSVC).')
      ..writeln('• Execute `flutter clean` se caches antigos de Gradle/CMake estiverem persistindo.')
      ..writeln('• Configure uma chave Gemini em Configurações/IA para análise contextual avançada.');
    return AppFixAnalysisResult(
      explanationMarkdown: buffer.toString().trimRight(),
      patches: patches,
      inspectedFiles: context.inspectedFiles,
    );
  }

  static void _collectGoogleFontsTextThemePatches({
    required String projectPath,
    required List<String> inspectedFiles,
    required String joinedLogs,
    required List<DiagnosticFilePatch> outPatches,
  }) {
    final canonicalRoot = p.normalize(p.absolute(projectPath.trim()));
    if (canonicalRoot.isEmpty) return;

    final candidateRelPaths = <String>{
      for (final file in inspectedFiles)
        if (file.toLowerCase().endsWith('.dart')) file.replaceAll('\\', '/'),
      for (final m in RegExp(r'(lib[/\\][a-zA-Z0-9_./\\-]+\.dart)')
          .allMatches(joinedLogs))
        m.group(1)!.replaceAll('\\', '/'),
      'lib/core/theme/app_theme.dart',
    };

    final seenFiles = <String>{};
    final pattern = RegExp(
      r'([ \t]*)textTheme\s*:\s*GoogleFonts\.([a-zA-Z0-9_]+)TextTheme\s*\(',
    );

    for (final rawRel in candidateRelPaths) {
      final relPath = rawRel.replaceAll('\\', '/').trim();
      if (relPath.isEmpty || !seenFiles.add(relPath.toLowerCase())) continue;

      final absPath = p.normalize(p.join(canonicalRoot, relPath));
      if (!p.isWithin(canonicalRoot, absPath)) continue;

      final file = File(absPath);
      if (!file.existsSync()) continue;

      String normalized;
      try {
        normalized = file.readAsStringSync().replaceAll('\r\n', '\n');
      } catch (_) {
        continue;
      }

      var lastPatchedEnd = 0;
      for (final m in pattern.allMatches(normalized)) {
        if (m.start < lastPatchedEnd) continue;

        final closeParenIdx =
            _findMatchingClosingParen(normalized, m.end - 1);
        if (closeParenIdx == null) continue;

        var afterIdx = closeParenIdx + 1;
        while (afterIdx < normalized.length &&
            (normalized[afterIdx] == ' ' ||
                normalized[afterIdx] == '\t' ||
                normalized[afterIdx] == '\r' ||
                normalized[afterIdx] == '\n')) {
          afterIdx++;
        }
        final hasComma =
            afterIdx < normalized.length && normalized[afterIdx] == ',';
        final endIdx = hasComma ? afterIdx + 1 : closeParenIdx + 1;
        final trailingComma = hasComma ? ',' : '';

        final indent = m.group(1)!;
        final fontMethod = m.group(2)!;
        final insideCopyWith = _isInsideCopyWithCall(normalized, m.start);

        final String replacementExpr;
        if (insideCopyWith) {
          final innerArg = normalized.substring(m.end, closeParenIdx).trim();
          if (innerArg.isEmpty) continue;
          replacementExpr =
              '${indent}textTheme: ($innerArg).apply(fontFamily: GoogleFonts.$fontMethod().fontFamily)$trailingComma';
        } else {
          replacementExpr =
              '${indent}fontFamily: GoogleFonts.$fontMethod().fontFamily$trailingComma';
        }

        final expandedStart =
            _expandPrecedingLinesUntilUnique(normalized, m.start, endIdx);
        final prefix = normalized.substring(expandedStart, m.start);
        final rawSearch = normalized.substring(m.start, endIdx);

        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relPath,
            description: insideCopyWith
                ? 'Substituir GoogleFonts.${fontMethod}TextTheme por TextTheme.apply(fontFamily: ...) em $relPath.'
                : 'Substituir GoogleFonts.${fontMethod}TextTheme por fontFamily: GoogleFonts.$fontMethod().fontFamily em $relPath.',
            searchText: '$prefix$rawSearch',
            replaceText: '$prefix$replacementExpr',
          ),
        );
        lastPatchedEnd = endIdx;
      }
    }
  }

  static void _collectAndroidCompileSdkPatches({
    required String projectPath,
    required ({
      String? currentSdk,
      String requiredSdk,
      List<String> plugins,
      String targetGradleFile,
    }) sdkMismatch,
    required List<DiagnosticFilePatch> outPatches,
  }) {
    final requiredInt = int.tryParse(sdkMismatch.requiredSdk);
    if (requiredInt == null || requiredInt <= 0) return;

    final canonicalRoot = p.normalize(p.absolute(projectPath.trim()));
    if (canonicalRoot.isEmpty) return;

    const gradleCandidates = <String>[
      'android/app/build.gradle.kts',
      'android/app/build.gradle',
    ];

    final pluginLabel = sdkMismatch.plugins.isNotEmpty
        ? sdkMismatch.plugins.join(', ')
        : 'plugin Android';

    final patterns = <RegExp>[
      RegExp(
        r'^([ \t]*compileSdk\s*=\s*)(\d+|flutter\.compileSdkVersion)\b([ \t]*(?://.*)?)$',
        multiLine: true,
      ),
      RegExp(
        r'^([ \t]*compileSdkVersion\s*(?:=|\s)\s*)(\d+|flutter\.compileSdkVersion)\b([ \t]*(?://.*)?)$',
        multiLine: true,
      ),
      RegExp(
        r'^([ \t]*compileSdk\s+)(\d+|flutter\.compileSdkVersion)\b([ \t]*(?://.*)?)$',
        multiLine: true,
      ),
    ];

    for (final relPath in gradleCandidates) {
      final absPath = p.normalize(p.join(canonicalRoot, relPath));
      if (!p.isWithin(canonicalRoot, absPath)) continue;

      final file = File(absPath);
      if (!file.existsSync()) continue;

      String normalized;
      try {
        normalized = file.readAsStringSync().replaceAll('\r\n', '\n');
      } catch (_) {
        continue;
      }

      RegExpMatch? match;
      for (final pattern in patterns) {
        match = pattern.firstMatch(normalized);
        if (match != null) break;
      }
      if (match == null) continue;

      final currentValue = match.group(2)!.trim();
      final currentInt = int.tryParse(currentValue);
      if (currentInt != null && currentInt >= requiredInt) {
        return;
      }

      final prefixOp = match.group(1)!;
      final suffixComment = match.group(3) ?? '';
      final rawSearch = match.group(0)!;
      final rawReplace = '$prefixOp$requiredInt$suffixComment';
      final expandedStart =
          _expandPrecedingLinesUntilUnique(normalized, match.start, match.end);
      final lineContextPrefix = normalized.substring(expandedStart, match.start);

      outPatches.add(
        DiagnosticFilePatch(
          relativePath: relPath,
          description:
              'Atualizar compileSdk de $currentValue para $requiredInt em $relPath (exigido por $pluginLabel).',
          searchText: '$lineContextPrefix$rawSearch',
          replaceText: '$lineContextPrefix$rawReplace',
        ),
      );
      return;
    }
  }

  static int? _findMatchingClosingParen(String source, int openParenIndex) {
    if (openParenIndex < 0 ||
        openParenIndex >= source.length ||
        source[openParenIndex] != '(') {
      return null;
    }
    var depth = 0;
    var i = openParenIndex;
    while (i < source.length) {
      final ch = source[i];
      if (ch == "'" || ch == '"') {
        final quote = ch;
        i++;
        while (i < source.length) {
          if (source[i] == r'\') {
            i += 2;
            continue;
          }
          if (source[i] == quote) break;
          i++;
        }
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }
    return null;
  }

  static bool _isInsideCopyWithCall(String source, int offset) {
    var depth = 0;
    for (var i = offset - 1; i >= 0; i--) {
      final ch = source[i];
      if (ch == ')') {
        depth++;
      } else if (ch == '(') {
        if (depth > 0) {
          depth--;
        } else {
          final start = (i - 24).clamp(0, i);
          final before = source.substring(start, i);
          return RegExp(r'\.copyWith\s*$').hasMatch(before);
        }
      }
    }
    return false;
  }

  static int _expandPrecedingLinesUntilUnique(
    String source,
    int startOffset,
    int endOffset,
  ) {
    var cursor = startOffset;
    if (_countOccurrences(source, source.substring(cursor, endOffset)) <= 1) {
      return cursor;
    }
    for (var step = 0; step < 5 && cursor > 0; step++) {
      final prevNewline = source.lastIndexOf('\n', cursor - 1);
      cursor = prevNewline == -1 ? 0 : prevNewline + 1;
      // Keep stepping back until we include at least one full preceding line if cursor started mid-line.
      if (step == 0 && cursor == startOffset && prevNewline > 0) {
        final earlierNewline = source.lastIndexOf('\n', prevNewline - 1);
        cursor = earlierNewline == -1 ? 0 : earlierNewline + 1;
      }
      if (_countOccurrences(source, source.substring(cursor, endOffset)) <= 1) {
        return cursor;
      }
      if (cursor > 0 && source[cursor - 1] == '\n') {
        cursor = cursor - 1;
        final lineStart = source.lastIndexOf('\n', cursor > 0 ? cursor - 1 : 0);
        cursor = lineStart == -1 ? 0 : lineStart + 1;
        if (_countOccurrences(source, source.substring(cursor, endOffset)) <= 1) {
          return cursor;
        }
      }
    }
    return cursor;
  }

  static int _countOccurrences(String source, String needle) {
    if (needle.isEmpty) return 0;
    var count = 0;
    var idx = 0;
    while (true) {
      final found = source.indexOf(needle, idx);
      if (found == -1) break;
      count++;
      idx = found + needle.length;
    }
    return count;
  }

  /// Extracts a fenced JSON `{ "patches": [...] }` block from an AI response,
  /// strips it from the displayed markdown, and keeps only patches whose target
  /// file exists safely inside [projectPath] and contains [searchText].
  static AppFixAnalysisResult extractAndValidateAiResponse({
    required String rawAiText,
    required String projectPath,
    required List<String> inspectedFiles,
  }) {
    final jsonBlockRegex = RegExp(
      r'```json\s*(\{[\s\S]*?"patches"[\s\S]*?\})\s*```',
      caseSensitive: false,
    );
    final match = jsonBlockRegex.firstMatch(rawAiText);
    var cleanedMarkdown = rawAiText;
    final parsedPatches = <DiagnosticFilePatch>[];

    if (match != null) {
      cleanedMarkdown = rawAiText.replaceRange(match.start, match.end, '').trim();
      final jsonStr = match.group(1) ?? '';
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic> && decoded['patches'] is List) {
          for (final item in decoded['patches'] as List) {
            if (item is Map<String, dynamic>) {
              final rel = (item['relativePath'] ?? '').toString().trim();
              final desc = (item['description'] ?? 'Correção sugerida pela IA')
                  .toString()
                  .trim();
              final search = (item['searchText'] ?? '').toString();
              final replace = (item['replaceText'] ?? '').toString();
              if (rel.isNotEmpty && search.isNotEmpty && search != replace) {
                parsedPatches.add(
                  DiagnosticFilePatch(
                    relativePath: rel.replaceAll('\\', '/'),
                    description: desc,
                    searchText: search,
                    replaceText: replace,
                  ),
                );
              }
            }
          }
        }
      } catch (_) {
        // Leave markdown intact if JSON block is malformed.
      }
    }

    final validated = filterValidPatches(
      projectPath: projectPath,
      patches: parsedPatches,
    );

    return AppFixAnalysisResult(
      explanationMarkdown:
          cleanedMarkdown.isNotEmpty ? cleanedMarkdown : rawAiText.trim(),
      patches: validated,
      inspectedFiles: inspectedFiles,
    );
  }

  /// Merges two patch lists without duplicating the same `(relativePath, searchText)`
  /// and guarantees all returned patches match actual files inside [projectPath].
  static List<DiagnosticFilePatch> mergeValidatedPatches({
    required String projectPath,
    required List<DiagnosticFilePatch> primary,
    required List<DiagnosticFilePatch> secondary,
  }) {
    final combined = <DiagnosticFilePatch>[];
    final seen = <String>{};

    for (final patch in [...primary, ...secondary]) {
      final key =
          '${patch.relativePath.replaceAll('\\', '/').toLowerCase()}::${patch.searchText}';
      if (seen.add(key)) {
        combined.add(patch);
      }
    }
    return filterValidPatches(projectPath: projectPath, patches: combined);
  }

  static ({String matchedSearch, String normalizedReplace})? _resolveLineEndingMatch(
    String fileContent,
    DiagnosticFilePatch patch,
  ) {
    if (fileContent.contains(patch.searchText)) {
      final hasCrlf = fileContent.contains('\r\n');
      final replace = hasCrlf && !patch.replaceText.contains('\r\n')
          ? patch.replaceText.replaceAll('\n', '\r\n')
          : patch.replaceText;
      return (matchedSearch: patch.searchText, normalizedReplace: replace);
    }

    if (fileContent.contains('\r\n') && !patch.searchText.contains('\r\n')) {
      final crlfSearch = patch.searchText.replaceAll('\n', '\r\n');
      if (fileContent.contains(crlfSearch)) {
        final crlfReplace = patch.replaceText.replaceAll('\n', '\r\n');
        return (matchedSearch: crlfSearch, normalizedReplace: crlfReplace);
      }
    }
    return null;
  }

  /// Filters [patches] to those strictly inside [projectPath] whose exact
  /// [DiagnosticFilePatch.searchText] exists in the target file.
  static List<DiagnosticFilePatch> filterValidPatches({
    required String projectPath,
    required List<DiagnosticFilePatch> patches,
  }) {
    final cleanRoot = projectPath.trim();
    if (cleanRoot.isEmpty || patches.isEmpty) return const [];
    final canonicalRoot = p.normalize(p.absolute(cleanRoot));
    final rootDir = Directory(canonicalRoot);
    if (!rootDir.existsSync()) return const [];

    final valid = <DiagnosticFilePatch>[];
    final simulatedByPath = <String, String>{};

    for (final patch in patches) {
      if (!patch.isValid) continue;
      final normalizedRel = patch.relativePath.replaceAll('\\', '/').trim();
      final targetPath = p.normalize(p.join(canonicalRoot, normalizedRel));
      if (!p.isWithin(canonicalRoot, targetPath)) continue;

      final file = File(targetPath);
      if (!file.existsSync()) continue;

      try {
        final content = simulatedByPath[targetPath] ?? file.readAsStringSync();
        final resolved = _resolveLineEndingMatch(content, patch);
        if (resolved == null) continue;
        // Simulate chaining multiple patches against the same file cleanly.
        simulatedByPath[targetPath] = content.replaceFirst(
          resolved.matchedSearch,
          resolved.normalizedReplace,
        );
        valid.add(
          DiagnosticFilePatch(
            relativePath: normalizedRel,
            description: patch.description,
            searchText: resolved.matchedSearch,
            replaceText: resolved.normalizedReplace,
          ),
        );
      } catch (_) {}
    }
    return valid;
  }

  /// Applies [patches] safely inside [projectPath], creating timestamped
  /// backups in `.flrd/backups/<timestamp>/` and clearing stale `.cxx` caches
  /// whenever C++/CMake files are modified.
  static Future<AppPatchApplyResult> applyPatches({
    required String projectPath,
    required List<DiagnosticFilePatch> patches,
  }) async {
    final cleanRoot = projectPath.trim();
    if (cleanRoot.isEmpty) {
      return const AppPatchApplyResult(
        appliedCount: 0,
        errorMessage: 'Caminho do projeto não informado.',
      );
    }

    final canonicalRoot = p.normalize(p.absolute(cleanRoot));
    final rootDir = Directory(canonicalRoot);
    if (!rootDir.existsSync()) {
      return AppPatchApplyResult(
        appliedCount: 0,
        errorMessage: 'Pasta do projeto não encontrada: $cleanRoot',
      );
    }

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backupRoot =
        p.join(canonicalRoot, '.flrd', 'backups', 'patch_$stamp');
    final backedUpFiles = <String>{};
    final modifiedFiles = <String>[];
    final skippedFiles = <String>[];
    var touchedNativeOrCmake = false;

    for (final patch in patches) {
      final normalizedRel = patch.relativePath.replaceAll('\\', '/').trim();
      if (!patch.isValid) {
        skippedFiles.add('$normalizedRel (patch inválido)');
        continue;
      }

      final targetPath = p.normalize(p.join(canonicalRoot, normalizedRel));
      if (!p.isWithin(canonicalRoot, targetPath)) {
        skippedFiles.add('$normalizedRel (caminho fora do projeto)');
        continue;
      }

      final targetFile = File(targetPath);
      if (!targetFile.existsSync()) {
        skippedFiles.add('$normalizedRel (arquivo não existe)');
        continue;
      }

      try {
        final currentContent = targetFile.readAsStringSync();
        final resolved = _resolveLineEndingMatch(currentContent, patch);
        if (resolved == null) {
          skippedFiles.add('$normalizedRel (trecho esperado não encontrado)');
          continue;
        }

        if (backedUpFiles.add(normalizedRel)) {
          final backupFile = File(p.join(backupRoot, normalizedRel));
          backupFile.parent.createSync(recursive: true);
          backupFile.writeAsStringSync(currentContent);
        }

        final updatedContent = currentContent.replaceFirst(
          resolved.matchedSearch,
          resolved.normalizedReplace,
        );
        targetFile.writeAsStringSync(updatedContent);
        if (!modifiedFiles.contains(normalizedRel)) {
          modifiedFiles.add(normalizedRel);
        }

        final lowerRel = normalizedRel.toLowerCase();
        if (lowerRel.endsWith('.cpp') ||
            lowerRel.endsWith('.cc') ||
            lowerRel.endsWith('.c') ||
            lowerRel.endsWith('.h') ||
            lowerRel.endsWith('.hpp') ||
            lowerRel.endsWith('cmakelists.txt')) {
          touchedNativeOrCmake = true;
        }
      } catch (e) {
        skippedFiles.add('$normalizedRel (erro: $e)');
      }
    }

    if (modifiedFiles.isEmpty) {
      return AppPatchApplyResult(
        appliedCount: 0,
        skippedFiles: skippedFiles,
        errorMessage: skippedFiles.isNotEmpty
            ? 'Nenhum patch pôde ser aplicado (${skippedFiles.join("; ")}).'
            : 'Nenhum patch aplicável selecionado.',
      );
    }

    var clearedCxx = false;
    if (touchedNativeOrCmake) {
      for (final cxxRel in const ['android/app/.cxx', 'build/.cxx']) {
        final cxxDir = Directory(p.join(canonicalRoot, cxxRel));
        if (cxxDir.existsSync()) {
          try {
            cxxDir.deleteSync(recursive: true);
            clearedCxx = true;
          } catch (_) {}
        }
      }
    }

    return AppPatchApplyResult(
      appliedCount: modifiedFiles.length,
      modifiedFiles: modifiedFiles,
      skippedFiles: skippedFiles,
      backupDir: backupRoot,
      clearedCxxCache: clearedCxx,
    );
  }

  /// Restores original file contents from a previously created `.flrd/backups/...` folder.
  static Future<List<String>> revertBackup({
    required String projectPath,
    required String backupDir,
  }) async {
    final canonicalRoot = p.normalize(p.absolute(projectPath.trim()));
    final backupRoot = p.normalize(p.absolute(backupDir.trim()));
    if (!p.isWithin(canonicalRoot, backupRoot)) return const [];

    final dir = Directory(backupRoot);
    if (!dir.existsSync()) return const [];

    final restored = <String>[];
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relPath = p.relative(entity.path, from: backupRoot);
      final targetPath = p.normalize(p.join(canonicalRoot, relPath));
      if (!p.isWithin(canonicalRoot, targetPath)) continue;
      try {
        final content = entity.readAsStringSync();
        File(targetPath).writeAsStringSync(content);
        restored.add(relPath.replaceAll('\\', '/'));
      } catch (_) {}
    }
    return restored;
  }

  static String _analyzeVulkanAndJniBridge({
    required String projectPath,
    required CollectedDiagnosticContext context,
    required List<DiagnosticFilePatch> outPatches,
  }) {
    final findings = <String>[];
    final fixes = <String>[];

    // 1. Check ggml-vulkan.cpp anywhere under android/app/src/main/cpp
    final vulkanFiles = _findFilesByName(
      Directory(p.join(projectPath, 'android', 'app', 'src', 'main', 'cpp')),
      const ['ggml-vulkan.cpp'],
    );
    for (final vkFile in vulkanFiles) {
      final relVk = p.relative(vkFile.path, from: projectPath).replaceAll('\\', '/');
      final vkSrc = _safeRead(vkFile, maxBytes: 2 * 1024 * 1024);
      if (vkSrc == null) continue;

      final waitMatch = RegExp(
        r'for\s*\(\s*auto\s*&\s*c\s*:\s*compiles\s*\)\s*\{(\r?\n)([ \t]*)c\.wait\(\);(\r?\n)([ \t]*)\}',
      ).firstMatch(vkSrc);
      if (waitMatch != null) {
        final exactWait = waitMatch.group(0)!;
        final replacementWait = exactWait.replaceFirst('c.wait();', 'c.get();');
        findings.add(
          '• **Exceção engolida em `$relVk` (`ggml_vk_load_shaders`):** `c.wait()` ignora erros de compilação de shaders Adreno (`Pipeline create failed`), deixando `pipeline->pipeline == VK_NULL_HANDLE` e disparando `SIGSEGV (0x8)` em `vkCmdBindPipeline`.',
        );
        fixes.add(
          '• Trocar `c.wait()` por `c.get()` em `$relVk` + adicionar `GGML_ASSERT(pipeline && pipeline->pipeline != VK_NULL_HANDLE);` antes de `bindPipeline`.',
        );
        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relVk,
            description:
                'Propagar exceções de shader Vulkan via c.get() em ggml_vk_load_shaders',
            searchText: exactWait,
            replaceText: replacementWait,
          ),
        );
      }

      // Guard bindPipeline against null VkPipeline
      const bindNeedle =
          'subctx->s->buffer->buf.bindPipeline(vk::PipelineBindPoint::eCompute, pipeline->pipeline);';
      if (vkSrc.contains(bindNeedle) &&
          !vkSrc.contains('pipeline->pipeline != VK_NULL_HANDLE')) {
        findings.add(
          '• **Falta de guarda contra `VK_NULL_HANDLE` em `$relVk`:** `bindPipeline` é invocado sem checar `pipeline->pipeline != VK_NULL_HANDLE`.',
        );
        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relVk,
            description:
                'Validar pipeline->pipeline != VK_NULL_HANDLE antes de vkCmdBindPipeline',
            searchText: bindNeedle,
            replaceText:
                'GGML_ASSERT(pipeline && pipeline->pipeline != VK_NULL_HANDLE);\n    $bindNeedle',
          ),
        );
      }

      // Check Qualcomm Adreno cooperative matrix blacklist
      const amdDefaultSwitch =
          'default:\n        return true;';
      const amdDefaultSwitchCrlf =
          'default:\r\n        return true;';
      if (vkSrc.contains('ggml_vk_khr_cooperative_matrix_support') &&
          !vkSrc.contains('case VK_VENDOR_ID_QUALCOMM') &&
          (vkSrc.contains(amdDefaultSwitch) ||
              vkSrc.contains(amdDefaultSwitchCrlf))) {
        final isCrlf = vkSrc.contains(amdDefaultSwitchCrlf);
        final nl = isCrlf ? '\r\n' : '\n';
        findings.add(
          '• **Adreno sem bloqueio de `COOPMAT` em `$relVk` (`ggml_vk_khr_cooperative_matrix_support`):** Apenas Intel e AMD são filtrados; GPUs Qualcomm Adreno caem no `default: return true;`, ativando pipelines `coopmat` instáveis na UNet.',
        );
        fixes.add(
          '• Desabilitar `VK_KHR_cooperative_matrix` para `VK_VENDOR_ID_QUALCOMM` em `$relVk`.',
        );
        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relVk,
            description:
                'Desabilitar cooperative matrix para Qualcomm Adreno (VK_VENDOR_ID_QUALCOMM)',
            searchText: isCrlf ? amdDefaultSwitchCrlf : amdDefaultSwitch,
            replaceText:
                'case VK_VENDOR_ID_QUALCOMM:$nl        return false;$nl    default:$nl        return true;',
          ),
        );
      }
    }

    // 2. Check JNI native wrapper (*.cpp with new_sd_ctx) + Dart/Kotlin MethodChannel bridge
    final jniCppFiles = _findTopLevelCppWithPattern(
      Directory(p.join(projectPath, 'android', 'app', 'src', 'main', 'cpp')),
      'new_sd_ctx',
    );
    final ktFiles = _findFilesByName(
      Directory(p.join(projectPath, 'android', 'app', 'src', 'main')),
      const ['MainActivity.kt'],
    );
    final aiDartFile = File(p.join(projectPath, 'lib', 'ai_service.dart'));
    final dartAiSrc = aiDartFile.existsSync() ? _safeRead(aiDartFile) : null;

    for (final cppFile in jniCppFiles) {
      final relCpp =
          p.relative(cppFile.path, from: projectPath).replaceAll('\\', '/');
      final cppSrc = _safeRead(cppFile);
      if (cppSrc == null) continue;

      final missingDisableF16 = !cppSrc.contains('GGML_VK_DISABLE_F16');
      final missingConvDirect = !cppSrc.contains('diffusion_conv_direct');
      final forcesQ8Wtype = cppSrc.contains('ctx_params.wtype = SD_TYPE_Q8_0;');
      final missingNullDataCheck = cppSrc.contains('if (results == nullptr)') &&
          !cppSrc.contains('results[0].data == nullptr');

      // Detect img2img MethodChannel -> Kotlin -> JNI mismatch
      File? mainKtFile;
      String? ktSrc;
      var hasImg2ImgMismatch = false;
      if (ktFiles.isNotEmpty) {
        mainKtFile = ktFiles.first;
        ktSrc = _safeRead(mainKtFile);
        if (ktSrc != null &&
            (dartAiSrc?.contains("'initImagePath'") ?? false) &&
            !ktSrc.contains('initImagePath') &&
            cppSrc.contains('sd_img_gen_params_init')) {
          hasImg2ImgMismatch = true;
          final relKt = p
              .relative(mainKtFile.path, from: projectPath)
              .replaceAll('\\', '/');
          findings.add(
            '• **Fluxo `img2img`/`inpaint` desconectado entre Dart, Kotlin e C++:** `lib/ai_service.dart` envia `initImagePath`, `maskImagePath` e `denoisingStrength`, mas `$relKt` e `$relCpp` os ignoram (além de `vae_decode_only` permanecer `true`, bloqueando o encoder VAE quando há imagem base).',
          );
          fixes.add(
            '• Decodificar `initImagePath` / `maskImagePath` no Kotlin e encaminhar `initRgbBytes`, `maskGrayBytes`, `denoisingStrength` + `vae_decode_only = !has_init` ao C++.',
          );
        }
      }

      if (missingDisableF16 || missingConvDirect) {
        findings.add(
          '• **Driver Adreno Vulkan sem proteções FP16/CoopMat em `$relCpp`:** O contexto nativo `new_sd_ctx(&ctx_params)` inicia sem `GGML_VK_DISABLE_F16=1`, `GGML_VK_DISABLE_COOPMAT=1` nem `diffusion_conv_direct = true`, disparando pipelines FP16/`im2col` incompatíveis no `UNetModel::compute`.',
        );
        fixes.add(
          '• Injetar `setenv("GGML_VK_DISABLE_COOPMAT", "1", 1)`, `setenv("GGML_VK_DISABLE_COOPMAT2", "1", 1)`, `setenv("GGML_VK_DISABLE_F16", "1", 1)` antes de `new_sd_ctx` e ativar `diffusion_conv_direct = true` / `vae_conv_direct = true` em `$relCpp`.',
        );
      }

      if (forcesQ8Wtype) {
        findings.add(
          '• **Sobrescrita forçada em `$relCpp`:** `ctx_params.wtype = SD_TYPE_Q8_0;` ignora o tipo nativo do modelo GGUF carregado.',
        );
      }

      if (missingNullDataCheck) {
        findings.add(
          '• **Risco de ponteiro nulo no retorno em `$relCpp`:** `if (results == nullptr)` não verifica `results[0].data == nullptr` antes de copiar pixels ao array JNI.',
        );
      }

      // Build safe, non-overlapping patch(es) for cpp & kt when anchors match
      if (hasImg2ImgMismatch && ktSrc != null && mainKtFile != null) {
        _tryBuildCoordinatedImg2ImgPatches(
          relKt: p.relative(mainKtFile.path, from: projectPath).replaceAll('\\', '/'),
          ktSrc: ktSrc,
          relCpp: relCpp,
          cppSrc: cppSrc,
          outPatches: outPatches,
        );
      } else {
        _tryBuildStandaloneCppVulkanPatches(
          relCpp: relCpp,
          cppSrc: cppSrc,
          missingDisableF16: missingDisableF16,
          missingConvDirect: missingConvDirect,
          forcesQ8Wtype: forcesQ8Wtype,
          missingNullDataCheck: missingNullDataCheck,
          outPatches: outPatches,
        );
      }
    }

    if (context.cacheHighlights.isNotEmpty) {
      findings.add(
        '• **Estado real do build em `.cxx/CMakeCache.txt`:** `${context.cacheHighlights.take(3).join(" | ")}` (ou seja, alterações em C++ exigem limpeza de `.cxx/` antes do rebuild).',
      );
    }

    final report = StringBuffer()..writeln('**1. Causa Raiz Exata Detectada no Código:**');
    if (findings.isEmpty) {
      report
        ..writeln(
          'O compilador de shaders do driver **Adreno Vulkan** falhou ao linkar um compute shader '
          '(`Failed to link shaders` / `Pipeline create failed`). Quando `ggml-vulkan` não checa o retorno, '
          'chama `vkCmdBindPipeline` com `VK_NULL_HANDLE` e causa `SIGSEGV (0x8)`.',
        )
        ..writeln()
        ..writeln('**2. Correções Recomendadas:**')
        ..writeln('• Defina `GGML_VK_DISABLE_COOPMAT=1`, `GGML_VK_DISABLE_COOPMAT2=1` e `GGML_VK_DISABLE_F16=1` (ou `GGML_VULKAN_COOPMAT=OFF` / fallback em CPU) antes de inicializar o contexto Vulkan nativo.')
        ..writeln('• Habilite `diffusion_conv_direct = true` / `vae_conv_direct = true` e propague falhas de pipeline via `c.get()`.')
        ..writeln('• Valide dimensões múltiplas de 64 (ex.: `512x512`) e checagem de ponteiros `VK_NULL_HANDLE` / `results[0].data`.');
    } else {
      for (final f in findings) {
        report.writeln(f);
      }
      report.writeln();
      report.writeln('**2. Plano de Correção Direta:**');
      for (final fix in fixes) {
        report.writeln(fix);
      }
      if (outPatches.isNotEmpty) {
        report.writeln(
          '• **Pronto para aplicar no FLRD:** ${outPatches.length} patch(es) verificado(s) podem ser aplicados com preview e backup automático em `.flrd/backups/`.',
        );
      }
    }

    return report.toString().trimRight();
  }

  static bool _analyzeNativeBridgeSafety({
    required String projectPath,
    required CollectedDiagnosticContext context,
    required List<DiagnosticFilePatch> outPatches,
  }) {
    var foundUnsafeReturn = false;
    final jniCppFiles = _findTopLevelCppWithPattern(
      Directory(p.join(projectPath, 'android', 'app', 'src', 'main', 'cpp')),
      'generate_image',
    );
    for (final cppFile in jniCppFiles) {
      final cppSrc = _safeRead(cppFile);
      if (cppSrc == null) continue;
      const unsafeCheck = 'if (results == nullptr) {\n';
      const unsafeCheckCrlf = 'if (results == nullptr) {\r\n';
      if ((cppSrc.contains(unsafeCheck) || cppSrc.contains(unsafeCheckCrlf)) &&
          !cppSrc.contains('results[0].data == nullptr')) {
        foundUnsafeReturn = true;
        final isCrlf = cppSrc.contains(unsafeCheckCrlf);
        final relCpp =
            p.relative(cppFile.path, from: projectPath).replaceAll('\\', '/');
        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relCpp,
            description: 'Validar results[0].data == nullptr antes de copiar pixels',
            searchText: isCrlf
                ? 'if (results == nullptr) {\r\n        LOGE("Falha ao gerar a imagem!");\r\n        free_sd_ctx(sd_ctx);\r\n        return env->NewByteArray(0);\r\n    }'
                : 'if (results == nullptr) {\n        LOGE("Falha ao gerar a imagem!");\n        free_sd_ctx(sd_ctx);\n        return env->NewByteArray(0);\n    }',
            replaceText:
                'if (results == nullptr || results[0].data == nullptr) {\n        LOGE("Falha ao gerar a imagem!");\n        if (results != nullptr) free(results);\n        free_sd_ctx(sd_ctx);\n        return env->NewByteArray(0);\n    }',
          ),
        );
      }
    }
    return foundUnsafeReturn;
  }

  static void _tryBuildCoordinatedImg2ImgPatches({
    required String relKt,
    required String ktSrc,
    required String relCpp,
    required String cppSrc,
    required List<DiagnosticFilePatch> outPatches,
  }) {
    // 1. Kotlin MainActivity.kt patch (disjoint or whole-processGGUF block if exact match exists)
    final ktExternalMatch = RegExp(
      r'private\s+external\s+fun\s+processarGGUF\s*\([\s\S]*?\):\s*ByteArray',
    ).firstMatch(ktSrc);
    final ktCallMatch = RegExp(
      r'val\s+height\s*=\s*call\.argument<Int>\("height"\)\s*\?:\s*512[\s\S]*?return@Thread\s*\r?\n\s*\}',
    ).firstMatch(ktSrc);

    if (ktExternalMatch != null && ktCallMatch != null) {
      outPatches.add(
        DiagnosticFilePatch(
          relativePath: relKt,
          description:
              'Atualizar assinatura JNI processarGGUF para aceitar initRgbBytes, maskGrayBytes e denoisingStrength',
          searchText: ktExternalMatch.group(0)!,
          replaceText: '''private external fun processarGGUF(
        modelPath: String,
        prompt: String,
        negativePrompt: String,
        steps: Int,
        cfgScale: Float,
        seed: Int,
        width: Int,
        height: Int,
        initRgbBytes: ByteArray?,
        maskGrayBytes: ByteArray?,
        denoisingStrength: Float
    ): ByteArray

    private fun decodeInitRgbBytes(path: String, w: Int, h: Int): ByteArray? {
        if (path.isBlank()) return null
        val src = android.graphics.BitmapFactory.decodeFile(path) ?: return null
        val scaled = Bitmap.createScaledBitmap(src, w, h, true)
        if (scaled !== src) src.recycle()
        val argb = IntArray(w * h)
        scaled.getPixels(argb, 0, w, 0, 0, w, h)
        scaled.recycle()
        val rgb = ByteArray(w * h * 3)
        for (i in argb.indices) {
            val c = argb[i]
            rgb[i * 3] = ((c shr 16) and 0xFF).toByte()
            rgb[i * 3 + 1] = ((c shr 8) and 0xFF).toByte()
            rgb[i * 3 + 2] = (c and 0xFF).toByte()
        }
        return rgb
    }

    private fun decodeMaskGrayBytes(path: String, w: Int, h: Int): ByteArray? {
        if (path.isBlank()) return null
        val src = android.graphics.BitmapFactory.decodeFile(path) ?: return null
        val scaled = Bitmap.createScaledBitmap(src, w, h, true)
        if (scaled !== src) src.recycle()
        val argb = IntArray(w * h)
        scaled.getPixels(argb, 0, w, 0, 0, w, h)
        scaled.recycle()
        val gray = ByteArray(w * h)
        for (i in argb.indices) {
            val c = argb[i]
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            gray[i] = ((r + g + b) / 3).toByte()
        }
        return gray
    }''',
        ),
      );

      final callBlock = ktCallMatch.group(0)!;
      if (callBlock.contains('val imageBytes = processarGGUF(modelPath, prompt, negativePrompt, steps, cfgScale, seed, width, height)')) {
        var updatedCall = callBlock.replaceFirst(
          'val height = call.argument<Int>("height") ?: 512',
          'val height = call.argument<Int>("height") ?: 512\n                val initImagePath = call.argument<String>("initImagePath") ?: ""\n                val maskImagePath = call.argument<String>("maskImagePath") ?: ""\n                val denoisingStrength = call.argument<Number>("denoisingStrength")?.toFloat() ?: 0.7f',
        );
        updatedCall = updatedCall.replaceFirst(
          'val imageBytes = processarGGUF(modelPath, prompt, negativePrompt, steps, cfgScale, seed, width, height)',
          'val initRgb = decodeInitRgbBytes(initImagePath, width, height)\n                        val maskGray = decodeMaskGrayBytes(maskImagePath, width, height)\n                        val imageBytes = processarGGUF(modelPath, prompt, negativePrompt, steps, cfgScale, seed, width, height, initRgb, maskGray, denoisingStrength)',
        );
        if (updatedCall != callBlock) {
          outPatches.add(
            DiagnosticFilePatch(
              relativePath: relKt,
              description:
                  'Ler initImagePath/maskImagePath/denoisingStrength e enviar para o motor C++',
              searchText: callBlock,
              replaceText: updatedCall,
            ),
          );
        }
      }
    }

    // 2. Full safe replacement of C++ processarGGUF entry function (only when exact anchor matches)
    final includeMatch = RegExp(
      r'#include <jni\.h>[\s\S]*?#include "stable-diffusion\.cpp/include/stable-diffusion\.h"',
    ).firstMatch(cppSrc);
    final fnMatch = RegExp(
      r'extern "C" JNIEXPORT jbyteArray JNICALL\s+Java_[A-Za-z0-9_]+\s*\([\s\S]*?\)\s*\{[\s\S]*$',
    ).firstMatch(cppSrc);

    if (includeMatch != null && fnMatch != null) {
      if (!cppSrc.contains('<vector>') || !cppSrc.contains('<stdlib.h>')) {
        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relCpp,
            description: 'Adicionar headers <stdlib.h> e <vector> para buffers e setenv Vulkan',
            searchText: includeMatch.group(0)!,
            replaceText:
                '#include <jni.h>\n#include <stdlib.h>\n#include <string>\n#include <vector>\n#include <android/log.h>\n#include "stable-diffusion.cpp/include/stable-diffusion.h"',
          ),
        );
      }

      final fnNameMatch = RegExp(r'Java_[A-Za-z0-9_]+').firstMatch(fnMatch.group(0)!);
      final fnName = fnNameMatch?.group(0) ??
          'Java_com_example_snapia_MainActivity_processarGGUF';

      outPatches.add(
        DiagnosticFilePatch(
          relativePath: relCpp,
          description:
              'Proteger Adreno Vulkan (DISABLE_COOPMAT/F16 + conv_direct) e ligar img2img/inpaint (init_image, mask_image, vae_decode_only)',
          searchText: fnMatch.group(0)!,
          replaceText: '''extern "C" JNIEXPORT jbyteArray JNICALL
$fnName(
        JNIEnv* env, jobject /* this */,
        jstring modelPathObj, jstring promptObj, jstring negPromptObj,
        jint steps, jfloat cfgScale, jint seed, jint width, jint height,
        jbyteArray initRgbObj, jbyteArray maskGrayObj, jfloat denoisingStrength) {

    // Protecao Adreno 7xx/8xx antes de inicializar o backend ggml-vulkan
    setenv("GGML_VK_DISABLE_COOPMAT", "1", 1);
    setenv("GGML_VK_DISABLE_COOPMAT2", "1", 1);
    setenv("GGML_VK_DISABLE_F16", "1", 1);

    const char* modelPath = env->GetStringUTFChars(modelPathObj, nullptr);
    const char* prompt = env->GetStringUTFChars(promptObj, nullptr);
    const char* negPrompt = env->GetStringUTFChars(negPromptObj, nullptr);

    bool has_init = (initRgbObj != nullptr);
    bool has_mask = (maskGrayObj != nullptr);
    std::vector<uint8_t> init_buf, mask_buf;
    if (has_init) {
        jsize len = env->GetArrayLength(initRgbObj);
        if (len >= width * height * 3) {
            init_buf.resize(width * height * 3);
            env->GetByteArrayRegion(initRgbObj, 0, width * height * 3, reinterpret_cast<jbyte*>(init_buf.data()));
        } else {
            has_init = false;
        }
    }
    if (has_mask) {
        jsize len = env->GetArrayLength(maskGrayObj);
        if (len >= width * height) {
            mask_buf.resize(width * height);
            env->GetByteArrayRegion(maskGrayObj, 0, width * height, reinterpret_cast<jbyte*>(mask_buf.data()));
        } else {
            has_mask = false;
        }
    }

    LOGI("Iniciando motor Vulkan GPU no Snapdragon (Adreno guards ativos)...");

    sd_ctx_params_t ctx_params;
    sd_ctx_params_init(&ctx_params);
    ctx_params.model_path = modelPath;
    ctx_params.n_threads = 4;
    ctx_params.vae_decode_only = !has_init;
    ctx_params.diffusion_conv_direct = true;
    ctx_params.vae_conv_direct = true;

    sd_ctx_t* sd_ctx = new_sd_ctx(&ctx_params);
    if (sd_ctx == nullptr) {
        LOGE("Falha ao carregar o modelo GGUF!");
        env->ReleaseStringUTFChars(modelPathObj, modelPath);
        env->ReleaseStringUTFChars(promptObj, prompt);
        env->ReleaseStringUTFChars(negPromptObj, negPrompt);
        return env->NewByteArray(0);
    }

    LOGI("Modelo GGUF carregado com sucesso! Gerando imagem...");

    sd_img_gen_params_t img_gen_params;
    sd_img_gen_params_init(&img_gen_params);
    img_gen_params.prompt = prompt;
    img_gen_params.negative_prompt = negPrompt;
    img_gen_params.width = width;
    img_gen_params.height = height;
    img_gen_params.seed = seed;
    img_gen_params.batch_count = 1;
    img_gen_params.sample_params.sample_steps = steps;
    img_gen_params.sample_params.guidance.txt_cfg = cfgScale;

    if (has_init) {
        img_gen_params.init_image = { (uint32_t)width, (uint32_t)height, 3, init_buf.data() };
        img_gen_params.strength = denoisingStrength;
        if (has_mask) {
            img_gen_params.mask_image = { (uint32_t)width, (uint32_t)height, 1, mask_buf.data() };
        }
    }

    sd_image_t* results = generate_image(sd_ctx, &img_gen_params);
    env->ReleaseStringUTFChars(modelPathObj, modelPath);
    env->ReleaseStringUTFChars(promptObj, prompt);
    env->ReleaseStringUTFChars(negPromptObj, negPrompt);

    if (results == nullptr || results[0].data == nullptr) {
        LOGE("Falha ao gerar a imagem!");
        if (results != nullptr) free(results);
        free_sd_ctx(sd_ctx);
        return env->NewByteArray(0);
    }

    int num_bytes = (int)results[0].width * (int)results[0].height * (int)results[0].channel;
    jbyteArray resultArray = env->NewByteArray(num_bytes);
    env->SetByteArrayRegion(resultArray, 0, num_bytes, reinterpret_cast<jbyte*>(results[0].data));

    free(results[0].data);
    free(results);
    free_sd_ctx(sd_ctx);

    LOGI("Imagem gerada com sucesso!");
    return resultArray;
}
''',
        ),
      );
    }
  }

  static void _tryBuildStandaloneCppVulkanPatches({
    required String relCpp,
    required String cppSrc,
    required bool missingDisableF16,
    required bool missingConvDirect,
    required bool forcesQ8Wtype,
    required bool missingNullDataCheck,
    required List<DiagnosticFilePatch> outPatches,
  }) {
    if (missingDisableF16 && cppSrc.contains('sd_ctx_params_t ctx_params;')) {
      if (!cppSrc.contains('<stdlib.h>') && cppSrc.contains('#include <jni.h>')) {
        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relCpp,
            description: 'Incluir <stdlib.h> para setenv()',
            searchText: '#include <jni.h>',
            replaceText: '#include <jni.h>\n#include <stdlib.h>',
          ),
        );
      }

      const initNeedle = 'sd_ctx_params_t ctx_params;\n    sd_ctx_params_init(&ctx_params);';
      const initNeedleCrlf =
          'sd_ctx_params_t ctx_params;\r\n    sd_ctx_params_init(&ctx_params);';
      if (cppSrc.contains(initNeedle) || cppSrc.contains(initNeedleCrlf)) {
        final isCrlf = cppSrc.contains(initNeedleCrlf);
        final nl = isCrlf ? '\r\n' : '\n';
        final extra = StringBuffer()
          ..write('setenv("GGML_VK_DISABLE_COOPMAT", "1", 1);$nl    ')
          ..write('setenv("GGML_VK_DISABLE_COOPMAT2", "1", 1);$nl    ')
          ..write('setenv("GGML_VK_DISABLE_F16", "1", 1);$nl    ')
          ..write(isCrlf ? initNeedleCrlf : initNeedle);
        if (missingConvDirect) {
          extra.write(
            '$nl    ctx_params.diffusion_conv_direct = true;$nl    ctx_params.vae_conv_direct = true;',
          );
        }
        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relCpp,
            description:
                'Desabilitar CoopMat/FP16 no Adreno e habilitar convolução direta antes de new_sd_ctx',
            searchText: isCrlf ? initNeedleCrlf : initNeedle,
            replaceText: extra.toString(),
          ),
        );
      }
    }

    if (forcesQ8Wtype) {
      const q8Line = '    ctx_params.wtype = SD_TYPE_Q8_0;\n';
      const q8LineCrlf = '    ctx_params.wtype = SD_TYPE_Q8_0;\r\n';
      if (cppSrc.contains(q8Line) || cppSrc.contains(q8LineCrlf)) {
        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relCpp,
            description: 'Preservar quantização original do GGUF (SD_TYPE_COUNT padrão)',
            searchText: cppSrc.contains(q8LineCrlf) ? q8LineCrlf : q8Line,
            replaceText:
                '    // ctx_params.wtype mantido como SD_TYPE_COUNT para respeitar o GGUF\n',
          ),
        );
      }
    }

    if (missingNullDataCheck) {
      const nullBlock =
          'if (results == nullptr) {\n        LOGE("Falha ao gerar a imagem!");\n        free_sd_ctx(sd_ctx);\n        return env->NewByteArray(0);\n    }';
      const nullBlockCrlf =
          'if (results == nullptr) {\r\n        LOGE("Falha ao gerar a imagem!");\r\n        free_sd_ctx(sd_ctx);\r\n        return env->NewByteArray(0);\r\n    }';
      if (cppSrc.contains(nullBlock) || cppSrc.contains(nullBlockCrlf)) {
        outPatches.add(
          DiagnosticFilePatch(
            relativePath: relCpp,
            description: 'Evitar SIGSEGV verificando results[0].data == nullptr',
            searchText:
                cppSrc.contains(nullBlockCrlf) ? nullBlockCrlf : nullBlock,
            replaceText:
                'if (results == nullptr || results[0].data == nullptr) {\n        LOGE("Falha ao gerar a imagem!");\n        if (results != nullptr) free(results);\n        free_sd_ctx(sd_ctx);\n        return env->NewByteArray(0);\n    }',
          ),
        );
      }
    }
  }

  static List<String> _findNestedNativeTargets({
    required String cleanRoot,
    required Directory cppDir,
    required String lowerLogs,
  }) {
    final matches = <String>[];
    final priorityNames = <String>[
      if (lowerLogs.contains('vulkan') ||
          lowerLogs.contains('adreno') ||
          lowerLogs.contains('pipeline') ||
          lowerLogs.contains('ggml'))
        'ggml-vulkan.cpp',
      if (lowerLogs.contains('unet') ||
          lowerLogs.contains('generate_image') ||
          lowerLogs.contains('sd_ctx'))
        'stable-diffusion.cpp',
      if (lowerLogs.contains('sd_ctx') ||
          lowerLogs.contains('diffusion_conv_direct') ||
          lowerLogs.contains('vae'))
        'stable-diffusion.h',
    ];
    if (priorityNames.isEmpty) return matches;

    final wanted = priorityNames.toSet();
    final visitedDirs = <Directory>[cppDir];
    var scanned = 0;

    while (visitedDirs.isNotEmpty &&
        scanned < _maxNativeScanFiles &&
        matches.length < wanted.length) {
      final dir = visitedDirs.removeAt(0);
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        continue;
      }

      for (final entity in entries) {
        if (scanned >= _maxNativeScanFiles) break;
        scanned++;
        final name = p.basename(entity.path);
        final lowerName = name.toLowerCase();
        if (entity is Directory) {
          if (lowerName == '.git' ||
              lowerName == 'build' ||
              lowerName == '.cxx' ||
              lowerName == 'tests') {
            continue;
          }
          final relDepth = p
              .split(p.relative(entity.path, from: cppDir.path))
              .length;
          if (relDepth <= 5) {
            visitedDirs.add(entity);
          }
        } else if (entity is File && wanted.contains(lowerName)) {
          matches.add(p.relative(entity.path, from: cleanRoot));
        }
      }
    }
    return matches;
  }

  static List<String> _readNewestCmakeCacheHighlights(String cleanRoot) {
    final candidates = <File>[];
    for (final rel in const ['android/app/.cxx', 'build/.cxx']) {
      final dir = Directory(p.join(cleanRoot, rel));
      if (!dir.existsSync()) continue;
      try {
        for (final entity in dir.listSync(recursive: true, followLinks: false)) {
          if (entity is File && p.basename(entity.path) == 'CMakeCache.txt') {
            candidates.add(entity);
          }
        }
      } catch (_) {}
    }
    if (candidates.isEmpty) return const [];

    candidates.sort((a, b) {
      try {
        return b.statSync().modified.compareTo(a.statSync().modified);
      } catch (_) {
        return 0;
      }
    });

    final newest = candidates.first;
    final raw = _safeRead(newest, maxBytes: 512 * 1024);
    if (raw == null) return const [];

    final interesting = <String>[];
    final pattern = RegExp(
      r'^(GGML_VULKAN[^:=]*|Vulkan_GLSLC_EXECUTABLE|CMAKE_BUILD_TYPE|ANDROID_ABI):[^=]*=.*',
      multiLine: true,
    );
    for (final m in pattern.allMatches(raw)) {
      interesting.add(m.group(0)!.trim());
      if (interesting.length >= 10) break;
    }
    return interesting;
  }

  static List<File> _findFilesByName(Directory root, List<String> exactNames) {
    if (!root.existsSync()) return const [];
    final targetLower = exactNames.map((e) => e.toLowerCase()).toSet();
    final found = <File>[];
    final queue = <Directory>[root];
    var scanned = 0;

    while (queue.isNotEmpty && scanned < _maxNativeScanFiles) {
      final dir = queue.removeAt(0);
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final entity in entries) {
        if (scanned >= _maxNativeScanFiles) break;
        scanned++;
        final lowerName = p.basename(entity.path).toLowerCase();
        if (entity is Directory) {
          if (lowerName == '.git' || lowerName == 'build' || lowerName == '.cxx') {
            continue;
          }
          queue.add(entity);
        } else if (entity is File && targetLower.contains(lowerName)) {
          found.add(entity);
        }
      }
    }
    return found;
  }

  static List<File> _findTopLevelCppWithPattern(
    Directory cppDir,
    String requiredSubstring,
  ) {
    if (!cppDir.existsSync()) return const [];
    final out = <File>[];
    try {
      for (final entity in cppDir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final lowerName = p.basename(entity.path).toLowerCase();
        if (!lowerName.endsWith('.cpp') && !lowerName.endsWith('.cc')) continue;
        final text = _safeRead(entity);
        if (text != null && text.contains(requiredSubstring)) {
          out.add(entity);
        }
      }
    } catch (_) {}
    return out;
  }

  static String? _safeRead(File file, {int maxBytes = 256 * 1024}) {
    try {
      if (!file.existsSync() || file.lengthSync() > maxBytes) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  static String _extractFocalSections(
    String content, {
    required int maxChars,
  }) {
    final lines = content.split(RegExp(r'\r?\n'));
    final chunks = <String>[];
    final coveredRanges = <(int, int)>[];

    for (final anchor in _vulkanFocalAnchors) {
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains(anchor)) continue;
        final start = (i - 8).clamp(0, lines.length - 1);
        final end = (i + 16).clamp(start + 1, lines.length);
        final overlaps = coveredRanges.any((r) => start <= r.$2 && end >= r.$1);
        if (overlaps) break;
        coveredRanges.add((start, end));
        final buf = StringBuffer('... [L${start + 1}-L$end] ...\n');
        for (var k = start; k < end; k++) {
          buf.writeln('${k + 1}: ${lines[k]}');
        }
        chunks.add(buf.toString().trimRight());
        break;
      }
      if (chunks.join('\n').length >= maxChars) break;
    }

    if (chunks.isEmpty) {
      return _sliceFileSnippet(content, maxChars: maxChars);
    }
    final combined = chunks.join('\n\n');
    return combined.length <= maxChars
        ? combined
        : '${combined.substring(0, maxChars)}\n... [truncado]';
  }

  static String _sliceFileSnippet(
    String content, {
    int? targetLine,
    required int maxChars,
  }) {
    final lines = content.split(RegExp(r'\r?\n'));
    if (targetLine != null && targetLine > 0 && lines.length > 45) {
      final start = (targetLine - 20).clamp(0, lines.length - 1);
      final end = (targetLine + 25).clamp(start + 1, lines.length);
      final numbered = <String>[];
      for (var i = start; i < end; i++) {
        final marker = (i + 1 == targetLine) ? '>>' : '  ';
        numbered.add('$marker ${i + 1}: ${lines[i]}');
      }
      final joined = numbered.join('\n');
      return joined.length <= maxChars
          ? joined
          : joined.substring(0, maxChars);
    }

    if (content.length <= maxChars) return content;
    return '${content.substring(0, maxChars)}\n... [truncado]';
  }
}
