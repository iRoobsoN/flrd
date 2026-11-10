import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/window/custom_titlebar.dart';
import '../../marketplace/presentation/widgets/publish_template_dialog.dart';
import '../../projects/models/registered_project.dart';
import '../models/route_node.dart';
import '../providers/studio_provider.dart';
import 'widgets/ai_screen_generator_dialog.dart';
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
  int _inspectorTabIndex = 0; // 0: Detalhes da Rota, 1: Ver Código Dart

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.project.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
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
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: AppColors.textMuted.withOpacity(0.8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Quick Action Buttons
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
                      'Pasta',
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
                      'Abrir VS Code',
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
                      'Publicar',
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
                    text: 'Fluxograma de Rotas & Telas',
                  ),
                  Tab(
                    icon: Icon(Icons.security_rounded, size: 16),
                    text: 'Injetor de Permissões Nativas',
                  ),
                  Tab(
                    icon: Icon(Icons.layers_rounded, size: 16),
                    text: 'Arquitetura & Pacotes',
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
    return Row(
      children: [
        // Flowchart Canvas Area
        Expanded(
          child: Stack(
            children: [
              // Zoomable & Pannable Canvas
              InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.4,
                maxScale: 2.2,
                boundaryMargin: const EdgeInsets.all(800),
                constrained: false,
                child: SizedBox(
                  width: 1800,
                  height: 900,
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
                            onDrag: (newPos) =>
                                notifier.updateNodePosition(node.id, newPos),
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
                        tooltip: 'Centralizar Visualização',
                        icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
                        color: AppColors.textPrimary,
                        onPressed: _resetZoom,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 1,
                        height: 20,
                        color: AppColors.border,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${studio.nodes.length} Rotas Mapeadas',
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

              // Top Right Action Buttons: AI Screen Gen & Add Node
              Positioned(
                top: 16,
                right: 16,
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
                        'Gerar Tela com IA',
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
            width: 440,
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

          // Segmented Switcher: [⚙️ Detalhes da Rota] vs [💻 Ver Código Dart]
          _buildInspectorSwitcher(),
          const SizedBox(height: 14),

          // Inspector Tab Body
          Expanded(
            child: _inspectorTabIndex == 0
                ? _buildRouteDetailsContent(node, notifier)
                : _buildDartCodeContent(node),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorSwitcher() {
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
              title: '⚙️ Detalhes da Rota',
              isSelected: _inspectorTabIndex == 0,
              onTap: () => setState(() => _inspectorTabIndex = 0),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildSegmentButton(
              title: '💻 Ver Código Dart',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Route Path
        const Text(
          'Caminho no GoRouter',
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
          'Arquivo Fonte',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          node.filePath,
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
              node.isProtected ? 'Protegida por Auth Guard' : 'Rota Pública',
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
              'Abrir Arquivo no VS Code',
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
              label: const Text('Remover Rota do Grafo',
                  style: TextStyle(fontSize: 11)),
            ),
          ),
      ],
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
              'Abrir em Modal Completo',
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
