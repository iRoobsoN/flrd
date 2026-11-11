import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../localization/language_provider.dart';
import '../services/flutter_sdk_service.dart';
import '../theme/app_colors.dart';

class FlutterSdkDialog extends ConsumerStatefulWidget {
  final bool requiredForGeneration;
  final VoidCallback? onProceedDryRun;

  const FlutterSdkDialog({
    super.key,
    this.requiredForGeneration = false,
    this.onProceedDryRun,
  });

  static Future<void> show(
    BuildContext context, {
    bool requiredForGeneration = false,
    VoidCallback? onProceedDryRun,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => FlutterSdkDialog(
        requiredForGeneration: requiredForGeneration,
        onProceedDryRun: onProceedDryRun,
      ),
    );
  }

  @override
  ConsumerState<FlutterSdkDialog> createState() => _FlutterSdkDialogState();
}

class _FlutterSdkDialogState extends ConsumerState<FlutterSdkDialog> {
  bool _isRechecking = false;

  Future<void> _openInstallUrl() async {
    const url = 'https://docs.flutter.dev/get-started/install';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _handleRecheck() async {
    setState(() => _isRechecking = true);
    await ref.read(flutterSdkProvider.notifier).checkSdk();
    if (mounted) {
      setState(() => _isRechecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sdk = ref.watch(flutterSdkProvider);
    final strings = ref.watch(appStringsProvider);

    final isReady = sdk.isInstalled;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        width: 560,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isReady
                ? AppColors.success.withOpacity(0.3)
                : AppColors.warning.withOpacity(0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isReady
                          ? AppColors.success.withOpacity(0.15)
                          : AppColors.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isReady ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                      color: isReady ? AppColors.success : AppColors.warning,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.flutterSdkDialogTitle,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isReady
                              ? 'Host environment is validated and ready for build operations.'
                              : 'Flutter SDK was not found in your system PATH.',
                          style: TextStyle(
                            color: isReady ? AppColors.success : AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.textMuted,
                    splashRadius: 16,
                  ),
                ],
              ),
            ),

            // Content Body
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isReady) ...[
                    // Success View
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                                ),
                                child: Text(
                                  'Flutter ${sdk.version ?? "Ready"}',
                                  style: const TextStyle(
                                    color: AppColors.success,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Detected & Active',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Executable Location:',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            sdk.sdkPath ?? 'flutter',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'All host features are active: flutter create scaffolding, dependency resolution, AST injection, and VS Code terminal bridging.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                    ),
                  ] else ...[
                    // Missing SDK Guide View
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Why is the Flutter SDK required?',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'FLRD uses your local Flutter CLI to generate clean architecture files, resolve pubspec dependencies, and configure platform permissions on disk. The UI, AI Studio, and Architecture Explorer remain fully functional.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '3-Step Quick Setup Guide:',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildStepRow(
                      step: '1',
                      title: 'Download the Flutter SDK archive',
                      desc: 'Get the official bundle for Windows, macOS or Linux from docs.flutter.dev.',
                    ),
                    const SizedBox(height: 6),
                    _buildStepRow(
                      step: '2',
                      title: 'Extract to a clean folder',
                      desc: 'Recommended: C:\\src\\flutter (avoid folders requiring admin rights like Program Files).',
                    ),
                    const SizedBox(height: 6),
                    _buildStepRow(
                      step: '3',
                      title: 'Add to System PATH',
                      desc: 'Add C:\\src\\flutter\\bin to your Environment Variables, then click "Re-check System".',
                    ),
                  ],
                ],
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(
                  top: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!isReady)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _openInstallUrl,
                          icon: const Icon(Icons.open_in_new_rounded, size: 14),
                          label: Text(
                            strings.downloadFlutter,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isRechecking ? null : _handleRecheck,
                        icon: _isRechecking
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondary),
                              )
                            : const Icon(Icons.refresh_rounded, size: 14, color: AppColors.secondary),
                        label: Text(
                          strings.recheckSdk,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.requiredForGeneration && widget.onProceedDryRun != null)
                        TextButton(
                          onPressed: widget.onProceedDryRun,
                          child: const Text(
                            'Continue in Dry-Run Mode',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildStepRow({
    required String step,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.2),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
          ),
          child: Text(
            step,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
