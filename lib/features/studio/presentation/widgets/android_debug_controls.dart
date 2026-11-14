import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../models/connected_device.dart';
import '../../models/terminal_session.dart';
import '../../providers/android_debug_provider.dart';
import '../../providers/terminal_provider.dart';
import '../../services/terminal_shell_service.dart';
import 'android_connection_troubleshooter_dialog.dart';

/// Compact toolbar controls rendered inside [AppStudioScreen] to detect
/// connected Android devices, launch real-time debug sessions, trigger
/// manual Hot Reload / Hot Restart, toggle the console panel, and stop runs.
class AndroidDebugToolbarControls extends ConsumerWidget {
  const AndroidDebugToolbarControls({
    super.key,
    required this.projectPath,
    this.isConsoleOpen = false,
    this.onToggleConsole,
  });

  final String projectPath;
  final bool isConsoleOpen;
  final VoidCallback? onToggleConsole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(androidDebugProvider);
    final notifier = ref.read(androidDebugProvider.notifier);
    final shellCount = ref.watch(
      terminalProvider.select((s) => s.interactiveShellCount),
    );

    if (state.isActiveSession) {
      return _ActiveSessionControls(
        state: state,
        notifier: notifier,
        isConsoleOpen: isConsoleOpen,
        shellCount: shellCount,
        onToggleConsole: onToggleConsole,
      );
    }

    if (state.devices.isEmpty) {
      final isScanning = state.status == DeviceRunStatus.scanning;
      final diagnostic = state.lastDiagnostic;
      final hasDetectedIssue = diagnostic != null &&
          diagnostic.hasActionableIssue &&
          diagnostic.issueType != AndroidConnectionIssueType.noDeviceConnected;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolbarActionPill(
            key: const ValueKey('android_scan_devices_button'),
            icon: isScanning ? Icons.sync_rounded : Icons.usb_rounded,
            label: isScanning ? 'Buscando...' : 'Android USB',
            tooltip: hasDetectedIssue
                ? '${diagnostic.title} (clique para diagnosticar e resolver)'
                : 'Detectar aparelhos Android conectados via USB/ADB',
            accentColor: isScanning
                ? AppColors.secondary
                : hasDetectedIssue
                    ? AppColors.warning
                    : AppColors.textSecondary,
            textColor: isScanning
                ? AppColors.secondary
                : hasDetectedIssue
                    ? AppColors.warning
                    : AppColors.textPrimary,
            backgroundColor: hasDetectedIssue && !isScanning
                ? AppColors.warning.withValues(alpha: 0.12)
                : null,
            borderColor: isScanning
                ? AppColors.secondary.withValues(alpha: 0.5)
                : hasDetectedIssue
                    ? AppColors.warning.withValues(alpha: 0.5)
                    : null,
            onPressed: isScanning
                ? null
                : () async {
                    await notifier.scanDevices();
                    if (!context.mounted) return;
                    final updated = ref.read(androidDebugProvider);
                    if (updated.devices.isNotEmpty) {
                      AppToast.success(
                        context,
                        '${updated.devices.first.name} conectado e pronto!',
                      );
                    } else {
                      await AndroidConnectionTroubleshooterDialog.show(context);
                    }
                  },
          ),
          if (diagnostic != null && diagnostic.hasActionableIssue) ...[
            const SizedBox(width: 4),
            _ToolbarIconButton(
              key: const ValueKey('android_troubleshoot_button'),
              icon: hasDetectedIssue
                  ? Icons.warning_amber_rounded
                  : Icons.help_outline_rounded,
              tooltip: 'Assistente de Conexão Android: ${diagnostic.title}',
              color: hasDetectedIssue
                  ? AppColors.warning
                  : AppColors.textSecondary,
              backgroundColor: hasDetectedIssue
                  ? AppColors.warning.withValues(alpha: 0.12)
                  : null,
              borderColor: hasDetectedIssue
                  ? AppColors.warning.withValues(alpha: 0.45)
                  : null,
              onPressed: () =>
                  AndroidConnectionTroubleshooterDialog.show(context),
            ),
          ],
          const SizedBox(width: 4),
          _ConsoleToggleButton(
            isConsoleOpen: isConsoleOpen,
            hasError: state.status == DeviceRunStatus.error,
            shellCount: shellCount,
            onToggleConsole: onToggleConsole,
          ),
        ],
      );
    }

    final selected = state.selectedDevice ?? state.devices.first;
    final isScanning = state.status == DeviceRunStatus.scanning;
    final hasError = state.status == DeviceRunStatus.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DeviceSelectorMenu(
          devices: state.devices,
          selected: selected,
          onSelected: notifier.selectDevice,
        ),
        const SizedBox(width: 4),
        _ToolbarIconButton(
          key: const ValueKey('android_refresh_devices_button'),
          icon: Icons.refresh_rounded,
          tooltip: 'Atualizar aparelhos Android conectados',
          color: isScanning ? AppColors.secondary : AppColors.textSecondary,
          onPressed: isScanning ? null : notifier.scanDevices,
        ),
        const SizedBox(width: 4),
        _ToolbarActionPill(
          key: const ValueKey('android_launch_button'),
          icon: Icons.play_arrow_rounded,
          label: '▶ ${selected.name}',
          tooltip: 'Lançar e depurar em tempo real no ${selected.displayLabel}',
          accentColor: AppColors.success,
          textColor: AppColors.success,
          backgroundColor: AppColors.success.withValues(alpha: 0.14),
          borderColor: AppColors.success.withValues(alpha: 0.55),
          maxLabelWidth: 115,
          onPressed: () => notifier.launchProject(projectPath),
        ),
        if (hasError) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: state.errorMessage ?? 'Erro ao executar no Android',
            child: InkWell(
              key: const ValueKey('android_error_badge'),
              onTap: onToggleConsole ?? notifier.dismissError,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.45),
                  ),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 12,
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 4),
        _ConsoleToggleButton(
          isConsoleOpen: isConsoleOpen,
          hasError: hasError,
          shellCount: shellCount,
          onToggleConsole: onToggleConsole,
        ),
      ],
    );
  }
}

