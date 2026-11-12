import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/language_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/window/custom_titlebar.dart';
import '../../marketplace/presentation/widgets/publish_template_dialog.dart';
import '../../projects/models/registered_project.dart';
import '../models/route_node.dart';
import '../providers/studio_provider.dart';
import 'widgets/ai_screen_generator_dialog.dart';
import 'widgets/device_screen_emulator.dart';
import 'widgets/embedded_code_viewer.dart';
import 'widgets/route_connector_painter.dart';
import 'widgets/route_node_card.dart';
import 'widgets/screen_materials_builder.dart';

class AppStudioScreen extends ConsumerStatefulWidget {
  final RegisteredProject project;

  const AppStudioScreen({super.key, required this.project});

  /// Opens a 750px wide code dialog displaying EmbeddedCodeViewer for the given node.
  static Future<void> showFullscreenCodeModal(
    BuildContext context, {
    required String projectPath,
    required RouteNode node,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SizedBox(
            width: 750,
            height: 650,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: EmbeddedCodeViewer(
                projectPath: projectPath,
                node: node,
                isExpanded: true,
                onToggleExpand: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  ConsumerState<AppStudioScreen> createState() => _AppStudioScreenState();
}

class _AppStudioScreenState extends ConsumerState<AppStudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TransformationController _transformationController =
      TransformationController();
  int _inspectorTabIndex = 0; // 0: Route Details, 1: View Dart Code
  bool _isDraggingNode = false;
  bool _showLivePreview = true;
  bool _isDiagramCollapsed = false;
  String? _currentCode;
  String? _lastSelectedNodeId;

  void _onCodeViewerChanged(String code) {
    if (_currentCode == code) return;
    _currentCode = code;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onNodeDragStart() {
    if (!mounted) return;
    if (!_isDraggingNode) {
      setState(() {
        _isDraggingNode = true;
      });
    }
  }

  void _onNodeDragEnd() {
    if (!mounted) return;
    if (_isDraggingNode) {
      setState(() {
        _isDraggingNode = false;
      });
    }
  }

  Size _lastCanvasViewportSize = const Size(1200, 800);

  void _onNodeDragUpdate(String nodeId, Offset delta) {
    final scale = _transformationController.value
        .getMaxScaleOnAxis()
        .clamp(0.1, 5.0);
    final canvasDelta = delta / scale;
    final studio = ref.read(studioProvider);
    final nodeIndex = studio.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;
    final currentPos = studio.nodes[nodeIndex].position;
    final newX = currentPos.dx + canvasDelta.dx;
    final newY = currentPos.dy + canvasDelta.dy;
    ref.read(studioProvider.notifier).updateNodePosition(nodeId, Offset(newX, newY));
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kIsWeb && Uri.base.queryParameters['inspect'] == 'true') {
        final nodes = ref.read(studioProvider).nodes;
        if (nodes.isNotEmpty) {
          ref.read(studioProvider.notifier).selectNode(nodes.first.id);
          setState(() {
            _inspectorTabIndex = 1;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _fitView(List<RouteNode> nodes) {
    if (nodes.isEmpty) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final node in nodes) {
      final double cardH = node.isCollapsed ? 38.0 : 110.0;
      const double cardW = 260.0;
      if (node.position.dx < minX) minX = node.position.dx;
      if (node.position.dy < minY) minY = node.position.dy;
      if (node.position.dx + cardW > maxX) maxX = node.position.dx + cardW;
      if (node.position.dy + cardH > maxY) maxY = node.position.dy + cardH;
    }

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;

    if (contentWidth <= 0 || contentHeight <= 0) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    const padding = 60.0;
    final availableWidth = (_lastCanvasViewportSize.width - padding * 2).clamp(100.0, 10000.0);
    final availableHeight = (_lastCanvasViewportSize.height - padding * 2).clamp(100.0, 10000.0);

    final scaleX = availableWidth / contentWidth;
    final scaleY = availableHeight / contentHeight;
    final targetScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 1.5);

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    final tx = (_lastCanvasViewportSize.width / 2) - (centerX * targetScale);
    final ty = (_lastCanvasViewportSize.height / 2) - (centerY * targetScale);

    final matrix = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(targetScale, targetScale);

    _transformationController.value = matrix;
  }

  void _zoomIn() {
    final matrix = _transformationController.value.clone();
    matrix.scale(1.2, 1.2);
    _transformationController.value = matrix;
  }

  void _zoomOut() {
    final matrix = _transformationController.value.clone();
    matrix.scale(0.8, 0.8);
    _transformationController.value = matrix;
  }

  Future<void> _openVsCode() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Abra no seu terminal local: code "${widget.project.path}"',
          ),
          backgroundColor: AppColors.surfaceCard,
        ),
      );
      return;
    }
    try {
      await Process.run('code', [widget.project.path], runInShell: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir VS Code: $e')),
        );
      }
    }
  }

