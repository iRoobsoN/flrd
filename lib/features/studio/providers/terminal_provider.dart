import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../ai/services/gemini_ai_service.dart';
import '../models/connected_device.dart';
import '../models/terminal_session.dart';
import '../services/android_device_runner_service.dart';
import '../services/diagnostic_code_fix_service.dart';
import '../services/terminal_shell_service.dart';
import 'android_debug_provider.dart';

class _ShellProcessHandle {
  final Process process;
  StreamSubscription<String>? stdoutSub;
  StreamSubscription<String>? stderrSub;

  _ShellProcessHandle(this.process);

  void cancelSubscriptions() {
    stdoutSub?.cancel();
    stdoutSub = null;
    stderrSub?.cancel();
    stderrSub = null;
  }
}

/// Manages multiple persistent VS Code-style terminal tabs inside FLRD Studio.
///
/// The pinned `Debug Android` tab stays intact even when `flutter run` fails or
/// a device disconnects, and users can open/switch/close any number of
/// interactive shell terminals (`PowerShell`, `CMD`, `bash`/`zsh`).
class TerminalNotifier extends StateNotifier<TerminalWorkspaceState> {
  final TerminalShellService _service;
  final AndroidDeviceRunnerService? _deviceRunner;
  final http.Client? _aiHttpClient;

  final Map<String, _ShellProcessHandle> _processes = {};
  final Map<String, Timer> _diagTimers = {};
  final Map<String, String> _lastDiagnosedSignature = {};
  int _nextShellNumber = 1;
  bool _disposed = false;

  static const int _maxLinesPerTab = 800;

  TerminalNotifier(
    this._service, {
    AndroidDeviceRunnerService? deviceRunner,
    http.Client? aiHttpClient,
  })  : _deviceRunner = deviceRunner,
        _aiHttpClient = aiHttpClient,
        super(TerminalWorkspaceState.initial());

  void setProjectDirectory(String workingDirectory) {
    final trimmed = workingDirectory.trim();
    if (trimmed.isEmpty) return;

    final updated = state.tabs
        .map((tab) => tab.isPinned
            ? tab.copyWith(workingDirectory: trimmed)
            : tab)
        .toList(growable: false);
    state = state.copyWith(tabs: updated);
  }

  void selectTab(String tabId) {
    if (!state.tabs.any((t) => t.id == tabId)) return;
    if (state.activeTabId == tabId) return;
    state = state.copyWith(activeTabId: tabId);
  }

  void focusDebugTab() {
    selectTab(TerminalWorkspaceState.debugTabId);
  }

  void setPanelHeight(double nextHeight) {
    final clamped = nextHeight.clamp(
      TerminalWorkspaceState.minPanelHeight,
      TerminalWorkspaceState.maxPanelHeight,
    );
    if ((clamped - state.panelHeight).abs() < 0.5) return;
    state = state.copyWith(panelHeight: clamped);
  }

  /// Creates a new persistent interactive shell terminal tab and starts its OS shell.
  Future<String> createShellTerminal({
    String? workingDirectory,
    TerminalShellProfile? profile,
    bool activate = true,
  }) async {
    final effectiveProfile = profile ?? _service.defaultProfile();
    final shellNumber = _nextShellNumber++;
    final tabId = 'shell-$shellNumber';
    final effectiveDir = _service.resolveWorkingDirectory(
      workingDirectory ?? state.activeTab.workingDirectory,
    );

    final newTab = TerminalTabSession(
      id: tabId,
      title: '${effectiveProfile.label} $shellNumber',
      kind: TerminalTabKind.interactiveShell,
      profile: effectiveProfile,
      workingDirectory: effectiveDir,
      status: TerminalProcessStatus.starting,
      lines: [
        TerminalLine(
          timestamp: DateTime.now(),
          text:
              'Terminal ${effectiveProfile.label} iniciado em: $effectiveDir',
          isSystem: true,
        ),
      ],
    );

    state = state.copyWith(
      tabs: [...state.tabs, newTab],
      activeTabId: activate ? tabId : state.activeTabId,
    );

    await _spawnShellForTab(tabId);
    return tabId;
  }

