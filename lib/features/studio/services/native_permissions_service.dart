import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../wizard/models/project_config.dart';

/// Descriptor for a common native permission across Android & iOS.
@immutable
class NativePermissionDescriptor {
  final String id;
  final String name;
  final String description;
  final String androidTag;
  final String? iosKey;
  final String? iosDefaultReason;
  final IconData icon;
  final DevicePermission? presetMapping;

  const NativePermissionDescriptor({
    required this.id,
    required this.name,
    required this.description,
    required this.androidTag,
    this.iosKey,
    this.iosDefaultReason,
    required this.icon,
    this.presetMapping,
  });
}

/// Snapshot of real permissions currently declared inside `AndroidManifest.xml`
/// and `ios/Runner/Info.plist`.
@immutable
class ProjectPermissionsSnapshot {
  final bool hasAndroidManifest;
  final bool hasIosPlist;
  final List<String> androidPermissions;
  final Map<String, String> iosUsageDescriptions;
  final String? errorMessage;

  const ProjectPermissionsSnapshot({
    required this.hasAndroidManifest,
    required this.hasIosPlist,
    this.androidPermissions = const [],
    this.iosUsageDescriptions = const {},
    this.errorMessage,
  });

  bool hasPermission(NativePermissionDescriptor descriptor) {
    final hasAndroid = androidPermissions.contains(descriptor.androidTag);
    final hasIos = descriptor.iosKey != null &&
        iosUsageDescriptions.containsKey(descriptor.iosKey);
    return hasAndroid || (!hasAndroidManifest && hasIos);
  }
}

/// Reads and mutates native permissions safely inside `AndroidManifest.xml`
/// and `ios/Runner/Info.plist` using XML AST parsing (`package:xml`).
class NativePermissionsService {
  NativePermissionsService._();

  static final List<NativePermissionDescriptor> commonPermissions = [
    NativePermissionDescriptor(
      id: 'camera',
      name: DevicePermission.camera.name,
      description: 'Acesso à câmera para fotos, vídeo e leitor QR.',
      androidTag: DevicePermission.camera.androidTag,
      iosKey: DevicePermission.camera.iosKey,
      iosDefaultReason: DevicePermission.camera.iosDefaultReason,
      icon: DevicePermission.camera.icon,
      presetMapping: DevicePermission.camera,
    ),
    NativePermissionDescriptor(
      id: 'photo_library',
      name: DevicePermission.photoLibrary.name,
      description: 'Selecionar fotos e imagens da galeria (Android 13+).',
      androidTag: DevicePermission.photoLibrary.androidTag,
      iosKey: DevicePermission.photoLibrary.iosKey,
      iosDefaultReason: DevicePermission.photoLibrary.iosDefaultReason,
      icon: DevicePermission.photoLibrary.icon,
      presetMapping: DevicePermission.photoLibrary,
    ),
    NativePermissionDescriptor(
      id: 'location',
      name: DevicePermission.location.name,
      description: 'Acesso à localização GPS precisa em primeiro plano.',
      androidTag: DevicePermission.location.androidTag,
      iosKey: DevicePermission.location.iosKey,
      iosDefaultReason: DevicePermission.location.iosDefaultReason,
      icon: DevicePermission.location.icon,
      presetMapping: DevicePermission.location,
    ),
    NativePermissionDescriptor(
      id: 'notifications',
      name: DevicePermission.notifications.name,
      description: 'Enviar notificações push e alertas (Android 13+).',
      androidTag: DevicePermission.notifications.androidTag,
      iosKey: DevicePermission.notifications.iosKey,
      iosDefaultReason: DevicePermission.notifications.iosDefaultReason,
      icon: DevicePermission.notifications.icon,
      presetMapping: DevicePermission.notifications,
    ),
    NativePermissionDescriptor(
      id: 'biometrics',
      name: DevicePermission.biometrics.name,
      description: 'Autenticação biométrica via digital ou Face ID.',
      androidTag: DevicePermission.biometrics.androidTag,
      iosKey: DevicePermission.biometrics.iosKey,
      iosDefaultReason: DevicePermission.biometrics.iosDefaultReason,
      icon: DevicePermission.biometrics.icon,
      presetMapping: DevicePermission.biometrics,
    ),
    const NativePermissionDescriptor(
      id: 'internet',
      name: 'Internet (Rede)',
      description: 'Acesso à internet para APIs REST, pub.dev e WebSockets.',
      androidTag: 'android.permission.INTERNET',
      icon: Icons.public_rounded,
    ),
    const NativePermissionDescriptor(
      id: 'microphone',
      name: 'Microfone / Áudio',
      description: 'Captura de áudio, gravação de voz ou chamadas.',
      androidTag: 'android.permission.RECORD_AUDIO',
      iosKey: 'NSMicrophoneUsageDescription',
      iosDefaultReason: 'Este app precisa acessar o microfone para gravar áudio.',
      icon: Icons.mic_rounded,
    ),
    const NativePermissionDescriptor(
      id: 'bluetooth',
      name: 'Bluetooth (Android 12+)',
      description: 'Conexão com dispositivos BLE, impressoras e acessórios.',
      androidTag: 'android.permission.BLUETOOTH_CONNECT',
      iosKey: 'NSBluetoothAlwaysUsageDescription',
      iosDefaultReason: 'Este app usa Bluetooth para conectar dispositivos próximos.',
      icon: Icons.bluetooth_rounded,
    ),
    const NativePermissionDescriptor(
      id: 'media_video',
      name: 'Vídeos da Galeria',
      description: 'Leitura de arquivos de vídeo do aparelho (Android 13+).',
      androidTag: 'android.permission.READ_MEDIA_VIDEO',
      icon: Icons.video_library_rounded,
    ),
    const NativePermissionDescriptor(
      id: 'foreground_service',
      name: 'Serviço em Segundo Plano',
      description: 'Execução contínua de geração/processamento sem pausa do OS.',
      androidTag: 'android.permission.FOREGROUND_SERVICE',
      icon: Icons.settings_applications_rounded,
    ),
  ];

