import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors.dart';
import '../../../projects/models/registered_project.dart';
import '../../domain/screen_material.dart';
import '../../models/route_node.dart';
import '../../providers/studio_provider.dart';
import 'ai_screen_generator_dialog.dart';

/// Interactive visual builder panel displaying materials currently in a screen,
/// a quick-add palette with 1-click & drag-and-drop addition, reordering,
/// per-component notes & prompts, focused widget AI generation, and full-screen AI elevation.
class ScreenMaterialsBuilder extends StatefulWidget {
  final RouteNode node;
  final RegisteredProject project;
  final String currentCode;
  final ValueChanged<String> onCodeChanged;
  final List<RouteNode>? existingRoutes;
  final WidgetRef? ref;

  const ScreenMaterialsBuilder({
    super.key,
    required this.node,
    required this.project,
    required this.currentCode,
    required this.onCodeChanged,
    this.existingRoutes,
    this.ref,
  });

  @override
  State<ScreenMaterialsBuilder> createState() => _ScreenMaterialsBuilderState();
}

class _ScreenMaterialsBuilderState extends State<ScreenMaterialsBuilder> {
  int? _hoveredDropIndex;
  bool _isDropAreaHovered = false;
  final Map<String, String> _localNotes = {};

  List<RouteNode>? get _effectiveExistingRoutes {
    if (widget.existingRoutes != null) return widget.existingRoutes;
    if (widget.ref != null) {
      try {
        return widget.ref!.read(studioProvider).nodes;
      } catch (_) {}
    }
    try {
      if (context.findAncestorWidgetOfExactType<ProviderScope>() != null) {
        return ProviderScope.containerOf(context, listen: false).read(studioProvider).nodes;
      }
    } catch (_) {}
    return null;
  }

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
    final list = ScreenMaterialParser.extractMaterialsFromCode(
      _effectiveCode,
      widget.node.title,
    );
    return list.asMap().entries.map((entry) {
      final idx = entry.key;
      final it = entry.value;
      final note = _getEffectiveNote(it, idx);
      return it.copyWith(note: note);
    }).toList();
  }

  String? _getEffectiveNote(ScreenMaterialItem item, int index) {
    if (_localNotes.containsKey(item.id)) {
      final note = _localNotes[item.id];
      return (note != null && note.isNotEmpty) ? note : null;
    }
    if (_localNotes.containsKey('$index')) {
      final note = _localNotes['$index'];
      return (note != null && note.isNotEmpty) ? note : null;
    }
    return item.note;
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
    _localNotes.remove('$index');
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

  void _updateMaterialNote(ScreenMaterialItem item, int index, String? newNote) {
    final cleanNote = (newNote != null && newNote.trim().isNotEmpty) ? newNote.trim() : null;
    setState(() {
      if (cleanNote != null) {
        _localNotes[item.id] = cleanNote;
        _localNotes['$index'] = cleanNote;
      } else {
        _localNotes.remove(item.id);
        _localNotes.remove('$index');
      }
    });

    final updatedCode = ScreenMaterialCodeUpdater.updateMaterialNoteInCode(
      currentCode: _effectiveCode,
      materialId: item.id,
      note: cleanNote,
      screenClassName: widget.node.title,
      routePath: widget.node.path,
      routeTitle: widget.node.title,
      isProtected: widget.node.isProtected,
    );
    _saveAndNotify(updatedCode);
  }

  void _handleRefineWidgetWithAi(ScreenMaterialItem material, int index) {
    final note = _getEffectiveNote(material, index);
    final targetMat = material.copyWith(note: note);
    AiScreenGeneratorDialog.show(
      context,
      widget.project,
      initialRoutePath: widget.node.path,
      initialScreenTitle: widget.node.title,
      targetMaterial: targetMat,
    );
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
    final annotatedMaterials = materials.asMap().entries.map((entry) {
      final idx = entry.key;
      final it = entry.value;
      final note = _getEffectiveNote(it, idx);
      return it.copyWith(note: note);
    }).toList();

    final prompt = ScreenMaterialCodeUpdater.generateAiEnhancePrompt(
      widget.node,
      annotatedMaterials,
      existingRoutes: _effectiveExistingRoutes,
      preset: widget.project.preset,
    );
    AiScreenGeneratorDialog.show(
      context,
      widget.project,
      initialPrompt: prompt,
      initialRoutePath: widget.node.path,
      initialScreenTitle: widget.node.title,
      initialMaterials: annotatedMaterials,
    );
  }

  Future<void> _showEditNoteDialog(ScreenMaterialItem item, int index) async {
    final currentNote = _getEffectiveNote(item, index) ?? '';
    final controller = TextEditingController(text: currentNote);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.borderSubtle),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: item.type.accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon ?? item.type.defaultIcon,
                  size: 16,
                  color: item.type.accentColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Anotação / Prompt do Widget',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.displayName,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Descreva como este componente deve se comportar, estilos visuais, interações ou estados com IA:',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('material_note_text_field'),
                controller: controller,
                maxLines: 4,
                autofocus: true,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  hintText: 'Ex: Botão azul que troca de cor quando toco nele...',
                  hintStyle: TextStyle(
                    color: AppColors.textMuted.withOpacity(0.6),
                    fontSize: 11.5,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          actions: [
            if (currentNote.isNotEmpty)
              TextButton.icon(
                key: const ValueKey('material_note_dialog_clear'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _updateMaterialNote(item, index, null);
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.danger),
                label: const Text(
                  'Remover Nota',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            TextButton(
              key: const ValueKey('material_note_dialog_cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            ElevatedButton(
              key: const ValueKey('material_note_dialog_save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: () {
                final newText = controller.text.trim();
                Navigator.of(dialogContext).pop();
                _updateMaterialNote(item, index, newText.isEmpty ? null : newText);
              },
              child: const Text(
                'Salvar Nota',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
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
    final effectiveNote = _getEffectiveNote(item, index);
    final hasNote = effectiveNote != null && effectiveNote.trim().isNotEmpty;

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
                  : hasNote
                      ? AppColors.primary.withOpacity(0.4)
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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

                  // Note button [💬 Nota] (when note does NOT exist)
                  if (!hasNote) ...[
                    InkWell(
                      key: ValueKey('material_note_button_$index'),
                      onTap: () => _showEditNoteDialog(item, index),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.2),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 11,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 3),
                            Text(
                              '💬 Nota',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],

                  // Up Arrow Button
                  IconButton(
                    key: ValueKey('material_up_$index'),
                    tooltip: 'Mover para cima',
                    icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                    color: index > 0
                        ? AppColors.textSecondary
                        : AppColors.textMuted.withOpacity(0.3),
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

              // Elegant Italic Card/Chip when note exists
              if (hasNote) ...[
                const SizedBox(height: 6),
                Container(
                  key: ValueKey('material_note_card_$index'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B4B).withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '💬 ',
                            style: TextStyle(fontSize: 10),
                          ),
                          Expanded(
                            child: Text(
                              '"$effectiveNote"',
                              style: const TextStyle(
                                color: Color(0xFFE0E7FF),
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Edit note button
                          InkWell(
                            key: ValueKey('material_note_edit_$index'),
                            onTap: () => _showEditNoteDialog(item, index),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(
                                Icons.edit_rounded,
                                size: 13,
                                color: AppColors.primary.withOpacity(0.9),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          // Clear note button
                          InkWell(
                            key: ValueKey('material_note_clear_$index'),
                            onTap: () => _updateMaterialNote(item, index, null),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: AppColors.textMuted.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // [✨ Refinar este Widget com IA] Button
                      SizedBox(
                        width: double.infinity,
                        child: InkWell(
                          key: ValueKey('material_ai_refine_$index'),
                          onTap: () => _handleRefineWidgetWithAi(item, index),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withOpacity(0.25),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 11,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '✨ Refinar este Widget com IA',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