  Future<bool> _spawnShellForTab(String tabId) async {
    final tab = _findTab(tabId);
    if (tab == null || !tab.isInteractiveShell) return false;

    if (kIsWeb) {
      _updateTab(
        tabId,
        (t) => t.copyWith(
          status: TerminalProcessStatus.exited,
          exitCode: 1,
        ),
      );
      _appendLine(
        tabId,
        'Terminal interativo disponível apenas no FLRD Desktop (Windows/macOS/Linux).',
        isError: true,
      );
      return false;
    }

    _updateTab(
      tabId,
      (t) => t.copyWith(
        status: TerminalProcessStatus.starting,
        exitCode: null,
      ),
    );

    try {
      final proc = await _service.startInteractiveShell(
        workingDirectory: tab.workingDirectory,
        profile: tab.profile,
      );
      if (_disposed || _findTab(tabId) == null) {
        await _service.killProcessTree(proc);
        return false;
      }

      final handle = _ShellProcessHandle(proc);
      _processes[tabId] = handle;

      handle.stdoutSub = proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) => _appendLine(tabId, line));

      handle.stderrSub = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) => _appendLine(tabId, line, isError: true));

      _updateTab(
        tabId,
        (t) => t.copyWith(
          status: TerminalProcessStatus.running,
          exitCode: null,
        ),
      );

      unawaited(proc.exitCode.then((code) {
        if (_disposed || _processes[tabId]?.process != proc) return;
        handle.cancelSubscriptions();
        _processes.remove(tabId);

        _updateTab(
          tabId,
          (t) => t.copyWith(
            status: TerminalProcessStatus.exited,
            exitCode: code,
          ),
        );
        _appendLine(
          tabId,
          '⏹️ Shell encerrado (código $code). O terminal permanece aberto — envie outro comando ou clique em Reiniciar.',
          isSystem: true,
          isError: code != 0,
        );
        if (code != 0) {
          _scheduleShellDiagnostic(tabId, immediate: true);
        }
      }));

      return true;
    } catch (e) {
      if (_disposed) return false;
      _updateTab(
        tabId,
        (t) => t.copyWith(
          status: TerminalProcessStatus.exited,
          exitCode: 1,
        ),
      );
      _appendLine(
        tabId,
        '❌ Falha ao iniciar shell (${tab.profile.label}): $e',
        isError: true,
      );
      return false;
    }
  }

  /// Sends a command to [tabId], automatically re-spawning the shell if it
  /// previously exited so the terminal stays usable persistently.
  Future<void> sendCommand(String tabId, String rawCommand) async {
    final command = rawCommand.trim();
    if (command.isEmpty) return;

    final tab = _findTab(tabId);
    if (tab == null || !tab.isInteractiveShell) return;

    // Record command history cleanly (avoid adjacent duplicates).
    final updatedHistory = List<String>.from(tab.commandHistory);
    if (updatedHistory.isEmpty || updatedHistory.last != command) {
      updatedHistory.add(command);
      if (updatedHistory.length > 100) {
        updatedHistory.removeRange(0, updatedHistory.length - 100);
      }
    }
    _updateTab(tabId, (t) => t.copyWith(commandHistory: updatedHistory));

    final lower = command.toLowerCase();
    if (lower == 'cls' || lower == 'clear') {
      clearTab(tabId);
      return;
    }

    _diagTimers.remove(tabId)?.cancel();
    _lastDiagnosedSignature.remove(tabId);
    _updateTab(tabId, (t) => t.copyWith(diagnostic: null));
    _appendLine(tabId, '\$ $command', isCommandEcho: true);

    if (!_processes.containsKey(tabId)) {
      final started = await _spawnShellForTab(tabId);
      if (!started) return;
    }

    final handle = _processes[tabId];
    if (handle == null) return;

    try {
      handle.process.stdin.writeln(command);
    } catch (e) {
      _appendLine(
        tabId,
        '⚠️ Não foi possível enviar o comando para o shell: $e',
        isError: true,
      );
    }
  }

  /// Restarts the OS shell process in [tabId] while keeping the tab open.
  Future<void> restartShellTerminal(String tabId) async {
    final tab = _findTab(tabId);
    if (tab == null || !tab.isInteractiveShell) return;

    final existing = _processes.remove(tabId);
    if (existing != null) {
      existing.cancelSubscriptions();
      await _service.killProcessTree(existing.process);
    }
    if (_disposed || _findTab(tabId) == null) return;

    _appendLine(
      tabId,
      '🔄 Reiniciando terminal ${tab.title}...',
      isSystem: true,
    );
    await _spawnShellForTab(tabId);
  }

  /// Closes an interactive shell tab and kills its process tree.
  /// Pinned tabs (`Debug Android`) cannot be removed.
  Future<void> closeTab(String tabId) async {
    final tab = _findTab(tabId);
    if (tab == null || tab.isPinned) return;

    final existing = _processes.remove(tabId);
    if (existing != null) {
      existing.cancelSubscriptions();
      await _service.killProcessTree(existing.process);
    }
    if (_disposed) return;

    final index = state.tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;

    final remaining = List<TerminalTabSession>.from(state.tabs)..removeAt(index);
    var nextActive = state.activeTabId;
    if (nextActive == tabId) {
      final fallbackIndex = (index - 1).clamp(0, remaining.length - 1);
      nextActive = remaining[fallbackIndex].id;
    }
    state = state.copyWith(tabs: remaining, activeTabId: nextActive);
  }

  void clearTab(String tabId) {
    final tab = _findTab(tabId);
    if (tab == null || !tab.isInteractiveShell) return;
    _diagTimers.remove(tabId)?.cancel();
    _lastDiagnosedSignature.remove(tabId);
    _updateTab(tabId, (t) => t.copyWith(lines: const [], diagnostic: null));
  }

  void dismissTabDiagnostic(String tabId) {
    final tab = _findTab(tabId);
    if (tab == null) return;
    _updateTab(tabId, (t) => t.copyWith(diagnostic: null));
  }

  /// Generates a deep AI/local diagnosis + code patches for an interactive shell tab's failure.
  Future<String?> generateAiDiagnosisForTab(
    String tabId, {
    String? apiKey,
  }) async {
    final tab = _findTab(tabId);
    final diagnostic = tab?.diagnostic;
    if (tab == null || diagnostic == null || diagnostic.isGeneratingAiFix) {
      return null;
    }

    final commandLogs = _extractLatestCommandLines(tab);
    final effectiveLogs = diagnostic.relevantLogLines.isNotEmpty
        ? diagnostic.relevantLogLines
        : commandLogs;

    _updateTab(
      tabId,
      (t) => t.copyWith(
        diagnostic: diagnostic.copyWith(isGeneratingAiFix: true, aiFixError: null),
      ),
    );

    try {
      final result = await GeminiAiService.analyzeAndBuildAppFix(
        projectPath: tab.workingDirectory,
        issueTitle: diagnostic.title,
        crashLogs: effectiveLogs,
        affectedLocation: diagnostic.affectedLocation,
        apiKey: apiKey,
        httpClient: _aiHttpClient,
      );
      if (_disposed) return null;
      final currentTab = _findTab(tabId);
      final currentDiag = currentTab?.diagnostic;
      if (currentTab == null || currentDiag == null) return null;

      final mergedPatches = DiagnosticCodeFixService.mergeValidatedPatches(
        projectPath: currentTab.workingDirectory,
        primary: result.patches,
        secondary: currentDiag.suggestedPatches,
      );

      final updatedDiag = currentDiag.copyWith(
        isGeneratingAiFix: false,
        aiFixSuggestion: result.explanationMarkdown,
        suggestedPatches: mergedPatches,
        aiFixError: null,
      );
      _updateTab(tabId, (t) => t.copyWith(diagnostic: updatedDiag));

      for (final line in DiagnosticCodeFixService.formatTerminalResolutionLines(
        updatedDiag,
        aiSummary: result.explanationMarkdown,
      )) {
        _appendLine(tabId, line, isSystem: true, isResolution: true);
      }
      return result.explanationMarkdown;
    } catch (e) {
      if (_disposed) return null;
      final currentDiag = _findTab(tabId)?.diagnostic;
      if (currentDiag != null) {
        _updateTab(
          tabId,
          (t) => t.copyWith(
            diagnostic: currentDiag.copyWith(
              isGeneratingAiFix: false,
              aiFixError: 'Falha ao analisar erro com IA: $e',
            ),
          ),
        );
      }
      return null;
    }
  }

  /// Applies [selectedPatches] for an interactive shell tab's active diagnostic.
  Future<AppPatchApplyResult> applyPatchesForTab(
    String tabId, {
    List<DiagnosticFilePatch>? selectedPatches,
  }) async {
    final tab = _findTab(tabId);
    final diagnostic = tab?.diagnostic;
    if (tab == null || diagnostic == null) {
      return const AppPatchApplyResult(
        appliedCount: 0,
        errorMessage: 'Nenhum diagnóstico ativo nesta aba.',
      );
    }

    final toApply = selectedPatches ?? diagnostic.suggestedPatches;
    final result = await DiagnosticCodeFixService.applyPatches(
      projectPath: tab.workingDirectory,
      patches: toApply,
    );
    if (_disposed) return result;

    if (!result.isSuccess) {
      _appendLine(
        tabId,
        '❌ ${result.errorMessage ?? "Falha ao aplicar patches."}',
        isError: true,
      );
      return result;
    }

    for (final file in result.modifiedFiles) {
      _appendLine(
        tabId,
        '✅ Correção aplicada em: $file',
        isSystem: true,
        isResolution: true,
      );
    }
    if (result.backupDir != null) {
      _appendLine(
        tabId,
        '💾 Backup salvo em: ${result.backupDir}',
        isSystem: true,
        isResolution: true,
      );
    }
    if (result.clearedCxxCache) {
      _appendLine(
        tabId,
        '🧹 Cache nativo .cxx limpo para garantir recompilação.',
        isSystem: true,
        isResolution: true,
      );
    }

    final remaining = diagnostic.suggestedPatches
        .where((p) => !toApply.contains(p))
        .toList(growable: false);
    _updateTab(
      tabId,
      (t) => t.copyWith(
        diagnostic: diagnostic.copyWith(
          suggestedPatches: remaining,
          lastAppliedBackupDir: result.backupDir,
          appliedFixSummary: 'Aplicado em: ${result.modifiedFiles.join(", ")}',
        ),
      ),
    );
    return result;
  }

  Future<bool> revertPatchesForTab(String tabId) async {
    final tab = _findTab(tabId);
    final backupDir = tab?.diagnostic?.lastAppliedBackupDir?.trim();
    if (tab == null || backupDir == null || backupDir.isEmpty) return false;

    final restored = await DiagnosticCodeFixService.revertBackup(
      projectPath: tab.workingDirectory,
      backupDir: backupDir,
    );
    if (_disposed || restored.isEmpty) return false;

    _appendLine(
      tabId,
      '↩️ Backup restaurado em: ${restored.join(", ")}',
      isSystem: true,
      isResolution: true,
    );
    final reEnriched = DiagnosticCodeFixService.enrichDiagnosticWithLocalAnalysis(
      tab.diagnostic!.copyWith(
        lastAppliedBackupDir: null,
        appliedFixSummary: null,
      ),
      projectPath: tab.workingDirectory,
      crashLogs: _extractLatestCommandLines(tab),
    );
    _updateTab(tabId, (t) => t.copyWith(diagnostic: reEnriched));
    return true;
  }

  static bool _looksLikeTerminalFailureLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('failed to link shaders') ||
        lower.contains('pipeline create failed') ||
        lower.contains('vkcmdbindpipeline') ||
        lower.contains('fatal signal 11') ||
        lower.contains('fatal signal 6') ||
        lower.contains('failure: build failed') ||
        lower.contains('gradle build failed') ||
        lower.contains('unhandled exception:') ||
        lower.contains('install_failed_') ||
        lower.contains('outofmemoryerror') ||
        lower.contains('std::bad_alloc') ||
        lower.contains('cmake error') ||
        lower.contains('no devices/emulators found') ||
        (lower.contains('adb.exe') && lower.contains('not found'));
  }

  List<String> _extractLatestCommandLines(TerminalTabSession tab) {
    final startIdx = tab.lines.lastIndexWhere((l) => l.isCommandEcho);
    final slice = startIdx >= 0 ? tab.lines.skip(startIdx + 1) : tab.lines;
    return slice
        .where((l) => !l.isResolution && !l.isSystem)
        .map((l) => l.text)
        .toList(growable: false);
  }

  void _scheduleShellDiagnostic(String tabId, {bool immediate = false}) {
    if (_disposed || _deviceRunner == null) return;
    _diagTimers.remove(tabId)?.cancel();
    _diagTimers[tabId] = Timer(
      Duration(milliseconds: immediate ? 30 : 220),
      () => unawaited(_evaluateShellDiagnostic(tabId)),
    );
  }

  Future<void> _evaluateShellDiagnostic(String tabId) async {
    final runner = _deviceRunner;
    if (_disposed || runner == null) return;
    final tab = _findTab(tabId);
    if (tab == null || !tab.isInteractiveShell) return;

    final rawLines = _extractLatestCommandLines(tab);
    if (rawLines.isEmpty) return;

    final base = await runner.diagnoseBuildFailure(
      rawLines,
      projectPath: tab.workingDirectory,
    );
    if (_disposed || base == null) return;

    final enriched = DiagnosticCodeFixService.enrichDiagnosticWithLocalAnalysis(
      base,
      projectPath: tab.workingDirectory,
      crashLogs: rawLines,
    );
    final sig = '${enriched.issueType.name}::${enriched.affectedLocation ?? ""}';
    if (_lastDiagnosedSignature[tabId] == sig && tab.diagnostic != null) {
      return;
    }
    _lastDiagnosedSignature[tabId] = sig;

    _updateTab(tabId, (t) => t.copyWith(diagnostic: enriched));
    for (final line in DiagnosticCodeFixService.formatTerminalResolutionLines(enriched)) {
      _appendLine(tabId, line, isSystem: true, isResolution: true);
    }
  }

  TerminalTabSession? _findTab(String tabId) {
    for (final tab in state.tabs) {
      if (tab.id == tabId) return tab;
    }
    return null;
  }

  void _updateTab(
    String tabId,
    TerminalTabSession Function(TerminalTabSession current) transform,
  ) {
    if (_disposed) return;
    final idx = state.tabs.indexWhere((t) => t.id == tabId);
    if (idx == -1) return;
    final updated = List<TerminalTabSession>.from(state.tabs);
    updated[idx] = transform(updated[idx]);
    state = state.copyWith(tabs: updated);
  }

  void _appendLine(
    String tabId,
    String rawText, {
    bool isError = false,
    bool isSystem = false,
    bool isCommandEcho = false,
    bool isResolution = false,
  }) {
    if (_disposed) return;
    final cleaned = TerminalShellService.stripAnsiCodes(rawText).trimRight();
    if (cleaned.isEmpty) return;

    final tab = _findTab(tabId);
    if (tab == null) return;

    final updatedLines = List<TerminalLine>.from(tab.lines)
      ..add(
        TerminalLine(
          timestamp: DateTime.now(),
          text: cleaned,
          isError: isError,
          isSystem: isSystem,
          isCommandEcho: isCommandEcho,
          isResolution: isResolution,
        ),
      );
    if (updatedLines.length > _maxLinesPerTab) {
      updatedLines.removeRange(0, updatedLines.length - _maxLinesPerTab);
    }
    _updateTab(tabId, (t) => t.copyWith(lines: updatedLines));

    if (!isResolution &&
        !isSystem &&
        !isCommandEcho &&
        _looksLikeTerminalFailureLine(cleaned)) {
      _scheduleShellDiagnostic(tabId);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _diagTimers.values) {
      timer.cancel();
    }
    _diagTimers.clear();
    final handles = _processes.values.toList(growable: false);
    _processes.clear();
    for (final handle in handles) {
      handle.cancelSubscriptions();
      unawaited(_service.killProcessTree(handle.process));
    }
    super.dispose();
  }
}

final terminalShellServiceProvider = Provider<TerminalShellService>((ref) {
  return TerminalShellService(
    buildEnvironmentResolver: () => ref
        .read(androidDeviceRunnerServiceProvider)
        .buildBuildEnvironment(),
  );
});

final terminalProvider =
    StateNotifierProvider<TerminalNotifier, TerminalWorkspaceState>((ref) {
  final service = ref.watch(terminalShellServiceProvider);
  final runner = ref.watch(androidDeviceRunnerServiceProvider);
  return TerminalNotifier(service, deviceRunner: runner);
});
