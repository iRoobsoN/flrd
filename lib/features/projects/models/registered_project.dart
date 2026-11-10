import '../../wizard/models/project_config.dart';

class RegisteredProject {
  final String id;
  final String name;
  final String orgId;
  final String path;
  final PresetType preset;
  final NavigationStyle navigationStyle;
  final Set<DevicePermission> permissions;
  final DateTime lastModified;
  final int routeCount;

  const RegisteredProject({
    required this.id,
    required this.name,
    required this.orgId,
    required this.path,
    required this.preset,
    required this.navigationStyle,
    required this.permissions,
    required this.lastModified,
    required this.routeCount,
  });

  RegisteredProject copyWith({
    String? id,
    String? name,
    String? orgId,
    String? path,
    PresetType? preset,
    NavigationStyle? navigationStyle,
    Set<DevicePermission>? permissions,
    DateTime? lastModified,
    int? routeCount,
  }) {
    return RegisteredProject(
      id: id ?? this.id,
      name: name ?? this.name,
      orgId: orgId ?? this.orgId,
      path: path ?? this.path,
      preset: preset ?? this.preset,
      navigationStyle: navigationStyle ?? this.navigationStyle,
      permissions: permissions ?? this.permissions,
      lastModified: lastModified ?? this.lastModified,
      routeCount: routeCount ?? this.routeCount,
    );
  }
}
