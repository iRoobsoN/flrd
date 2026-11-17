import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/presentation/widgets/project_packages_permissions_hub.dart';
import 'package:flrd/features/studio/services/native_permissions_service.dart';
import 'package:flrd/features/studio/services/pub_dev_and_dependencies_service.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

http.Client _createFakePubDevClient({
  Map<String, ({String version, String desc, int points, int likes, bool favorite, String? publisher})>?
      catalog,
}) {
  final db = catalog ??
      {
        'dio': (
          version: '5.7.0',
          desc: 'A powerful HTTP networking package for Dart/Flutter.',
          points: 160,
          likes: 7100,
          favorite: true,
          publisher: 'cfug.dev',
        ),
        'go_router': (
          version: '14.6.2',
          desc: 'A declarative router for Flutter based on Navigation 2.',
          points: 160,
          likes: 3400,
          favorite: true,
          publisher: 'flutter.dev',
        ),
        'obscure_low_score': (
          version: '0.1.0',
          desc: 'Low rated experimental library.',
          points: 40,
          likes: 3,
          favorite: false,
          publisher: null,
        ),
      };

  return MockClient((request) async {
    final uri = request.url;
    if (uri.path == '/api/search') {
      final q = (uri.queryParameters['q'] ?? '').toLowerCase();
      final matches = db.keys.where((name) {
        if (q.isEmpty || q == 'sdk:flutter') return true;
        if (q == 'is:flutter-favorite') return db[name]!.favorite;
        return name.contains(q) || db[name]!.desc.toLowerCase().contains(q);
      }).map((name) => {'package': name}).toList();

      return http.Response(jsonEncode({'packages': matches}), 200);
    }

    final scoreMatch = RegExp(r'^/api/packages/([^/]+)/score$').firstMatch(uri.path);
    if (scoreMatch != null) {
      final name = Uri.decodeComponent(scoreMatch.group(1)!);
      final entry = db[name];
      if (entry == null) return http.Response('Not Found', 404);
      final tags = <String>[
        'sdk:flutter',
        if (entry.favorite) 'is:flutter-favorite',
        if (entry.publisher != null) 'publisher:${entry.publisher}',
      ];
      return http.Response(
        jsonEncode({
          'grantedPoints': entry.points,
          'maxPoints': 160,
          'likeCount': entry.likes,
          'downloadCount30Days': 250000,
          'tags': tags,
        }),
        200,
      );
    }

    final pkgMatch = RegExp(r'^/api/packages/([^/]+)$').firstMatch(uri.path);
    if (pkgMatch != null) {
      final name = Uri.decodeComponent(pkgMatch.group(1)!);
      final entry = db[name];
      if (entry == null) return http.Response('Not Found', 404);
      return http.Response(
        jsonEncode({
          'name': name,
          'latest': {
            'version': entry.version,
            'pubspec': {'description': entry.desc},
          },
        }),
        200,
      );
    }

    return http.Response('Not Found', 404);
  });
}

