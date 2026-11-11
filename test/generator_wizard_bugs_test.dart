import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flrd/features/generator/injectors/pubspec_injector.dart';
import 'package:flrd/features/generator/injectors/android_manifest_injector.dart';
import 'package:flrd/features/generator/injectors/ios_plist_injector.dart';
import 'package:flrd/features/generator/pipeline/project_generator.dart';
import 'package:flrd/features/generator/presets/preset_file_helper.dart';

void main() {
  group('ProjectNameValidator Tests', () {
    test('Valid package names pass validation', () {
      expect(ProjectNameValidator.validate('my_awesome_app'), isNull);
      expect(ProjectNameValidator.validate('saas_app_2'), isNull);
      expect(ProjectNameValidator.validate('flrd'), isNull);
      expect(ProjectNameValidator.validate('app123'), isNull);
      expect(ProjectNameValidator.validate('z'), isNull);
    });

    test('Rejects empty or whitespace-only names', () {
      expect(ProjectNameValidator.validate(''), contains('cannot be empty'));
      expect(ProjectNameValidator.validate('   '), contains('cannot be empty'));
      expect(ProjectNameValidator.validate('my app'), contains('whitespace'));
    });

    test('Rejects uppercase characters and suggests lowercase', () {
      final err = ProjectNameValidator.validate('MyApp');
      expect(err, isNotNull);
      expect(err, contains('must be all lowercase'));
      expect(err, contains('myapp'));
    });

    test('Rejects hyphens and suggests underscores', () {
      final err = ProjectNameValidator.validate('my-flutter-app');
      expect(err, isNotNull);
      expect(err, contains('cannot contain hyphens'));
      expect(err, contains('my_flutter_app'));
    });

    test('Rejects names starting with digit or underscore', () {
      expect(ProjectNameValidator.validate('123app'), contains('cannot start with a digit'));
      expect(ProjectNameValidator.validate('_app'), contains('must start with a lowercase letter'));
    });

    test('Rejects Dart reserved words (keywords)', () {
      const reserved = ['class', 'void', 'return', 'switch', 'null', 'int', 'assert', 'for', 'is', 'try', 'catch', 'do', 'while'];
      for (final word in reserved) {
        final err = ProjectNameValidator.validate(word);
        expect(err, isNotNull, reason: 'Expected "$word" to be rejected as a Dart keyword');
        expect(err, contains('is a Dart reserved keyword'));
      }
    });

    test('Rejects Flutter framework reserved package names', () {
      expect(ProjectNameValidator.validate('flutter'), contains('reserved by the Flutter framework'));
      expect(ProjectNameValidator.validate('flutter_test'), contains('reserved by the Flutter framework'));
      expect(ProjectNameValidator.validate('sky_engine'), contains('reserved by the Flutter framework'));
    });
  });

  group('OrgIdValidator Tests', () {
    test('Valid reverse domain IDs pass validation', () {
      expect(OrgIdValidator.validate('com.example'), isNull);
      expect(OrgIdValidator.validate('dev.robson'), isNull);
      expect(OrgIdValidator.validate('io.github.iroobson'), isNull);
      expect(OrgIdValidator.validate('br.com.empresa'), isNull);
    });

    test('Rejects empty or single segment IDs', () {
      expect(OrgIdValidator.validate(''), contains('cannot be empty'));
      expect(OrgIdValidator.validate('com'), contains('at least two segments'));
      expect(OrgIdValidator.validate('mycompany'), contains('at least two segments'));
    });

    test('Rejects empty segments or double dots', () {
      expect(OrgIdValidator.validate('com..example'), contains('empty segment'));
      expect(OrgIdValidator.validate('.com.example'), contains('empty segment'));
    });

    test('Rejects segments starting with digits or containing reserved words', () {
      expect(OrgIdValidator.validate('com.123company.app'), contains('cannot start with a digit'));
      expect(OrgIdValidator.validate('com.class.app'), contains('cannot be a Dart reserved keyword'));
    });
  });

  group('PubspecInjector AST Tests (yaml_edit Resilience)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flrd_pubspec_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Injects dependencies cleanly while preserving comments and structure', () async {
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
      await pubspec.writeAsString('''
name: sample_app
description: A sample application.
# Developer comments that must be preserved
version: 1.0.0+1

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  # Existing comment in dependencies
  cupertino_icons: ^1.0.6
''');

      final success = await PubspecInjector.injectDependencies(
        projectRoot: tempDir.path,
        dependencies: {
          'flutter_riverpod': '^2.5.1',
          'supabase_flutter': '^2.5.0',
        },
      );

      expect(success, isTrue);

      final content = await pubspec.readAsString();
      expect(content, contains('Developer comments that must be preserved'));
      expect(content, contains('Existing comment in dependencies'));
      expect(content, contains('flutter_riverpod: ^2.5.1'));
      expect(content, contains('supabase_flutter: ^2.5.0'));
      expect(content, contains('cupertino_icons: ^1.0.6'));
    });

    test('Handles missing dependencies map and null scalar gracefully', () async {
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
      await pubspec.writeAsString('''
name: minimal_app
# No dependencies key defined here
version: 1.0.0
''');

      final success = await PubspecInjector.injectDependencies(
        projectRoot: tempDir.path,
        dependencies: {'dio': '^5.4.0'},
      );

      expect(success, isTrue);

      final content = await pubspec.readAsString();
      expect(content, contains('dio: ^5.4.0'));
    });

    test('Handles Windows CRLF line endings without corrupting AST offsets', () async {
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
      // Intentionally using Windows CRLF
      await pubspec.writeAsString("name: crlf_app\r\nversion: 1.0.0\r\ndependencies:\r\n  flutter:\r\n    sdk: flutter\r\n");

      final success = await PubspecInjector.injectDependencies(
        projectRoot: tempDir.path,
        dependencies: {'go_router': '^13.0.0'},
      );

      expect(success, isTrue);
      final content = await pubspec.readAsString();
      expect(content, contains('go_router: ^13.0.0'));
    });

    test('Injects assets under flutter: assets node and avoids duplicates', () async {
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
      await pubspec.writeAsString('''
name: assets_app
version: 1.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
''');

      final success = await PubspecInjector.injectAssets(
        projectRoot: tempDir.path,
        assets: [
          'assets/images/', // Duplicate, must not be duplicated
          'assets/icons/',
          'assets/templates/',
        ],
      );

      expect(success, isTrue);
      final content = await pubspec.readAsString();
      expect(content, contains('assets/images/'));
      expect(content, contains('assets/icons/'));
      expect(content, contains('assets/templates/'));

      // Check 'assets/images/' appears only once in assets section
      final matches = RegExp(r'-\s+assets/images/').allMatches(content);
      expect(matches.length, 1);
    });

    test('Handles missing pubspec.yaml gracefully without unhandled exception', () async {
      final success = await PubspecInjector.injectDependencies(
        projectRoot: p.join(tempDir.path, 'non_existent_folder'),
        dependencies: {'dio': '^5.0.0'},
      );
      expect(success, isFalse);
    });
  });

  group('Windows vs POSIX Path Separator Normalization Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flrd_path_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('AndroidManifestInjector safely normalizes paths with mixed or Windows separators', () async {
      final manifestDir = Directory(p.join(tempDir.path, 'android', 'app', 'src', 'main'));
      await manifestDir.create(recursive: true);
      final manifestFile = File(p.join(manifestDir.path, 'AndroidManifest.xml'));
      await manifestFile.writeAsString('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="test_app"></application>
</manifest>''');

      // Emulate Windows path with mixed slashes / backslashes
      final mixedPath = '${tempDir.path}\\android/../';

      final success = await AndroidManifestInjector.injectPermissions(
        projectRoot: mixedPath,
        permissions: {DevicePermission.biometrics},
      );

      expect(success, isTrue);
      final content = await manifestFile.readAsString();
      expect(content, contains('android.permission.USE_BIOMETRIC'));
    });

    test('IosPlistInjector safely normalizes paths with mixed or Windows separators', () async {
      final iosDir = Directory(p.join(tempDir.path, 'ios', 'Runner'));
      await iosDir.create(recursive: true);
      final plistFile = File(p.join(iosDir.path, 'Info.plist'));
      await plistFile.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>test_app</string>
</dict>
</plist>''');

      final mixedPath = '${tempDir.path}\\ios/../';

      final success = await IosPlistInjector.injectPermissions(
        projectRoot: mixedPath,
        permissions: {DevicePermission.photoLibrary},
      );

      expect(success, isTrue);
      final content = await plistFile.readAsString();
      expect(content, contains('NSPhotoLibraryUsageDescription'));
    });

    test('PresetFileHelper writes files with path normalization and directory auto-creation', () async {
      await PresetFileHelper.writeFile(
        projectRoot: tempDir.path,
        relativePath: 'lib/core/theme/test_theme.dart',
        content: '// Theme file content',
      );

      final writtenFile = File(p.join(tempDir.path, 'lib', 'core', 'theme', 'test_theme.dart'));
      expect(await writtenFile.exists(), isTrue);
      expect(await writtenFile.readAsString(), '// Theme file content');
    });
  });

  group('ProjectGenerator Preflight Validation Guard Tests', () {
    test('execute() halts immediately with false when project name is a reserved keyword', () async {
      final logs = <String>[];
      final generator = ProjectGenerator(
        config: const ProjectConfig(projectName: 'class'),
        onLog: logs.add,
      );

      final success = await generator.execute();
      expect(success, isFalse);
      expect(logs.any((l) => l.contains('Invalid project name') && l.contains('reserved keyword')), isTrue);
    });

    test('execute() halts immediately with false when org ID is single-segment or invalid', () async {
      final logs = <String>[];
      final generator = ProjectGenerator(
        config: const ProjectConfig(orgId: 'invalidorg'),
        onLog: logs.add,
      );

      final success = await generator.execute();
      expect(success, isFalse);
      expect(logs.any((l) => l.contains('Invalid organization ID') && l.contains('at least two segments')), isTrue);
    });
  });
}
