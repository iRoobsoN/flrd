import 'dart:io';
import 'package:path/path.dart' as p;
import '../../wizard/models/project_config.dart';

class PermissionServiceTemplate {
  PermissionServiceTemplate._();

  static Future<void> synthesize(String targetPath, Set<DevicePermission> permissions) async {
    if (permissions.isEmpty) return;

    final filePath = p.normalize(
      p.join(targetPath, 'lib', 'core', 'services', 'permission_service.dart'),
    );
    final file = File(filePath);

    try {
      await file.parent.create(recursive: true);
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Failed to create parent directory for permission service: ${e.message}',
        file.parent.path,
        e.osError,
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('''
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Pre-built permission service scaffolded by FLRD.
/// Provides friendly pre-permission rationale dialogs before triggering native OS dialogs.
class PermissionService {
  PermissionService._();
''');

    for (final perm in permissions) {
      final methodName = _getMethodName(perm);
      final permissionType = _getPermissionHandlerEnum(perm);

      buffer.writeln('''
  /// Request ${perm.name} access with pre-rationale dialog
  static Future<bool> $methodName(BuildContext context) async {
    final status = await $permissionType.status;
    if (status.isGranted) return true;

    // Show friendly in-app explanation before native prompt
    if (context.mounted) {
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('${perm.name} Permission Required'),
          content: const Text('${perm.description}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );

      if (shouldRequest != true) return false;
    }

    final result = await $permissionType.request();
    if (result.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return result.isGranted;
  }
''');
    }

    buffer.writeln('}');

    try {
      await file.writeAsString(buffer.toString());
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Failed to write permission service: ${e.message}',
        file.path,
        e.osError,
      );
    }
  }

  static String _getMethodName(DevicePermission perm) {
    switch (perm) {
      case DevicePermission.camera:
        return 'requestCamera';
      case DevicePermission.location:
        return 'requestLocation';
      case DevicePermission.notifications:
        return 'requestNotifications';
      case DevicePermission.photoLibrary:
        return 'requestPhotoLibrary';
      case DevicePermission.biometrics:
        return 'requestBiometrics';
    }
  }

  static String _getPermissionHandlerEnum(DevicePermission perm) {
    switch (perm) {
      case DevicePermission.camera:
        return 'Permission.camera';
      case DevicePermission.location:
        return 'Permission.locationWhenInUse';
      case DevicePermission.notifications:
        return 'Permission.notification';
      case DevicePermission.photoLibrary:
        return 'Permission.photos';
      case DevicePermission.biometrics:
        return 'Permission.sensors'; // or biometric wrapper
    }
  }
}
