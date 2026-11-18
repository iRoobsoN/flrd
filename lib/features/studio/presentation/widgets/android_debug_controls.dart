import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../ai/providers/ai_settings_provider.dart';
import '../../models/connected_device.dart';
import '../../models/terminal_session.dart';
import '../../providers/android_debug_provider.dart';
import '../../providers/terminal_provider.dart';
import '../../services/diagnostic_code_fix_service.dart';
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
  bool _isApplyingShellPatch = false;

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
              effectiveHeight: effectiveHeight,
              isApplyingBuildFix: debugState.isApplyingBuildFix,
              isScanningOrLaunching:
                  debugState.status == DeviceRunStatus.scanning ||
                  debugState.status == DeviceRunStatus.launching,
              fallbackLogLines: debugState.logs
                  .skip(math.max(0, debugState.logs.length - 40))
                  .map((entry) => entry.message)
                  .toList(growable: false),
              onDismiss: debugNotifier.dismissBuildDiagnostic,
              onGenerateAiDiagnosis: (apiKey) =>
                  debugNotifier.generateAiDiagnosisForCurrentDiagnostic(
                projectPath: widget.projectPath,
                apiKey: apiKey,
              ),
              onApplyPatches: (selectedPatches, relaunchAfterApply) =>
                  debugNotifier.applyDiagnosticPatches(
                projectPath: widget.projectPath,
                selectedPatches: selectedPatches,
                relaunchAfterApply: relaunchAfterApply,
              ),
              onRevertPatches: () => debugNotifier.revertLastDiagnosticPatches(
                projectPath: widget.projectPath,
              ),
              onApplyJdkFix: () =>
                  debugNotifier.applyCompatibleJdkAndRelaunch(),
              onApplyCmakeFix: () => debugNotifier.applyCmakeFixAndRelaunch(),
              onRescanAndRelaunch: () => debugNotifier.rescanAndRelaunch(
                projectPath: widget.projectPath,
              ),
              showRelaunchAfterPatchOption: true,
            )
          else if (activeTab.isPinned && debugState.errorMessage != null)
            _buildErrorBanner(debugState.errorMessage!, debugNotifier),
          if (!activeTab.isPinned &&
              activeTab.status == TerminalProcessStatus.exited)
            _buildExitedShellBanner(activeTab, terminalNotifier),
          if (!activeTab.isPinned && activeTab.diagnostic != null)
            _buildDiagnosticAssistantCard(
              context: context,
              diagnostic: activeTab.diagnostic!,
              effectiveHeight: effectiveHeight,
              isApplyingBuildFix: _isApplyingShellPatch,
              isScanningOrLaunching: false,
              fallbackLogLines: activeTab.lines
                  .skip(math.max(0, activeTab.lines.length - 40))
                  .map((line) => line.text)
                  .toList(growable: false),
              onDismiss: () =>
                  terminalNotifier.dismissTabDiagnostic(activeTab.id),
              onGenerateAiDiagnosis: (apiKey) =>
                  terminalNotifier.generateAiDiagnosisForTab(
                activeTab.id,
                apiKey: apiKey,
              ),
              onApplyPatches: (selectedPatches, _) async {
                setState(() => _isApplyingShellPatch = true);
                try {
                  return await terminalNotifier.applyPatchesForTab(
                    activeTab.id,
                    selectedPatches: selectedPatches,
                  );
                } finally {
                  if (mounted) {
                    setState(() => _isApplyingShellPatch = false);
                  }
                }
              },
              onRevertPatches: () async {
                setState(() => _isApplyingShellPatch = true);
                try {
                  return await terminalNotifier.revertPatchesForTab(
                    activeTab.id,
                  );
                } finally {
                  if (mounted) {
                    setState(() => _isApplyingShellPatch = false);
                  }
                }
              },
              showRelaunchAfterPatchOption: false,
            ),
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

  String _buildAiDiagnosticReport(
    AndroidBuildDiagnostic diagnostic,
    List<String> fallbackLogLines,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('=== FLRD Android Diagnostic Report ===');
    buffer.writeln('Título: ${diagnostic.title}');
    buffer.writeln('Tipo: ${diagnostic.issueType.name}');
    buffer.writeln('Runtime crash: ${diagnostic.isRuntimeCrash ? "sim" : "não"}');
    if (diagnostic.affectedLocation != null &&
        diagnostic.affectedLocation!.trim().isNotEmpty) {
      buffer.writeln('Local afetado: ${diagnostic.affectedLocation}');
    }
    if (diagnostic.crashSummary != null &&
        diagnostic.crashSummary!.trim().isNotEmpty) {
      buffer.writeln('Resumo do erro: ${diagnostic.crashSummary}');
    }
    buffer.writeln();
    buffer.writeln('Explicação:');
    buffer.writeln(diagnostic.explanation);
    if (diagnostic.steps.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Passos recomendados:');
      for (final step in diagnostic.steps) {
        buffer.writeln('- $step');
      }
    }
    final logLines = diagnostic.relevantLogLines.isNotEmpty
        ? diagnostic.relevantLogLines
        : fallbackLogLines;
    if (logLines.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Logs relevantes:');
      for (final line in logLines) {
        buffer.writeln(line);
      }
    }
    if (diagnostic.aiFixSuggestion != null &&
        diagnostic.aiFixSuggestion!.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Solução sugerida pela IA:');
      buffer.writeln(diagnostic.aiFixSuggestion);
    }
    if (diagnostic.suggestedPatches.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Correções sugeridas nos arquivos:');
      for (final patch in diagnostic.suggestedPatches) {
        buffer.writeln('- ${patch.relativePath}: ${patch.description}');
      }
    }
    return buffer.toString().trimRight();
  }

  Widget _buildDiagnosticAssistantCard({
    required BuildContext context,
    required AndroidBuildDiagnostic diagnostic,
    required double effectiveHeight,
    required bool isApplyingBuildFix,
    required bool isScanningOrLaunching,
    required List<String> fallbackLogLines,
    required VoidCallback onDismiss,
    required Future<String?> Function(String? apiKey) onGenerateAiDiagnosis,
    required Future<AppPatchApplyResult> Function(
      List<DiagnosticFilePatch> selectedPatches,
      bool relaunchAfterApply,
    )? onApplyPatches,
    required Future<bool> Function()? onRevertPatches,
    Future<bool> Function()? onApplyJdkFix,
    Future<bool> Function()? onApplyCmakeFix,
    Future<bool> Function()? onRescanAndRelaunch,
    bool showRelaunchAfterPatchOption = true,
  }) {
    final hasAiFix = diagnostic.aiFixSuggestion != null &&
        diagnostic.aiFixSuggestion!.trim().isNotEmpty;
    final desiredCap = hasAiFix
        ? 245.0
        : (diagnostic.hasSuggestedPatches ? 220.0 : 175.0);
    final maxCardHeight =
        math.max(36.0, math.min(desiredCap, (effectiveHeight - 82.0) * 0.65));
    final accentColor =
        diagnostic.isRuntimeCrash ? AppColors.danger : AppColors.warning;

    return Container(
      key: const ValueKey('android_build_diagnostic_card'),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: accentColor.withValues(alpha: 0.35),
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
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      diagnostic.isRuntimeCrash
                          ? Icons.bug_report_rounded
                          : Icons.auto_fix_high_rounded,
                      size: 14,
                      color: accentColor,
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
                  if (diagnostic.isRuntimeCrash) ...[
                    const SizedBox(width: 6),
                    Container(
                      key: const ValueKey('android_runtime_crash_badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Text(
                        'Crash em Runtime',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
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
                    onTap: onDismiss,
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
              if (diagnostic.affectedLocation != null &&
                  diagnostic.affectedLocation!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  key: const ValueKey('android_diagnostic_location_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.my_location_rounded,
                        size: 11,
                        color: accentColor,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Onde: ${diagnostic.affectedLocation!}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (diagnostic.appliedFixSummary != null &&
                  diagnostic.appliedFixSummary!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  key: const ValueKey('android_applied_fix_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 11,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          diagnostic.appliedFixSummary!,
                          style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (diagnostic.crashSummary != null &&
                  diagnostic.crashSummary!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  diagnostic.crashSummary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accentColor,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
                        Text(
                          '• ',
                          style: TextStyle(
                            color: accentColor,
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
                  if (diagnostic.hasSuggestedPatches && onApplyPatches != null)
                    ElevatedButton.icon(
                      key: const ValueKey('android_apply_patches_button'),
                      onPressed: isApplyingBuildFix
                          ? null
                          : () => _showPatchPreviewAndApplyDialog(
                                context: context,
                                diagnostic: diagnostic,
                                onApplyPatches: onApplyPatches,
                                showRelaunchAfterPatchOption:
                                    showRelaunchAfterPatchOption,
                              ),
                      icon: Icon(
                        isApplyingBuildFix
                            ? Icons.hourglass_top_rounded
                            : Icons.build_circle_rounded,
                        size: 13,
                      ),
                      label: Text(
                        isApplyingBuildFix
                            ? 'Aplicando Correções...'
                            : 'Ver & Aplicar Correções (${diagnostic.suggestedPatches.length})',
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
                  if (diagnostic.canRevertAppliedPatches &&
                      onRevertPatches != null)
                    OutlinedButton.icon(
                      key: const ValueKey('android_revert_patches_button'),
                      onPressed: isApplyingBuildFix
                          ? null
                          : () async {
                              final ok = await onRevertPatches();
                              if (!context.mounted) return;
                              if (ok) {
                                AppToast.success(
                                  context,
                                  'Backup restaurado! Arquivos originais recuperados.',
                                );
                              } else {
                                AppToast.error(
                                  context,
                                  'Não foi possível restaurar o backup anterior.',
                                );
                              }
                            },
                      icon: const Icon(Icons.undo_rounded, size: 13),
                      label: const Text(
                        'Reverter Backup',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: BorderSide(
                          color: AppColors.warning.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (diagnostic.canAutoApplyJdk && onApplyJdkFix != null)
                    ElevatedButton.icon(
                      key: const ValueKey('android_fix_jdk_button'),
                      onPressed: isApplyingBuildFix
                          ? null
                          : () async {
                              final ok = await onApplyJdkFix();
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
                        isApplyingBuildFix
                            ? Icons.hourglass_top_rounded
                            : Icons.flash_on_rounded,
                        size: 13,
                      ),
                      label: Text(
                        isApplyingBuildFix
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
                  if (diagnostic.canAutoFixCmake && onApplyCmakeFix != null)
                    ElevatedButton.icon(
                      key: diagnostic.canFixCmakeHostToolchain
                          ? const ValueKey('android_fix_cmake_host_button')
                          : (diagnostic.issueType ==
                                  AndroidBuildIssueType.cmakeMsvcEnvironmentMissing
                              ? const ValueKey('android_fix_cmake_msvc_env_button')
                              : const ValueKey('android_fix_cmake_ninja_button')),
                      onPressed: isApplyingBuildFix
                          ? null
                          : () async {
                              final ok = await onApplyCmakeFix();
                              if (!context.mounted) return;
                              if (ok) {
                                AppToast.success(
                                  context,
                                  diagnostic.canFixCmakeHostToolchain
                                      ? 'CMake ajustado para MSVC/glslc e cache .cxx limpo! Relançando app...'
                                      : (diagnostic.issueType ==
                                              AndroidBuildIssueType
                                                  .cmakeMsvcEnvironmentMissing
                                          ? 'Gradle Daemon reiniciado com Windows SDK e cache .cxx limpo! Relançando...'
                                          : 'Cache .cxx limpo! Relançando com Ninja e ambiente atualizados...'),
                                );
                              } else {
                                AppToast.error(
                                  context,
                                  'Não foi possível aplicar o ajuste CMake/.cxx automaticamente.',
                                );
                              }
                            },
                      icon: Icon(
                        isApplyingBuildFix
                            ? Icons.hourglass_top_rounded
                            : Icons.auto_fix_high_rounded,
                        size: 13,
                      ),
                      label: Text(
                        isApplyingBuildFix
                            ? 'Aplicando ajuste CMake...'
                            : (diagnostic.canFixCmakeHostToolchain
                                ? 'Aplicar Fix Host MSVC/Vulkan no CMake e Rodar'
                                : (diagnostic.issueType ==
                                        AndroidBuildIssueType
                                            .cmakeMsvcEnvironmentMissing
                                    ? 'Reiniciar Gradle Daemon, Limpar .cxx e Rodar'
                                    : 'Limpar Cache .cxx e Rodar com Ninja')),
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
                  if (diagnostic.canRescanAndRelaunch &&
                      onRescanAndRelaunch != null)
                    ElevatedButton.icon(
                      key: const ValueKey('android_rescan_and_run_button'),
                      onPressed: (isScanningOrLaunching || isApplyingBuildFix)
                          ? null
                          : () async {
                              final ok = await onRescanAndRelaunch();
                              if (!context.mounted) return;
                              if (ok) {
                                AppToast.success(
                                  context,
                                  'Dispositivo re-detectado! Relançando app...',
                                );
                              } else {
                                AppToast.error(
                                  context,
                                  'Nenhum dispositivo Android detectado no ADB.',
                                );
                              }
                            },
                      icon: Icon(
                        isScanningOrLaunching
                            ? Icons.hourglass_top_rounded
                            : Icons.usb_rounded,
                        size: 13,
                      ),
                      label: Text(
                        isScanningOrLaunching
                            ? 'Escaneando ADB...'
                            : 'Re-detectar & Rodar',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ElevatedButton.icon(
                    key: const ValueKey('android_ai_diagnose_button'),
                    onPressed: diagnostic.isGeneratingAiFix
                        ? null
                        : () async {
                            final apiKey = ref.read(aiSettingsProvider).apiKey;
                            final suggestion = await onGenerateAiDiagnosis(
                              apiKey,
                            );
                            if (!context.mounted) return;
                            if (suggestion != null &&
                                suggestion.trim().isNotEmpty) {
                              AppToast.success(
                                context,
                                'Diagnóstico e sugestão de correção gerados!',
                              );
                            }
                          },
                    icon: Icon(
                      diagnostic.isGeneratingAiFix
                          ? Icons.hourglass_top_rounded
                          : Icons.auto_awesome_rounded,
                      size: 13,
                    ),
                    label: Text(
                      diagnostic.isGeneratingAiFix
                          ? 'Analisando com IA...'
                          : 'Gerar Solução com IA',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('android_copy_ai_report_button'),
                    onPressed: () async {
                      final report =
                          _buildAiDiagnosticReport(diagnostic, fallbackLogLines);
                      await Clipboard.setData(ClipboardData(text: report));
                      if (!context.mounted) return;
                      AppToast.success(
                        context,
                        'Relatório completo copiado para colar na IA.',
                      );
                    },
                    icon: const Icon(Icons.assignment_rounded, size: 12),
                    label: const Text(
                      'Copiar Relatório p/ IA',
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
              if (diagnostic.aiFixError != null &&
                  diagnostic.aiFixError!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Falha na análise com IA: ${diagnostic.aiFixError!}',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (hasAiFix) ...[
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('android_ai_fix_box'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            size: 12,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 5),
                          const Expanded(
                            child: Text(
                              'Análise & Solução Sugerida (IA)',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          InkWell(
                            key: const ValueKey('android_copy_ai_fix_button'),
                            onTap: () async {
                              await Clipboard.setData(
                                ClipboardData(text: diagnostic.aiFixSuggestion!),
                              );
                              if (!context.mounted) return;
                              AppToast.success(
                                context,
                                'Solução da IA copiada!',
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.copy_rounded,
                                    size: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Copiar Solução',
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
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        diagnostic.aiFixSuggestion!,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 10.8,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPatchPreviewAndApplyDialog({
    required BuildContext context,
    required AndroidBuildDiagnostic diagnostic,
    required Future<AppPatchApplyResult> Function(
      List<DiagnosticFilePatch> selectedPatches,
      bool relaunchAfterApply,
    ) onApplyPatches,
    required bool showRelaunchAfterPatchOption,
  }) async {
    final patches = diagnostic.suggestedPatches;
    if (patches.isEmpty) return;

    final selectedFlags = List<bool>.filled(patches.length, true);
    var isSubmitting = false;

    Future<void> handleApply({
      required BuildContext dialogContext,
      required StateSetter setDialogState,
      required bool relaunch,
    }) async {
      final chosen = <DiagnosticFilePatch>[
        for (var i = 0; i < patches.length; i++)
          if (selectedFlags[i]) patches[i],
      ];
      if (chosen.isEmpty) return;
      setDialogState(() => isSubmitting = true);
      final result = await onApplyPatches(chosen, relaunch);
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      if (!context.mounted) return;
      if (result.isSuccess) {
        final cxxInfo = result.clearedCxxCache ? ' + cache .cxx limpo' : '';
        AppToast.success(
          context,
          '${result.appliedCount} correção(ões) aplicada(s)$cxxInfo!',
        );
      } else {
        AppToast.error(
          context,
          result.errorMessage ?? 'Nenhum patch pôde ser aplicado.',
        );
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final selectedCount = selectedFlags.where((v) => v).length;
            return Dialog(
              key: const ValueKey('android_patch_preview_dialog'),
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.borderHover),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 680,
                  maxHeight: 540,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_fix_high_rounded,
                            size: 18,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Preview & Aplicação Segura de Correções',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: AppColors.textSecondary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Text(
                          'Antes de editar qualquer arquivo, o FLRD cria backup automático em .flrd/backups/patch_<timestamp>/ e limpa android/app/.cxx quando houver alteração C++/CMake.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: patches.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final patch = patches[i];
                            return Material(
                              color: AppColors.surfaceCard,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: selectedFlags[i]
                                      ? AppColors.success
                                          .withValues(alpha: 0.45)
                                      : AppColors.border,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CheckboxListTile(
                                    key: ValueKey('patch_preview_checkbox_$i'),
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    activeColor: AppColors.success,
                                    value: selectedFlags[i],
                                    onChanged: isSubmitting
                                        ? null
                                        : (v) => setDialogState(
                                              () =>
                                                  selectedFlags[i] = v ?? false,
                                            ),
                                    title: Text(
                                      patch.relativePath,
                                      style: const TextStyle(
                                        color: AppColors.secondary,
                                        fontFamily: 'monospace',
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      patch.description,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  if (patch.searchText.isNotEmpty)
                                    _PatchDiffSection(
                                      prefix: '-',
                                      code: patch.searchText,
                                      accentColor: AppColors.danger,
                                    ),
                                  _PatchDiffSection(
                                    prefix: '+',
                                    code: patch.replaceText,
                                    accentColor: AppColors.success,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('confirm_apply_patches_button'),
                            onPressed: (isSubmitting || selectedCount == 0)
                                ? null
                                : () => handleApply(
                                      dialogContext: dialogContext,
                                      setDialogState: setDialogState,
                                      relaunch: false,
                                    ),
                            icon: Icon(
                              isSubmitting
                                  ? Icons.hourglass_top_rounded
                                  : Icons.check_rounded,
                              size: 14,
                            ),
                            label: Text(
                              isSubmitting
                                  ? 'Aplicando...'
                                  : 'Aplicar Correções ($selectedCount)',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.border),
                            ),
                          ),
                          if (showRelaunchAfterPatchOption)
                            ElevatedButton.icon(
                              key: const ValueKey(
                                'confirm_apply_and_run_patches_button',
                              ),
                              onPressed: (isSubmitting || selectedCount == 0)
                                  ? null
                                  : () => handleApply(
                                        dialogContext: dialogContext,
                                        setDialogState: setDialogState,
                                        relaunch: true,
                                      ),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 15,
                              ),
                              label: const Text('Aplicar e Rodar no Celular'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
        final isHeader = entry.isResolution &&
            (entry.message.startsWith('🔧') || entry.message.startsWith('══'));
        final msgColor = entry.isResolution
            ? (isHeader ? AppColors.success : const Color(0xFF6EE7B7))
            : entry.isError
                ? AppColors.danger
                : entry.isSystem
                    ? AppColors.secondary
                    : AppColors.textPrimary;

        return _TerminalOutputRow(
          timestamp: entry.formattedTime,
          text: entry.message,
          color: msgColor,
          isBold: isHeader,
          isResolution: entry.isResolution,
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
        final isHeader = line.isResolution &&
            (line.text.startsWith('🔧') || line.text.startsWith('══'));
        final color = line.isResolution
            ? (isHeader ? AppColors.success : const Color(0xFF6EE7B7))
            : line.isError
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
          isBold: line.isCommandEcho || isHeader,
          isResolution: line.isResolution,
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
        TerminalProcessStatus.running => tab.diagnostic != null
            ? (tab.diagnostic!.isRuntimeCrash
                ? AppColors.danger
                : AppColors.warning)
            : AppColors.success,
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
    this.isResolution = false,
  });

  final String timestamp;
  final String text;
  final Color color;
  final bool isBold;
  final bool isResolution;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '[$timestamp] ',
          style: TextStyle(
            color: isResolution
                ? AppColors.success.withValues(alpha: 0.72)
                : AppColors.textMuted,
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
    );

    if (!isResolution) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: row,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(
            color: AppColors.success.withValues(alpha: 0.7),
            width: 2,
          ),
        ),
      ),
      child: row,
    );
  }
}

class _PatchDiffSection extends StatelessWidget {
  const _PatchDiffSection({
    required this.prefix,
    required this.code,
    required this.accentColor,
  });

  final String prefix;
  final String code;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final preview = code
        .split('\n')
        .map((line) => '$prefix $line')
        .join('\n');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 110),
        child: SingleChildScrollView(
          child: SelectableText(
            preview,
            style: TextStyle(
              color: accentColor == AppColors.success
                  ? const Color(0xFF6EE7B7)
                  : const Color(0xFFFCA5A5),
              fontFamily: 'monospace',
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ),
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
