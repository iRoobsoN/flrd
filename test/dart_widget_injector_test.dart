import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flrd/features/ai/models/ai_execution_plan.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/domain/widget_variation.dart';
import 'package:flrd/features/studio/services/dart_widget_injector_service.dart';

void main() {
  const digitalClockWidgetCode = '''
import 'dart:async';
import 'package:flutter/material.dart';

class DigitalClockWidget extends StatefulWidget {
  const DigitalClockWidget({super.key});

  @override
  State<DigitalClockWidget> createState() => _DigitalClockWidgetState();
}

class _DigitalClockWidgetState extends State<DigitalClockWidget> {
  late Timer _timer;
  DateTime _now = DateTime.now();
  int _styleIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final ss = _now.second.toString().padLeft(2, '0');
    return GestureDetector(
      onTap: () => setState(() => _styleIndex = (_styleIndex + 1) % 3),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '\$hh:\$mm:\$ss',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
''';

  const screenWithConstChildren = '''
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            Text(
              'Welcome, dev!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: null,
              child: Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
''';

  Directory createTempFlutterProject({
    required String projectName,
    required String screenRelPath,
    required String screenContent,
  }) {
    final root = Directory.systemTemp.createTempSync('flrd_injector_test_');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    File(p.join(root.path, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: $projectName
description: Test project
version: 1.0.0+1
environment:
  sdk: ">=3.2.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');

    File(p.join(root.path, screenRelPath))
      ..createSync(recursive: true)
      ..writeAsStringSync(screenContent);

    return root;
  }

  WidgetVariation buildDigitalClockVariation({
    required AiExecutionPlan plan,
    String? extractedWidgetCode,
  }) {
    return WidgetVariation(
      id: 'clock_var_1',
      title: 'Interactive Digital Clock',
      styleTag: 'Minimalist Neon',
      description: 'Live digital clock with tap-to-cycle style.',
      dartCode: extractedWidgetCode ?? digitalClockWidgetCode,
      techApproach: 'StatefulWidget + Timer.periodic + _styleIndex',
      icon: Icons.access_time_rounded,
      requiredImports: const ['dart:async', 'package:flutter/material.dart'],
      extractedWidgetCode: extractedWidgetCode ?? digitalClockWidgetCode,
      callSiteSnippet: 'const DigitalClockWidget()',
      plan: plan,
    );
  }

  group('DartWidgetInjectorService separate widget file & anchor resolution', () {
    test(
      'injects StatefulWidget Digital Clock at top_of_body, strips children: const [, creates separate widget file with dart:async, adds package import, and creates backup',
      () async {
        final projectDir = createTempFlutterProject(
          projectName: 'clock_demo_app',
          screenRelPath: 'lib/features/home/home_screen.dart',
          screenContent: screenWithConstChildren,
        );

        const plan = AiExecutionPlan(
          goalSummary: 'Add live interactive digital clock at top of body',
          widgetName: 'DigitalClockWidget',
          architectureType: 'statefulWidgetClass',
          stateFields: ['Timer _timer', 'DateTime _now', 'int _styleIndex'],
          interactions: ['onTap cycles _styleIndex'],
          requiredImports: ['dart:async', 'package:flutter/material.dart'],
          placementStrategy: AiPlanPlacementStrategy.separateWidgetFile,
          targetFilePath: 'lib/features/home/home_screen.dart',
          extractedWidgetFilePath:
              'lib/features/home/widgets/digital_clock_widget.dart',
          insertionAnchorHint: 'top_of_body',
        );

        final variation = buildDigitalClockVariation(plan: plan);
        final result = await DartWidgetInjectorService.injectWidget(
          projectPath: projectDir.path,
          screenFilePath: 'lib/features/home/home_screen.dart',
          variation: variation,
          plan: plan,
        );

        expect(result.success, isTrue);
        expect(result.errorMessage, isNull);
        expect(
          result.createdFiles,
          contains('lib/features/home/widgets/digital_clock_widget.dart'),
        );
        expect(
          result.modifiedFiles,
          contains('lib/features/home/home_screen.dart'),
        );
        expect(result.backupDir, isNotNull);
        expect(result.backupDir, contains('.flrd'));
        expect(result.backupDir, contains('widget_'));

        // Verify backup preserves original screen content verbatim.
        final backupScreenFile = File(
          p.join(result.backupDir!, 'lib/features/home/home_screen.dart'),
        );
        expect(backupScreenFile.existsSync(), isTrue);
        expect(backupScreenFile.readAsStringSync(), equals(screenWithConstChildren));

        // Verify created widget file contains dart:async, Timer.periodic, _styleIndex without duplicate imports.
        final widgetFile = File(
          p.join(
            projectDir.path,
            'lib/features/home/widgets/digital_clock_widget.dart',
          ),
        );
        expect(widgetFile.existsSync(), isTrue);
        final widgetText = widgetFile.readAsStringSync();
        expect(widgetText, contains("import 'dart:async';"));
        expect(widgetText, contains("import 'package:flutter/material.dart';"));
        expect(
          RegExp(r"import 'dart:async';").allMatches(widgetText).length,
          equals(1),
        );
        expect(
          RegExp(r"import 'package:flutter/material\.dart';")
              .allMatches(widgetText)
              .length,
          equals(1),
        );
        expect(widgetText, contains('Timer.periodic'));
        expect(widgetText, contains('_styleIndex'));

        // Verify updated screen file: import added, children: const [ stripped, exact top order.
        final updatedScreen = File(
          p.join(projectDir.path, 'lib/features/home/home_screen.dart'),
        ).readAsStringSync();
        expect(result.updatedScreenCode, equals(updatedScreen));
        expect(
          updatedScreen,
          contains(
            "import 'package:clock_demo_app/features/home/widgets/digital_clock_widget.dart';",
          ),
        );
        expect(
          RegExp(r"import 'package:flutter/material\.dart';")
              .allMatches(updatedScreen)
              .length,
          equals(1),
        );
        expect(updatedScreen, contains('children: ['));
        expect(updatedScreen, isNot(contains('children: const [')));
        expect(updatedScreen, contains('// FLRD:CUSTOM_WIDGET_START'));
        expect(updatedScreen, contains('const DigitalClockWidget(),'));

        final clockPos = updatedScreen.indexOf('const DigitalClockWidget()');
        final welcomePos = updatedScreen.indexOf("'Welcome, dev!'");
        final buttonPos = updatedScreen.indexOf("'Continue'");
        expect(clockPos, greaterThan(-1));
        expect(clockPos, lessThan(welcomePos));
        expect(welcomePos, lessThan(buttonPos));
      },
    );

    test(
      'injects Digital Clock at after_text:Welcome, dev!, derives widgets/<snake_case>.dart when extractedWidgetFilePath is omitted, and places strictly between Welcome and Continue',
      () async {
        final projectDir = createTempFlutterProject(
          projectName: 'clock_demo_app',
          screenRelPath: 'lib/features/home/screens/home_screen.dart',
          screenContent: screenWithConstChildren,
        );

        // Omit extractedWidgetFilePath and wrap extractedWidgetCode without header imports
        // so the injector derives `<feature_dir>/widgets/digital_clock_widget.dart`
        // and prepends material + requiredImports cleanly.
        const bodyOnlyClock = '''
class DigitalClockWidget extends StatefulWidget {
  const DigitalClockWidget({super.key});

  @override
  State<DigitalClockWidget> createState() => _DigitalClockWidgetState();
}

class _DigitalClockWidgetState extends State<DigitalClockWidget> {
  Timer? _timer;
  int _styleIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _styleIndex++),
      child: const Text('12:00:00'),
    );
  }
}
''';

        const plan = AiExecutionPlan(
          goalSummary: 'Place digital clock directly after Welcome, dev!',
          widgetName: 'DigitalClockWidget',
          architectureType: 'statefulWidgetClass',
          requiredImports: ['dart:async'],
          placementStrategy: AiPlanPlacementStrategy.separateWidgetFile,
          targetFilePath: 'lib/features/home/screens/home_screen.dart',
          insertionAnchorHint: 'after_text:Welcome, dev!',
        );

        final variation = buildDigitalClockVariation(
          plan: plan,
          extractedWidgetCode: bodyOnlyClock,
        );

        final result = await DartWidgetInjectorService.injectWidget(
          projectPath: projectDir.path,
          screenFilePath: 'lib/features/home/screens/home_screen.dart',
          variation: variation,
          plan: plan,
        );

        expect(result.success, isTrue);
        expect(
          result.createdFiles,
          contains('lib/features/home/widgets/digital_clock_widget.dart'),
        );
        expect(result.backupDir, isNotNull);

        final derivedFile = File(
          p.join(
            projectDir.path,
            'lib/features/home/widgets/digital_clock_widget.dart',
          ),
        );
        expect(derivedFile.existsSync(), isTrue);
        final widgetText = derivedFile.readAsStringSync();
        expect(widgetText, contains("import 'dart:async';"));
        expect(widgetText, contains("import 'package:flutter/material.dart';"));

        final updatedScreen = result.updatedScreenCode!;
        expect(updatedScreen, contains('children: ['));
        expect(updatedScreen, isNot(contains('children: const [')));
        expect(
          updatedScreen,
          contains(
            "import 'package:clock_demo_app/features/home/widgets/digital_clock_widget.dart';",
          ),
        );

        final welcomePos = updatedScreen.indexOf("'Welcome, dev!'");
        final clockPos = updatedScreen.indexOf('const DigitalClockWidget()');
        final sizedBoxPos = updatedScreen.indexOf('SizedBox(height: 16)');
        final buttonPos = updatedScreen.indexOf("'Continue'");
        expect(welcomePos, greaterThan(-1));
        expect(clockPos, greaterThan(welcomePos));
        expect(clockPos, lessThan(sizedBoxPos));
        expect(sizedBoxPos, lessThan(buttonPos));
      },
    );

    test(
      'supports before_text:<needle> with paren-balanced widget boundaries (does not insert inside ElevatedButton args)',
      () async {
        final projectDir = createTempFlutterProject(
          projectName: 'clock_demo_app',
          screenRelPath: 'lib/features/home/home_screen.dart',
          screenContent: screenWithConstChildren,
        );

        const plan = AiExecutionPlan(
          goalSummary: 'Place widget before Continue button',
          widgetName: 'StatusBadge',
          architectureType: 'statelessSnippet',
          placementStrategy: AiPlanPlacementStrategy.inlineInScreen,
          insertionAnchorHint: 'before_text:Continue',
        );

        const variation = WidgetVariation(
          id: 'badge_1',
          title: 'Status Badge',
          styleTag: 'Pill',
          description: 'Status indicator',
          dartCode: "const Chip(label: Text('Online'))",
          techApproach: 'Chip',
          plan: plan,
        );

        final result = await DartWidgetInjectorService.injectWidget(
          projectPath: projectDir.path,
          screenFilePath: 'lib/features/home/home_screen.dart',
          variation: variation,
          plan: plan,
        );

        expect(result.success, isTrue);
        final code = result.updatedScreenCode!;
        final sizedBoxPos = code.indexOf('SizedBox(height: 16)');
        final chipPos = code.indexOf("const Chip(label: Text('Online'))");
        final btnStartPos = code.indexOf('ElevatedButton(');
        expect(chipPos, greaterThan(sizedBoxPos));
        expect(chipPos, lessThan(btnStartPos));
      },
    );

    test(
      'supports center_body on Center(child: ...) screen without children: [ by wrapping in Column(mainAxisSize: MainAxisSize.min)',
      () async {
        const centerScreen = '''
import 'package:flutter/material.dart';

class MinimalCenterScreen extends StatelessWidget {
  const MinimalCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minimal')),
      body: const Center(
        child: Text('Empty State'),
      ),
    );
  }
}
''';
        final projectDir = createTempFlutterProject(
          projectName: 'center_app',
          screenRelPath: 'lib/minimal_center_screen.dart',
          screenContent: centerScreen,
        );

        const plan = AiExecutionPlan(
          goalSummary: 'Insert clock inside centered body',
          widgetName: 'DigitalClockWidget',
          architectureType: 'statefulWidgetClass',
          requiredImports: ['dart:async'],
          placementStrategy: AiPlanPlacementStrategy.separateWidgetFile,
          insertionAnchorHint: 'center_body',
        );

        final result = await DartWidgetInjectorService.injectWidget(
          projectPath: projectDir.path,
          screenFilePath: 'lib/minimal_center_screen.dart',
          variation: buildDigitalClockVariation(plan: plan),
          plan: plan,
        );

        expect(result.success, isTrue);
        final updated = result.updatedScreenCode!;
        expect(updated, isNot(contains('body: const Center')));
        expect(updated, contains('body: Center('));
        expect(updated, contains('Column('));
        expect(updated, contains('mainAxisSize: MainAxisSize.min'));
        expect(updated, contains("Text('Empty State')"));
        expect(updated, contains('const DigitalClockWidget()'));
      },
    );
  });

  group('DartWidgetInjectorService inlineInScreen placement', () {
    test(
      'appends extracted StatefulWidget class cleanly after all top-level classes (never inside build()) and hoists imports',
      () async {
        final projectDir = createTempFlutterProject(
          projectName: 'inline_app',
          screenRelPath: 'lib/features/home/home_screen.dart',
          screenContent: screenWithConstChildren,
        );

        const plan = AiExecutionPlan(
          goalSummary: 'Inline digital clock widget inside screen file',
          widgetName: 'DigitalClockWidget',
          architectureType: 'statefulWidgetClass',
          requiredImports: ['dart:async', 'package:flutter/material.dart'],
          placementStrategy: AiPlanPlacementStrategy.inlineInScreen,
          targetFilePath: 'lib/features/home/home_screen.dart',
          insertionAnchorHint: 'bottom_of_column',
        );

        final result = await DartWidgetInjectorService.injectWidget(
          projectPath: projectDir.path,
          screenFilePath: 'lib/features/home/home_screen.dart',
          variation: buildDigitalClockVariation(plan: plan),
          plan: plan,
        );

        expect(result.success, isTrue);
        expect(result.createdFiles, isEmpty);
        expect(result.modifiedFiles, equals(['lib/features/home/home_screen.dart']));

        final updated = result.updatedScreenCode!;
        // Import hoisted to top and deduplicated.
        expect(updated, contains("import 'dart:async';"));
        expect(
          RegExp(r"import 'package:flutter/material\.dart';")
              .allMatches(updated)
              .length,
          equals(1),
        );

        // Class declaration MUST appear AFTER HomeScreen class ends (never inside build()).
        final homeScreenBuildEnd = updated.indexOf('class DigitalClockWidget');
        final homeScreenClose = updated.indexOf('    );\n  }\n}');
        expect(homeScreenClose, greaterThan(-1));
        expect(homeScreenBuildEnd, greaterThan(homeScreenClose));

        // Verify call site is inside children: [ ... ] while class declaration is outside.
        final childrenIdx = updated.indexOf('children: [');
        final callSiteIdx = updated.indexOf('const DigitalClockWidget(),');
        expect(callSiteIdx, greaterThan(childrenIdx));
        expect(callSiteIdx, lessThan(homeScreenClose));
        expect(updated, contains('class _DigitalClockWidgetState extends State<DigitalClockWidget>'));
        // No stray `import` inside the middle/bottom of the file.
        expect(
          updated.indexOf("import 'dart:async';"),
          lessThan(updated.indexOf('class HomeScreen')),
        );
      },
    );
  });

  group('DartWidgetInjectorService security & failure guarantees', () {
    test('refuses screenFilePath path traversal outside projectPath', () async {
      final projectDir = createTempFlutterProject(
        projectName: 'sec_app',
        screenRelPath: 'lib/home_screen.dart',
        screenContent: screenWithConstChildren,
      );
      final outsideDir = Directory.systemTemp.createTempSync('flrd_outside_');
      addTearDown(() {
        if (outsideDir.existsSync()) outsideDir.deleteSync(recursive: true);
      });
      final outsideFile = File(p.join(outsideDir.path, 'outside_screen.dart'))
        ..writeAsStringSync(screenWithConstChildren);

      const plan = AiExecutionPlan(
        goalSummary: 'Attempt traversal',
        widgetName: 'DigitalClockWidget',
      );
      final variation = buildDigitalClockVariation(plan: plan);

      final relTraversal = await DartWidgetInjectorService.injectWidget(
        projectPath: projectDir.path,
        screenFilePath: '../outside_screen.dart',
        variation: variation,
        plan: plan,
      );
      expect(relTraversal.success, isFalse);
      expect(relTraversal.errorMessage, isNotNull);
      expect(relTraversal.createdFiles, isEmpty);
      expect(relTraversal.modifiedFiles, isEmpty);

      final absTraversal = await DartWidgetInjectorService.injectWidget(
        projectPath: projectDir.path,
        screenFilePath: outsideFile.path,
        variation: variation,
        plan: plan,
      );
      expect(absTraversal.success, isFalse);
      expect(absTraversal.errorMessage, isNotNull);
      expect(
        outsideFile.readAsStringSync(),
        equals(screenWithConstChildren),
      );
    });

    test('refuses extractedWidgetFilePath traversal outside projectPath', () async {
      final projectDir = createTempFlutterProject(
        projectName: 'sec_app',
        screenRelPath: 'lib/home_screen.dart',
        screenContent: screenWithConstChildren,
      );

      const plan = AiExecutionPlan(
        goalSummary: 'Write widget outside project',
        widgetName: 'DigitalClockWidget',
        placementStrategy: AiPlanPlacementStrategy.customPath,
        extractedWidgetFilePath: '../../evil_widget.dart',
      );

      final result = await DartWidgetInjectorService.injectWidget(
        projectPath: projectDir.path,
        screenFilePath: 'lib/home_screen.dart',
        variation: buildDigitalClockVariation(plan: plan),
        plan: plan,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(result.createdFiles, isEmpty);
      expect(result.backupDir, isNull);
      // Original screen remains completely untouched.
      expect(
        File(p.join(projectDir.path, 'lib/home_screen.dart')).readAsStringSync(),
        equals(screenWithConstChildren),
      );
    });

    test(
      'returns success: false (never fake success: true) when target file has invalid or unplaceable structure',
      () async {
        final projectDir = createTempFlutterProject(
          projectName: 'invalid_app',
          screenRelPath: 'lib/broken_screen.dart',
          screenContent: 'class NotAWidget { int value() => 42; }',
        );
        File(p.join(projectDir.path, 'lib/empty_build.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('''
import 'package:flutter/material.dart';
class EmptyBuild extends StatelessWidget {
  const EmptyBuild({super.key});
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
''');
        File(p.join(projectDir.path, 'lib/unbalanced.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('''
import 'package:flutter/material.dart';
class BrokenBrackets extends StatelessWidget {
  const BrokenBrackets({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Unclosed')
      ),
    );
  }
}
''');

        const plan = AiExecutionPlan(
          goalSummary: 'Inject clock',
          widgetName: 'DigitalClockWidget',
          insertionAnchorHint: 'top_of_body',
        );
        final variation = buildDigitalClockVariation(plan: plan);

        for (final target in [
          'lib/broken_screen.dart',
          'lib/empty_build.dart',
          'lib/unbalanced.dart',
        ]) {
          final result = await DartWidgetInjectorService.injectWidget(
            projectPath: projectDir.path,
            screenFilePath: target,
            variation: variation,
            plan: plan,
          );
          expect(
            result.success,
            isFalse,
            reason: 'Expected failure for unplaceable target $target',
          );
          expect(result.errorMessage, isNotNull);
          expect(result.createdFiles, isEmpty);
          expect(result.backupDir, isNull);
        }
      },
    );
  });

  group('ScreenMaterialCodeUpdater const fix & AST-preserving roundtrip', () {
    test(
      'insertWidgetSnippetIntoScreenCode strips const from children: const [ before inserting snippet',
      () {
        final updated = ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode(
          screenWithConstChildren,
          'DigitalClockWidget()',
        );

        expect(updated, contains('children: ['));
        expect(updated, isNot(contains('children: const [')));
        expect(updated, contains('DigitalClockWidget(),'));
        expect(updated, contains("'Welcome, dev!'"));
      },
    );

    test(
      'updateMaterialNoteInCode and reorderMaterialsInCode preserve extra imports, custom widget call sites, and inline custom classes',
      () async {
        final projectDir = createTempFlutterProject(
          projectName: 'roundtrip_app',
          screenRelPath: 'lib/features/home/home_screen.dart',
          screenContent: screenWithConstChildren,
        );

        const plan = AiExecutionPlan(
          goalSummary: 'Inject inline DigitalClockWidget',
          widgetName: 'DigitalClockWidget',
          architectureType: 'statefulWidgetClass',
          requiredImports: ['dart:async', 'package:flutter/material.dart'],
          placementStrategy: AiPlanPlacementStrategy.inlineInScreen,
          insertionAnchorHint: 'top_of_body',
        );

        final injected = await DartWidgetInjectorService.injectWidget(
          projectPath: projectDir.path,
          screenFilePath: 'lib/features/home/home_screen.dart',
          variation: buildDigitalClockVariation(plan: plan),
          plan: plan,
        );
        expect(injected.success, isTrue);

        // Also inject a separate-file import style to ensure arbitrary imports stay preserved.
        final codeWithExtraImport = injected.updatedScreenCode!.replaceFirst(
          "import 'dart:async';",
          "import 'dart:async';\nimport 'package:roundtrip_app/features/home/widgets/extra_helper.dart';",
        );

        // 1. Extract materials ONLY from primary screen (must not extract Text inside DigitalClockWidget!).
        final extracted = ScreenMaterialParser.extractMaterialsFromCode(
          codeWithExtraImport,
          'HomeScreen',
        );
        expect(
          extracted.any((m) => m.label.contains(r'$hh:$mm:$ss')),
          isFalse,
        );
        expect(
          extracted.any((m) => m.label == 'Welcome, dev!'),
          isTrue,
        );
        expect(
          extracted.any((m) => m.label == 'Continue'),
          isTrue,
        );

        final headerItem = extracted.firstWhere((m) => m.label == 'Welcome, dev!');

        // 2. Roundtrip updateMaterialNoteInCode: must preserve imports, custom call site, and inline class.
        final withNote = ScreenMaterialCodeUpdater.updateMaterialNoteInCode(
          currentCode: codeWithExtraImport,
          materialId: headerItem.id,
          note: 'Display greeting with live status badge',
          routeTitle: 'HomeScreen',
        );
        expect(withNote, contains('/// Note: Display greeting with live status badge'));
        expect(withNote, contains("import 'dart:async';"));
        expect(
          withNote,
          contains(
            "import 'package:roundtrip_app/features/home/widgets/extra_helper.dart';",
          ),
        );
        expect(withNote, contains('// FLRD:CUSTOM_WIDGET_START'));
        expect(withNote, contains('const DigitalClockWidget(),'));
        expect(withNote, contains('class DigitalClockWidget extends StatefulWidget'));
        expect(withNote, contains('Timer.periodic'));

        // 3. Roundtrip reorderMaterialsInCode: swap Welcome header and Continue button.
        final materialsBeforeReorder = ScreenMaterialParser.extractMaterialsFromCode(
          withNote,
          'HomeScreen',
        );
        final welcomeIdx = materialsBeforeReorder.indexWhere(
          (m) => m.label == 'Welcome, dev!',
        );
        final continueIdx = materialsBeforeReorder.indexWhere(
          (m) => m.label == 'Continue',
        );
        expect(welcomeIdx, greaterThan(0));
        expect(continueIdx, greaterThan(welcomeIdx));

        final reordered = ScreenMaterialCodeUpdater.reorderMaterialsInCode(
          currentCode: withNote,
          oldIndex: continueIdx,
          newIndex: welcomeIdx,
          routeTitle: 'HomeScreen',
        );

        expect(reordered, contains("import 'dart:async';"));
        expect(
          reordered,
          contains(
            "import 'package:roundtrip_app/features/home/widgets/extra_helper.dart';",
          ),
        );
        expect(reordered, contains('// FLRD:CUSTOM_WIDGET_START'));
        expect(reordered, contains('const DigitalClockWidget(),'));
        expect(reordered, contains('class DigitalClockWidget extends StatefulWidget'));

        final afterReorder = ScreenMaterialParser.extractMaterialsFromCode(
          reordered,
          'HomeScreen',
        );
        final newContinueIdx =
            afterReorder.indexWhere((m) => m.label == 'Continue');
        final newWelcomeIdx =
            afterReorder.indexWhere((m) => m.label == 'Welcome, dev!');
        expect(newContinueIdx, lessThan(newWelcomeIdx));
        expect(afterReorder[newWelcomeIdx].note, equals('Display greeting with live status badge'));
      },
    );
  });
}
