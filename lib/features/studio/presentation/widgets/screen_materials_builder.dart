import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors.dart';
import '../../../projects/models/registered_project.dart';
import '../../domain/screen_material.dart';
import '../../models/route_node.dart';
import 'ai_screen_generator_dialog.dart';

/// Interactive visual builder panel displaying materials currently in a screen,
/// a quick-add palette with 1-click & drag-and-drop addition, reordering,
/// and AI prompt generation.
class ScreenMaterialsBuilder extends StatefulWidget {
  final RouteNode node;
  final RegisteredProject project;
  final String currentCode;
  final ValueChanged<String> onCodeChanged;

  const ScreenMaterialsBuilder({
    super.key,
    required this.node,
    required this.project,
    required this.currentCode,
    required this.onCodeChanged,
  });

  @override
  State<ScreenMaterialsBuilder> createState() => _ScreenMaterialsBuilderState();
}

class _ScreenMaterialsBuilderState extends State<ScreenMaterialsBuilder> {
  int? _hoveredDropIndex;
  bool _isDropAreaHovered = false;

  String get _effectiveCode {
    if (widget.currentCode.trim().isNotEmpty) {
      return widget.currentCode;
    }
    try {
      final filePath = p.isAbsolute(widget.node.filePath)
          ? p.normalize(widget.node.filePath)
          : p.normalize(p.join(widget.project.path, widget.node.filePath));
      final file = File(filePath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.trim().isNotEmpty) {
          return content;
        }
      }
    } catch (_) {}
    return '';
  }

  List<ScreenMaterialItem> get _materials {
    return ScreenMaterialParser.extractMaterialsFromCode(
      _effectiveCode,
      widget.node.title,
    );
  }

  void _addMaterial(ScreenMaterialItem prototype, {int? index}) {
    final baseCode = _effectiveCode.isNotEmpty
        ? _effectiveCode
        : ScreenMaterialParser.buildDartCodeFromMaterials(
            screenClassName: widget.node.title,
            routePath: widget.node.path,
            materials: [],
            isProtected: widget.node.isProtected,
          );
    final newMaterial = prototype.createInstance();
    final updatedCode = ScreenMaterialCodeUpdater.addMaterialToCode(
      currentCode: baseCode,
      newMaterial: newMaterial,
      index: index,
      screenClassName: widget.node.title,
      routePath: widget.node.path,
      routeTitle: widget.node.title,
      isProtected: widget.node.isProtected,
    );
    _saveAndNotify(updatedCode);
  }

  void _removeMaterial(int index) {
    final updatedCode = ScreenMaterialCodeUpdater.removeMaterialAtIndexInCode(
      currentCode: _effectiveCode,
      index: index,
      screenClassName: widget.node.title,
      routePath: widget.node.path,
      routeTitle: widget.node.title,
      isProtected: widget.node.isProtected,
    );
    _saveAndNotify(updatedCode);
  }

  void _reorderMaterial(int oldIndex, int newIndex) {
    final updatedCode = ScreenMaterialCodeUpdater.reorderMaterialsInCode(
      currentCode: _effectiveCode,
      oldIndex: oldIndex,
      newIndex: newIndex,
      screenClassName: widget.node.title,
      routePath: widget.node.path,
      routeTitle: widget.node.title,
      isProtected: widget.node.isProtected,
    );
    _saveAndNotify(updatedCode);
  }

  void _saveAndNotify(String newCode) {
    widget.onCodeChanged(newCode);

    try {
      final filePath = p.isAbsolute(widget.node.filePath)
          ? p.normalize(widget.node.filePath)
          : p.normalize(p.join(widget.project.path, widget.node.filePath));
      final file = File(filePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsStringSync(newCode, flush: true);
    } catch (e) {
      debugPrint('ScreenMaterialsBuilder error saving to file: $e');
    }
  }

  void _handleAiEnhance(List<ScreenMaterialItem> materials) {
    final prompt = ScreenMaterialCodeUpdater.generateAiEnhancePrompt(
      widget.node,
      materials,
    );
    AiScreenGeneratorDialog.show(
      context,
      widget.project,
      initialPrompt: prompt,
      initialRoutePath: widget.node.path,
      initialScreenTitle: widget.node.title,
    );
  }

  String _getChipEmoji(ScreenMaterialType type) {
    switch (type) {
      case ScreenMaterialType.textInput:
        return '📝';
      case ScreenMaterialType.passwordInput:
        return '🔒';
      case ScreenMaterialType.primaryButton:
        return '🔘';
      case ScreenMaterialType.headerText:
        return '🔤';
      case ScreenMaterialType.subtitleText:
        return '📄';
      case ScreenMaterialType.containerCard:
        return '📑';
      case ScreenMaterialType.socialButton:
        return '🌐';
      case ScreenMaterialType.icon:
        return '🖼️';
      case ScreenMaterialType.appBar:
        return '🧭';
      case ScreenMaterialType.secondaryButton:
        return '🔘';
      case ScreenMaterialType.switchTile:
        return '🔲';
      case ScreenMaterialType.checkboxTile:
        return '☑️';
    }
  }

  @override
  Widget build(BuildContext context) {
    final materials = _materials;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ---------------------------------------------------------------------
        // Header: Title & Materials Count Badge
        // ---------------------------------------------------------------------
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.layers_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Materiais & Componentes da Tela',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Text(
                '${materials.length}',
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ---------------------------------------------------------------------
        // Prominent Button: ✨ Melhorar & Organizar com IA
        // ---------------------------------------------------------------------
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              key: const ValueKey('ai_enhance_materials_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => _handleAiEnhance(materials),
              icon: const Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: Colors.white,
              ),
              label: const Text(
                '✨ Melhorar & Organizar com IA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ---------------------------------------------------------------------
        // Quick Add Palette (1-Click & Drag-and-Drop)
        // ---------------------------------------------------------------------
        Row(
          children: [
            const Icon(
              Icons.add_circle_outline_rounded,
              size: 12,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Adicionar Componente (clique ou arraste):',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildPaletteScroll(availableMaterialPalette),
        const SizedBox(height: 12),

        // ---------------------------------------------------------------------
        // Materials Stack in the Screen
        // ---------------------------------------------------------------------
        DragTarget<ScreenMaterialItem>(
          key: const ValueKey('materials_drag_target'),
          onWillAcceptWithDetails: (details) => true,
          onAcceptWithDetails: (details) {
            setState(() => _isDropAreaHovered = false);
            _addMaterial(details.data);
          },
          onMove: (details) {
            if (!_isDropAreaHovered) {
              setState(() => _isDropAreaHovered = true);
            }
          },
          onLeave: (details) {
            if (_isDropAreaHovered) {
              setState(() => _isDropAreaHovered = false);
            }
          },
          builder: (context, candidateData, rejectedData) {
            if (materials.isEmpty) {
              return _buildEmptyDropZone();
            }

            return Container(
              decoration: BoxDecoration(
                color: _isDropAreaHovered
                    ? AppColors.primary.withOpacity(0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: _isDropAreaHovered
                    ? Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5)
                    : null,
              ),
              child: ListView.separated(
                key: const ValueKey('screen_materials_list'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: materials.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final item = materials[index];
                  return _buildMaterialItemCard(
                    item: item,
                    index: index,
                    totalCount: materials.length,
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPaletteScroll(List<ScreenMaterialItem> palette) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: palette.map((prototype) {
          final emoji = _getChipEmoji(prototype.type);
          final label = '+ $emoji ${prototype.type.shortChipLabel}';

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Draggable<ScreenMaterialItem>(
              data: prototype,
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: prototype.type.accentColor,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        prototype.icon ?? prototype.type.defaultIcon,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        prototype.type.shortChipLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: _buildChipButton(
                  prototype: prototype,
                  label: label,
                  onTap: () => _addMaterial(prototype),
                ),
              ),
              child: _buildChipButton(
                prototype: prototype,
                label: label,
                onTap: () => _addMaterial(prototype),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChipButton({
    required ScreenMaterialItem prototype,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: ValueKey('palette_chip_${prototype.type.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: prototype.type.accentColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: prototype.type.accentColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDropZone() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: _isDropAreaHovered
            ? AppColors.primary.withOpacity(0.1)
            : AppColors.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDropAreaHovered
              ? AppColors.primary
              : AppColors.borderSubtle,
          style: BorderStyle.solid,
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            size: 28,
            color: _isDropAreaHovered
                ? AppColors.primary
                : AppColors.textMuted,
          ),
          const SizedBox(height: 8),
          Text(
            'Nenhum material adicionado ainda',
            style: TextStyle(
              color: _isDropAreaHovered
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Clique nos chips acima ou arraste componentes para montar a tela visualmente!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialItemCard({
    required ScreenMaterialItem item,
    required int index,
    required int totalCount,
  }) {
    final accentColor = item.type.accentColor;
    final iconData = item.icon ?? item.type.defaultIcon;

    return DragTarget<ScreenMaterialItem>(
      key: ValueKey('material_drop_target_$index'),
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        setState(() => _hoveredDropIndex = null);
        _addMaterial(details.data, index: index);
      },
      onMove: (details) {
        if (_hoveredDropIndex != index) {
          setState(() => _hoveredDropIndex = index);
        }
      },
      onLeave: (details) {
        if (_hoveredDropIndex == index) {
          setState(() => _hoveredDropIndex = null);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = _hoveredDropIndex == index;

        return Container(
          key: ValueKey('material_item_$index'),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHovered
                  ? AppColors.primary
                  : AppColors.borderSubtle,
              width: isHovered ? 1.5 : 1,
            ),
            boxShadow: isHovered
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Color-coded icon pill
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  iconData,
                  size: 15,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 10),

              // Title & Description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.hint ?? item.type.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Up Arrow Button
              IconButton(
                key: ValueKey('material_up_$index'),
                tooltip: 'Mover para cima',
                icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                color: index > 0 ? AppColors.textSecondary : AppColors.textMuted.withOpacity(0.3),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: index > 0 ? () => _reorderMaterial(index, index - 1) : null,
              ),

              // Down Arrow Button
              IconButton(
                key: ValueKey('material_down_$index'),
                tooltip: 'Mover para baixo',
                icon: const Icon(Icons.arrow_downward_rounded, size: 14),
                color: index < totalCount - 1
                    ? AppColors.textSecondary
                    : AppColors.textMuted.withOpacity(0.3),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: index < totalCount - 1
                    ? () => _reorderMaterial(index, index + 1)
                    : null,
              ),

              const SizedBox(width: 4),

              // Delete Button (Trash icon)
              IconButton(
                key: ValueKey('material_delete_$index'),
                tooltip: 'Remover da tela',
                icon: const Icon(Icons.delete_outline_rounded, size: 14),
                color: AppColors.danger.withOpacity(0.85),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => _removeMaterial(index),
              ),
            ],
          ),
        );
      },
    );
  }
}