  static String normalizeAndroidTag(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return '';
    if (cleaned.contains('.')) return cleaned;
    return 'android.permission.${cleaned.toUpperCase()}';
  }

  static File _androidManifestFile(String projectRoot) => File(
        p.join(
          p.normalize(projectRoot.isEmpty ? '.' : projectRoot),
          'android',
          'app',
          'src',
          'main',
          'AndroidManifest.xml',
        ),
      );

  static File _iosPlistFile(String projectRoot) => File(
        p.join(
          p.normalize(projectRoot.isEmpty ? '.' : projectRoot),
          'ios',
          'Runner',
          'Info.plist',
        ),
      );

  /// Reads all real Android & iOS permissions currently present on disk.
  static ProjectPermissionsSnapshot readPermissions(String projectRoot) {
    if (kIsWeb || projectRoot.trim().isEmpty) {
      return const ProjectPermissionsSnapshot(
        hasAndroidManifest: false,
        hasIosPlist: false,
        errorMessage: 'Projeto local indisponível.',
      );
    }

    final manifestFile = _androidManifestFile(projectRoot);
    final plistFile = _iosPlistFile(projectRoot);

    final hasAndroid = manifestFile.existsSync();
    final hasIos = plistFile.existsSync();

    final androidTags = <String>[];
    String? errorMsg;

    if (hasAndroid) {
      try {
        final content = manifestFile.readAsStringSync();
        final doc = XmlDocument.parse(content);
        for (final el in doc.findAllElements('uses-permission')) {
          final name =
              el.getAttribute('android:name') ?? el.getAttribute('name') ?? '';
          if (name.isNotEmpty && !androidTags.contains(name)) {
            androidTags.add(name);
          }
        }
      } catch (e) {
        errorMsg = 'Falha ao ler AndroidManifest.xml: $e';
      }
    }

    final iosMap = <String, String>{};
    if (hasIos) {
      try {
        final content = plistFile.readAsStringSync();
        final doc = XmlDocument.parse(content);
        final dictNode = doc.findAllElements('dict').firstOrNull;
        if (dictNode != null) {
          final elements = dictNode.childElements.toList();
          for (var i = 0; i + 1 < elements.length; i++) {
            final curr = elements[i];
            final next = elements[i + 1];
            if (curr.name.local == 'key' && next.name.local == 'string') {
              final keyName = curr.innerText.trim();
              if (keyName.startsWith('NS') &&
                  keyName.endsWith('UsageDescription')) {
                iosMap[keyName] = next.innerText.trim();
              }
            }
          }
        }
      } catch (e) {
        errorMsg = errorMsg ?? 'Falha ao ler Info.plist: $e';
      }
    }

    return ProjectPermissionsSnapshot(
      hasAndroidManifest: hasAndroid,
      hasIosPlist: hasIos,
      androidPermissions: androidTags,
      iosUsageDescriptions: iosMap,
      errorMessage: errorMsg,
    );
  }

