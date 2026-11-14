import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/terminal_session.dart';
import '../services/terminal_shell_service.dart';

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

  final Map<String, _ShellProcessHandle> _processes = {};
  int _nextShellNumber = 1;
  bool _disposed = false;

  static const int _maxLinesPerTab = 800;

  TerminalNotifier(this._service) : super(TerminalWorkspaceState.initial());

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
    _updateTab(tabId, (t) => t.copyWith(lines: const []));
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
        ),
      );
    if (updatedLines.length > _maxLinesPerTab) {
      updatedLines.removeRange(0, updatedLines.length - _maxLinesPerTab);
    }
    _updateTab(tabId, (t) => t.copyWith(lines: updatedLines));
  }

  @override
  void dispose() {
    _disposed = true;
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
  return TerminalShellService();
});

final terminalProvider =
    StateNotifierProvider<TerminalNotifier, TerminalWorkspaceState>((ref) {
  final service = ref.watch(terminalShellServiceProvider);
  return TerminalNotifier(service);
});
