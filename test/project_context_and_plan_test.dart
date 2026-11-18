import 'dart:convert';
import 'dart:io';

import 'package:flrd/features/ai/models/ai_execution_plan.dart';
import 'package:flrd/features/ai/services/project_context_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AiGenerationOutcome', () {
    test('isSuccess is true only when liveAi and non-null data', () {
      const liveSuccess = AiGenerationOutcome<String>(
        data: 'class ClockWidget {}',
        source: AiResultSource.liveAi,
        modelUsed: 'gemini-2.5-flash',
      );
      expect(liveSuccess.isSuccess, isTrue);
      expect(liveSuccess.isOfflineFallback, isFalse);
      expect(liveSuccess.hasData, isTrue);

      const liveNullData = AiGenerationOutcome<String>(
        data: null,
        source: AiResultSource.liveAi,
        modelUsed: 'gemini-2.5-flash',
      );
      expect(liveNullData.isSuccess, isFalse);
      expect(liveNullData.hasData, isFalse);

      const offlineOutcome = AiGenerationOutcome<String>(
        data: 'fallback',
        source: AiResultSource.offlineFallback,
      );
      expect(offlineOutcome.isSuccess, isFalse);
      expect(offlineOutcome.isOfflineFallback, isTrue);
      expect(offlineOutcome.hasData, isTrue);

      const unconfigured = AiGenerationOutcome<String>(
        source: AiResultSource.unconfiguredKey,
        errorMessage: 'API key missing',
      );
      expect(unconfigured.isSuccess, isFalse);
      expect(unconfigured.hasData, isFalse);

      const errored = AiGenerationOutcome<String>(
        source: AiResultSource.error,
        errorMessage: 'HTTP 500',
      );
      expect(errored.isSuccess, isFalse);
      expect(errored.hasData, isFalse);

      final cleared = liveSuccess.copyWith(
        data: null,
        errorMessage: 'timeout',
        source: AiResultSource.error,
      );
      expect(cleared.data, isNull);
      expect(cleared.isSuccess, isFalse);
      expect(cleared.errorMessage, 'timeout');
    });
  });

  group('AiExecutionPlan', () {
    test('fromJson and toJson roundtrip preserves all fields accurately', () {
      const plan = AiExecutionPlan(
        goalSummary: 'Create an interactive digital clock with 4 switchable styles',
        widgetName: 'DigitalClockWidget',
        architectureType: 'statefulWidgetClass',
        stateFields: ['DateTime _now', 'Timer? _timer', 'int _styleIndex'],
        interactions: ['onTap cycles between 4 digital clock themes'],
        requiredImports: ['dart:async', 'package:flutter/material.dart'],
        requiredPackages: ['google_fonts'],
        placementStrategy: AiPlanPlacementStrategy.separateWidgetFile,
        targetFilePath: 'lib/features/home/presentation/home_screen.dart',
        extractedWidgetFilePath:
            'lib/features/home/widgets/digital_clock_widget.dart',
        visualAnchorDescription:
            'Placed right below the Enterprise-Ready Architecture heading at the top of the home column',
        insertionAnchorHint: 'after_text:Enterprise-Ready Architecture',
      );

      final json = plan.toJson();
      final decoded = AiExecutionPlan.fromJson(json);

      expect(decoded, equals(plan));
      expect(decoded.toJson(), equals(json));
      expect(decoded.placementStrategy, AiPlanPlacementStrategy.separateWidgetFile);
      expect(
        () => decoded.stateFields.add('int _extra'),
        throwsUnsupportedError,
      );
    });

    test('PascalCase sanitizer handles snake, kebab, spaces, accents, digits, and invalid inputs', () {
      expect(
        AiExecutionPlan.sanitizeWidgetName('DigitalClockWidget'),
        'DigitalClockWidget',
      );
      expect(
        AiExecutionPlan.sanitizeWidgetName('digital_clock_widget'),
        'DigitalClockWidget',
      );
      expect(
        AiExecutionPlan.sanitizeWidgetName('digital-clock widget'),
        'DigitalClockWidget',
      );
      expect(
        AiExecutionPlan.sanitizeWidgetName('myDigitalClock'),
        'MyDigitalClock',
      );
      expect(
        AiExecutionPlan.sanitizeWidgetName('  relógio digital 24h!  '),
        'RelogioDigital24h',
      );
      expect(
        AiExecutionPlan.sanitizeWidgetName('123_clock_widget'),
        'Widget123ClockWidget',
      );
      expect(
        AiExecutionPlan.sanitizeWidgetName('HTMLParser'),
        'HtmlParser',
      );
      expect(
        AiExecutionPlan.sanitizeWidgetName('---!!!   '),
        'GeneratedWidget',
      );
      expect(
        AiExecutionPlan.sanitizeWidgetName('widget'),
        'GeneratedWidget',
      );
      expect(
        AiExecutionPlan.sanitizeWidgetName('state'),
        'CustomState',
      );
    });

    test('fromJson safely coerces malformed, missing, and snake_case JSON values', () {
      final plan = AiExecutionPlan.fromJson({
        'goal_summary': 'Add a compact metrics card',
        'widget_name': '123_metrics-card!',
        'architecture_type': 'stateless_snippet',
        'state_fields': 'final int count\nMap<String, int> _buckets',
        'interactions': 42,
        'required_imports': 'package:flutter/material.dart, dart:math',
        'required_packages': 'google_fonts, intl',
        'placement_strategy': 'inline_in_screen',
        'target_file_path': r'lib\features\home\presentation\home_screen.dart',
        'extracted_widget_file_path': '',
        'visual_anchor_description': 'Centered in body',
        'insertion_anchor_hint': 'center_body',
      });

      expect(plan.goalSummary, 'Add a compact metrics card');
      expect(plan.widgetName, 'Widget123MetricsCard');
      expect(plan.architectureType, 'statelessSnippet');
      expect(
        plan.stateFields,
        ['final int count', 'Map<String, int> _buckets'],
      );
      expect(plan.interactions, isEmpty);
      expect(
        plan.requiredImports,
        ['package:flutter/material.dart', 'dart:math'],
      );
      expect(plan.requiredPackages, ['google_fonts', 'intl']);
      expect(plan.placementStrategy, AiPlanPlacementStrategy.inlineInScreen);
      expect(
        plan.targetFilePath,
        'lib/features/home/presentation/home_screen.dart',
      );
      expect(plan.extractedWidgetFilePath, isNull);
      expect(plan.visualAnchorDescription, 'Centered in body');
      expect(plan.insertionAnchorHint, 'center_body');

      final emptyFallback = AiExecutionPlan.fromJson({
        'architectureType': 'totallyUnknownType',
        'placementStrategy': 'unknownPlace',
      });
      expect(emptyFallback.widgetName, 'GeneratedWidget');
      expect(emptyFallback.architectureType, 'statefulWidgetClass');
      expect(
        emptyFallback.placementStrategy,
        AiPlanPlacementStrategy.separateWidgetFile,
      );
      expect(emptyFallback.insertionAnchorHint, 'bottom_of_column');
    });
  });

  group('ProjectContextSnapshotService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flrd_context_snap_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'captures manifest, pubspec, app_theme.dart, widgets, and target screen when AppColors and go_router are absent',
      () async {
        // Real .flrd/manifest.json (single-string aiPromptRules format written by ProjectAnalyzerService)
        final flrdDir = Directory(p.join(tempDir.path, '.flrd'))
          ..createSync(recursive: true);
        await File(p.join(flrdDir.path, 'manifest.json')).writeAsString(
          jsonEncode({
            'name': 'pulse_app',
            'preset': 'saas',
            'presetName': 'SaaS / Indie Hacker',
            'designSystem': 'Material 3 Adaptive',
            'stateManagement': 'Riverpod 2.5 + AsyncNotifier',
            'routingPattern': 'Navigator 2.0 Standard',
            'aiPromptRules':
                'Use Theme.of(context) tokens strictly.\nKeep widgets modular under lib/features/*/widgets/.',
          }),
        );

        await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString('''
name: pulse_app
description: Sample FLRD project without go_router
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  google_fonts: ^6.2.1
dev_dependencies:
  flutter_test:
    sdk: flutter
''');

        final themeDir = Directory(p.join(tempDir.path, 'lib', 'core', 'theme'))
          ..createSync(recursive: true);
        await File(p.join(themeDir.path, 'app_theme.dart')).writeAsString('''
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();
  static ThemeData get lightTheme => ThemeData(useMaterial3: true);
}
''');

        final widgetsDir =
            Directory(p.join(tempDir.path, 'lib', 'features', 'home', 'widgets'))
              ..createSync(recursive: true);
        await File(p.join(widgetsDir.path, 'greeting_card.dart')).writeAsString(
          'class GreetingCard {}',
        );
        // Generated files should be ignored
        await File(p.join(widgetsDir.path, 'greeting_card.g.dart'))
            .writeAsString('// generated');

        final screenDir = Directory(
          p.join(tempDir.path, 'lib', 'features', 'home', 'presentation'),
        )..createSync(recursive: true);
        const screenRelativePath =
            'lib/features/home/presentation/home_screen.dart';
        await File(p.join(screenDir.path, 'home_screen.dart')).writeAsString('''
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pulse')),
      body: Column(
        children: const [
          Text('Enterprise-Ready Architecture'),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}
''');

        final snapshot = await ProjectContextSnapshotService.capture(
          projectPath: tempDir.path,
          targetScreenPath: screenRelativePath,
        );

        expect(snapshot.projectName, 'pulse_app');
        expect(
          snapshot.dependencies,
          equals({'flutter', 'flutter_riverpod', 'google_fonts'}),
        );
        expect(snapshot.dependencies.contains('flutter_test'), isFalse);
        expect(snapshot.hasAppColors, isFalse);
        expect(snapshot.hasGoRouter, isFalse);
        expect(snapshot.manifestRules['designSystem'], 'Material 3 Adaptive');
        expect(snapshot.aiPromptRules, [
          'Use Theme.of(context) tokens strictly.',
          'Keep widgets modular under lib/features/*/widgets/.',
        ]);
        expect(snapshot.themeExcerpt, contains('class AppTheme'));
        expect(snapshot.routerExcerpt, isNull);
        expect(
          snapshot.existingWidgetFiles,
          ['lib/features/home/widgets/greeting_card.dart'],
        );
        expect(snapshot.targetScreenPath, screenRelativePath);
        expect(
          snapshot.targetScreenSource,
          contains('Enterprise-Ready Architecture'),
        );

        final summary = snapshot.toPromptSummary();
        expect(summary, contains('flutter_riverpod'));
        expect(summary, contains('google_fonts'));
        expect(summary, contains('hasAppColors == false'));
        expect(summary, contains('Theme.of(context).colorScheme'));
        expect(summary, contains('Theme.of(context).textTheme'));
        expect(summary, contains('hasGoRouter == false'));
        expect(summary, contains('Navigator'));
        expect(summary, contains('Use Theme.of(context) tokens strictly.'));
        expect(
          summary,
          contains('lib/features/home/widgets/greeting_card.dart'),
        );
        expect(summary, contains('Enterprise-Ready Architecture'));
      },
    );

    test(
      'detects hasAppColors=true and hasGoRouter=true when app_colors.dart and go_router exist',
      () async {
        final flrdDir = Directory(p.join(tempDir.path, '.flrd'))
          ..createSync(recursive: true);
        await File(p.join(flrdDir.path, 'manifest.json')).writeAsString(
          jsonEncode({
            'name': 'obsidian_pro',
            'aiPromptRules': [
              'Use AppColors.surfaceCard for elevated panels.',
              'Navigate using GoRouter context.go routes.',
            ],
          }),
        );

        await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString('''
name: obsidian_pro
dependencies:
  flutter:
    sdk: flutter
  go_router: ^14.2.0
  flutter_riverpod: ^2.5.1
''');

        final themeDir = Directory(p.join(tempDir.path, 'lib', 'core', 'theme'))
          ..createSync(recursive: true);
        await File(p.join(themeDir.path, 'app_colors.dart')).writeAsString('''
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const Color primary = Color(0xFF6366F1);
  static const Color surfaceCard = Color(0xFF141B2D);
}
''');

        final routerDir =
            Directory(p.join(tempDir.path, 'lib', 'core', 'router'))
              ..createSync(recursive: true);
        await File(p.join(routerDir.path, 'app_router.dart')).writeAsString('''
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(routes: []);
''');

        final absScreenPath = p.join(
          tempDir.path,
          'lib',
          'features',
          'dashboard',
          'presentation',
          'dashboard_screen.dart',
        );
        await File(absScreenPath).create(recursive: true);
        await File(absScreenPath).writeAsString('class DashboardScreen {}');

        final snapshot = await ProjectContextSnapshot.capture(
          projectPath: tempDir.path,
          targetScreenPath: absScreenPath,
        );

        expect(snapshot.projectName, 'obsidian_pro');
        expect(snapshot.hasAppColors, isTrue);
        expect(snapshot.hasGoRouter, isTrue);
        expect(snapshot.dependencies.contains('go_router'), isTrue);
        expect(snapshot.themeExcerpt, contains('class AppColors'));
        expect(snapshot.themeExcerpt, contains('surfaceCard'));
        expect(snapshot.routerExcerpt, contains('GoRouter'));
        expect(
          snapshot.targetScreenPath,
          'lib/features/dashboard/presentation/dashboard_screen.dart',
        );
        expect(snapshot.aiPromptRules, [
          'Use AppColors.surfaceCard for elevated panels.',
          'Navigate using GoRouter context.go routes.',
        ]);

        final summary = snapshot.toPromptSummary();
        expect(summary, contains('hasAppColors == true'));
        expect(summary, contains('hasGoRouter == true'));
        expect(summary, contains('context.go'));
        expect(summary, contains('context.push'));
        expect(summary, contains('class AppColors'));
        expect(summary, contains('AppColors.surfaceCard'));
        expect(summary, contains('GoRouter(routes: [])'));
      },
    );

    test(
      'handles missing directories, missing target screen, and corrupt pubspec/manifest gracefully',
      () async {
        final missingDir = p.join(tempDir.path, 'does_not_exist');
        final missingSnapshot = await ProjectContextSnapshotService.capture(
          projectPath: missingDir,
          targetScreenPath: 'lib/missing_screen.dart',
        );

        expect(missingSnapshot.projectName, 'does_not_exist');
        expect(missingSnapshot.dependencies, isEmpty);
        expect(missingSnapshot.manifestRules, isEmpty);
        expect(missingSnapshot.aiPromptRules, isEmpty);
        expect(missingSnapshot.hasAppColors, isFalse);
        expect(missingSnapshot.hasGoRouter, isFalse);
        expect(missingSnapshot.themeExcerpt, isNull);
        expect(missingSnapshot.routerExcerpt, isNull);
        expect(missingSnapshot.targetScreenPath, 'lib/missing_screen.dart');
        expect(missingSnapshot.targetScreenSource, isNull);
        expect(missingSnapshot.existingWidgetFiles, isEmpty);

        // Corrupt files inside an existing directory
        final corruptDir = Directory(p.join(tempDir.path, 'corrupt_proj'))
          ..createSync(recursive: true);
        await File(p.join(corruptDir.path, 'pubspec.yaml'))
            .writeAsString(': [unterminated yaml');
        Directory(p.join(corruptDir.path, '.flrd')).createSync(recursive: true);
        await File(p.join(corruptDir.path, '.flrd', 'manifest.json'))
            .writeAsString('{bad json');

        final corruptSnapshot = await ProjectContextSnapshotService.capture(
          projectPath: corruptDir.path,
        );

        expect(corruptSnapshot.projectName, 'corrupt_proj');
        expect(corruptSnapshot.dependencies, isEmpty);
        expect(corruptSnapshot.manifestRules, isEmpty);
        expect(corruptSnapshot.toPromptSummary(), isNotEmpty);
      },
    );
  });
}
