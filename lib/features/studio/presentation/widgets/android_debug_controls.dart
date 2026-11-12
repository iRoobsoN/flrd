import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../models/connected_device.dart';
import '../../providers/android_debug_provider.dart';
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

    if (state.isActiveSession) {
      return _ActiveSessionControls(
        state: state,
        notifier: notifier,
        isConsoleOpen: isConsoleOpen,
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
            label: isScanning ? 'Buscando Android...' : 'Android USB',
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
          if (state.status == DeviceRunStatus.error ||
              state.logs.isNotEmpty ||
              isConsoleOpen) ...[
            const SizedBox(width: 4),
            _ConsoleToggleButton(
              isConsoleOpen: isConsoleOpen,
              hasError: state.status == DeviceRunStatus.error,
              onToggleConsole: onToggleConsole,
            ),
          ],
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
        if (hasError || state.logs.isNotEmpty || isConsoleOpen) ...[
          const SizedBox(width: 4),
          _ConsoleToggleButton(
            isConsoleOpen: isConsoleOpen,
            hasError: hasError,
            onToggleConsole: onToggleConsole,
          ),
        ],
      ],
    );
  }
}

class _ActiveSessionControls extends StatelessWidget {
  const _ActiveSessionControls({
    required this.state,
    required this.notifier,
    required this.isConsoleOpen,
    required this.onToggleConsole,
  });

  final AndroidDebugState state;
  final AndroidDebugNotifier notifier;
  final bool isConsoleOpen;
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
    required this.onToggleConsole,
  });

  final bool isConsoleOpen;
  final bool hasError;
  final VoidCallback? onToggleConsole;

  @override
  Widget build(BuildContext context) {
    final accent = hasError
        ? AppColors.danger
        : isConsoleOpen
            ? AppColors.secondary
            : AppColors.textSecondary;
    return _ToolbarActionPill(
      key: const ValueKey('android_logs_button'),
      icon: Icons.terminal_rounded,
      label: 'Logs',
      tooltip: isConsoleOpen
          ? 'Ocultar console de debug Android'
          : 'Exibir console de debug Android',
      accentColor: accent,
      textColor: isConsoleOpen || hasError ? accent : AppColors.textPrimary,
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

/// Collapsible real-time console panel displaying `flutter run --machine`
/// build progress, VM Service/DevTools URIs, and device log output.
class AndroidDebugConsolePanel extends ConsumerWidget {
  const AndroidDebugConsolePanel({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(androidDebugProvider);
    final notifier = ref.read(androidDebugProvider.notifier);

    final statusColor = switch (state.status) {
      DeviceRunStatus.running => AppColors.success,
      DeviceRunStatus.launching => AppColors.warning,
      DeviceRunStatus.reloading => AppColors.secondary,
      DeviceRunStatus.error => AppColors.danger,
      _ => AppColors.textMuted,
    };

    return Container(
      key: const ValueKey('android_debug_console_panel'),
      height: 196,
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildConsoleHeader(context, state, notifier, statusColor),
          if (state.errorMessage != null)
            _buildErrorBanner(state.errorMessage!, notifier),
          Expanded(child: _buildLogList(state.logs)),
        ],
      ),
    );
  }

  Widget _buildConsoleHeader(
    BuildContext context,
    AndroidDebugState state,
    AndroidDebugNotifier notifier,
    Color statusColor,
  ) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Console Android Real-Time',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (state.selectedDevice != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                state.selectedDevice!.displayLabel,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
          ],
          if (state.progressMessage != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                state.progressMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 10,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (state.vmServiceUri != null) ...[
            _UriCopyChip(
              label: 'VM Service',
              uri: state.vmServiceUri!,
            ),
            const SizedBox(width: 6),
          ],
          if (state.devToolsUri != null) ...[
            _UriCopyChip(
              label: 'DevTools',
              uri: state.devToolsUri!,
            ),
            const SizedBox(width: 6),
          ],
          IconButton(
            key: const ValueKey('android_clear_logs_button'),
            onPressed: notifier.clearLogs,
            icon: const Icon(Icons.delete_sweep_rounded, size: 15),
            color: AppColors.textSecondary,
            tooltip: 'Limpar logs',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
          const SizedBox(width: 2),
          IconButton(
            key: const ValueKey('android_close_console_button'),
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 15),
            color: AppColors.textSecondary,
            tooltip: 'Fechar console',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(
    String errorMessage,
    AndroidDebugNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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

  Widget _buildLogList(List<DeviceLogEntry> logs) {
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'Aguardando saída do dispositivo Android...',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final entry = logs[index];
        final msgColor = entry.isError
            ? AppColors.danger
            : entry.isSystem
                ? AppColors.secondary
                : AppColors.textPrimary;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '[${entry.formattedTime}] ',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              Expanded(
                child: SelectableText(
                  entry.message,
                  style: TextStyle(
                    color: msgColor,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