class _ActiveSessionControls extends StatelessWidget {
  const _ActiveSessionControls({
    required this.state,
    required this.notifier,
    required this.isConsoleOpen,
    required this.shellCount,
    required this.onToggleConsole,
  });

  final AndroidDebugState state;
  final AndroidDebugNotifier notifier;
  final bool isConsoleOpen;
  final int shellCount;
  final VoidCallback? onToggleConsole;

  @override
  Widget build(BuildContext context) {
    final deviceName = state.selectedDevice?.name ?? 'Android';
    final statusColor = switch (state.status) {
      DeviceRunStatus.launching => AppColors.warning,
      DeviceRunStatus.reloading => AppColors.secondary,
      _ => AppColors.success,
    };
    final statusLabel = switch (state.status) {
      DeviceRunStatus.launching => 'Lançando • $deviceName',
      DeviceRunStatus.reloading => 'Reload... • $deviceName',
      _ => 'Ao Vivo • $deviceName',
    };
    final canTriggerReload =
        state.activeAppId != null && state.status == DeviceRunStatus.running;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('android_running_badge'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: statusColor.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 135),
                child: Text(
                  statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        _ToolbarIconButton(
          key: const ValueKey('android_hot_reload_button'),
          icon: Icons.bolt_rounded,
          tooltip: 'Hot Reload no aparelho conectado',
          color: canTriggerReload ? AppColors.warning : AppColors.textMuted,
          backgroundColor: canTriggerReload
              ? AppColors.warning.withValues(alpha: 0.12)
              : null,
          borderColor: canTriggerReload
              ? AppColors.warning.withValues(alpha: 0.45)
              : null,
          onPressed:
              canTriggerReload ? () => notifier.hotReload(reason: 'manual') : null,
        ),
        const SizedBox(width: 4),
        _ToolbarIconButton(
          key: const ValueKey('android_hot_restart_button'),
          icon: Icons.restart_alt_rounded,
          tooltip: 'Hot Restart (reinicia estado do app)',
          color: canTriggerReload ? AppColors.secondary : AppColors.textMuted,
          onPressed: canTriggerReload ? notifier.hotRestart : null,
        ),
        const SizedBox(width: 4),
        _ConsoleToggleButton(
          isConsoleOpen: isConsoleOpen,
          hasError: state.status == DeviceRunStatus.error,
          shellCount: shellCount,
          onToggleConsole: onToggleConsole,
        ),
        const SizedBox(width: 4),
        _ToolbarIconButton(
          key: const ValueKey('android_stop_button'),
          icon: Icons.stop_rounded,
          tooltip: 'Encerrar sessão no aparelho Android',
          color: AppColors.danger,
          backgroundColor: AppColors.danger.withValues(alpha: 0.14),
          borderColor: AppColors.danger.withValues(alpha: 0.5),
          onPressed: notifier.stopSession,
        ),
      ],
    );
  }
}