Directory _createTempFlutterProject(
  Directory root, {
  String name = 'sample_real_app',
}) {
  final projDir = Directory(p.join(root.path, name))..createSync(recursive: true);

  File(p.join(projDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $name
description: Real test Flutter project
version: 1.0.0+1

environment:
  sdk: ">=3.4.0 <4.0.0"

# Existing comment should be preserved
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1

dev_dependencies:
  flutter_test:
    sdk: flutter
''');

  final androidMain = Directory(
    p.join(projDir.path, 'android', 'app', 'src', 'main'),
  )..createSync(recursive: true);
  File(p.join(androidMain.path, 'AndroidManifest.xml')).writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <application android:label="$name">
    </application>
</manifest>
''');

  final iosRunner = Directory(p.join(projDir.path, 'ios', 'Runner'))
    ..createSync(recursive: true);
  File(p.join(iosRunner.path, 'Info.plist')).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>$name</string>
\t<key>NSPhotoLibraryUsageDescription</key>
\t<string>Permissão para ler fotos da galeria.</string>
</dict>
</plist>
''');

  Directory(p.join(projDir.path, 'lib')).createSync(recursive: true);
  File(p.join(projDir.path, 'lib', 'main.dart')).writeAsStringSync(
    'void main() {}\n',
  );

  return projDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flrd_pkg_perm_hub_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('PubDevService & PubspecDependenciesService Unit Tests', () {
    test('searchPackages enriches results from pub.dev API and filters well-rated packages', () async {
      final client = _createFakePubDevClient();

      final highRated = await PubDevService.searchPackages(
        '',
        highRatedOnly: true,
        favoritesOnly: false,
        httpClient: client,
      );

      expect(highRated.fromOfflineFallback, isFalse);
      expect(highRated.packages.map((p) => p.name), containsAll(['dio', 'go_router']));
      expect(highRated.packages.map((p) => p.name), isNot(contains('obscure_low_score')));

      final dio = highRated.packages.firstWhere((p) => p.name == 'dio');
      expect(dio.latestVersion, '5.7.0');
      expect(dio.grantedPoints, 160);
      expect(dio.likeCount, 7100);
      expect(dio.isFlutterFavorite, isTrue);
      expect(dio.publisher, 'cfug.dev');

      final favorites = await PubDevService.searchPackages(
        '',
        highRatedOnly: true,
        favoritesOnly: true,
        httpClient: client,
      );
      expect(favorites.packages.every((p) => p.isFlutterFavorite), isTrue);
    });

    test('searchPackages falls back gracefully to curated list when pub.dev fails', () async {
      final failingClient = MockClient(
        (_) async => http.Response('Service Unavailable', 503),
      );

      final result = await PubDevService.searchPackages(
        'dio',
        httpClient: failingClient,
      );

      expect(result.fromOfflineFallback, isTrue);
      expect(result.packages.any((p) => p.name == 'dio'), isTrue);
      expect(result.errorMessage, contains('503'));
    });

    test('PubspecDependenciesService reads, adds, updates and removes deps preserving comments', () async {
      final projDir = _createTempFlutterProject(tempDir);

      final initial = PubspecDependenciesService.readDependencies(projDir.path);
      expect(initial.exists, isTrue);
      expect(initial.dependencies.map((d) => d.name), containsAll(['flutter', 'flutter_riverpod']));
      expect(
        initial.dependencies.firstWhere((d) => d.name == 'flutter').sourceType,
        'sdk',
      );

      // Add runtime dependency
      final added = await PubspecDependenciesService.addOrUpdateDependency(
        projectRoot: projDir.path,
        packageName: 'dio',
        versionConstraint: '^5.7.0',
      );
      expect(added, isTrue);

      // Add dev dependency
      final addedDev = await PubspecDependenciesService.addOrUpdateDependency(
        projectRoot: projDir.path,
        packageName: 'build_runner',
        versionConstraint: '^2.4.13',
        isDev: true,
      );
      expect(addedDev, isTrue);

      // Update version
      final updated = await PubspecDependenciesService.addOrUpdateDependency(
        projectRoot: projDir.path,
        packageName: 'dio',
        versionConstraint: '^5.8.0',
      );
      expect(updated, isTrue);

      final afterEdit = PubspecDependenciesService.readDependencies(projDir.path);
      expect(
        afterEdit.dependencies.firstWhere((d) => d.name == 'dio').constraint,
        '^5.8.0',
      );
      expect(
        afterEdit.devDependencies.map((d) => d.name),
        contains('build_runner'),
      );

      // Verify existing YAML comment is still intact
      final rawYaml = File(p.join(projDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(rawYaml, contains('# Existing comment should be preserved'));

      // Protected SDK dependency cannot be removed
      final removeSdk = await PubspecDependenciesService.removeDependency(
        projectRoot: projDir.path,
        packageName: 'flutter',
      );
      expect(removeSdk, isFalse);

      // Remove regular dependency
      final removed = await PubspecDependenciesService.removeDependency(
        projectRoot: projDir.path,
        packageName: 'dio',
      );
      expect(removed, isTrue);

      final afterRemove = PubspecDependenciesService.readDependencies(projDir.path);
      expect(afterRemove.dependencies.map((d) => d.name), isNot(contains('dio')));
    });
  });

  group('NativePermissionsService Unit Tests', () {
    test('reads, toggles across Android & iOS XML, adds custom and removes cleanly', () async {
      final projDir = _createTempFlutterProject(tempDir);

      final initial = NativePermissionsService.readPermissions(projDir.path);
      expect(initial.hasAndroidManifest, isTrue);
      expect(initial.hasIosPlist, isTrue);
      expect(
        initial.androidPermissions,
        containsAll([
          'android.permission.INTERNET',
          'android.permission.READ_MEDIA_IMAGES',
        ]),
      );
      expect(
        initial.iosUsageDescriptions.keys,
        contains('NSPhotoLibraryUsageDescription'),
      );

      final detectedInitial =
          NativePermissionsService.computeDetectedDevicePermissions(initial);
      expect(detectedInitial, contains(DevicePermission.photoLibrary));
      expect(detectedInitial, isNot(contains(DevicePermission.camera)));

      // Enable Camera across both XML files
      final cameraDesc = NativePermissionsService.commonPermissions
          .firstWhere((d) => d.id == 'camera');
      final enabledCamera =
          await NativePermissionsService.setKnownPermissionEnabled(
        projectRoot: projDir.path,
        descriptor: cameraDesc,
        enabled: true,
      );
      expect(enabledCamera, isTrue);

      var afterCam = NativePermissionsService.readPermissions(projDir.path);
      expect(afterCam.androidPermissions, contains('android.permission.CAMERA'));
      expect(afterCam.iosUsageDescriptions, contains('NSCameraUsageDescription'));
      expect(
        NativePermissionsService.computeDetectedDevicePermissions(afterCam),
        contains(DevicePermission.camera),
      );

      // Add custom Android permission (short name gets normalized) and custom iOS key
      expect(
        await NativePermissionsService.addAndroidPermission(
          projectRoot: projDir.path,
          permissionTag: 'WAKE_LOCK',
        ),
        isTrue,
      );
      expect(
        await NativePermissionsService.setIosPermission(
          projectRoot: projDir.path,
          iosKey: 'NSMicrophoneUsageDescription',
          reason: 'Gravar áudios na conversa.',
        ),
        isTrue,
      );

      afterCam = NativePermissionsService.readPermissions(projDir.path);
      expect(afterCam.androidPermissions, contains('android.permission.WAKE_LOCK'));
      expect(
        afterCam.iosUsageDescriptions['NSMicrophoneUsageDescription'],
        'Gravar áudios na conversa.',
      );

      // Disable Camera -> removes both Android & iOS entries without damaging sibling entries
      expect(
        await NativePermissionsService.setKnownPermissionEnabled(
          projectRoot: projDir.path,
          descriptor: cameraDesc,
          enabled: false,
        ),
        isTrue,
      );
      final afterDisable = NativePermissionsService.readPermissions(projDir.path);
      expect(afterDisable.androidPermissions, isNot(contains('android.permission.CAMERA')));
      expect(afterDisable.iosUsageDescriptions, isNot(contains('NSCameraUsageDescription')));
      expect(
        afterDisable.androidPermissions,
        containsAll([
          'android.permission.INTERNET',
          'android.permission.WAKE_LOCK',
        ]),
      );
    });
  });

  group('Unified Packages & Permissions Hub Widget Tests', () {
    testWidgets('AppStudioScreen unifies Permissions & Architecture into one Packages & Permissions tab', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final projDir = _createTempFlutterProject(tempDir);
      final project = RegisteredProject(
        id: 'hub_proj',
        name: 'sample_real_app',
        orgId: 'com.example.sample',
        path: projDir.path,
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {DevicePermission.photoLibrary},
        lastModified: DateTime.now(),
        routeCount: 3,
      );

      final container = ProviderContainer(
        overrides: [
          pubDevHttpClientProvider.overrideWithValue(_createFakePubDevClient()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppStudioScreen(project: project),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Verify old separate tabs are replaced by unified tab
      expect(find.byKey(const ValueKey('studio_view_tab_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_view_tab_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_view_tab_2')), findsNothing);
      expect(find.text('Routes Flowchart'), findsOneWidget);
      expect(find.text('Packages & Permissions'), findsOneWidget);

      // Switch to unified Hub tab
      await tester.tap(find.byKey(const ValueKey('studio_view_tab_1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('packages_permissions_unified_hub')),
        findsOneWidget,
      );
      expect(find.text('Dependências (pub.dev & pubspec.yaml)'), findsOneWidget);
      expect(find.text('Permissões Nativas (Android & iOS)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Hub supports pub.dev search + install, manual add/edit/remove, pub get, and native permission manipulation', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final projDir = _createTempFlutterProject(tempDir);
      final project = RegisteredProject(
        id: 'interactive_proj',
        name: 'sample_real_app',
        orgId: 'com.example.sample',
        path: projDir.path,
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {DevicePermission.photoLibrary},
        lastModified: DateTime.now(),
        routeCount: 3,
      );

      final container = ProviderContainer(
        overrides: [
          pubDevHttpClientProvider.overrideWithValue(_createFakePubDevClient()),
        ],
      );
      addTearDown(container.dispose);

      String? pubGetCalledPath;
      RegisteredProject? lastSyncedProject;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ProjectPackagesPermissionsHub(
                project: project,
                onProjectUpdated: (p) => lastSyncedProject = p,
                pubGetRunner: (path) async {
                  pubGetCalledPath = path;
                  return (success: true, output: 'Got dependencies!');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Search pub.dev for 'dio' and 1-click install
      await tester.enterText(
        find.byKey(const ValueKey('pubdev_search_input')),
        'dio',
      );
      await tester.tap(find.byKey(const ValueKey('pubdev_search_button')));
      await tester.pumpAndSettle();

      final addDioFinder = find.byKey(const ValueKey('pubdev_add_dio'));
      expect(addDioFinder, findsOneWidget);
      await tester.ensureVisible(addDioFinder);
      await tester.tap(addDioFinder);
      await tester.pumpAndSettle();

      var deps = PubspecDependenciesService.readDependencies(projDir.path);
      expect(deps.dependencies.map((d) => d.name), contains('dio'));
      expect(
        deps.dependencies.firstWhere((d) => d.name == 'dio').constraint,
        '^5.7.0',
      );

      // 2. Manual package add
      final manualNameFinder = find.byKey(const ValueKey('manual_pkg_name_input'));
      await tester.ensureVisible(manualNameFinder);
      await tester.enterText(manualNameFinder, 'equatable');
      await tester.enterText(
        find.byKey(const ValueKey('manual_pkg_version_input')),
        '^2.0.7',
      );
      final manualAddFinder = find.byKey(const ValueKey('manual_pkg_add_button'));
      await tester.ensureVisible(manualAddFinder);
      await tester.tap(manualAddFinder);
      await tester.pumpAndSettle();

      deps = PubspecDependenciesService.readDependencies(projDir.path);
      expect(
        deps.dependencies.firstWhere((d) => d.name == 'equatable').constraint,
        '^2.0.7',
      );

      // 3. Edit dependency version via dialog
      final editEquatableFinder = find.byKey(const ValueKey('edit_dep_equatable'));
      await tester.ensureVisible(editEquatableFinder);
      await tester.tap(editEquatableFinder);
      await tester.pumpAndSettle();

      final dialogTextField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogTextField, '^2.0.8');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      deps = PubspecDependenciesService.readDependencies(projDir.path);
      expect(
        deps.dependencies.firstWhere((d) => d.name == 'equatable').constraint,
        '^2.0.8',
      );

      // 4. Remove dependency
      final removeEquatableFinder =
          find.byKey(const ValueKey('remove_dep_equatable'));
      await tester.ensureVisible(removeEquatableFinder);
      await tester.tap(removeEquatableFinder);
      await tester.pumpAndSettle();

      deps = PubspecDependenciesService.readDependencies(projDir.path);
      expect(deps.dependencies.map((d) => d.name), isNot(contains('equatable')));

      // 5. Run flutter pub get hook
      await tester.tap(find.byKey(const ValueKey('hub_run_pub_get_button')));
      await tester.pumpAndSettle();
      expect(pubGetCalledPath, projDir.path);

      // 6. Toggle Camera permission -> updates AndroidManifest.xml + Info.plist + RegisteredProject
      final cameraToggleFinder = find.byKey(const ValueKey('perm_toggle_camera'));
      await tester.ensureVisible(cameraToggleFinder);
      await tester.tap(cameraToggleFinder);
      await tester.pumpAndSettle();

      var perms = NativePermissionsService.readPermissions(projDir.path);
      expect(perms.androidPermissions, contains('android.permission.CAMERA'));
      expect(perms.iosUsageDescriptions, contains('NSCameraUsageDescription'));
      expect(lastSyncedProject?.permissions, contains(DevicePermission.camera));

      // 7. Add custom Android permission + remove it from active XML list
      final customAndroidFinder =
          find.byKey(const ValueKey('custom_perm_android_input'));
      await tester.ensureVisible(customAndroidFinder);
      await tester.enterText(customAndroidFinder, 'WAKE_LOCK');
      final customAddFinder =
          find.byKey(const ValueKey('custom_perm_add_button'));
      await tester.ensureVisible(customAddFinder);
      await tester.tap(customAddFinder);
      await tester.pumpAndSettle();

      perms = NativePermissionsService.readPermissions(projDir.path);
      expect(perms.androidPermissions, contains('android.permission.WAKE_LOCK'));

      final removeWakeLockFinder = find.byKey(
        const ValueKey('remove_android_perm_android.permission.WAKE_LOCK'),
      );
      await tester.ensureVisible(removeWakeLockFinder);
      await tester.tap(removeWakeLockFinder);
      await tester.pumpAndSettle();

      perms = NativePermissionsService.readPermissions(projDir.path);
      expect(
        perms.androidPermissions,
        isNot(contains('android.permission.WAKE_LOCK')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Hub renders stacked layout cleanly on narrow viewport without overflow', (tester) async {
      tester.view.physicalSize = const Size(760, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final projDir = _createTempFlutterProject(tempDir);
      final project = RegisteredProject(
        id: 'narrow_proj',
        name: 'narrow_real_app',
        orgId: 'com.example.narrow',
        path: projDir.path,
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: const {},
        lastModified: DateTime.now(),
        routeCount: 2,
      );

      final container = ProviderContainer(
        overrides: [
          pubDevHttpClientProvider.overrideWithValue(_createFakePubDevClient()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ProjectPackagesPermissionsHub(project: project),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
