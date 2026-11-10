import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/features/projects/services/project_analyzer_service.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  group('ProjectAnalyzerService Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flrd_analyzer_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Throws clear Exception when pubspec.yaml does not exist', () async {
      expect(
        () => ProjectAnalyzerService.analyzeProject(tempDir.path),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No pubspec.yaml found'),
          ),
        ),
      );
    });

    test('Throws Exception when pubspec.yaml is invalid YAML', () async {
      final pubspec = File('${tempDir.path}/pubspec.yaml');
      await pubspec.writeAsString(': [invalid yaml : :');

      expect(
        () => ProjectAnalyzerService.analyzeProject(tempDir.path),
        throwsA(isA<Exception>()),
      );
    });

    test('Detects SaaS preset with flutter_riverpod', () async {
      final pubspec = File('${tempDir.path}/pubspec.yaml');
      await pubspec.writeAsString('''
name: my_saas_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
''');

      final result = await ProjectAnalyzerService.analyzeProject(tempDir.path);
      expect(result.project.preset, PresetType.saas);
      expect(result.project.name, 'my_saas_app');
    });

    test('Detects cleanLite preset with flutter_bloc', () async {
      final pubspec = File('${tempDir.path}/pubspec.yaml');
      await pubspec.writeAsString('''
name: my_clean_app
dependencies:
  flutter:
    sdk: flutter
  flutter_bloc: ^8.1.3
''');

      final result = await ProjectAnalyzerService.analyzeProject(tempDir.path);
      expect(result.project.preset, PresetType.cleanLite);
      expect(result.project.name, 'my_clean_app');
    });

    test('Detects offline preset with sqflite, drift, isar, or hive', () async {
      final pubspec = File('${tempDir.path}/pubspec.yaml');
      await pubspec.writeAsString('''
name: my_offline_vault
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.3.0
''');

      final result = await ProjectAnalyzerService.analyzeProject(tempDir.path);
      expect(result.project.preset, PresetType.offline);
      expect(result.project.name, 'my_offline_vault');
    });

    test('Defaults to SaaS preset when unknown dependencies', () async {
      final pubspec = File('${tempDir.path}/pubspec.yaml');
      await pubspec.writeAsString('''
name: plain_app
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
''');

      final result = await ProjectAnalyzerService.analyzeProject(tempDir.path);
      expect(result.project.preset, PresetType.saas);
    });

    test('Detects permissions from AndroidManifest.xml and Info.plist', () async {
      final pubspec = File('${tempDir.path}/pubspec.yaml');
      await pubspec.writeAsString('''
name: perm_app
dependencies:
  flutter:
    sdk: flutter
''');

      // Android Manifest
      final androidDir = Directory('${tempDir.path}/android/app/src/main');
      await androidDir.create(recursive: true);
      final manifestFile = File('${androidDir.path}/AndroidManifest.xml');
      await manifestFile.writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.CAMERA" />
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
</manifest>
''');

      // iOS Info.plist
      final iosDir = Directory('${tempDir.path}/ios/Runner');
      await iosDir.create(recursive: true);
      final plistFile = File('${iosDir.path}/Info.plist');
      await plistFile.writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Location description</string>
</dict>
</plist>
''');

      final result = await ProjectAnalyzerService.analyzeProject(tempDir.path);
      expect(result.project.permissions.contains(DevicePermission.camera), isTrue);
      expect(result.project.permissions.contains(DevicePermission.notifications), isTrue);
      expect(result.project.permissions.contains(DevicePermission.location), isTrue);
      expect(result.project.permissions.contains(DevicePermission.biometrics), isFalse);
    });

    test('Scans lib/ recursively for screens, pages, views and links to root', () async {
      final pubspec = File('${tempDir.path}/pubspec.yaml');
      await pubspec.writeAsString('''
name: screen_app
dependencies:
  flutter:
    sdk: flutter
''');

      // Create dummy screens
      final libDir = Directory('${tempDir.path}/lib/features/home');
      await libDir.create(recursive: true);

      final homeScreen = File('${libDir.path}/home_screen.dart');
      await homeScreen.writeAsString('''
import 'package:flutter/material.dart';
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Scaffold();
}
''');

      final authDir = Directory('${tempDir.path}/lib/features/auth');
      await authDir.create(recursive: true);

      final loginPage = File('${authDir.path}/login_page.dart');
      await loginPage.writeAsString('''
import 'package:flutter/material.dart';
class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Scaffold();
}
''');

      final profileDir = Directory('${tempDir.path}/lib/features/profile');
      await profileDir.create(recursive: true);

      final profileView = File('${profileDir.path}/profile_view.dart');
      await profileView.writeAsString('''
import 'package:flutter/material.dart';
class ProfileView extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Scaffold();
}
''');

      final nonScreen = File('${libDir.path}/home_controller.dart');
      await nonScreen.writeAsString('class HomeController {}');

      final result = await ProjectAnalyzerService.analyzeProject(tempDir.path);

      // 1 root node + 3 child screens = 4 route nodes
      expect(result.routeNodes.length, 4);

      // Root node checks
      final root = result.routeNodes.first;
      expect(root.id, 'root');
      expect(root.path, '/');
      expect(root.position, const Offset(50, 220));

      // Child screen checks
      final children = result.routeNodes.skip(1).toList();
      for (final child in children) {
        expect(child.parentRouteId, 'root');
        expect(child.position.dx, greaterThanOrEqualTo(380));
      }

      final titles = children.map((c) => c.title).toSet();
      expect(titles.contains('HomeScreen'), isTrue);
      expect(titles.contains('LoginPage'), isTrue);
      expect(titles.contains('ProfileView'), isTrue);

      // Non-screen file must not be included
      expect(titles.contains('HomeController'), isFalse);
    });

    test('Generates and updates .flrd/manifest.json properly', () async {
      final pubspec = File('${tempDir.path}/pubspec.yaml');
      await pubspec.writeAsString('''
name: manifest_test_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
''');

      final libDir = Directory('${tempDir.path}/lib');
      await libDir.create(recursive: true);
      final screenFile = File('${libDir.path}/home_screen.dart');
      await screenFile.writeAsString('class HomeScreen extends StatelessWidget {}');

      final result = await ProjectAnalyzerService.analyzeProject(tempDir.path);
      expect(result.project.name, 'manifest_test_app');

      final manifestFile = File('${tempDir.path}/.flrd/manifest.json');
      expect(await manifestFile.exists(), isTrue);

      final jsonContent = jsonDecode(await manifestFile.readAsString());
      expect(jsonContent['name'], 'manifest_test_app');
      expect(jsonContent['preset'], 'saas');
      expect(jsonContent['stateManagement'], contains('Riverpod'));
      expect(jsonContent['screenNames'], contains('HomeScreen'));
      expect(jsonContent['routes'], isNotEmpty);
    });
  });
}
