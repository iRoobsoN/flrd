import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/route_node.dart';

class RouteNodeCard extends StatefulWidget {
  final RouteNode node;
  final bool isSelected;
  final VoidCallback onTap;
  final Function(Offset newPos) onDrag;

  const RouteNodeCard({
    super.key,
    required this.node,
    required this.isSelected,
    required this.onTap,
    required this.onDrag,
  });

  @override
  State<RouteNodeCard> createState() => _RouteNodeCardState();
}

class _RouteNodeCardState extends State<RouteNodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onPanUpdate: (details) {
          widget.onDrag(node.position + details.delta);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 260,
          height: 110,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.surfaceSelected
                : (_isHovered ? AppColors.surfaceHover : AppColors.surfaceCard),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primary
                  : (_isHovered
                      ? AppColors.secondary.withOpacity(0.6)
                      : (node.isAIGenerated
                          ? AppColors.secondary.withOpacity(0.4)
                          : AppColors.border)),
              width: widget.isSelected ? 1.8 : 1.0,
            ),
            boxShadow: widget.isSelected
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
                    : []),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Route Path + Status Badges
              Row(
                children: [
                  Container(
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
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: AppColors.secondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
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
          ),
        ),
      ),
    );
  }
}
