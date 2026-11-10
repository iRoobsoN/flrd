import 'dart:io';
import 'package:xml/xml.dart';
import '../../wizard/models/project_config.dart';

class AndroidManifestInjector {
  AndroidManifestInjector._();

  /// Safely injects requested permissions into the AndroidManifest.xml using AST parsing.
  static Future<bool> injectPermissions({
    required String projectRoot,
    required Set<DevicePermission> permissions,
  }) async {
    final manifestFile = File(
      '$projectRoot/android/app/src/main/AndroidManifest.xml',
    );

    if (!await manifestFile.exists()) {
      return false;
    }

    try {
      final content = await manifestFile.readAsString();
      final document = XmlDocument.parse(content);
      final manifestNode = document.findAllElements('manifest').firstOrNull;

      if (manifestNode == null) return false;

      // Existing permissions to avoid duplicates
      final existingPermissions = document
          .findAllElements('uses-permission')
          .map((el) => el.getAttribute('android:name'))
          .whereType<String>()
          .toSet();

      for (final perm in permissions) {
        if (!existingPermissions.contains(perm.androidTag)) {
          final newElement = XmlElement(
            XmlName('uses-permission'),
            [XmlAttribute(XmlName('android:name'), perm.androidTag)],
          );
          manifestNode.children.add(newElement);
        }
      }

      await manifestFile.writeAsString(document.toXmlString(pretty: true, indent: '    '));
      return true;
    } catch (_) {
      return false;
    }
  }
}