  Future<void> _openDirectory() async {
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [widget.project.path.replaceAll('/', '\\')]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final studio = ref.watch(studioProvider);
    final studioNotifier = ref.read(studioProvider.notifier);
    final selectedNode = studio.selectedNode;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Custom TitleBar with Back Button
            CustomTitleBar(
              showBackButton: true,
              onBack: () => Navigator.of(context).pop(),
            ),

            // Studio Header & Project Bar with integrated compact view switcher
            _buildProjectHeader(studio, studioNotifier),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Tab 1: Interactive Route Flowchart
                  _buildFlowchartTab(context, studio, studioNotifier, selectedNode),

                  // Tab 2: Permissions Injector
                  _buildPermissionsTab(),

                  // Tab 3: Architecture & Dependencies
                  _buildArchitectureTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectHeader(StudioState studio, StudioNotifier studioNotifier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.hub_rounded,
              color: AppColors.primary,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  widget.project.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: AppColors.textMuted.withOpacity(0.8),
                    fontSize: 8.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Integrated Studio View Switcher Pills (Reclaims ~50px vertical TabBar space)
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildStudioViewSwitcher(),
            ),
          ),

          const SizedBox(width: 8),

          // Quick Action Buttons
          Expanded(
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('collapse_all_button'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        backgroundColor: AppColors.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: () {
                        final allCollapsed = studio.nodes.isNotEmpty &&
                            studio.nodes.every((n) => n.isCollapsed);
                        studioNotifier.setAllNodesCollapsed(!allCollapsed);
                      },
                      icon: Icon(
                        studio.nodes.isNotEmpty &&
                                studio.nodes.every((n) => n.isCollapsed)
                            ? Icons.unfold_more_rounded
                            : Icons.unfold_less_rounded,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      label: Text(
                        studio.nodes.isNotEmpty &&
                                studio.nodes.every((n) => n.isCollapsed)
                            ? 'Expand All'
                            : 'Collapse All',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      key: const ValueKey('toolbar_fit_view_button'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        backgroundColor: AppColors.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: () => _fitView(studio.nodes),
                      icon: const Icon(
                        Icons.fit_screen_rounded,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      label: const Text(
                        'Fit View',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Toggle Diagram Collapse Button (Full width expansion for Code + Phone)
                    OutlinedButton.icon(
                      key: const ValueKey('toggle_diagram_collapse_button'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _isDiagramCollapsed
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                        backgroundColor: _isDiagramCollapsed
                            ? AppColors.primary.withOpacity(0.12)
                            : AppColors.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _isDiagramCollapsed = !_isDiagramCollapsed;
                          if (_isDiagramCollapsed &&
                              studio.selectedNodeId == null &&
                              studio.nodes.isNotEmpty) {
                            studioNotifier.selectNode(studio.nodes.first.id);
                            _inspectorTabIndex = 1;
                          }
                        });
                      },
                      icon: Icon(
                        _isDiagramCollapsed
                            ? Icons.arrow_right_rounded
                            : Icons.arrow_left_rounded,
                        size: 12,
                        color: _isDiagramCollapsed
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      label: Text(
                        _isDiagramCollapsed
                            ? '▶ Show Diagram'
                            : '◀ Collapse Diagram',
                        style: TextStyle(
                          color: _isDiagramCollapsed
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Toggle Live Preview Button (1-click right dock emulator toggle)
                    OutlinedButton.icon(
                      key: const ValueKey('toggle_live_preview_button'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _showLivePreview
                              ? AppColors.secondary
                              : AppColors.border,
                        ),
                        backgroundColor: _showLivePreview
                            ? AppColors.secondary.withOpacity(0.12)
                            : AppColors.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _showLivePreview = !_showLivePreview;
                        });
                      },
                      icon: Icon(
                        _showLivePreview
                            ? Icons.smartphone_rounded
                            : Icons.smartphone_outlined,
                        size: 12,
                        color: _showLivePreview
                            ? AppColors.secondary
                            : AppColors.textSecondary,
                      ),
                      label: Text(
                        _showLivePreview
                            ? 'Hide Preview'
                            : '📱 Live Preview',
                        style: TextStyle(
                          color: _showLivePreview
                              ? AppColors.secondary
                              : AppColors.textPrimary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        backgroundColor: AppColors.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: _openDirectory,
                      icon: const Icon(
                        Icons.folder_open_rounded,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      label: const Text(
                        'Folder',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: _openVsCode,
                      icon: const Icon(Icons.code_rounded, size: 12),
                      label: const Text(
                        'Open VS Code',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.secondary),
                        backgroundColor: AppColors.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: () => PublishTemplateDialog.show(
                        context,
                        projectPath: widget.project.path,
                      ),
                      icon: const Icon(
                        Icons.verified_user_outlined,
                        size: 12,
                        color: AppColors.secondary,
                      ),
                      label: const Text(
                        'Publish',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
  }

  Widget _buildStudioViewSwitcher() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final currentIndex = _tabController.index;
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStudioViewTab(
                index: 0,
                icon: Icons.alt_route_rounded,
                label: 'Routes Flowchart',
                isSelected: currentIndex == 0,
              ),
              const SizedBox(width: 2),
              _buildStudioViewTab(
                index: 1,
                icon: Icons.security_rounded,
                label: 'Native Permissions',
                isSelected: currentIndex == 1,
              ),
              const SizedBox(width: 2),
              _buildStudioViewTab(
                index: 2,
                icon: Icons.layers_rounded,
                label: 'Architecture & Packages',
                isSelected: currentIndex == 2,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudioViewTab({
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return InkWell(
      key: ValueKey('studio_view_tab_$index'),
      onTap: () {
        _tabController.animateTo(index);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowchartTab(
    BuildContext context,
    StudioState studio,
    StudioNotifier notifier,
    RouteNode? selectedNode,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isViewingCode = _inspectorTabIndex == 1;
        final double previewWidth = constraints.maxWidth < 900
            ? (constraints.maxWidth * 0.4).clamp(320.0, 420.0)
            : 420.0;

        final double sidebarWidth;
        if (selectedNode == null) {
          sidebarWidth = 0.0;
        } else if (_isDiagramCollapsed) {
          sidebarWidth = constraints.maxWidth;
        } else {
          final maxInspectorWidth = (constraints.maxWidth -
                  (_showLivePreview ? previewWidth : 0.0) -
                  280.0)
              .clamp(300.0, constraints.maxWidth);
          final double defaultSidebarWidth = isViewingCode ? 500.0 : 440.0;
          sidebarWidth = defaultSidebarWidth.clamp(280.0, maxInspectorWidth);
        }

        final canvasWidth = selectedNode != null
            ? (_isDiagramCollapsed
                ? 0.0
                : (constraints.maxWidth -
                        sidebarWidth -
                        (_showLivePreview ? previewWidth : 0.0))
                    .clamp(0.0, constraints.maxWidth))
            : (constraints.maxWidth - (_showLivePreview ? previewWidth : 0.0))
                .clamp(0.0, constraints.maxWidth);
        final isNarrowCanvas = canvasWidth < 480;
        final safeCanvasWidth =
            canvasWidth.isFinite && canvasWidth > 0 ? canvasWidth : 1200.0;
        final safeCanvasHeight = constraints.maxHeight.isFinite &&
                constraints.maxHeight > 0
            ? constraints.maxHeight
            : 800.0;
        _lastCanvasViewportSize = Size(safeCanvasWidth, safeCanvasHeight);

        final showCanvas = !_isDiagramCollapsed || selectedNode == null;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Flowchart Canvas Area (Isolated with RepaintBoundary)
            if (showCanvas)
              Expanded(
                child: RepaintBoundary(
                  child: Stack(
                    children: [
                      // Zoomable & Pannable Canvas (RepaintBoundary isolates zooming/panning/dragging)
                      RepaintBoundary(
                        child: InteractiveViewer(
                          transformationController: _transformationController,
                          panEnabled: !_isDraggingNode,
                          minScale: 0.1,
                          maxScale: 2.5,
                          boundaryMargin: const EdgeInsets.all(5000),
                          constrained: false,
                          child: SizedBox(
                            width: 10000,
                            height: 6000,
                            child: Stack(
                              children: [
                                // Canvas Paint Layer (Dot-Grid + Curved Arrow Connections)
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: RouteConnectorPainter(
                                      nodes: studio.nodes,
                                      selectedNodeId: studio.selectedNodeId,
                                    ),
                                  ),
                                ),

                                // Interactive Node Cards
                                ...studio.nodes.map((node) {
                                  return Positioned(
                                    left: node.position.dx,
                                    top: node.position.dy,
                                    child: RouteNodeCard(
                                      node: node,
                                      isSelected: node.id == studio.selectedNodeId,
                                      onTap: () => notifier.selectNode(node.id),
                                      onToggleCollapse: () =>
                                          notifier.toggleNodeCollapse(node.id),
                                      onDragStart: _onNodeDragStart,
                                      onDragUpdate: (delta) =>
                                          _onNodeDragUpdate(node.id, delta),
                                      onDragEnd: _onNodeDragEnd,
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),

                  // Floating Canvas Controls & AI Generator Trigger
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Aumentar Zoom',
                            icon: const Icon(Icons.add_rounded, size: 16),
                            color: AppColors.textPrimary,
                            onPressed: _zoomIn,
                          ),
                          IconButton(
                            tooltip: 'Diminuir Zoom',
                            icon: const Icon(Icons.remove_rounded, size: 16),
                            color: AppColors.textPrimary,
                            onPressed: _zoomOut,
                          ),
                          IconButton(
                            key: const ValueKey('fit_view_button'),
                            tooltip: 'Center/Fit View',
                            icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
                            color: AppColors.textPrimary,
                            onPressed: () => _fitView(studio.nodes),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 20,
                            color: AppColors.border,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${studio.nodes.length} Routes Mapped',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 20,
                            color: AppColors.border,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const ValueKey('canvas_collapse_diagram_button'),
                            tooltip: 'Collapse Diagram',
                            icon: const Icon(Icons.arrow_left_rounded, size: 16),
                            color: AppColors.textPrimary,
                            onPressed: () {
                              setState(() {
                                _isDiagramCollapsed = true;
                                if (studio.selectedNodeId == null &&
                                    studio.nodes.isNotEmpty) {
                                  notifier.selectNode(studio.nodes.first.id);
                                  _inspectorTabIndex = 1;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Action Button: AI Screen Gen (Repositions dynamically when canvas is narrow)
                  Positioned(
                    top: isNarrowCanvas ? 72 : 16,
                    right: isNarrowCanvas ? null : 16,
                    left: isNarrowCanvas ? 16 : null,
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            foregroundColor: AppColors.background,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => AiScreenGeneratorDialog.show(
                            context,
                            widget.project,
                          ),
                          icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                          label: const Text(
                            'Generate Screen with AI',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

            // Node Inspector Sidebar (When a node is selected)
            if (selectedNode != null)
              _isDiagramCollapsed
                  ? Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppColors.backgroundSecondary,
                        ),
                        child: RepaintBoundary(
                          child: _buildNodeInspector(selectedNode, notifier),
                        ),
                      ),
                    )
                  : Container(
                      width: sidebarWidth,
                      decoration: const BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        border: Border(
                          left: BorderSide(color: AppColors.borderSubtle),
                        ),
                      ),
                      child: RepaintBoundary(
                        child: _buildNodeInspector(selectedNode, notifier),
                      ),
                    ),

            // Dedicated Right-Anchored Live Preview Pane (when _showLivePreview is true)
            if (_showLivePreview)
              RepaintBoundary(
                child: _buildAnchoredLivePreviewPane(
                  studio: studio,
                  node: selectedNode ?? studio.nodes.firstOrNull,
                  width: previewWidth,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showFullscreenCodeModal(BuildContext context, RouteNode node) {
    return AppStudioScreen.showFullscreenCodeModal(
      context,
      projectPath: widget.project.path,
      node: node,
    );
  }

  Widget _buildNodeInspector(RouteNode node, StudioNotifier notifier) {
    if (_lastSelectedNodeId != node.id) {
      _lastSelectedNodeId = node.id;
      _currentCode = null;
    }
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(node.icon, color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_inspectorTabIndex == 1) ...[
                  OutlinedButton.icon(
                    key: const ValueKey('inspector_toggle_preview_button'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _showLivePreview ? AppColors.secondary : AppColors.border,
                      ),
                      backgroundColor: _showLivePreview
                          ? AppColors.secondary.withOpacity(0.12)
                          : AppColors.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => setState(() => _showLivePreview = !_showLivePreview),
                    icon: Icon(
                      _showLivePreview ? Icons.smartphone_rounded : Icons.smartphone_outlined,
                      size: 13,
                      color: _showLivePreview ? AppColors.secondary : AppColors.textSecondary,
                    ),
                    label: Text(
                      _showLivePreview ? 'Hide Preview' : '📱 Live Preview',
                      style: TextStyle(
                        color: _showLivePreview ? AppColors.secondary : AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (_isDiagramCollapsed) ...[
                  OutlinedButton.icon(
                    key: const ValueKey('inspector_show_diagram_button'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => setState(() => _isDiagramCollapsed = false),
                    icon: const Icon(Icons.arrow_right_rounded, size: 14, color: AppColors.primary),
                    label: const Text(
                      '▶ Show Diagram',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: AppColors.textMuted,
                  onPressed: () => notifier.selectNode(null),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Segmented Switcher: [⚙️ Details] vs [💻 Code]
            _buildInspectorSwitcher(),
            const SizedBox(height: 14),

            // Inspector Tab Body
            Expanded(
              child: _buildInspectorBody(node, notifier),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorBody(RouteNode node, StudioNotifier notifier) {
    switch (_inspectorTabIndex) {
      case 0:
        return _buildRouteDetailsContent(node, notifier);
      case 1:
      default:
        return _buildDartCodeContent(node);
    }
  }

  Widget _buildInspectorSwitcher() {
    final strings = ref.watch(appStringsProvider);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentButton(
              title: '⚙️ ${strings.routeDetailsTab}',
              isSelected: _inspectorTabIndex == 0,
              onTap: () => setState(() => _inspectorTabIndex = 0),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildSegmentButton(
              title: '💻 ${strings.viewCodeTab}',
              isSelected: _inspectorTabIndex == 1,
              onTap: () => setState(() => _inspectorTabIndex = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildRouteDetailsContent(RouteNode node, StudioNotifier notifier) {
    if (_lastSelectedNodeId != node.id) {
      _lastSelectedNodeId = node.id;
      _currentCode = null;
    }

    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route Path
          const Text(
            'GoRouter Route Path',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Text(
              node.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: AppColors.secondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // File Path
          const Text(
            'Source Code File',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            node.filePath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),

          // Protection Badge
          Row(
            children: [
              Icon(
                node.isProtected ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 14,
                color: node.isProtected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                node.isProtected ? 'Protected by Auth Guard' : 'Public Route',
                style: TextStyle(
                  color: node.isProtected
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.borderSubtle, height: 1),
          const SizedBox(height: 16),

          // Interactive "Materiais & Componentes da Tela" Panel
          ScreenMaterialsBuilder(
            node: node,
            project: widget.project,
            currentCode: _currentCode ?? '',
            onCodeChanged: _onCodeViewerChanged,
            existingRoutes: ref.read(studioProvider).nodes,
          ),

          const SizedBox(height: 20),
          const Divider(color: AppColors.borderSubtle, height: 1),
          const SizedBox(height: 16),

          // Node Actions
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                backgroundColor: AppColors.surface,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _openVsCode,
              icon: const Icon(Icons.code_rounded, size: 14),
              label: const Text(
                'Open File in VS Code',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (node.id != 'root')
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                onPressed: () => notifier.removeNode(node.id),
                icon: const Icon(Icons.delete_outline_rounded, size: 14),
                label: const Text('Remove Route from Graph',
                    style: TextStyle(fontSize: 11)),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDartCodeContent(RouteNode node) {
    return Column(
      children: [
        Expanded(
          child: EmbeddedCodeViewer(
            projectPath: widget.project.path,
            node: node,
            isExpanded: false,
            onToggleExpand: () => _showFullscreenCodeModal(context, node),
            onCodeChanged: _onCodeViewerChanged,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('open_fullscreen_modal_button'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              backgroundColor: AppColors.surface,
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _showFullscreenCodeModal(context, node),
            icon: const Icon(
              Icons.fullscreen_rounded,
              size: 15,
              color: AppColors.secondary,
            ),
            label: const Text(
              'Open in Fullscreen Modal',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnchoredLivePreviewPane({
    required StudioState studio,
    required RouteNode? node,
    double width = 420.0,
  }) {
    final activeNode = node ?? studio.nodes.firstOrNull;

    return RepaintBoundary(
      child: Container(
        key: const ValueKey('anchored_live_preview_pane'),
        width: width,
        decoration: const BoxDecoration(
          color: AppColors.backgroundSecondary,
          border: Border(
            left: BorderSide(color: AppColors.borderSubtle),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Elegant Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                bottom: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.smartphone_rounded,
                    color: AppColors.secondary,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Flexible(
                        child: Text(
                          'Live Screen Preview',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (activeNode != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceCard,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Text(
                              activeNode.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: AppColors.secondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (activeNode != null)
                  IconButton(
                    tooltip: 'Expand Preview Modal',
                    icon: const Icon(Icons.open_in_full_rounded, size: 14),
                    color: AppColors.textMuted,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => DeviceScreenEmulator.showModal(
                      context,
                      node: activeNode,
                      project: widget.project,
                      sourceCode: _currentCode,
                    ),
                  ),
                IconButton(
                  key: const ValueKey('close_live_preview_pane_button'),
                  tooltip: 'Hide Preview',
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: AppColors.textMuted,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    setState(() {
                      _showLivePreview = false;
                    });
                  },
                ),
              ],
            ),
          ),

          // Body: DeviceScreenEmulator filling 100% of remaining vertical height
          Expanded(
            child: activeNode != null
                ? DeviceScreenEmulator(
                    sourceCode: _currentCode,
                    node: activeNode,
                    project: widget.project,
                    onToggleExpand: () => DeviceScreenEmulator.showModal(
                      context,
                      node: activeNode,
                      project: widget.project,
                      sourceCode: _currentCode,
                    ),
                  )
                : const Center(
                    child: Text(
                      'No route selected',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildPermissionsTab() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Permissões Nativas Injetadas',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Injeção semântica com parsing AST sem corromper AndroidManifest.xml ou Info.plist.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: widget.project.permissions.map((perm) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      perm.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildArchitectureTab() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Visão da Arquitetura & Stack',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Padrão ativo: ${widget.project.preset.name.toUpperCase()} • Anti-Obsolescência Garantida',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pacotes & Dependências Curadas:',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '• flutter_riverpod: ^2.5.1\n'
                  '• go_router: ^14.0.0 (Blindado com refreshListenable)\n'
                  '• supabase_flutter: ^2.5.0\n'
                  '• google_fonts: ^6.2.1\n'
                  '• flutter_animate: ^4.5.0',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: AppColors.secondary,
                    fontSize: 12,
                    height: 1.6,
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
