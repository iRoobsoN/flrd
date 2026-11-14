import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/terminal_session.dart';
import 'android_device_runner_service.dart';

/// Spawns and manages persistent OS shell processes (PowerShell, CMD, Bash/Zsh)
/// for VS Code-style interactive terminal tabs inside FLRD Studio.
class TerminalShellService {
  final ProcessStarterFn _processStarter;
  final ProcessRunnerFn _processRunner;
  final Map<String, String> Function() _environmentProvider;
  final bool Function(String path) _dirExists;
  final bool? _isWindowsOverride;

  TerminalShellService({
    ProcessStarterFn? processStarter,
    ProcessRunnerFn? processRunner,
    Map<String, String> Function()? environmentProvider,
    bool Function(String path)? dirExists,
    bool? isWindowsOverride,
  })  : _processStarter = processStarter ?? _defaultProcessStarter,
        _processRunner = processRunner ?? _defaultProcessRunner,
        _environmentProvider =
            environmentProvider ?? (() => Platform.environment),
        _dirExists = dirExists ?? ((path) => Directory(path).existsSync()),
        _isWindowsOverride = isWindowsOverride;

  bool get isWindows => _isWindowsOverride ?? (!kIsWeb && Platform.isWindows);

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = true,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = true,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }

  TerminalShellProfile defaultProfile() {
    return isWindows
        ? TerminalShellProfile.powerShell
        : TerminalShellProfile.systemShell;
  }

  List<TerminalShellProfile> availableProfiles() {
    if (isWindows) {
      return const [
        TerminalShellProfile.powerShell,
        TerminalShellProfile.cmd,
      ];
    }
    return const [TerminalShellProfile.systemShell];
  }

  ({String executable, List<String> arguments, List<String> initCommands})
      resolveShellCommand(TerminalShellProfile profile) {
    if (isWindows) {
      if (profile == TerminalShellProfile.cmd) {
        return (
          executable: 'cmd.exe',
          arguments: const ['/Q', '/K', 'chcp 65001 >nul'],
          initCommands: const <String>[],
        );
      }
      // Wrapping PowerShell through chcp 65001 guarantees UTF-8 console pipes
      // before PowerShell parses its first stdin command line.
      return (
        executable: 'cmd.exe',
        arguments: const [
          '/c',
          'chcp 65001 >nul && powershell.exe -NoLogo -NoProfile -NoExit -Command -',
        ],
        initCommands: const [
          '[Console]::InputEncoding = [System.Text.Encoding]::UTF8; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; \$OutputEncoding = [System.Text.Encoding]::UTF8',
        ],
      );
    }

    final env = _environmentProvider();
    final shellPath = (env['SHELL'] ?? '').trim();
    final executable = shellPath.isNotEmpty ? shellPath : '/bin/bash';
    return (
      executable: executable,
      arguments: const <String>[],
      initCommands: const <String>[],
    );
  }

  /// Resolves a valid working directory, falling back to `Directory.current.path`.
  String resolveWorkingDirectory(String? requestedPath) {
    final trimmed = (requestedPath ?? '').trim();
    if (trimmed.isNotEmpty && _dirExists(trimmed)) {
      return trimmed;
    }
    return Directory.current.path;
  }

  /// Starts a persistent interactive shell process in [workingDirectory].
  Future<Process> startInteractiveShell({
    required String workingDirectory,
    required TerminalShellProfile profile,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'O terminal interativo requer o aplicativo Desktop (Windows/macOS/Linux).',
      );
    }

    final resolvedDir = resolveWorkingDirectory(workingDirectory);
    final cmd = resolveShellCommand(profile);
    final process = await _processStarter(
      cmd.executable,
      cmd.arguments,
      workingDirectory: resolvedDir,
      runInShell: false,
    );

    for (final initCmd in cmd.initCommands) {
      try {
        process.stdin.writeln(initCmd);
      } catch (_) {}
    }

    return process;
  }

  /// Strips ANSI CSI/OSC escape sequences so shell and Flutter CLI logs render
  /// cleanly in selectable Flutter text widgets.
  static String stripAnsiCodes(String input) {
    return input.replaceAll(
      RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))'),
      '',
    );
  }

  /// Terminates an interactive shell process and any spawned child commands.
  Future<void> killProcessTree(Process process) async {
    try {
      if (isWindows) {
        await _processRunner(
          'taskkill',
          ['/F', '/T', '/PID', '${process.pid}'],
          runInShell: true,
        );
      } else {
        process.kill();
      }
    } catch (_) {
      try {
        process.kill();
      } catch (_) {}
    }
  }
}
