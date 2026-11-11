import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/route_node.dart';

class RouteConnectorPainter extends CustomPainter {
  final List<RouteNode> nodes;
  final String? selectedNodeId;
  final double cardWidth;
  final double cardHeight;

  const RouteConnectorPainter({
    required this.nodes,
    this.selectedNodeId,
    this.cardWidth = 260.0,
    this.cardHeight = 110.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Subtle Dot-Grid Background
    final dotPaint = Paint()
      ..color = AppColors.border.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

    // 2. Draw Connections Between Nodes
    final nodeMap = {for (var n in nodes) n.id: n};

    for (final node in nodes) {
      if (node.parentRouteId == null) continue;
      final parent = nodeMap[node.parentRouteId];
      if (parent == null) continue;

      final parentHeight = parent.isCollapsed ? 38.0 : 110.0;
      final nodeHeight = node.isCollapsed ? 38.0 : 110.0;

      final start = Offset(
        parent.position.dx + cardWidth,
        parent.position.dy + (parentHeight / 2),
      );
      final end = Offset(
        node.position.dx,
        node.position.dy + (nodeHeight / 2),
      );

      final isHighlighted =
          node.id == selectedNodeId || parent.id == selectedNodeId;

      final strokeColor = isHighlighted
          ? AppColors.secondary
          : (node.isAIGenerated
              ? AppColors.secondary.withOpacity(0.7)
              : (node.isProtected
                  ? AppColors.primary.withOpacity(0.6)
                  : AppColors.textMuted.withOpacity(0.4)));

      final linePaint = Paint()
        ..color = strokeColor
        ..strokeWidth = isHighlighted ? 2.5 : 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // Cubic Bezier curve for elegant flow
      final controlDistance = (end.dx - start.dx).abs() * 0.5;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + controlDistance,
          start.dy,
          end.dx - controlDistance,
          end.dy,
          end.dx,
          end.dy,
        );

      canvas.drawPath(path, linePaint);

      // Draw Arrow Head at end
      _drawArrowHead(canvas, end, linePaint.color);
    }
  }

  void _drawArrowHead(Canvas canvas, Offset endPoint, Color color) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const arrowLength = 7.0;
    const arrowWidth = 5.0;

    final arrowPath = Path()
      ..moveTo(endPoint.dx, endPoint.dy)
      ..lineTo(endPoint.dx - arrowLength, endPoint.dy - arrowWidth)
      ..lineTo(endPoint.dx - arrowLength + 2, endPoint.dy)
      ..lineTo(endPoint.dx - arrowLength, endPoint.dy + arrowWidth)
      ..close();

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant RouteConnectorPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.selectedNodeId != selectedNodeId;
  }
}
