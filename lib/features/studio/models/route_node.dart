import 'package:flutter/material.dart';
import '../../wizard/models/project_config.dart';

const _nodeSentinel = Object();

class RouteNode {
  final String id;
  final String path;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isProtected;
  final bool isAIGenerated;
  final List<DevicePermission> requiredPermissions;
  final Offset position;
  final String filePath;
  final String? parentRouteId;

  const RouteNode({
    required this.id,
    required this.path,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isProtected = false,
    this.isAIGenerated = false,
    this.requiredPermissions = const [],
    required this.position,
    required this.filePath,
    this.parentRouteId,
  });

  RouteNode copyWith({
    String? id,
    String? path,
    String? title,
    String? subtitle,
    IconData? icon,
    bool? isProtected,
    bool? isAIGenerated,
    List<DevicePermission>? requiredPermissions,
    Offset? position,
    String? filePath,
    Object? parentRouteId = _nodeSentinel,
  }) {
    return RouteNode(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      isProtected: isProtected ?? this.isProtected,
      isAIGenerated: isAIGenerated ?? this.isAIGenerated,
      requiredPermissions: requiredPermissions ?? this.requiredPermissions,
      position: position ?? this.position,
      filePath: filePath ?? this.filePath,
      parentRouteId: identical(parentRouteId, _nodeSentinel)
          ? this.parentRouteId
          : parentRouteId as String?,
    );
  }
}
