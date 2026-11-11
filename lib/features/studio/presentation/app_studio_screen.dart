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
  int _inspectorTabIndex = 0; // 0: Route Details, 1: View Dart Code, 2: Device Screen Emulator
  bool _isDraggingNode = false;

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

            // Studio Header & Project Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.backgroundSecondary,
                border: Border(
                  bottom: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.hub_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.project.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                widget.project.preset.name.toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.secondary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.project.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: AppColors.textMuted.withOpacity(0.8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Quick Action Buttons
                  Flexible(
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
                              horizontal: 10,
                              vertical: 6,
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
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          label: Text(
                            studio.nodes.isNotEmpty &&
                                    studio.nodes.every((n) => n.isCollapsed)
                                ? 'Expand All'
                                : 'Collapse All',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          key: const ValueKey('toolbar_fit_view_button'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            backgroundColor: AppColors.surface,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: () => _fitView(studio.nodes),
                          icon: const Icon(
                            Icons.fit_screen_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          label: const Text(
                            'Fit View',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            backgroundColor: AppColors.surface,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: _openDirectory,
                          icon: const Icon(
                            Icons.folder_open_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          label: const Text(
                            'Folder',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: _openVsCode,
                          icon: const Icon(Icons.code_rounded, size: 14),
                          label: const Text(
                            'Open VS Code',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.secondary),
                            backgroundColor: AppColors.surface,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
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
                            size: 14,
                            color: AppColors.secondary,
                          ),
                          label: const Text(
                            'Publish',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontSize: 11,
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
          ),

            // Tab Navigation Bar
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.alt_route_rounded, size: 16),
                    text: 'Routes Flowchart',
                  ),
                  Tab(
                    icon: Icon(Icons.security_rounded, size: 16),
                    text: 'Native Permissions',
                  ),
                  Tab(
                    icon: Icon(Icons.layers_rounded, size: 16),
                    text: 'Architecture & Packages',
                  ),
                ],
              ),
            ),

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

  Widget _buildFlowchartTab(
    BuildContext context,
    StudioState studio,
    StudioNotifier notifier,
    RouteNode? selectedNode,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isEmulate = _inspectorTabIndex == 2;
        final defaultWidth = isEmulate ? 480.0 : 440.0;
        final isNarrowScreen = constraints.maxWidth < (defaultWidth + 360.0);
        final sidebarWidth = isNarrowScreen
            ? (constraints.maxWidth < 600
                ? (constraints.maxWidth * 0.55).clamp(280.0, constraints.maxWidth - 120.0)
                : (constraints.maxWidth * (isEmulate ? 0.55 : 0.5)))
            : defaultWidth;
        final canvasWidth = selectedNode != null
            ? constraints.maxWidth - sidebarWidth
            : constraints.maxWidth;
        final isNarrowCanvas = canvasWidth < 480;
        final safeCanvasWidth = canvasWidth.isFinite && canvasWidth > 0 ? canvasWidth : 1200.0;
        final safeCanvasHeight = constraints.maxHeight.isFinite && constraints.maxHeight > 0 ? constraints.maxHeight : 800.0;
        _lastCanvasViewportSize = Size(safeCanvasWidth, safeCanvasHeight);

        return Row(
          children: [
            // Flowchart Canvas Area
            Expanded(
              child: Stack(
                children: [
                  // Zoomable & Pannable Canvas
                  InteractiveViewer(
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

            // Node Inspector Sidebar (When a node is selected)
            if (selectedNode != null) ...[
              Container(
                width: sidebarWidth,
                decoration: const BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  border: Border(
                    left: BorderSide(color: AppColors.borderSubtle),
                  ),
                ),
                child: _buildNodeInspector(selectedNode, notifier),
              ),
            ],
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
    return Padding(
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
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                color: AppColors.textMuted,
                onPressed: () => notifier.selectNode(null),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Segmented Switcher: [⚙️ Details] vs [💻 Code] vs [📱 Emulate]
          _buildInspectorSwitcher(),
          const SizedBox(height: 14),

          // Inspector Tab Body
          Expanded(
            child: _buildInspectorBody(node, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorBody(RouteNode node, StudioNotifier notifier) {
    switch (_inspectorTabIndex) {
      case 0:
        return _buildRouteDetailsContent(node, notifier);
      case 1:
        return _buildDartCodeContent(node);
      case 2:
      default:
        return DeviceScreenEmulator(
          node: node,
          project: widget.project,
          onToggleExpand: () => DeviceScreenEmulator.showModal(
            context,
            node: node,
            project: widget.project,
          ),
        );
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
          const SizedBox(width: 4),
          Expanded(
            child: _buildSegmentButton(
              title: '📱 ${strings.emulateScreenTab}',
              isSelected: _inspectorTabIndex == 2,
              onTap: () => setState(() => _inspectorTabIndex = 2),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
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
                  const Spacer(),
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
                ],
              ),
            ),
          ),
        );
      },
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
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
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
