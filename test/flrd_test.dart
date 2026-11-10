import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flrd/features/generator/injectors/android_manifest_injector.dart';
import 'package:flrd/features/generator/injectors/ios_plist_injector.dart';

void main() {
  group('ProjectConfig Model Tests', () {
    test('Default values are initialized properly', () {
      const config = ProjectConfig();
      expect(config.projectName, 'my_awesome_app');
      expect(config.orgId, 'com.example');
      expect(config.preset, PresetType.saas);
      expect(config.navigationStyle, NavigationStyle.tabs);
      expect(config.enableDarkTheme, isTrue);
      expect(config.androidMinSdk, 24);
    });

    test('copyWith updates state correctly', () {
      const config = ProjectConfig();
      final updated = config.copyWith(
        projectName: 'new_app',
        preset: PresetType.cleanLite,
        androidMinSdk: 26,
      );

      expect(updated.projectName, 'new_app');
      expect(updated.preset, PresetType.cleanLite);
      expect(updated.androidMinSdk, 26);
      expect(updated.orgId, config.orgId);
    });
  });

  group('Semantic Injector Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flrd_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('AndroidManifestInjector injects permission safely without corrupting XML', () async {
      final manifestDir = Directory('${tempDir.path}/android/app/src/main');
      await manifestDir.create(recursive: true);
      final manifestFile = File('${manifestDir.path}/AndroidManifest.xml');

      await manifestFile.writeAsString('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="test_app">
    </application>
</manifest>''');

      final success = await AndroidManifestInjector.injectPermissions(
        projectRoot: tempDir.path,
        permissions: {DevicePermission.camera, DevicePermission.location},
      );

      expect(success, isTrue);

      final content = await manifestFile.readAsString();
      expect(content.contains('android.permission.CAMERA'), isTrue);
      expect(content.contains('android.permission.ACCESS_FINE_LOCATION'), isTrue);
    });

    test('IosPlistInjector injects usage descriptions into Info.plist', () async {
      final iosDir = Directory('${tempDir.path}/ios/Runner');
      await iosDir.create(recursive: true);
      final plistFile = File('${iosDir.path}/Info.plist');

      await plistFile.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>test_app</string>
</dict>
</plist>''');

      final success = await IosPlistInjector.injectPermissions(
        projectRoot: tempDir.path,
        permissions: {DevicePermission.camera},
      );

      expect(success, isTrue);

      final content = await plistFile.readAsString();
      expect(content.contains('NSCameraUsageDescription'), isTrue);
      expect(content.contains('This app requires camera access'), isTrue);
    });
  });
}
