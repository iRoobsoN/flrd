import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flrd/features/generator/injectors/android_manifest_injector.dart';
import 'package:flrd/features/generator/injectors/ios_plist_injector.dart';
import 'package:flrd/core/localization/app_strings.dart';
import 'package:flrd/features/projects/providers/projects_provider.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/marketplace/providers/marketplace_provider.dart';

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

  group('Localization Provider Tests', () {
    test('Default language is pt and returns correct strings', () {
      const stringsPt = AppStrings(AppLanguage.pt);
      expect(stringsPt.hubTitle, 'FLRD Studio');
      expect(stringsPt.newProjectTitle, 'Criar Novo Projeto');
      expect(stringsPt.myProjectsTitle, 'Meus Projetos');
      expect(stringsPt.engineStatus, 'Engine Pronta');
    });

    test('English language returns correct localized strings', () {
      const stringsEn = AppStrings(AppLanguage.en);
      expect(stringsEn.hubTitle, 'FLRD Studio');
      expect(stringsEn.newProjectTitle, 'Create New Project');
      expect(stringsEn.myProjectsTitle, 'My Projects');
      expect(stringsEn.engineStatus, 'Engine Ready');
    });

    test('Spanish language returns correct localized strings', () {
      const stringsEs = AppStrings(AppLanguage.es);
      expect(stringsEs.hubTitle, 'FLRD Studio');
      expect(stringsEs.newProjectTitle, 'Crear Nuevo Proyecto');
      expect(stringsEs.myProjectsTitle, 'Mis Proyectos');
      expect(stringsEs.engineStatus, 'Motor Listo');
    });
  });

  group('Projects & Workspace Tests', () {
    test('ProjectsNotifier initializes with starter projects', () {
      final notifier = ProjectsNotifier();
      expect(notifier.state.projects.isNotEmpty, isTrue);
      expect(notifier.state.projects.length, greaterThanOrEqualTo(3));
    });

    test('addProject inserts a new registered project at the top', () {
      final notifier = ProjectsNotifier();
      notifier.addProject(
        name: 'flutter_fintech',
        orgId: 'com.fintech.app',
        path: 'C:/Projects/flutter_fintech',
        preset: PresetType.saas,
        navigationStyle: NavigationStyle.tabs,
        permissions: {DevicePermission.biometrics},
      );

      expect(notifier.state.projects.first.name, 'flutter_fintech');
      expect(notifier.state.projects.first.orgId, 'com.fintech.app');
    });

    test('removeProject removes project by id', () {
      final notifier = ProjectsNotifier();
      final initialCount = notifier.state.projects.length;
      final firstId = notifier.state.projects.first.id;

      notifier.removeProject(firstId);
      expect(notifier.state.projects.length, initialCount - 1);
      expect(notifier.state.projects.any((p) => p.id == firstId), isFalse);
    });
  });

  group('Studio & Route Flowchart Tests', () {
    test('StudioNotifier initializes with default core routes', () {
      final notifier = StudioNotifier();
      expect(notifier.state.nodes.length, greaterThanOrEqualTo(5));
      expect(notifier.state.nodes.any((n) => n.path == '/'), isTrue);
      expect(notifier.state.nodes.any((n) => n.path == '/dashboard'), isTrue);
    });

    test('addRouteNode inserts a new route node into flowchart', () {
      final notifier = StudioNotifier();
      final initialCount = notifier.state.nodes.length;

      notifier.addRouteNode(
        path: '/checkout/payment',
        title: 'PaymentScreen',
        subtitle: 'Pix and Credit Card',
        icon: Icons.payment_rounded,
        isAIGenerated: true,
        position: const Offset(900, 300),
        filePath: 'lib/features/payment/presentation/payment_screen.dart',
        parentRouteId: 'dashboard',
      );

      expect(notifier.state.nodes.length, initialCount + 1);
      expect(notifier.state.selectedNodeId, 'paymentscreen');
      final created = notifier.state.selectedNode;
      expect(created, isNotNull);
      expect(created?.isAIGenerated, isTrue);
      expect(created?.path, '/checkout/payment');
      expect(created?.parentRouteId, 'dashboard');
    });

    test('updateNodePosition changes node coordinates', () {
      final notifier = StudioNotifier();
      notifier.updateNodePosition('dashboard', const Offset(420, 500));
      final dashboard = notifier.state.nodes.firstWhere((n) => n.id == 'dashboard');
      expect(dashboard.position, const Offset(420, 500));
    });
  });

  group('Marketplace Provider Tests', () {
    test('MarketplaceNotifier initializes with curated community templates', () {
      final notifier = MarketplaceNotifier();
      expect(notifier.state.templates.isNotEmpty, isTrue);
      expect(notifier.state.templates.length, greaterThanOrEqualTo(5));
    });

    test('Templates carry consistency blueprint and manifest', () {
      final notifier = MarketplaceNotifier();
      final fintech = notifier.state.templates.firstWhere((t) => t.id == 'novabank-fintech');
      expect(fintech.manifest.designSystem.isNotEmpty, isTrue);
      expect(fintech.manifest.aiPromptRules.isNotEmpty, isTrue);
      expect(fintech.manifest.screenNames.length, greaterThanOrEqualTo(5));
      expect(fintech.isFree, isFalse);
      expect(fintech.priceUsd, 49.0);
    });

    test('Category filtering filters templates accurately', () {
      final notifier = MarketplaceNotifier();
      notifier.setCategory('Fintech');
      expect(notifier.state.filteredTemplates.every((t) => t.category == 'Fintech'), isTrue);

      notifier.setCategory('Gratuitos');
      expect(notifier.state.filteredTemplates.every((t) => t.isFree), isTrue);
    });

    test('Search query filters templates by title or tags', () {
      final notifier = MarketplaceNotifier();
      notifier.setSearchQuery('Pix');
      expect(notifier.state.filteredTemplates.isNotEmpty, isTrue);
      expect(
        notifier.state.filteredTemplates.any(
          (t) => t.tags.contains('Pix') || t.title.contains('Pix'),
        ),
        isTrue,
      );
    });
  });
}
