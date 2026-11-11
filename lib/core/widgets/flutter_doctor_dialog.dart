import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../localization/app_strings.dart';
import '../localization/language_provider.dart';
import '../services/flutter_doctor_service.dart';
import '../theme/app_colors.dart';

/// Modal dialog providing comprehensive environment health diagnostics
/// powered by `flutter doctor -v` and [flutterDoctorProvider].
class FlutterDoctorDialog extends ConsumerStatefulWidget {
  const FlutterDoctorDialog({super.key});

  /// Displays the FLRD Doctor modal dialog.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const FlutterDoctorDialog(),
    );
  }

  @override
  ConsumerState<FlutterDoctorDialog> createState() => _FlutterDoctorDialogState();
}

class _FlutterDoctorDialogState extends ConsumerState<FlutterDoctorDialog> {
  final Set<String> _expandedItemIds = {};
  bool _initializedExpansion = false;
  bool _showRawLog = false;
  String? _filter; // null = all, 'issues' = warnings & errors, 'healthy' = healthy only

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncInitialExpansion();
    });
  }

  void _syncInitialExpansion() {
    if (!mounted) return;
    final report = ref.read(flutterDoctorProvider);
    if (!_initializedExpansion && report.items.isNotEmpty) {
      _initializedExpansion = true;
      setState(() {
        for (final item in report.items) {
          if (item.status != DoctorItemStatus.healthy) {
            _expandedItemIds.add(item.id);
          }
        }
        // If all items are healthy, expand the first one by default
        if (_expandedItemIds.isEmpty && report.items.isNotEmpty) {
          _expandedItemIds.add(report.items.first.id);
        }
      });
    }
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedItemIds.contains(id)) {
        _expandedItemIds.remove(id);
      } else {
        _expandedItemIds.add(id);
      }
    });
  }

  void _expandAll(List<DoctorItem> items) {
    setState(() {
      _expandedItemIds.addAll(items.map((i) => i.id));
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedItemIds.clear();
    });
  }

  Future<void> _handleRescan() async {
    await ref.read(flutterDoctorProvider.notifier).runDoctor();
    if (mounted) {
      final report = ref.read(flutterDoctorProvider);
      setState(() {
        for (final item in report.items) {
          if (item.status != DoctorItemStatus.healthy) {
            _expandedItemIds.add(item.id);
          }
        }
      });
    }
  }

  Future<void> _copyToClipboard(String text, String successMessage) async {
    if (text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e) {
      debugPrint('Failed to copy to clipboard: $e');
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                successMessage,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surfaceSelected,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Invalid link: $url'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Could not open link: $url'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Error opening link: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(flutterDoctorProvider);
    final strings = ref.watch(appStringsProvider);
    final lang = ref.watch(appLanguageProvider);
    final isPt = lang == AppLanguage.pt;
    final isEs = lang == AppLanguage.es;

    // Localized helper strings
    final readyLabel = isPt
        ? 'Componentes Prontos'
        : (isEs ? 'Componentes Listos' : 'Components Ready');
    final scanningLabel = isPt
        ? 'Escaneando ambiente...'
        : (isEs ? 'Escaneando entorno...' : 'Scanning environment...');
    final scanningBtnLabel = isPt
        ? 'Escaneando...'
        : (isEs ? 'Escaneando...' : 'Scanning...');
    final expandAllLabel = isPt
        ? 'Expandir Todos'
        : (isEs ? 'Expandir Todo' : 'Expand All');
    final collapseAllLabel = isPt
        ? 'Recolher Todos'
        : (isEs ? 'Contraer Todo' : 'Collapse All');
    final filterAllLabel = isPt
        ? 'Todos'
        : (isEs ? 'Todos' : 'All');
    final filterIssuesLabel = isPt
        ? 'Atenção'
        : (isEs ? 'Atención' : 'Needs Attention');
    final filterHealthyLabel = isPt
        ? 'Prontos'
        : (isEs ? 'Listos' : 'Healthy');
    final rawLogLabel = isPt
        ? 'Log do flutter doctor'
        : (isEs ? 'Registro de flutter doctor' : 'flutter doctor Output');
    final copyLogLabel = isPt
        ? 'Copiar Log'
        : (isEs ? 'Copiar Registro' : 'Copy Log');
    final logCopiedLabel = isPt
        ? 'Log do terminal copiado!'
        : (isEs ? '¡Registro copiado!' : 'Terminal log copied!');
    final closeLabel = isPt
        ? 'Fechar'
        : (isEs ? 'Cerrar' : 'Close');

    // Auto-sync expansion on scan completion
    if (!_initializedExpansion && report.items.isNotEmpty && !report.isScanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncInitialExpansion();
      });
    }

    final filteredItems = report.items.where((item) {
      if (_filter == 'issues') return item.status != DoctorItemStatus.healthy;
      if (_filter == 'healthy') return item.status == DoctorItemStatus.healthy;
      return true;
    }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 680,
          maxHeight: 740,
          minHeight: 380,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 36,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header with Health Score bar
              _buildHeader(
                context: context,
                report: report,
                strings: strings,
                readyLabel: readyLabel,
                scanningLabel: scanningLabel,
              ),

              const Divider(height: 1, color: AppColors.borderSubtle),

              // 2. Action Toolbar (Rescan, Filters, Expand/Collapse)
              _buildToolbar(
                report: report,
                strings: strings,
                scanningBtnLabel: scanningBtnLabel,
                expandAllLabel: expandAllLabel,
                collapseAllLabel: collapseAllLabel,
                filterAllLabel: filterAllLabel,
                filterIssuesLabel: filterIssuesLabel,
                filterHealthyLabel: filterHealthyLabel,
              ),

              const Divider(height: 1, color: AppColors.borderSubtle),

              // 3. Body: Doctor Items List / Loading / Empty State
              Expanded(
                child: _buildBody(
                  context: context,
                  report: report,
                  items: filteredItems,
                  strings: strings,
                  isPt: isPt,
                  isEs: isEs,
                  scanningLabel: scanningLabel,
                ),
              ),

              // 4. Raw Output Collapsible Drawer (if available)
              if (report.rawOutput != null && report.rawOutput!.trim().isNotEmpty) ...[
                const Divider(height: 1, color: AppColors.borderSubtle),
                _buildRawOutputSection(
                  rawOutput: report.rawOutput!,
                  rawLogLabel: rawLogLabel,
                  copyLogLabel: copyLogLabel,
                  logCopiedLabel: logCopiedLabel,
                ),
              ],

              const Divider(height: 1, color: AppColors.borderSubtle),

              // 5. Footer Actions
              _buildFooter(
                context: context,
                report: report,
                closeLabel: closeLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required DoctorReport report,
    required AppStrings strings,
    required String readyLabel,
    required String scanningLabel,
  }) {
    final healthScore = report.healthScore;
    final scorePercentage = report.scorePercentage;
    final isScanning = report.isScanning;

    Color progressColor;
    if (report.isAllHealthy) {
      progressColor = AppColors.success;
    } else if (healthScore >= 0.7) {
      progressColor = AppColors.secondary;
    } else if (healthScore >= 0.4) {
      progressColor = AppColors.warning;
    } else {
      progressColor = AppColors.danger;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Doctor Brand Pill Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.medical_services_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.doctorTitle,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isScanning
                          ? scanningLabel
                          : (report.isAllHealthy
                              ? strings.doctorAllGreen
                              : strings.doctorIssuesFound),
                      style: TextStyle(
                        color: isScanning
                            ? AppColors.secondary
                            : (report.isAllHealthy
                                ? AppColors.success
                                : AppColors.textSecondary),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Close Button
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.textMuted,
                splashRadius: 18,
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Health Score Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Health Score text: e.g. "6/7 Componentes Prontos - 85%"
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            report.isAllHealthy
                                ? Icons.check_circle_rounded
                                : (report.hasIssues
                                    ? Icons.health_and_safety_rounded
                                    : Icons.info_outline_rounded),
                            size: 15,
                            color: progressColor,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${report.healthyCount}/${report.totalCount} $readyLabel - $scorePercentage%',
                              style: TextStyle(
                                color: progressColor,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Status Pill Badge
                    if (isScanning)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.secondary,
                              ),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Scanning',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (report.isAllHealthy)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.success.withOpacity(0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, color: AppColors.success, size: 12),
                            SizedBox(width: 4),
                            Text(
                              '100% OK',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (report.warningCount > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                              ),
                              child: Text(
                                '${report.warningCount} !',
                                style: const TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          if (report.missingCount > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                              ),
                              child: Text(
                                '${report.missingCount} X',
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Linear Health Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: report.totalCount > 0 ? healthScore : 0.0,
                    minHeight: 7,
                    backgroundColor: AppColors.surfaceHover,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar({
    required DoctorReport report,
    required AppStrings strings,
    required String scanningBtnLabel,
    required String expandAllLabel,
    required String collapseAllLabel,
    required String filterAllLabel,
    required String filterIssuesLabel,
    required String filterHealthyLabel,
  }) {
    final isScanning = report.isScanning;
    final allExpanded = report.items.isNotEmpty &&
        report.items.every((item) => _expandedItemIds.contains(item.id));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surfaceCard,
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // "Re-escanear Agora" Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isScanning ? AppColors.surfaceHover : AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: isScanning ? null : _handleRescan,
            icon: isScanning
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.secondary,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 14),
            label: Text(
              isScanning ? scanningBtnLabel : strings.doctorRescan,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),

          // Filter Segmented Buttons
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFilterButton(
                    label: '$filterAllLabel (${report.totalCount})',
                    isSelected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  if (report.warningCount + report.missingCount > 0)
                    _buildFilterButton(
                      label: '$filterIssuesLabel (${report.warningCount + report.missingCount})',
                      isSelected: _filter == 'issues',
                      color: AppColors.warning,
                      onTap: () => setState(() => _filter = 'issues'),
                    ),
                  _buildFilterButton(
                    label: '$filterHealthyLabel (${report.healthyCount})',
                    isSelected: _filter == 'healthy',
                    color: AppColors.success,
                    onTap: () => setState(() => _filter = 'healthy'),
                  ),
                ],
              ),
            ),
          ),

          // Expand All / Collapse All Button
          if (report.items.isNotEmpty)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              onPressed: () {
                if (allExpanded) {
                  _collapseAll();
                } else {
                  _expandAll(report.items);
                }
              },
              icon: Icon(
                allExpanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
              label: Text(
                allExpanded ? collapseAllLabel : expandAllLabel,
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (color != null ? color.withOpacity(0.15) : AppColors.surfaceSelected)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(
                  color: color != null
                      ? color.withOpacity(0.4)
                      : AppColors.primary.withOpacity(0.4),
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? (color ?? AppColors.textPrimary)
                : AppColors.textMuted,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required DoctorReport report,
    required List<DoctorItem> items,
    required AppStrings strings,
    required bool isPt,
    required bool isEs,
    required String scanningLabel,
  }) {
    // 1. Initial scanning state with no parsed items yet
    if (report.isScanning && report.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                scanningLabel,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'flutter doctor -v',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Empty items state
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 36,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                _filter != null
                    ? (isPt ? 'Nenhum componente com esse filtro.' : 'No components match filter.')
                    : (isPt ? 'Nenhum item detectado.' : 'No items detected.'),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Scrollable List of DoctorItem Cards
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _buildDoctorItemCard(
              context: context,
              item: items[i],
              isExpanded: _expandedItemIds.contains(items[i].id),
              strings: strings,
              isPt: isPt,
              isEs: isEs,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDoctorItemCard({
    required BuildContext context,
    required DoctorItem item,
    required bool isExpanded,
    required AppStrings strings,
    required bool isPt,
    required bool isEs,
  }) {
    Color statusColor;
    IconData statusIcon;
    String statusBadgeLabel;

    switch (item.status) {
      case DoctorItemStatus.healthy:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle_rounded;
        statusBadgeLabel = isPt ? 'Pronto' : (isEs ? 'Listo' : 'Ready');
        break;
      case DoctorItemStatus.warning:
        statusColor = AppColors.warning;
        statusIcon = Icons.warning_amber_rounded;
        statusBadgeLabel = isPt ? 'Aviso' : (isEs ? 'Aviso' : 'Warning');
        break;
      case DoctorItemStatus.missing:
        statusColor = AppColors.danger;
        statusIcon = Icons.cancel_rounded;
        statusBadgeLabel = isPt ? 'Faltando' : (isEs ? 'Faltante' : 'Missing');
        break;
    }

    // First line for preview
    final firstDetailLine = item.details.split('\n').firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '',
        );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.status == DoctorItemStatus.healthy
              ? AppColors.borderSubtle
              : statusColor.withOpacity(0.35),
          width: item.status == DoctorItemStatus.healthy ? 1.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Expandable Card Header
          InkWell(
            onTap: () => _toggleExpand(item.id),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Status Badge Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, color: statusColor, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          statusBadgeLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Item Title & Preview
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!isExpanded && firstDetailLine.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            firstDetailLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Quick Action tag if collapsed
                  if (!isExpanded && item.hasAction) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.actionCommand != null
                                ? Icons.content_copy_rounded
                                : Icons.open_in_new_rounded,
                            size: 10,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isPt ? 'Ação' : 'Action',
                            style: const TextStyle(
                              color: AppColors.secondary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Chevron Icon
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Details & Actions
          if (isExpanded) ...[
            const Divider(height: 1, color: AppColors.borderSubtle),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Full Details block
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: SelectableText(
                      item.details,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),

                  // Solution Guidance Box (if provided)
                  if (item.solutionGuidance != null &&
                      item.solutionGuidance!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.lightbulb_rounded,
                                color: AppColors.primary,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isPt
                                    ? 'Solução Recomendada'
                                    : (isEs ? 'Solución Recomendada' : 'Recommended Solution'),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            item.solutionGuidance!,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Action Buttons Row (Copy Command / Open URL)
                  if (item.hasAction) ...[
                    const SizedBox(height: 12),
                    _buildItemActionButtons(
                      context: context,
                      item: item,
                      strings: strings,
                      isPt: isPt,
                      isEs: isEs,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemActionButtons({
    required BuildContext context,
    required DoctorItem item,
    required AppStrings strings,
    required bool isPt,
    required bool isEs,
  }) {
    final hasCommand = item.actionCommand != null && item.actionCommand!.trim().isNotEmpty;
    final hasUrl = item.actionUrl != null && item.actionUrl!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Command bar with inline Copy button
        if (hasCommand) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 14, color: AppColors.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      item.actionCommand!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceSelected,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () => _copyToClipboard(item.actionCommand!, strings.doctorCopied),
                  icon: const Icon(Icons.content_copy_rounded, size: 12, color: AppColors.secondary),
                  label: Text(
                    strings.doctorCopyCommand,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 2. Open Download / Docs URL Button
        if (hasUrl) ...[
          if (hasCommand) const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () => _openUrl(item.actionUrl!),
              icon: const Icon(Icons.open_in_new_rounded, size: 13),
              label: Text(
                strings.doctorDownload,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRawOutputSection({
    required String rawOutput,
    required String rawLogLabel,
    required String copyLogLabel,
    required String logCopiedLabel,
  }) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _showRawLog = !_showRawLog),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.terminal_rounded, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    rawLogLabel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (_showRawLog)
                    InkWell(
                      onTap: () => _copyToClipboard(rawOutput, logCopiedLabel),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.content_copy_rounded, size: 11, color: AppColors.secondary),
                            const SizedBox(width: 4),
                            Text(
                              copyLogLabel,
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _showRawLog ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_showRawLog)
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  rawOutput,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter({
    required BuildContext context,
    required DoctorReport report,
    required String closeLabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'FLRD Doctor • v0.2.1',
            style: TextStyle(
              color: AppColors.textPlaceholder,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(closeLabel, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
