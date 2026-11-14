import 'package:flutter/foundation.dart';

/// Shell binary profile used when creating interactive persistent terminals.
enum TerminalShellProfile {
  powerShell('PowerShell'),
  cmd('CMD'),
  systemShell('Shell');

  const TerminalShellProfile(this.label);
  final String label;
}

/// Kind of tab inside the bottom VS Code-style terminal workspace.
enum TerminalTabKind {
  androidDebug,
  interactiveShell,
}

/// Lifecycle state of an interactive shell tab's underlying OS process.
enum TerminalProcessStatus {
  idle,
  starting,
  running,
  exited,
}

/// A single timestamped output or command-echo entry inside a terminal tab.
@immutable
class TerminalLine {
  final DateTime timestamp;
  final String text;
  final bool isError;
  final bool isSystem;
  final bool isCommandEcho;

  const TerminalLine({
    required this.timestamp,
    required this.text,
    this.isError = false,
    this.isSystem = false,
    this.isCommandEcho = false,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

const Object _terminalUnset = Object();

/// Immutable snapshot of a single terminal tab (either pinned Android Debug or shell).
@immutable
class TerminalTabSession {
  final String id;
  final String title;
  final TerminalTabKind kind;
  final TerminalShellProfile profile;
  final String workingDirectory;
  final TerminalProcessStatus status;
  final int? exitCode;
  final List<TerminalLine> lines;
  final List<String> commandHistory;

  const TerminalTabSession({
    required this.id,
    required this.title,
    required this.kind,
    required this.profile,
    required this.workingDirectory,
    this.status = TerminalProcessStatus.idle,
    this.exitCode,
    this.lines = const [],
    this.commandHistory = const [],
  });

  bool get isPinned => kind == TerminalTabKind.androidDebug;
  bool get isInteractiveShell => kind == TerminalTabKind.interactiveShell;

  TerminalTabSession copyWith({
    String? title,
    TerminalShellProfile? profile,
    String? workingDirectory,
    TerminalProcessStatus? status,
    Object? exitCode = _terminalUnset,
    List<TerminalLine>? lines,
    List<String>? commandHistory,
  }) {
    return TerminalTabSession(
      id: id,
      title: title ?? this.title,
      kind: kind,
      profile: profile ?? this.profile,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      status: status ?? this.status,
      exitCode: identical(exitCode, _terminalUnset)
          ? this.exitCode
          : exitCode as int?,
      lines: lines ?? this.lines,
      commandHistory: commandHistory ?? this.commandHistory,
    );
  }
}

/// Complete state of the multi-tab persistent terminal workspace.
@immutable
class TerminalWorkspaceState {
  static const String debugTabId = 'android-debug';
  static const double minPanelHeight = 140.0;
  static const double maxPanelHeight = 480.0;
  static const double defaultPanelHeight = 224.0;

  final List<TerminalTabSession> tabs;
  final String activeTabId;
  final double panelHeight;

  const TerminalWorkspaceState({
    required this.tabs,
    this.activeTabId = debugTabId,
    this.panelHeight = defaultPanelHeight,
  });

  factory TerminalWorkspaceState.initial() {
    return const TerminalWorkspaceState(
      tabs: [
        TerminalTabSession(
          id: debugTabId,
          title: 'Debug Android',
          kind: TerminalTabKind.androidDebug,
          profile: TerminalShellProfile.systemShell,
          workingDirectory: '',
        ),
      ],
      activeTabId: debugTabId,
      panelHeight: defaultPanelHeight,
    );
  }

  TerminalTabSession get activeTab => tabs.firstWhere(
        (tab) => tab.id == activeTabId,
        orElse: () => tabs.first,
      );

  int get interactiveShellCount =>
      tabs.where((tab) => tab.kind == TerminalTabKind.interactiveShell).length;

  TerminalWorkspaceState copyWith({
    List<TerminalTabSession>? tabs,
    String? activeTabId,
    double? panelHeight,
  }) {
    return TerminalWorkspaceState(
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
      panelHeight: panelHeight ?? this.panelHeight,
    );
  }
}