  /// Adds or removes a known [NativePermissionDescriptor] across Android & iOS.
  static Future<bool> setKnownPermissionEnabled({
    required String projectRoot,
    required NativePermissionDescriptor descriptor,
    required bool enabled,
  }) async {
    var touchedAny = false;

    final manifestFile = _androidManifestFile(projectRoot);
    if (manifestFile.existsSync()) {
      final ok = enabled
          ? await addAndroidPermission(
              projectRoot: projectRoot,
              permissionTag: descriptor.androidTag,
            )
          : await removeAndroidPermission(
              projectRoot: projectRoot,
              permissionTag: descriptor.androidTag,
            );
      if (ok) touchedAny = true;
    }

    final plistFile = _iosPlistFile(projectRoot);
    if (descriptor.iosKey != null && plistFile.existsSync()) {
      final ok = enabled
          ? await setIosPermission(
              projectRoot: projectRoot,
              iosKey: descriptor.iosKey!,
              reason: descriptor.iosDefaultReason ??
                  'Required for ${descriptor.name} functionality.',
            )
          : await removeIosPermission(
              projectRoot: projectRoot,
              iosKey: descriptor.iosKey!,
            );
      if (ok) touchedAny = true;
    }

    return touchedAny;
  }

  /// Injects a `<uses-permission android:name="..."/>` element if absent.
  static Future<bool> addAndroidPermission({
    required String projectRoot,
    required String permissionTag,
  }) async {
    final normalizedTag = normalizeAndroidTag(permissionTag);
    if (normalizedTag.isEmpty) return false;

    final file = _androidManifestFile(projectRoot);
    if (!file.existsSync()) return false;

    try {
      final content = file.readAsStringSync();
      final isCrlf = content.contains('\r\n');
      final document = XmlDocument.parse(content);
      final manifestNode = document.findAllElements('manifest').firstOrNull;
      if (manifestNode == null) return false;

      final existing = document
          .findAllElements('uses-permission')
          .map((el) => el.getAttribute('android:name') ?? el.getAttribute('name'))
          .whereType<String>()
          .toSet();

      if (!existing.contains(normalizedTag)) {
        final newElement = XmlElement(
          XmlName('uses-permission'),
          [XmlAttribute(XmlName('android:name'), normalizedTag)],
        );
        // Insert before <application> if present so manifest ordering stays tidy.
        final appIdx = manifestNode.children.indexWhere(
          (n) => n is XmlElement && n.name.local == 'application',
        );
        if (appIdx >= 0) {
          manifestNode.children.insert(appIdx, newElement);
        } else {
          manifestNode.children.add(newElement);
        }
        var updated = document.toXmlString(pretty: true, indent: '    ');
        if (isCrlf) updated = updated.replaceAll('\n', '\r\n');
        file.writeAsStringSync(updated);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes `<uses-permission android:name="..."/>` from `AndroidManifest.xml`.
  static Future<bool> removeAndroidPermission({
    required String projectRoot,
    required String permissionTag,
  }) async {
    final normalizedTag = normalizeAndroidTag(permissionTag);
    if (normalizedTag.isEmpty) return false;

    final file = _androidManifestFile(projectRoot);
    if (!file.existsSync()) return false;

    try {
      final content = file.readAsStringSync();
      final isCrlf = content.contains('\r\n');
      final document = XmlDocument.parse(content);
      final manifestNode = document.findAllElements('manifest').firstOrNull;
      if (manifestNode == null) return false;

      final toRemove = manifestNode.childElements.where((el) {
        if (el.name.local != 'uses-permission') return false;
        final name = el.getAttribute('android:name') ?? el.getAttribute('name');
        return name == normalizedTag;
      }).toList();

      if (toRemove.isEmpty) return true;
      for (final node in toRemove) {
        node.remove();
      }

      var updated = document.toXmlString(pretty: true, indent: '    ');
      if (isCrlf) updated = updated.replaceAll('\n', '\r\n');
      file.writeAsStringSync(updated);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Adds or updates an `NS*UsageDescription` key/string pair inside `Info.plist`.
  static Future<bool> setIosPermission({
    required String projectRoot,
    required String iosKey,
    required String reason,
  }) async {
    final cleanKey = iosKey.trim();
    final cleanReason = reason.trim();
    if (cleanKey.isEmpty || cleanReason.isEmpty) return false;

    final file = _iosPlistFile(projectRoot);
    if (!file.existsSync()) return false;

    try {
      final content = file.readAsStringSync();
      final isCrlf = content.contains('\r\n');
      final document = XmlDocument.parse(content);
      final dictNode = document.findAllElements('dict').firstOrNull;
      if (dictNode == null) return false;

      final children = dictNode.childElements.toList();
      var updatedExisting = false;
      for (var i = 0; i + 1 < children.length; i++) {
        final k = children[i];
        final v = children[i + 1];
        if (k.name.local == 'key' &&
            k.innerText.trim() == cleanKey &&
            v.name.local == 'string') {
          v.innerText = cleanReason;
          updatedExisting = true;
          break;
        }
      }

      if (!updatedExisting) {
        dictNode.children.add(
          XmlElement(XmlName('key'), [], [XmlText(cleanKey)]),
        );
        dictNode.children.add(
          XmlElement(XmlName('string'), [], [XmlText(cleanReason)]),
        );
      }

      var updated = document.toXmlString(pretty: true, indent: '\t');
      if (isCrlf) updated = updated.replaceAll('\n', '\r\n');
      file.writeAsStringSync(updated);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes an iOS `<key>/<string>` permission pair from `Info.plist`.
  static Future<bool> removeIosPermission({
    required String projectRoot,
    required String iosKey,
  }) async {
    final cleanKey = iosKey.trim();
    if (cleanKey.isEmpty) return false;

    final file = _iosPlistFile(projectRoot);
    if (!file.existsSync()) return false;

    try {
      final content = file.readAsStringSync();
      final isCrlf = content.contains('\r\n');
      final document = XmlDocument.parse(content);
      final dictNode = document.findAllElements('dict').firstOrNull;
      if (dictNode == null) return false;

      final children = dictNode.childElements.toList();
      for (var i = 0; i < children.length; i++) {
        final k = children[i];
        if (k.name.local == 'key' && k.innerText.trim() == cleanKey) {
          if (i + 1 < children.length && children[i + 1].name.local == 'string') {
            children[i + 1].remove();
          }
          k.remove();
          break;
        }
      }

      var updated = document.toXmlString(pretty: true, indent: '\t');
      if (isCrlf) updated = updated.replaceAll('\n', '\r\n');
      file.writeAsStringSync(updated);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Maps currently configured native tags back to [DevicePermission] values
  /// so `RegisteredProject` stays synchronized across FLRD.
  static Set<DevicePermission> computeDetectedDevicePermissions(
    ProjectPermissionsSnapshot snapshot,
  ) {
    final result = <DevicePermission>{};
    for (final perm in DevicePermission.values) {
      final hasAndroid = snapshot.androidPermissions.any(
        (tag) =>
            tag == perm.androidTag ||
            (perm == DevicePermission.photoLibrary &&
                tag == 'android.permission.READ_EXTERNAL_STORAGE') ||
            (perm == DevicePermission.location &&
                tag == 'android.permission.ACCESS_COARSE_LOCATION') ||
            (perm == DevicePermission.biometrics &&
                tag == 'android.permission.USE_FINGERPRINT'),
      );
      final hasIos = snapshot.iosUsageDescriptions.containsKey(perm.iosKey);
      if (hasAndroid || hasIos) {
        result.add(perm);
      }
    }
    return result;
  }
}