class _DeviceSelectorMenu extends StatelessWidget {
  const _DeviceSelectorMenu({
    required this.devices,
    required this.selected,
    required this.onSelected,
  });

  final List<ConnectedAndroidDevice> devices;
  final ConnectedAndroidDevice selected;
  final ValueChanged<ConnectedAndroidDevice> onSelected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Selecionar aparelho Android (${selected.displayLabel})',
      child: PopupMenuButton<ConnectedAndroidDevice>(
        key: const ValueKey('android_device_selector'),
        color: AppColors.surfaceCard,
        initialValue: selected,
        onSelected: onSelected,
        itemBuilder: (context) => devices
            .map(
              (device) => PopupMenuItem<ConnectedAndroidDevice>(
                value: device,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      device.isEmulator
                          ? Icons.phonelink_setup_rounded
                          : Icons.phone_android_rounded,
                      size: 14,
                      color: device.id == selected.id
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          device.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${device.id} • ${device.isEmulator ? "Emulador" : "USB Físico"} • ${device.sdk}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected.isEmulator
                    ? Icons.phonelink_setup_rounded
                    : Icons.phone_android_rounded,
                size: 11,
                color: selected.isEmulator
                    ? AppColors.secondary
                    : AppColors.success,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 95),
                child: Text(
                  selected.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.arrow_drop_down_rounded,
                size: 13,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsoleToggleButton extends StatelessWidget {
  const _ConsoleToggleButton({
    required this.isConsoleOpen,
    required this.hasError,
    required this.shellCount,
    required this.onToggleConsole,
  });

  final bool isConsoleOpen;
  final bool hasError;
  final int shellCount;
  final VoidCallback? onToggleConsole;

  @override
  Widget build(BuildContext context) {
    final accent = hasError
        ? AppColors.danger
        : isConsoleOpen || shellCount > 0
            ? AppColors.secondary
            : AppColors.textSecondary;
    final tooltip = isConsoleOpen
        ? 'Ocultar terminal persistente (sessões continuam ativas)'
        : 'Abrir terminal persistente / console Android';

    if (shellCount > 0) {
      return _ToolbarActionPill(
        key: const ValueKey('android_logs_button'),
        icon: Icons.terminal_rounded,
        label: '$shellCount',
        tooltip: tooltip,
        accentColor: accent,
        textColor: accent,
        backgroundColor: isConsoleOpen
            ? AppColors.secondary.withValues(alpha: 0.14)
            : AppColors.surface,
        borderColor: isConsoleOpen
            ? AppColors.secondary.withValues(alpha: 0.55)
            : hasError
                ? AppColors.danger.withValues(alpha: 0.55)
                : null,
        onPressed: onToggleConsole,
      );
    }

    return _ToolbarIconButton(
      key: const ValueKey('android_logs_button'),
      icon: Icons.terminal_rounded,
      tooltip: tooltip,
      color: accent,
      backgroundColor: isConsoleOpen
          ? AppColors.secondary.withValues(alpha: 0.14)
          : AppColors.surface,
      borderColor: isConsoleOpen
          ? AppColors.secondary.withValues(alpha: 0.55)
          : hasError
              ? AppColors.danger.withValues(alpha: 0.55)
              : null,
      onPressed: onToggleConsole,
    );
  }
}

class _ToolbarActionPill extends StatelessWidget {
  const _ToolbarActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.accentColor,
    required this.textColor,
    this.backgroundColor,
    this.borderColor,
    this.maxLabelWidth,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final Color accentColor;
  final Color textColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? maxLabelWidth;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: textColor,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
      ),
    );

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor ?? AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: accentColor),
              const SizedBox(width: 4),
              if (maxLabelWidth != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLabelWidth!),
                  child: textWidget,
                )
              else
                textWidget,
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    this.backgroundColor,
    this.borderColor,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(4.5),
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor ?? AppColors.border),
          ),
          child: Icon(icon, size: 13, color: color),
        ),
      ),
    );
  }
}

/// VS Code-style persistent bottom terminal & real-time Android debug console.
///
/// Stays alive across build failures, USB disconnects, and session stops, and
/// lets the user create, switch, restart, resize, and close additional shell tabs.
class AndroidDebugConsolePanel extends ConsumerStatefulWidget {
  const AndroidDebugConsolePanel({
    super.key,
    required this.onClose,
    this.projectPath,
  });

  final VoidCallback onClose;
  final String? projectPath;

  @override
  ConsumerState<AndroidDebugConsolePanel> createState() =>
      _AndroidDebugConsolePanelState();
}

