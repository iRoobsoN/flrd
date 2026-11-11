import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../../wizard/models/project_config.dart';

class IosPlistInjector {
  IosPlistInjector._();

  /// Safely injects App Store compliant permission descriptions into ios/Runner/Info.plist.
  static Future<bool> injectPermissions({
    required String projectRoot,
    required Set<DevicePermission> permissions,
  }) async {
    final plistPath = p.normalize(
      p.join(
        projectRoot.isEmpty ? '.' : projectRoot,
        'ios',
        'Runner',
        'Info.plist',
      ),
    );
    final plistFile = File(plistPath);

    if (!await plistFile.exists()) {
      return false;
    }

    try {
      final content = await plistFile.readAsString();
      final document = XmlDocument.parse(content);
      final dictNode = document.findAllElements('dict').firstOrNull;

      if (dictNode == null) return false;

      // Collect existing keys in <dict>
      final existingKeys = <String>{};
      for (final child in dictNode.children) {
        if (child is XmlElement && child.name.local == 'key') {
          existingKeys.add(child.innerText.trim());
        }
      }

      for (final perm in permissions) {
        if (!existingKeys.contains(perm.iosKey)) {
          final keyElement = XmlElement(XmlName('key'), [], [XmlText(perm.iosKey)]);
          final stringElement = XmlElement(
            XmlName('string'),
            [],
            [XmlText(perm.iosDefaultReason)],
          );

          dictNode.children.add(keyElement);
          dictNode.children.add(stringElement);
        }
      }

      await plistFile.writeAsString(document.toXmlString(pretty: true, indent: '\t'));
      return true;
    } on FileSystemException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
