import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../wizard/models/project_config.dart';
import '../models/route_node.dart';

const _studioSentinel = Object();

class StudioState {
  final List<RouteNode> nodes;
  final String? selectedNodeId;
  final double zoomScale;

  const StudioState({
    required this.nodes,
    this.selectedNodeId,
    this.zoomScale = 1.0,
  });

  RouteNode? get selectedNode {
    if (selectedNodeId == null) return null;
    try {
      return nodes.firstWhere((n) => n.id == selectedNodeId);
    } catch (_) {
      return null;
    }
  }

  StudioState copyWith({
    List<RouteNode>? nodes,
    Object? selectedNodeId = _studioSentinel,
    double? zoomScale,
  }) {
    return StudioState(
      nodes: nodes ?? this.nodes,
      selectedNodeId: identical(selectedNodeId, _studioSentinel)
          ? this.selectedNodeId
          : selectedNodeId as String?,
      zoomScale: zoomScale ?? this.zoomScale,
    );
  }
}

class StudioNotifier extends StateNotifier<StudioState> {
  StudioNotifier()
      : super(
          StudioState(
            nodes: [
              const RouteNode(
                id: 'root',
                path: '/',
                title: 'Splash & AuthGuard',
                subtitle: 'Automatic redirection via GoRouter',
                icon: Icons.alt_route_rounded,
                isProtected: false,
                position: Offset(50, 220),
                filePath: 'lib/core/router/app_router.dart',
              ),
              const RouteNode(
                id: 'login',
                path: '/auth/login',
                title: 'LoginScreen',
                subtitle: 'Supabase / BLoC Authentication',
                icon: Icons.lock_outline_rounded,
                isProtected: false,
                position: Offset(380, 80),
                filePath: 'lib/features/auth/presentation/login_screen.dart',
                parentRouteId: 'root',
              ),
              const RouteNode(
                id: 'register',
                path: '/auth/register',
                title: 'RegisterScreen',
                subtitle: 'New user onboarding & sign-up',
                icon: Icons.person_add_alt_1_rounded,
                isProtected: false,
                position: Offset(710, 80),
                filePath: 'lib/features/auth/presentation/register_screen.dart',
                parentRouteId: 'login',
              ),
              const RouteNode(
                id: 'dashboard',
                path: '/dashboard',
                title: 'DashboardScreen',
                subtitle: 'Shell navigation, metrics & stats',
                icon: Icons.space_dashboard_rounded,
                isProtected: true,
                position: Offset(380, 360),
                filePath: 'lib/features/dashboard/presentation/dashboard_screen.dart',
                parentRouteId: 'root',
              ),
              const RouteNode(
                id: 'explore',
                path: '/explore',
                title: 'ExploreScreen',
                subtitle: 'Project catalog & community feed',
                icon: Icons.explore_rounded,
                isProtected: true,
                position: Offset(710, 270),
                filePath: 'lib/features/explore/presentation/explore_screen.dart',
                parentRouteId: 'dashboard',
              ),
              const RouteNode(
                id: 'profile',
                path: '/profile',
                title: 'ProfileScreen',
                subtitle: 'User account & device permissions',
                icon: Icons.account_circle_rounded,
                isProtected: true,
                requiredPermissions: [DevicePermission.camera],
                position: Offset(710, 450),
                filePath: 'lib/features/profile/presentation/profile_screen.dart',
                parentRouteId: 'dashboard',
              ),
            ],
          ),
        );

  void selectNode(String? id) {
    state = state.copyWith(selectedNodeId: id);
  }

  void setNodes(List<RouteNode> nodes) {
    state = state.copyWith(
      nodes: nodes,
      selectedNodeId: nodes.isNotEmpty ? nodes.first.id : null,
    );
  }

  void addRouteNode({
    required String path,
    required String title,
    required String subtitle,
    required IconData icon,
    bool isProtected = true,
    bool isAIGenerated = false,
    List<DevicePermission> requiredPermissions = const [],
    required Offset position,
    required String filePath,
    String? parentRouteId,
  }) {
    final newNode = RouteNode(
      id: title.toLowerCase().replaceAll(' ', '_'),
      path: path,
      title: title,
      subtitle: subtitle,
      icon: icon,
      isProtected: isProtected,
      isAIGenerated: isAIGenerated,
      requiredPermissions: requiredPermissions,
      position: position,
      filePath: filePath,
      parentRouteId: parentRouteId,
    );

    state = state.copyWith(
      nodes: [...state.nodes, newNode],
      selectedNodeId: newNode.id,
    );
  }

  void updateNodePosition(String id, Offset newPosition) {
    state = state.copyWith(
      nodes: state.nodes.map((node) {
        if (node.id == id) {
          return node.copyWith(position: newPosition);
        }
        return node;
      }).toList(),
    );
  }

  void removeNode(String id) {
    state = state.copyWith(
      nodes: state.nodes.where((n) => n.id != id).toList(),
      selectedNodeId: state.selectedNodeId == id ? null : state.selectedNodeId,
    );
  }
}

final studioProvider =
    StateNotifierProvider<StudioNotifier, StudioState>((ref) {
  return StudioNotifier();
});
