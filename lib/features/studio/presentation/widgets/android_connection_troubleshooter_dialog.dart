import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/flutter_doctor_dialog.dart';
import '../../models/connected_device.dart';
import '../../providers/android_debug_provider.dart';

/// Modal assistant that shows real-time USB, ADB, Android SDK, and Java JDK
/// diagnostics alongside step-by-step instructions to unblock physical device debugging.
class AndroidConnectionTroubleshooterDialog extends ConsumerWidget {
  const AndroidConnectionTroubleshooterDialog({super.key});

  /// Opens the Android USB/SDK connection troubleshooting dialog.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const AndroidConnectionTroubleshooterDialog(),
    );
  }

  Future<void> _copyCommand(BuildContext context, String command) async {
    await Clipboard.setData(ClipboardData(text: command));
    if (!context.mounted) return;
    AppToast.success(context, 'Comando copiado para a área de transferência!');
  }

  Future<void> _openExternalUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        AppToast.error(context, 'Não foi possível abrir o link: $url');
      }
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Erro ao abrir navegador: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(androidDebugProvider);
    final notifier = ref.read(androidDebugProvider.notifier);
    final isScanning = state.status == DeviceRunStatus.scanning;
    final hasConnectedDevices = state.devices.isNotEmpty;

    final diagnostic = state.lastDiagnostic ??
        AndroidConnectionDiagnostic(
          devices: state.devices,
          issueType: hasConnectedDevices
              ? AndroidConnectionIssueType.none
              : AndroidConnectionIssueType.noDeviceConnected,
          title: hasConnectedDevices
              ? 'Aparelho Android pronto para depuração'
              : 'Nenhum aparelho Android pronto ainda',
          summary: hasConnectedDevices
              ? 'Dispositivo detectado e autorizado pelo Flutter.'
              : 'Clique em "Testar Conexão Novamente" para diagnosticar USB, ADB e SDK.',
        );

    final accentColor = hasConnectedDevices
        ? AppColors.success
        : diagnostic.issueType == AndroidConnectionIssueType.scanError
            ? AppColors.danger
            : AppColors.warning;

    return Dialog(
      key: const ValueKey('android_connection_troubleshooter_dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 660,
          maxHeight: 720,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, diagnostic, accentColor),
              const Divider(height: 1, color: AppColors.borderSubtle),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusBanner(
                        state: state,
                        diagnostic: diagnostic,
                        accentColor: accentColor,
                      ),
                      if (diagnostic.checks.isNotEmpty && !hasConnectedDevices) ...[
                        const SizedBox(height: 16),
                        _buildChecksSection(diagnostic.checks),
                      ],
                      if (diagnostic.steps.isNotEmpty && !hasConnectedDevices) ...[
                        const SizedBox(height: 16),
                        _buildStepsSection(diagnostic.steps),
                      ],
                      if (diagnostic.suggestedCommand != null &&
                          !hasConnectedDevices) ...[
                        const SizedBox(height: 16),
                        _buildSuggestedCommandCard(
                          context,
                          diagnostic.suggestedCommand!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.borderSubtle),
              _buildFooter(
                context: context,
                ref: ref,
                state: state,
                notifier: notifier,
                diagnostic: diagnostic,
                isScanning: isScanning,
                hasConnectedDevices: hasConnectedDevices,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AndroidConnectionDiagnostic diagnostic,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Icon(Icons.usb_rounded, color: accentColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assistente de Conexão Android (USB / ADB)',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  diagnostic.detectedUsbDeviceName ??
                      'Diagnóstico automático do celular, drivers USB, ADB e SDK',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('android_troubleshooter_close_icon'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textSecondary,
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner({
    required AndroidDebugState state,
    required AndroidConnectionDiagnostic diagnostic,
    required Color accentColor,
  }) {
    final hasConnected = state.devices.isNotEmpty;
    final bannerTitle = hasConnected
        ? '${state.devices.first.name} conectado e pronto!'
        : diagnostic.title;
    final bannerSummary = hasConnected
        ? 'O aparelho já está liberado para depuração em tempo real no Studio. Feche esta janela e clique em ▶ ${state.devices.first.name}.'
        : diagnostic.summary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasConnected
                ? Icons.check_circle_rounded
                : Icons.warning_amber_rounded,
            color: accentColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bannerTitle,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  bannerSummary,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecksSection(List<AndroidEnvironmentCheck> checks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'O que verificamos neste PC:',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < checks.length; i++) ...[
                _CheckRow(check: checks[i]),
                if (i < checks.length - 1)
                  const Divider(height: 1, color: AppColors.borderSubtle),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepsSection(List<String> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Como resolver (passo a passo):',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                if (i < steps.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestedCommandCard(BuildContext context, String command) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.terminal_rounded,
                size: 14,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Comando rápido no PowerShell / Terminal:',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('android_troubleshooter_copy_command_button'),
                onPressed: () => _copyCommand(context, command),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Copiar Comando'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: SelectableText(
              command,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter({
    required BuildContext context,
    required WidgetRef ref,
    required AndroidDebugState state,
    required AndroidDebugNotifier notifier,
    required AndroidConnectionDiagnostic diagnostic,
    required bool isScanning,
    required bool hasConnectedDevices,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('android_troubleshooter_doctor_button'),
            onPressed: () => FlutterDoctorDialog.show(context),
            icon: const Icon(Icons.medical_services_outlined, size: 15),
            label: const Text('Flutter Doctor'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
            ),
          ),
          if (!hasConnectedDevices && diagnostic.discoveredSdkPath != null)
            OutlinedButton.icon(
              key: const ValueKey('android_troubleshooter_configure_sdk_button'),
              onPressed: isScanning
                  ? null
                  : () async {
                      final ok = await notifier
                          .configureAndroidSdk(diagnostic.discoveredSdkPath!);
                      if (!context.mounted) return;
                      if (ok) {
                        AppToast.success(
                          context,
                          'Android SDK vinculado no Flutter! Testando aparelho...',
                        );
                      } else {
                        AppToast.error(
                          context,
                          'Não foi possível executar flutter config --android-sdk.',
                        );
                      }
                    },
              icon: const Icon(Icons.build_rounded, size: 15),
              label: const Text('Configurar SDK no Flutter'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.secondary,
                side: BorderSide(
                  color: AppColors.secondary.withValues(alpha: 0.45),
                ),
              ),
            ),
          if (!hasConnectedDevices && diagnostic.actionUrl != null)
            OutlinedButton.icon(
              key: const ValueKey('android_troubleshooter_external_link_button'),
              onPressed: () => _openExternalUrl(context, diagnostic.actionUrl!),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: Text(diagnostic.actionUrlLabel ?? 'Abrir Guia'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.secondary,
                side: BorderSide(
                  color: AppColors.secondary.withValues(alpha: 0.45),
                ),
              ),
            ),
          if (hasConnectedDevices)
            ElevatedButton.icon(
              key: const ValueKey('android_troubleshooter_done_button'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Concluir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.black,
              ),
            )
          else
            ElevatedButton.icon(
              key: const ValueKey('android_troubleshooter_rescan_button'),
              onPressed: isScanning
                  ? null
                  : () async {
                      await notifier.scanDevices();
                      if (!context.mounted) return;
                      final next = ref.read(androidDebugProvider);
                      if (next.devices.isNotEmpty) {
                        AppToast.success(
                          context,
                          '${next.devices.first.name} detectado e pronto!',
                        );
                      }
                    },
              icon: isScanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                isScanning ? 'Testando...' : 'Testar Conexão Novamente',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textPrimary,
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final AndroidEnvironmentCheck check;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.status) {
      DiagnosticCheckStatus.ok => (Icons.check_circle_rounded, AppColors.success),
      DiagnosticCheckStatus.warning => (Icons.info_rounded, AppColors.warning),
      DiagnosticCheckStatus.error => (Icons.cancel_rounded, AppColors.danger),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  check.detail,
                  style: TextStyle(
                    color: check.status == DiagnosticCheckStatus.error
                        ? AppColors.danger
                        : AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
