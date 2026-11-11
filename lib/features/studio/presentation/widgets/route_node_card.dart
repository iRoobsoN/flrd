import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/route_node.dart';

class RouteNodeCard extends StatefulWidget {
  final RouteNode node;
  final bool isSelected;
  final VoidCallback onTap;
  final Function(Offset newPos)? onDrag;
  final VoidCallback? onDragStart;
  final void Function(Offset delta)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final VoidCallback? onToggleCollapse;

  const RouteNodeCard({
    super.key,
    required this.node,
    required this.isSelected,
    required this.onTap,
    this.onDrag,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onToggleCollapse,
  });

  @override
  State<RouteNodeCard> createState() => _RouteNodeCardState();
}

class _RouteNodeCardState extends State<RouteNodeCard> {
  bool _isHovered = false;
  bool _isDragging = false;
  bool? _localCollapsed;

  DateTime? _lastTapTime;

  bool get _isCollapsed => _localCollapsed ?? widget.node.isCollapsed;

  @override
  void didUpdateWidget(RouteNodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.isCollapsed != widget.node.isCollapsed) {
      _localCollapsed = null;
    }
  }

  void _handleTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 350)) {
      _lastTapTime = null;
      _toggleCollapse();
    } else {
      _lastTapTime = now;
      widget.onTap();
    }
  }

  void _toggleCollapse() {
    if (widget.onToggleCollapse != null) {
      widget.onToggleCollapse!();
    } else {
      setState(() {
        _localCollapsed = !_isCollapsed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isCollapsed = _isCollapsed;

    return MouseRegion(
      cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTap: _handleTap,
        onPanStart: (details) {
          if (mounted) {
            setState(() => _isDragging = true);
          }
          try {
            HapticFeedback.selectionClick();
          } catch (_) {}
          widget.onDragStart?.call();
        },
        onPanUpdate: (details) {
          widget.onDrag?.call(node.position + details.delta);
          widget.onDragUpdate?.call(details.delta);
        },
        onPanEnd: (details) {
          if (mounted) {
            setState(() => _isDragging = false);
          }
          widget.onDragEnd?.call();
        },
        onPanCancel: () {
          if (mounted) {
            setState(() => _isDragging = false);
          }
          widget.onDragEnd?.call();
        },
        child: AnimatedContainer(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 150),
          clipBehavior: Clip.antiAlias,
          width: 260,
          height: isCollapsed ? 38 : 110,
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 10 : 12,
            vertical: isCollapsed ? 7 : 12,
          ),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.surfaceSelected
                : (_isDragging || _isHovered ? AppColors.surfaceHover : AppColors.surfaceCard),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primary
                  : (_isDragging
                      ? AppColors.secondary
                      : (_isHovered
                          ? AppColors.secondary.withOpacity(0.6)
                          : (node.isAIGenerated
                              ? AppColors.secondary.withOpacity(0.4)
                              : AppColors.border))),
              width: widget.isSelected || _isDragging ? 1.8 : 1.0,
            ),
            boxShadow: _isDragging
                ? [
                    BoxShadow(
                      color: (widget.isSelected ? AppColors.primary : AppColors.secondary).withOpacity(0.35),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : (widget.isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : (_isHovered
                        ? [
                            BoxShadow(
                              color: AppColors.secondary.withOpacity(0.12),
                              blurRadius: 12,
                            ),
                          ]
                        : [])),
          ),
          child: isCollapsed
              ? _buildCollapsedRow(node)
              : SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    height: 86,
                    child: _buildExpandedColumn(node),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCollapseButton({required bool isExpand}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleCollapse,
      child: Container(
        key: ValueKey(isExpand ? 'expand_btn_${widget.node.id}' : 'collapse_btn_${widget.node.id}'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.borderSubtle.withOpacity(0.5)),
        ),
        child: Icon(
          isExpand ? Icons.expand_more_rounded : Icons.expand_less_rounded,
          size: 14,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildCollapsedRow(RouteNode node) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Screen Icon
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: node.isAIGenerated
                ? AppColors.secondary.withOpacity(0.12)
                : AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(
            node.icon,
            size: 13,
            color: node.isAIGenerated
                ? AppColors.secondary
                : AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),

        // Screen Title
        Flexible(
          child: Text(
            node.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Route Path Capsule
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Text(
              node.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: AppColors.secondary,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),

        // Expand Icon Button
        _buildCollapseButton(isExpand: true),
      ],
    );
  }

  Widget _buildExpandedColumn(RouteNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Bar: Route Path + Status Badges + Collapse Button
        Row(
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Text(
                  node.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: AppColors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (node.isAIGenerated) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 10,
                      color: AppColors.secondary,
                    ),
                    SizedBox(width: 3),
                    Text(
                      'AI Gen',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (node.isProtected) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 9,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 3),
                    Text(
                      'Guard',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            _buildCollapseButton(isExpand: false),
          ],
        ),
        const SizedBox(height: 8),

        // Middle: Icon + Screen Title
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: node.isAIGenerated
                    ? AppColors.secondary.withOpacity(0.12)
                    : AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                node.icon,
                size: 16,
                color: node.isAIGenerated
                    ? AppColors.secondary
                    : AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    node.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),

        // Bottom Info: File path snippet & permissions
        Row(
          children: [
            Expanded(
              child: Text(
                node.filePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: AppColors.textMuted.withOpacity(0.7),
                  fontSize: 9,
                ),
              ),
            ),
            if (node.requiredPermissions.isNotEmpty) ...[
              const Icon(
                Icons.security_rounded,
                size: 11,
                color: AppColors.warning,
              ),
              const SizedBox(width: 2),
              Text(
                '${node.requiredPermissions.length}',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
