import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flrd/features/ai/providers/ai_settings_provider.dart';
import 'package:flrd/features/settings/presentation/settings_and_billing_dialog.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flrd_ai_settings_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String uniqueSettingsPath([String name = 'ai_settings.json']) {
    return p.join(tempDir.path, '.flrd', name);
  }

  group('AiSettingsState Model & Serialization', () {
    test('defaults selectedModel to gemini-2.5-flash and supports flash & pro', () {
      const state = AiSettingsState();
      expect(state.selectedModel, equals('gemini-2.5-flash'));
      expect(
        AiSettingsState.supportedModels,
        containsAllInOrder(['gemini-2.5-flash', 'gemini-2.5-pro']),
      );
    });

    test('copyWith updates selectedModel and preserves other fields', () {
      const base = AiSettingsState(
        apiKey: 'AIzaSy_abc',
        isProActive: true,
        isAnnualBilling: false,
        selectedPlan: 'studioPro',
        selectedModel: 'gemini-2.5-flash',
      );

      final updatedModel = base.copyWith(selectedModel: 'gemini-2.5-pro');
      expect(updatedModel.selectedModel, equals('gemini-2.5-pro'));
      expect(updatedModel.apiKey, equals('AIzaSy_abc'));
      expect(updatedModel.isProActive, isTrue);
      expect(updatedModel.isAnnualBilling, isFalse);
      expect(updatedModel.selectedPlan, equals('studioPro'));

      final updatedKey = updatedModel.copyWith(apiKey: null);
      expect(updatedKey.apiKey, isNull);
      expect(updatedKey.selectedModel, equals('gemini-2.5-pro'));
    });

    test('toJson and fromJson round-trip all fields including selectedModel', () {
      const original = AiSettingsState(
        apiKey: 'AIzaSy_serialized_99',
        isProActive: true,
        isAnnualBilling: false,
        selectedPlan: 'starter',
        selectedModel: 'gemini-2.5-pro',
      );

      final json = original.toJson();
      expect(json['selectedModel'], equals('gemini-2.5-pro'));

      final restored = AiSettingsState.fromJson(json);
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
    });

    test('fromJson falls back safely on missing or unknown selectedModel', () {
      final missingModel = AiSettingsState.fromJson({
        'apiKey': '  AIzaSy_trimmed  ',
        'isProActive': true,
      });
      expect(missingModel.apiKey, equals('AIzaSy_trimmed'));
      expect(missingModel.selectedModel, equals('gemini-2.5-flash'));
      expect(missingModel.selectedPlan, equals('studioPro'));

      final unknownModel = AiSettingsState.fromJson({
        'apiKey': '   ',
        'selectedModel': 'gemini-unknown-99',
      });
      expect(unknownModel.apiKey, isNull);
      expect(unknownModel.selectedModel, equals('gemini-2.5-flash'));
    });

    test('equality, hashCode, and masked toString reflect selectedModel', () {
      const flash = AiSettingsState(
        apiKey: 'secret-key-123',
        selectedModel: 'gemini-2.5-flash',
      );
      const pro = AiSettingsState(
        apiKey: 'secret-key-123',
        selectedModel: 'gemini-2.5-pro',
      );

      expect(flash == pro, isFalse);
      expect(flash.hashCode == pro.hashCode, isFalse);
      expect(pro.toString(), contains('selectedModel: gemini-2.5-pro'));
      expect(pro.toString(), contains('apiKey: ***'));
      expect(pro.toString(), isNot(contains('secret-key-123')));
    });
  });

  group('AiSettingsStorageService Path Resolution & Atomic Disk I/O', () {
    test('resolves ~/.flrd/ai_settings.json cross-platform using USERPROFILE and HOME', () {
      final winPath = AiSettingsStorageService.resolveSettingsFilePath(
        environment: {'USERPROFILE': r'C:\Users\Rob'},
        isWindows: true,
        isWeb: false,
      );
      expect(winPath, equals(r'C:\Users\Rob\.flrd\ai_settings.json'));

      final winFallback = AiSettingsStorageService.resolveSettingsFilePath(
        environment: {'APPDATA': r'C:\Users\Rob\AppData\Roaming'},
        isWindows: true,
        isWeb: false,
      );
      expect(
        winFallback,
        equals(r'C:\Users\Rob\AppData\Roaming\.flrd\ai_settings.json'),
      );

      final posixPath = AiSettingsStorageService.resolveSettingsFilePath(
        environment: {'HOME': '/home/rob'},
        isWindows: false,
        isWeb: false,
      );
      expect(posixPath, equals('/home/rob/.flrd/ai_settings.json'));
    });

    test('saveSync writes atomically without leaving temp files and loadSync reads back', () {
      final path = uniqueSettingsPath();
      final storage = AiSettingsStorageService(settingsFilePath: path);

      const first = AiSettingsState(
        apiKey: 'AIzaSy_first',
        selectedModel: 'gemini-2.5-flash',
      );
      storage.saveSync(first);

      final file = File(path);
      expect(file.existsSync(), isTrue);
      expect(storage.loadSync(), equals(first));

      const second = AiSettingsState(
        apiKey: 'AIzaSy_second',
        isProActive: true,
        isAnnualBilling: false,
        selectedPlan: 'studioPro',
        selectedModel: 'gemini-2.5-pro',
      );
      storage.saveSync(second);

      expect(storage.loadSync(), equals(second));
      final siblings = file.parent.listSync().map((e) => p.basename(e.path)).toList();
      expect(siblings, equals(['ai_settings.json']));
    });

    test('loadSync returns null when file is missing, empty, or malformed JSON', () {
      final path = uniqueSettingsPath('corrupt_settings.json');
      final storage = AiSettingsStorageService(settingsFilePath: path);

      expect(storage.loadSync(), isNull);

      final file = File(path);
      file.parent.createSync(recursive: true);

      file.writeAsStringSync('   ');
      expect(storage.loadSync(), isNull);

      file.writeAsStringSync('{not valid json');
      expect(storage.loadSync(), isNull);

      file.writeAsStringSync('[1, 2, 3]');
      expect(storage.loadSync(), isNull);
    });
  });

  group('AiSettingsNotifier Persistence Round-Trip', () {
    test('bare constructor and flutter_test global provider remain in-memory and isolated', () {
      expect(AiSettingsStorageService.isDiskPersistenceAllowedByDefault(), isFalse);

      final bare = AiSettingsNotifier(const AiSettingsState(apiKey: 'inline'));
      expect(bare.isPersistenceEnabled, isFalse);
      expect(bare.settingsFilePath, isNull);
      expect(bare.state.apiKey, equals('inline'));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(aiSettingsProvider.notifier).isPersistenceEnabled, isFalse);
    });

    test('persists setApiKey, setSelectedModel, plan & billing mutations across fresh notifier reload', () {
      final path = uniqueSettingsPath('roundtrip.json');

      final notifier1 = AiSettingsNotifier.persistent(settingsFilePath: path);
      expect(notifier1.isPersistenceEnabled, isTrue);
      expect(notifier1.state.selectedModel, equals('gemini-2.5-flash'));

      notifier1.setApiKey('  AIzaSy_persisted_key_42  ');
      notifier1.setSelectedModel('gemini-2.5-pro');
      notifier1.setAnnualBilling(false);
      notifier1.setSelectedPlan('starter');

      expect(notifier1.state.apiKey, equals('AIzaSy_persisted_key_42'));
      expect(notifier1.state.selectedModel, equals('gemini-2.5-pro'));
      expect(notifier1.state.isAnnualBilling, isFalse);
      expect(notifier1.state.selectedPlan, equals('starter'));
      expect(notifier1.state.isProActive, isTrue);

      // Verify raw JSON on disk
      final rawJson =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(rawJson['apiKey'], equals('AIzaSy_persisted_key_42'));
      expect(rawJson['selectedModel'], equals('gemini-2.5-pro'));
      expect(rawJson['isAnnualBilling'], isFalse);
      expect(rawJson['selectedPlan'], equals('starter'));
      expect(rawJson['isProActive'], isTrue);

      // Reload in a brand-new notifier instance
      final notifier2 = AiSettingsNotifier.persistent(settingsFilePath: path);
      expect(notifier2.state.apiKey, equals('AIzaSy_persisted_key_42'));
      expect(notifier2.state.hasApiKey, isTrue);
      expect(notifier2.state.selectedModel, equals('gemini-2.5-pro'));
      expect(notifier2.state.isAnnualBilling, isFalse);
      expect(notifier2.state.selectedPlan, equals('starter'));
      expect(notifier2.state.isProActive, isTrue);

      // Verify toggleProActive and setProActive also persist
      notifier2.toggleProActive();
      final notifier3 = AiSettingsNotifier.persistent(settingsFilePath: path);
      expect(notifier3.state.isProActive, isFalse);
      expect(notifier3.state.selectedPlan, equals('community'));

      notifier3.setProActive(true, plan: 'studioPro');
      final notifier4 = AiSettingsNotifier.persistent(settingsFilePath: path);
      expect(notifier4.state.isProActive, isTrue);
      expect(notifier4.state.selectedPlan, equals('studioPro'));
    });

    test('clearApiKey and blank setApiKey remove API key from disk while preserving selectedModel', () {
      final path = uniqueSettingsPath('clear_key.json');

      final writer = AiSettingsNotifier.persistent(settingsFilePath: path);
      writer.setApiKey('AIzaSy_secret_to_clear');
      writer.setSelectedModel('gemini-2.5-pro');
      expect(File(path).readAsStringSync(), contains('AIzaSy_secret_to_clear'));

      writer.clearApiKey();

      final fileContents = File(path).readAsStringSync();
      expect(fileContents, isNot(contains('AIzaSy_secret_to_clear')));
      final decoded = jsonDecode(fileContents) as Map<String, dynamic>;
      expect(decoded['apiKey'], isNull);
      expect(decoded['selectedModel'], equals('gemini-2.5-pro'));

      final reloaded = AiSettingsNotifier.persistent(settingsFilePath: path);
      expect(reloaded.state.apiKey, isNull);
      expect(reloaded.state.hasApiKey, isFalse);
      expect(reloaded.state.selectedModel, equals('gemini-2.5-pro'));

      // Also verify blank setApiKey clears persisted key
      reloaded.setApiKey('AIzaSy_temp_again');
      expect(File(path).readAsStringSync(), contains('AIzaSy_temp_again'));
      reloaded.setApiKey('   ');
      expect(File(path).readAsStringSync(), isNot(contains('AIzaSy_temp_again')));
      final reloadedAfterBlank =
          AiSettingsNotifier.persistent(settingsFilePath: path);
      expect(reloadedAfterBlank.state.apiKey, isNull);
    });
  });

  group('SettingsAndBillingDialog Model Selector & Persistence Integration', () {
    testWidgets('selects Gemini 2.5 Pro, saves BYOK key, and reloads from disk in new dialog', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final path = uniqueSettingsPath('widget_roundtrip.json');

      final container1 = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.persistent(settingsFilePath: path),
          ),
        ],
      );
      addTearDown(container1.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container1,
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsAndBillingDialog(initialTabIndex: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gemini Model'), findsOneWidget);
      expect(find.text('Gemini 2.5 Flash'), findsOneWidget);
      expect(find.text('Gemini 2.5 Pro'), findsOneWidget);
      expect(
        find.textContaining('~/.flrd/ai_settings.json'),
        findsOneWidget,
      );

      // Default selectedModel is gemini-2.5-flash
      expect(
        container1.read(aiSettingsProvider).selectedModel,
        equals('gemini-2.5-flash'),
      );

      // Select Gemini 2.5 Pro
      final proFinder = find.byKey(const ValueKey('ai_model_option_gemini-2.5-pro'));
      await tester.ensureVisible(proFinder);
      await tester.tap(proFinder);
      await tester.pumpAndSettle();

      expect(
        container1.read(aiSettingsProvider).selectedModel,
        equals('gemini-2.5-pro'),
      );

      // Enter and save API key
      final keyField = find.byType(TextField);
      await tester.ensureVisible(keyField);
      await tester.enterText(keyField, 'AIzaSy_widget_saved_777');
      await tester.pump();

      final saveBtn = find.text('Save API Key');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Mount a completely fresh ProviderContainer + dialog pointing at the same file
      final container2 = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.persistent(settingsFilePath: path),
          ),
        ],
      );
      addTearDown(container2.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container2,
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsAndBillingDialog(initialTabIndex: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        container2.read(aiSettingsProvider).apiKey,
        equals('AIzaSy_widget_saved_777'),
      );
      expect(
        container2.read(aiSettingsProvider).selectedModel,
        equals('gemini-2.5-pro'),
      );
      expect(find.text('API Key Configured & Ready'), findsOneWidget);
      expect(find.text('AIzaSy_widget_saved_777'), findsOneWidget);

      // Clear API key via UI clear button and confirm persisted clear
      final clearBtn = find.byTooltip('Clear');
      await tester.ensureVisible(clearBtn);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      final reloaded = AiSettingsNotifier.persistent(settingsFilePath: path);
      expect(reloaded.state.apiKey, isNull);
      expect(reloaded.state.selectedModel, equals('gemini-2.5-pro'));
    });
  });
}
