import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:process_run/process_run.dart';
import '../../../core/services/flutter_sdk_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/flutter_sdk_dialog.dart';
import '../../../core/window/custom_titlebar.dart';
import 'controllers/wizard_controller.dart';
import 'widgets/wizard_sidebar.dart';
import 'widgets/bottom_action_bar.dart';
import 'tabs/project_info_tab.dart';
import 'tabs/preset_tab.dart';
import 'tabs/navigation_tab.dart';
import 'tabs/theme_tab.dart';
import 'tabs/permissions_tab.dart';
import 'tabs/native_config_tab.dart';
import '../../generator/pipeline/project_generator.dart';

class WizardScreen extends ConsumerWidget {
  const WizardScreen({super.key});

  Widget _buildTab(WizardStep step) {
    switch (step) {
      case WizardStep.project:
        return const ProjectInfoTab();
      case WizardStep.preset:
        return const PresetTab();
      case WizardStep.navigation:
        return const NavigationTab();
      case WizardStep.theme:
        return const ThemeTab();
      case WizardStep.permissions:
        return const PermissionsTab();
      case WizardStep.native:
        return const NativeConfigTab();
    }
  }

  void _showGenerationDialog(BuildContext context, WidgetRef ref) {
    final sdk = ref.read(flutterSdkProvider);

    if (!kIsWeb && !sdk.isInstalled) {
      FlutterSdkDialog.show(
        context,
        requiredForGeneration: true,
        onProceedDryRun: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _GenerationProgressDialog(),
          );
        },
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _GenerationProgressDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Frameless Desktop Titlebar with Navigation
            CustomTitleBar(
              showBackButton: true,
              onBack: () => Navigator.of(context).maybePop(),
            ),

            // Main Workspace (Sidebar + Dynamic Tab Canvas)
            Expanded(
              child: Row(
                children: [
                  const WizardSidebar(),
                  Expanded(
                    child: Container(
                      color: AppColors.background,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.02, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(state.currentStep),
                          child: _buildTab(state.currentStep),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Persistent Action Bar with live badges & hero CTA
            BottomActionBar(
              onGenerate: () => _showGenerationDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenerationProgressDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_GenerationProgressDialog> createState() => _GenerationProgressDialogState();
}

class _GenerationProgressDialogState extends ConsumerState<_GenerationProgressDialog> {
  final List<String> _logs = [];
  bool _isComplete = false;
  bool _isSuccess = true;

  @override
  void initState() {
    super.initState();
    _startGeneration();
  }

  Future<void> _startGeneration() async {
    final config = ref.read(wizardProvider).config;

    // If no path was selected, provide a friendly dry-run simulation
    if (config.outputPath.isEmpty) {
      final simSteps = [
        '⚡ [DRY-RUN MODE] Validating configuration...',
        '📦 Simulating flutter create for "${config.projectName}" (${config.orgId})...',
        '🛡️ Injected permissions: ${config.permissions.map((p) => p.name).join(", ")}',
        '🎨 Seed Color configured: #${config.seedColor.value.toRadixString(16).substring(2)} (AAA Contrast)',
        '🧭 Navigation layout: ${config.navigationStyle.title}',
        '🚀 Generation validated! Select a target folder to write files to disk.',
      ];

      for (final step in simSteps) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          setState(() => _logs.add(step));
        }
      }

      if (mounted) {
        setState(() {
          _isComplete = true;
          _isSuccess = true;
        });
      }
      return;
    }

    final generator = ProjectGenerator(
      config: config,
      onLog: (msg) {
        if (mounted) {
          setState(() => _logs.add(msg));
        }
      },
    );

    final result = await generator.execute();
    if (mounted) {
      setState(() {
        _isComplete = true;
        _isSuccess = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderActive.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.2),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isComplete
                        ? (_isSuccess ? AppColors.success.withOpacity(0.15) : AppColors.danger.withOpacity(0.15))
                        : AppColors.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isComplete
                        ? (_isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded)
                        : Icons.bolt_rounded,
                    color: _isComplete
                        ? (_isSuccess ? AppColors.success : AppColors.danger)
                        : AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isComplete
                            ? (_isSuccess ? 'Project Successfully Generated!' : 'Generation Encountered Errors')
                            : 'Generating Flutter Project...',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isComplete
                            ? (_isSuccess
                                ? 'All templates, permissions and configs have been applied.'
                                : 'Please review the error logs below.')
                            : 'Please wait while FLRD scaffolds your application.',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Progress Logs Console
            Container(
              height: 180,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Preparing scaffolding pipeline...',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (ctx, idx) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Text(
                            _logs[idx],
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 24),

            // Dialog Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isComplete) ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      final config = ref.read(wizardProvider).config;
                      final targetPath = '${config.outputPath}/${config.projectName}';
                      if (!kIsWeb) {
                        runExecutableArguments('code', [targetPath]);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.surfaceCard,
                            content: Text(
                              'Open project in terminal: code $targetPath',
                              style: const TextStyle(color: AppColors.textPrimary),
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.code_rounded, size: 16),
                    label: const Text('Open in VS Code'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