class _AndroidDebugConsolePanelState
    extends ConsumerState<AndroidDebugConsolePanel> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _commandController = TextEditingController();
  late final FocusNode _commandFocusNode;
  int _historyCursor = -1;
  int _lastLineCount = 0;
  String _lastTabId = '';

  @override
  void initState() {
    super.initState();
    _commandFocusNode = FocusNode(onKeyEvent: _handleCommandKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dir = widget.projectPath;
      if (dir != null && dir.trim().isNotEmpty) {
        ref.read(terminalProvider.notifier).setProjectDirectory(dir);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _commandController.dispose();
    _commandFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleCommandKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
    final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!isUp && !isDown) return KeyEventResult.ignored;

    final history = _activeCommandHistory();
    if (history.isEmpty) return KeyEventResult.ignored;

    if (isUp) {
      if (_historyCursor == -1) {
        _historyCursor = history.length - 1;
      } else if (_historyCursor > 0) {
        _historyCursor--;
      }
      _applyCommandText(history[_historyCursor]);
      return KeyEventResult.handled;
    }

    if (_historyCursor == -1) return KeyEventResult.ignored;
    if (_historyCursor < history.length - 1) {
      _historyCursor++;
      _applyCommandText(history[_historyCursor]);
    } else {
      _historyCursor = -1;
      _applyCommandText('');
    }
    return KeyEventResult.handled;
  }

  List<String> _activeCommandHistory() {
    final workspace = ref.read(terminalProvider);
    final active = workspace.activeTab;
    if (active.isInteractiveShell) return active.commandHistory;
    for (final tab in workspace.tabs) {
      if (tab.isInteractiveShell && tab.commandHistory.isNotEmpty) {
        return tab.commandHistory;
      }
    }
    return const [];
  }

  void _applyCommandText(String value) {
    _commandController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _scheduleAutoScroll(int lineCount, String tabId) {
    if (tabId == _lastTabId && lineCount <= _lastLineCount) return;
    _lastTabId = tabId;
    _lastLineCount = lineCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  String _effectiveWorkingDirectory(TerminalWorkspaceState workspace) {
    final fromWidget = (widget.projectPath ?? '').trim();
    if (fromWidget.isNotEmpty) return fromWidget;
    final fromDebug = (ref.read(androidDebugProvider).projectPath ?? '').trim();
    if (fromDebug.isNotEmpty) return fromDebug;
    return workspace.activeTab.workingDirectory;
  }

  Future<void> _runInInteractiveShell(String cmd) async {
    final trimmed = cmd.trim();
    if (trimmed.isEmpty) return;

    final workspace = ref.read(terminalProvider);
    final terminalNotifier = ref.read(terminalProvider.notifier);

    String? targetShellId;
    for (final tab in workspace.tabs) {
      if (tab.isInteractiveShell) {
        targetShellId = tab.id;
        break;
      }
    }
    targetShellId ??= await terminalNotifier.createShellTerminal(
      workingDirectory: _effectiveWorkingDirectory(workspace),
      activate: true,
    );
    terminalNotifier.selectTab(targetShellId);
    await terminalNotifier.sendCommand(targetShellId, trimmed);
  }

  Future<void> _submitCommand(String raw) async {
    final cmd = raw.trim();
    if (cmd.isEmpty) return;

    _commandController.clear();
    _historyCursor = -1;

    final debugState = ref.read(androidDebugProvider);
    final debugNotifier = ref.read(androidDebugProvider.notifier);
    final workspace = ref.read(terminalProvider);
    final terminalNotifier = ref.read(terminalProvider.notifier);
    final activeTab = workspace.activeTab;

    if (activeTab.isPinned) {
      final lower = cmd.toLowerCase();
      if (debugState.isRunningOrReloading) {
        if (cmd == 'r') {
          await debugNotifier.hotReload(reason: 'terminal');
          return;
        }
        if (cmd == 'R') {
          await debugNotifier.hotRestart();
          return;
        }
        if (lower == 'q' || lower == 'quit') {
          await debugNotifier.stopSession();
          return;
        }
      }
      if (lower == 'cls' || lower == 'clear') {
        debugNotifier.clearLogs();
        return;
      }

      // Route shell commands typed in Debug Android into an active/new shell tab
      // so the terminal stays immediately interactive without dead ends.
      await _runInInteractiveShell(cmd);
      return;
    }

    await terminalNotifier.sendCommand(activeTab.id, cmd);
  }

  Future<void> _copyActiveOutput(
    BuildContext context,
    TerminalTabSession activeTab,
    AndroidDebugState debugState,
  ) async {
    final buffer = StringBuffer();
    if (activeTab.isPinned) {
      for (final entry in debugState.logs) {
        buffer.writeln('[${entry.formattedTime}] ${entry.message}');
      }
    } else {
      for (final line in activeTab.lines) {
        buffer.writeln('[${line.formattedTime}] ${line.text}');
      }
    }
    final text = buffer.toString().trimRight();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    AppToast.success(context, 'Saída do terminal "${activeTab.title}" copiada.');
  }

  @override
  Widget build(BuildContext context) {
    final debugState = ref.watch(androidDebugProvider);
    final debugNotifier = ref.read(androidDebugProvider.notifier);
    final workspace = ref.watch(terminalProvider);
    final terminalNotifier = ref.read(terminalProvider.notifier);
    final shellService = ref.read(terminalShellServiceProvider);

    final activeTab = workspace.activeTab;
    final lineCount =
        activeTab.isPinned ? debugState.logs.length : activeTab.lines.length;
    _scheduleAutoScroll(lineCount, activeTab.id);

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final maxResponsiveHeight =
        (viewportHeight * 0.44).clamp(140.0, TerminalWorkspaceState.maxPanelHeight);
    final effectiveHeight = math.min(workspace.panelHeight, maxResponsiveHeight);

    return Container(
      key: const ValueKey('android_debug_console_panel'),
      height: effectiveHeight,
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResizeHandle(terminalNotifier, workspace.panelHeight),
          _buildTabStripHeader(
            context: context,
            workspace: workspace,
            activeTab: activeTab,
            debugState: debugState,
            debugNotifier: debugNotifier,
            terminalNotifier: terminalNotifier,
            shellService: shellService,
          ),
          if (activeTab.isPinned && debugState.buildDiagnostic != null)
            _buildDiagnosticAssistantCard(
              context: context,
              diagnostic: debugState.buildDiagnostic!,
              debugState: debugState,
              debugNotifier: debugNotifier,
              effectiveHeight: effectiveHeight,
            )
          else if (activeTab.isPinned && debugState.errorMessage != null)
            _buildErrorBanner(debugState.errorMessage!, debugNotifier),
          if (!activeTab.isPinned &&
              activeTab.status == TerminalProcessStatus.exited)
            _buildExitedShellBanner(activeTab, terminalNotifier),
          Expanded(
            child: activeTab.isPinned
                ? _buildAndroidDebugLogList(debugState, workspace, terminalNotifier)
                : _buildShellLineList(activeTab),
          ),
          _buildCommandInputBar(
            workspace: workspace,
            activeTab: activeTab,
            debugState: debugState,
          ),
        ],
      ),
    );
  }

  Widget _buildResizeHandle(
    TerminalNotifier terminalNotifier,
    double currentHeight,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (details) {
          terminalNotifier.setPanelHeight(currentHeight - details.delta.dy);
        },
        child: Container(
          height: 5,
          alignment: Alignment.center,
          color: AppColors.surface,
          child: Container(
            width: 34,
            height: 2,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabStripHeader({
    required BuildContext context,
    required TerminalWorkspaceState workspace,
    required TerminalTabSession activeTab,
    required AndroidDebugState debugState,
    required AndroidDebugNotifier debugNotifier,
    required TerminalNotifier terminalNotifier,
    required TerminalShellService shellService,
  }) {
    final availableProfiles = shellService.availableProfiles();

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in workspace.tabs) ...[
                    _TerminalTabChip(
                      tab: tab,
                      isSelected: tab.id == activeTab.id,
                      debugStatus: tab.isPinned ? debugState.status : null,
                      onTap: () => terminalNotifier.selectTab(tab.id),
                      onClose: tab.isPinned
                          ? null
                          : () => terminalNotifier.closeTab(tab.id),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Tooltip(
                    message: 'Criar novo terminal interativo',
                    child: InkWell(
                      key: const ValueKey('terminal_add_tab_button'),
                      onTap: () => terminalNotifier.createShellTerminal(
                        workingDirectory: _effectiveWorkingDirectory(workspace),
                      ),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceCard,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 14,
                              color: AppColors.textPrimary,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'Novo Terminal',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (availableProfiles.length > 1) ...[
                    const SizedBox(width: 2),
                    PopupMenuButton<TerminalShellProfile>(
                      key: const ValueKey('terminal_shell_menu_button'),
                      tooltip: 'Escolher tipo de terminal (PowerShell / CMD)',
                      padding: EdgeInsets.zero,
                      color: AppColors.surfaceCard,
                      onSelected: (profile) =>
                          terminalNotifier.createShellTerminal(
                        workingDirectory: _effectiveWorkingDirectory(workspace),
                        profile: profile,
                      ),
                      itemBuilder: (context) => [
                        for (final profile in availableProfiles)
                          PopupMenuItem(
                            value: profile,
                            height: 32,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.terminal_rounded,
                                  size: 13,
                                  color: AppColors.secondary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Novo ${profile.label}',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceCard,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (activeTab.isPinned && debugState.selectedDevice != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                debugState.selectedDevice!.displayLabel,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (activeTab.isPinned && debugState.progressMessage != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                debugState.progressMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (activeTab.isPinned && debugState.vmServiceUri != null) ...[
            _UriCopyChip(
              label: 'VM Service',
              uri: debugState.vmServiceUri!,
            ),
            const SizedBox(width: 4),
          ],
          if (activeTab.isPinned && debugState.devToolsUri != null) ...[
            _UriCopyChip(
              label: 'DevTools',
              uri: debugState.devToolsUri!,
            ),
            const SizedBox(width: 4),
          ],
          if (activeTab.isInteractiveShell)
            IconButton(
              key: const ValueKey('terminal_restart_button'),
              onPressed: () =>
                  terminalNotifier.restartShellTerminal(activeTab.id),
              icon: const Icon(Icons.restart_alt_rounded, size: 15),
              color: AppColors.textSecondary,
              tooltip: 'Reiniciar sessão deste terminal',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
          IconButton(
            key: const ValueKey('terminal_copy_output_button'),
            onPressed: () => _copyActiveOutput(context, activeTab, debugState),
            icon: const Icon(Icons.content_copy_rounded, size: 13.5),
            color: AppColors.textSecondary,
            tooltip: 'Copiar saída do terminal atual',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
          IconButton(
            key: const ValueKey('android_clear_logs_button'),
            onPressed: () {
              if (activeTab.isPinned) {
                debugNotifier.clearLogs();
              } else {
                terminalNotifier.clearTab(activeTab.id);
              }
            },
            icon: const Icon(Icons.delete_sweep_rounded, size: 15),
            color: AppColors.textSecondary,
            tooltip: 'Limpar saída deste terminal',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
          IconButton(
            key: const ValueKey('android_close_console_button'),
            onPressed: widget.onClose,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
            color: AppColors.textSecondary,
            tooltip: 'Minimizar painel (terminais continuam ativos)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticAssistantCard({
    required BuildContext context,
    required AndroidBuildDiagnostic diagnostic,
    required AndroidDebugState debugState,
    required AndroidDebugNotifier debugNotifier,
    required double effectiveHeight,
  }) {
    final maxCardHeight =
        math.max(36.0, math.min(136.0, (effectiveHeight - 82.0) * 0.65));

    return Container(
      key: const ValueKey('android_build_diagnostic_card'),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: AppColors.warning.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxCardHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.auto_fix_high_rounded,
                      size: 14,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      diagnostic.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (diagnostic.detectedJavaVersion != null ||
                      diagnostic.gradleVersion != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        [
                          if (diagnostic.detectedJavaVersion != null)
                            'Java ${diagnostic.detectedJavaVersion}',
                          if (diagnostic.gradleVersion != null)
                            'Gradle ${diagnostic.gradleVersion}',
                        ].join(' · '),
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  InkWell(
                    key: const ValueKey('android_build_diagnostic_close'),
                    onTap: debugNotifier.dismissBuildDiagnostic,
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
              const SizedBox(height: 5),
              Text(
                diagnostic.explanation,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              if (diagnostic.steps.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final step in diagnostic.steps)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            step,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 7),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (diagnostic.canAutoApplyJdk)
                    ElevatedButton.icon(
                      key: const ValueKey('android_fix_jdk_button'),
                      onPressed: debugState.isApplyingBuildFix
                          ? null
                          : () async {
                              final ok = await debugNotifier
                                  .applyCompatibleJdkAndRelaunch();
                              if (!context.mounted) return;
                              if (ok) {
                                AppToast.success(
                                  context,
                                  'JDK ${diagnostic.compatibleJdk!.version} configurado no Flutter! Relançando app...',
                                );
                              } else {
                                AppToast.error(
                                  context,
                                  'Não foi possível aplicar --jdk-dir automaticamente.',
                                );
                              }
                            },
                      icon: Icon(
                        debugState.isApplyingBuildFix
                            ? Icons.hourglass_top_rounded
                            : Icons.flash_on_rounded,
                        size: 13,
                      ),
                      label: Text(
                        debugState.isApplyingBuildFix
                            ? 'Configurando JDK ${diagnostic.compatibleJdk!.majorVersion}...'
                            : 'Aplicar JDK ${diagnostic.compatibleJdk!.majorVersion} no Flutter e Rodar',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (diagnostic.canAutoFixCmake)
                    ElevatedButton.icon(
                      key: diagnostic.canFixCmakeHostToolchain
                          ? const ValueKey('android_fix_cmake_host_button')
                          : const ValueKey('android_fix_cmake_ninja_button'),
                      onPressed: debugState.isApplyingBuildFix
                          ? null
                          : () async {
                              final ok = await debugNotifier
                                  .applyCmakeFixAndRelaunch();
                              if (!context.mounted) return;
                              if (ok) {
                                AppToast.success(
                                  context,
                                  diagnostic.canFixCmakeHostToolchain
                                      ? 'CMake ajustado para MSVC/glslc e cache .cxx limpo! Relançando app...'
                                      : 'Cache .cxx limpo! Relançando com Ninja e ambiente atualizados...',
                                );
                              } else {
                                AppToast.error(
                                  context,
                                  'Não foi possível aplicar o ajuste CMake/.cxx automaticamente.',
                                );
                              }
                            },
                      icon: Icon(
                        debugState.isApplyingBuildFix
                            ? Icons.hourglass_top_rounded
                            : Icons.auto_fix_high_rounded,
                        size: 13,
                      ),
                      label: Text(
                        debugState.isApplyingBuildFix
                            ? 'Aplicando ajuste CMake...'
                            : (diagnostic.canFixCmakeHostToolchain
                                ? 'Aplicar Fix Host MSVC/Vulkan no CMake e Rodar'
                                : 'Limpar Cache .cxx e Rodar com Ninja'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (diagnostic.suggestedTerminalCommand != null) ...[
                    OutlinedButton.icon(
                      key: const ValueKey('android_run_fix_in_terminal_button'),
                      onPressed: () => _runInInteractiveShell(
                        diagnostic.suggestedTerminalCommand!,
                      ),
                      icon: const Icon(Icons.terminal_rounded, size: 13),
                      label: const Text(
                        'Executar no Terminal',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.secondary,
                        side: BorderSide(
                          color: AppColors.secondary.withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('android_copy_fix_command_button'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: diagnostic.suggestedTerminalCommand!,
                          ),
                        );
                        if (!context.mounted) return;
                        AppToast.success(
                          context,
                          'Comando copiado: ${diagnostic.suggestedTerminalCommand}',
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 12),
                      label: const Text(
                        'Copiar Comando',
                        style: TextStyle(fontSize: 10.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                  if (diagnostic.externalHelpUrl != null)
                    OutlinedButton.icon(
                      key: const ValueKey('android_open_fix_help_url_button'),
                      onPressed: () async {
                        final uri = Uri.tryParse(diagnostic.externalHelpUrl!);
                        if (uri == null) return;
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 12),
                      label: const Text(
                        'Baixar / Guia',
                        style: TextStyle(fontSize: 10.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(
    String errorMessage,
    AndroidDebugNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: AppColors.danger.withValues(alpha: 0.14),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: notifier.dismissError,
            child: const Icon(
              Icons.close_rounded,
              size: 13,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExitedShellBanner(
    TerminalTabSession tab,
    TerminalNotifier terminalNotifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: AppColors.warning.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Shell encerrado (código ${tab.exitCode ?? 0}). O terminal permanece aberto — envie um comando ou reinicie.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => terminalNotifier.restartShellTerminal(tab.id),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: const Size(0, 22),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Reiniciar',
              style: TextStyle(
                color: AppColors.secondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidDebugLogList(
    AndroidDebugState state,
    TerminalWorkspaceState workspace,
    TerminalNotifier terminalNotifier,
  ) {
    if (state.logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              const Text(
                'Terminal persistente pronto — execute no Android ou rode comandos abaixo.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              OutlinedButton.icon(
                onPressed: () => terminalNotifier.createShellTerminal(
                  workingDirectory: _effectiveWorkingDirectory(workspace),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 26),
                ),
                icon: const Icon(
                  Icons.terminal_rounded,
                  size: 12,
                  color: AppColors.secondary,
                ),
                label: const Text(
                  'Abrir Terminal Shell',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: state.logs.length,
      itemBuilder: (context, index) {
        final entry = state.logs[index];
        final msgColor = entry.isError
            ? AppColors.danger
            : entry.isSystem
                ? AppColors.secondary
                : AppColors.textPrimary;

        return _TerminalOutputRow(
          timestamp: entry.formattedTime,
          text: entry.message,
          color: msgColor,
        );
      },
    );
  }

  Widget _buildShellLineList(TerminalTabSession tab) {
    if (tab.lines.isEmpty) {
      return const Center(
        child: Text(
          'Terminal interativo pronto. Digite um comando abaixo.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: tab.lines.length,
      itemBuilder: (context, index) {
        final line = tab.lines[index];
        final color = line.isError
            ? AppColors.danger
            : line.isCommandEcho
                ? AppColors.secondary
                : line.isSystem
                    ? AppColors.textSecondary
                    : AppColors.textPrimary;

        return _TerminalOutputRow(
          timestamp: line.formattedTime,
          text: line.text,
          color: color,
          isBold: line.isCommandEcho,
        );
      },
    );
  }

  Widget _buildCommandInputBar({
    required TerminalWorkspaceState workspace,
    required TerminalTabSession activeTab,
    required AndroidDebugState debugState,
  }) {
    final workDir = _effectiveWorkingDirectory(workspace);
    final dirLabel = activeTab.isPinned
        ? (debugState.isRunningOrReloading ? 'debug' : 'android')
        : (workDir.isNotEmpty ? p.basename(workDir) : 'shell');

    final hint = activeTab.isPinned
        ? (debugState.isRunningOrReloading
            ? 'r = Hot Reload · R = Hot Restart · q = Parar · ou comando CLI...'
            : 'Digite um comando CLI (ex: flutter devices, adb devices, flutter doctor)...')
        : 'Digite um comando (${activeTab.profile.label}) — Enter para executar, ↑/↓ histórico';

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$dirLabel >',
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 10.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('terminal_command_input'),
              controller: _commandController,
              focusNode: _commandFocusNode,
              onSubmitted: _submitCommand,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11.5,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('terminal_send_command_button'),
            onPressed: () => _submitCommand(_commandController.text),
            icon: const Icon(Icons.keyboard_return_rounded, size: 14),
            color: AppColors.secondary,
            tooltip: 'Executar comando',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

class _TerminalTabChip extends StatelessWidget {
  const _TerminalTabChip({
    required this.tab,
    required this.isSelected,
    this.debugStatus,
    required this.onTap,
    this.onClose,
  });

  final TerminalTabSession tab;
  final bool isSelected;
  final DeviceRunStatus? debugStatus;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    if (tab.isPinned) {
      statusColor = switch (debugStatus) {
        DeviceRunStatus.running => AppColors.success,
        DeviceRunStatus.launching => AppColors.warning,
        DeviceRunStatus.reloading => AppColors.secondary,
        DeviceRunStatus.error => AppColors.danger,
        _ => AppColors.textMuted,
      };
    } else {
      statusColor = switch (tab.status) {
        TerminalProcessStatus.running => AppColors.success,
        TerminalProcessStatus.starting => AppColors.warning,
        TerminalProcessStatus.exited =>
          (tab.exitCode ?? 0) != 0 ? AppColors.danger : AppColors.textMuted,
        TerminalProcessStatus.idle => AppColors.textMuted,
      };
    }

    return Tooltip(
      message: tab.workingDirectory.isNotEmpty
          ? '${tab.title} • ${tab.workingDirectory}'
          : tab.title,
      child: InkWell(
        key: ValueKey('terminal_tab_${tab.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: EdgeInsets.only(
            left: 8,
            right: onClose != null ? 4 : 8,
            top: 4,
            bottom: 4,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.backgroundSecondary
                : AppColors.surfaceCard.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.65)
                  : AppColors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                tab.isPinned
                    ? Icons.phone_android_rounded
                    : Icons.terminal_rounded,
                size: 11.5,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                tab.title,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 4),
                InkWell(
                  key: ValueKey('terminal_close_tab_${tab.id}'),
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(3),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalOutputRow extends StatelessWidget {
  const _TerminalOutputRow({
    required this.timestamp,
    required this.text,
    required this.color,
    this.isBold = false,
  });

  final String timestamp;
  final String text;
  final Color color;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[$timestamp] ',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
                height: 1.32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UriCopyChip extends StatelessWidget {
  const _UriCopyChip({
    required this.label,
    required this.uri,
  });

  final String label;
  final String uri;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label: $uri (clique para copiar)',
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: uri));
          if (!context.mounted) return;
          AppToast.success(context, '$label copiado: $uri');
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.link_rounded,
                size: 11,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
