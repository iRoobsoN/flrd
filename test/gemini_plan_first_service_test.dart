import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flrd/features/ai/models/ai_execution_plan.dart';
import 'package:flrd/features/ai/services/gemini_ai_service.dart';
import 'package:flrd/features/ai/services/project_context_snapshot_service.dart';
import 'package:flrd/features/studio/domain/widget_variation.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

class _MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  _MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final httpRequest = request as http.Request;
    final response = await handler(httpRequest);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

Map<String, dynamic> _geminiTextResponse(String text) {
  return {
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  };
}

void main() {
  const sampleRoute = RouteNode(
    id: 'home',
    title: 'HomeScreen',
    subtitle: 'Tela Inicial',
    path: '/home',
    filePath: 'lib/features/home/home_screen.dart',
    position: Offset(0, 0),
    isProtected: false,
    icon: Icons.home_rounded,
  );

  final snapshotWithoutAppColors = ProjectContextSnapshot(
    projectPath: '/tmp/sample_app',
    projectName: 'sample_app',
    dependencies: const {'flutter_riverpod', 'google_fonts'},
    hasAppColors: false,
    hasGoRouter: false,
    aiPromptRules: const ['Use Material 3 ColorScheme tokens only.'],
    targetScreenPath: 'lib/features/home/home_screen.dart',
    targetScreenSource: '''
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Welcome'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
''',
  );

  group('GeminiAiService.buildModelCascade', () {
    test('prioritizes preferred Gemini 2.5 model and cascades cleanly', () {
      expect(
        GeminiAiService.buildModelCascade('gemini-2.5-flash'),
        equals(['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.0-flash']),
      );
      expect(
        GeminiAiService.buildModelCascade('gemini-2.5-pro'),
        equals(['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.0-flash']),
      );
      expect(
        GeminiAiService.buildModelCascade('gemini-1.5-flash'),
        equals(['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.0-flash']),
      );
      expect(
        GeminiAiService.buildModelCascade(null),
        equals(['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.0-flash']),
      );
    });
  });

  group('Missing API key outcome transparency', () {
    test(
      'returns AiResultSource.unconfiguredKey across all Plan-First methods and never returns generic placeholder cards',
      () async {
        for (final invalidKey in [null, '', '   ', 'null', 'undefined']) {
          final planOutcome = await GeminiAiService.planWidgetCreation(
            prompt:
                'Um relogio digital muito bonito que troca de estilo quando eu clico nele',
            userPlacementHint: 'no topo abaixo do Welcome',
            preset: PresetType.cleanLite,
            routeNode: sampleRoute,
            projectContext: snapshotWithoutAppColors,
            apiKey: invalidKey,
          );
          expect(planOutcome.source, AiResultSource.unconfiguredKey);
          expect(planOutcome.isSuccess, isFalse);
          expect(planOutcome.data, isNull);
          expect(planOutcome.errorMessage, contains('BYOK'));

          final variationsOutcome =
              await GeminiAiService.generatePlannedWidgetVariationsWithOutcome(
            prompt:
                'Um relogio digital muito bonito que troca de estilo quando eu clico nele',
            userPlacementHint: 'no topo abaixo do Welcome',
            preset: PresetType.cleanLite,
            routeNode: sampleRoute,
            projectContext: snapshotWithoutAppColors,
            apiKey: invalidKey,
          );
          expect(variationsOutcome.source, AiResultSource.unconfiguredKey);
          expect(variationsOutcome.isSuccess, isFalse);
          expect(variationsOutcome.data, isNull);
          expect(
            variationsOutcome.toString(),
            isNot(contains('Relogio Digital Muito')),
          );

          const dummyPlan = AiExecutionPlan(
            goalSummary: 'Digital clock',
            widgetName: 'DigitalClockWidget',
          );
          final singleOutcome = await GeminiAiService.generateWidgetFromPlan(
            plan: dummyPlan,
            originalPrompt:
                'Um relogio digital muito bonito que troca de estilo quando eu clico nele',
            preset: PresetType.cleanLite,
            apiKey: invalidKey,
          );
          expect(singleOutcome.source, AiResultSource.unconfiguredKey);
          expect(singleOutcome.data, isNull);

          final screenOutcome = await GeminiAiService.generateScreenWithOutcome(
            prompt: 'Tela de configurações com perfil',
            preset: PresetType.cleanLite,
            projectContext: snapshotWithoutAppColors,
            apiKey: invalidKey,
          );
          expect(screenOutcome.source, AiResultSource.unconfiguredKey);
          expect(screenOutcome.data, isNull);
        }
      },
    );
  });

  group('HTTP error diagnostics and Gemini 2.5 cascade', () {
    test(
      'HTTP 401 returns AiResultSource.error with clear auth diagnostic and cascades through all 3 models',
      () async {
        final requestedModels = <String>[];
        final mock401Client = _MockHttpClient((request) async {
          requestedModels.add(request.url.path);
          return http.Response(
            jsonEncode({
              'error': {
                'code': 401,
                'message': 'API key not valid. Please pass a valid API key.',
              },
            }),
            401,
          );
        });

        final outcome = await GeminiAiService.planWidgetCreation(
          prompt: 'Relógio digital interativo',
          preset: PresetType.cleanLite,
          apiKey: 'bad-key',
          client: mock401Client,
        );

        expect(requestedModels.length, 3);
        expect(requestedModels[0], contains('gemini-2.5-flash:generateContent'));
        expect(requestedModels[1], contains('gemini-2.5-pro:generateContent'));
        expect(requestedModels[2], contains('gemini-2.0-flash:generateContent'));

        expect(outcome.source, AiResultSource.error);
        expect(outcome.isSuccess, isFalse);
        expect(outcome.data, isNull);
        expect(outcome.modelUsed, 'gemini-2.0-flash');
        expect(outcome.errorMessage, contains('HTTP 401'));
        expect(outcome.errorMessage, contains('API key not valid'));
      },
    );

    test(
      'HTTP 500 across cascade returns AiResultSource.error in generatePlannedWidgetVariationsWithOutcome and never falls back to "Relogio Digital Muito"',
      () async {
        final requestedModels = <String>[];
        final mock500Client = _MockHttpClient((request) async {
          requestedModels.add(request.url.path);
          return http.Response('{"error":{"message":"Backend overloaded"}}', 500);
        });

        final outcome =
            await GeminiAiService.generatePlannedWidgetVariationsWithOutcome(
          prompt:
              'Um relogio digital muito bonito que troca de estilo quando eu clico nele',
          preset: PresetType.cleanLite,
          apiKey: 'valid-key',
          client: mock500Client,
        );

        expect(requestedModels.length, 3);
        expect(requestedModels[0], contains('gemini-2.5-flash'));
        expect(requestedModels[1], contains('gemini-2.5-pro'));
        expect(requestedModels[2], contains('gemini-2.0-flash'));

        expect(outcome.source, AiResultSource.error);
        expect(outcome.data, isNull);
        expect(outcome.errorMessage, contains('HTTP 500'));
        expect(outcome.errorMessage, contains('Backend overloaded'));
      },
    );

    test(
      'cascades from gemini-2.5-flash (500) to gemini-2.5-pro (200) and reports modelUsed accurately',
      () async {
        final requestedModels = <String>[];
        final cascadingClient = _MockHttpClient((request) async {
          requestedModels.add(request.url.path);
          if (request.url.path.contains('gemini-2.5-flash')) {
            return http.Response('Internal Server Error', 500);
          }
          return http.Response(
            jsonEncode(
              _geminiTextResponse(
                jsonEncode({
                  'goalSummary': 'Relógio digital em tempo real',
                  'widgetName': 'DigitalClockWidget',
                  'architectureType': 'statefulWidgetClass',
                  'stateFields': ['DateTime _now', 'Timer? _timer', 'int _styleIndex'],
                  'interactions': ['onTap alterna entre 4 estilos'],
                  'requiredImports': ['dart:async', 'package:flutter/material.dart'],
                  'requiredPackages': [],
                  'placementStrategy': 'separateWidgetFile',
                  'extractedWidgetFilePath': 'lib/features/home/widgets/digital_clock_widget.dart',
                  'visualAnchorDescription': 'No topo da tela logo abaixo do Welcome',
                  'insertionAnchorHint': 'after_text:Welcome',
                }),
              ),
            ),
            200,
          );
        });

        final outcome = await GeminiAiService.planWidgetCreation(
          prompt: 'Relógio digital interativo',
          userPlacementHint: 'no topo abaixo do Welcome',
          preset: PresetType.cleanLite,
          projectContext: snapshotWithoutAppColors,
          apiKey: 'valid-key',
          client: cascadingClient,
        );

        expect(requestedModels.length, 2);
        expect(requestedModels[0], contains('gemini-2.5-flash'));
        expect(requestedModels[1], contains('gemini-2.5-pro'));
        expect(outcome.isSuccess, isTrue);
        expect(outcome.source, AiResultSource.liveAi);
        expect(outcome.modelUsed, 'gemini-2.5-pro');
        expect(outcome.data?.widgetName, 'DigitalClockWidget');
      },
    );

    test(
      'generateScreenWithOutcome returns AiResultSource.error on network exception without falling back to fake template',
      () async {
        final throwingClient = _MockHttpClient((request) async {
          throw const SocketException('Network unreachable');
        });

        final outcome = await GeminiAiService.generateScreenWithOutcome(
          prompt: 'Tela de configurações',
          preset: PresetType.cleanLite,
          projectContext: snapshotWithoutAppColors,
          apiKey: 'valid-key',
          client: throwingClient,
        );

        expect(outcome.source, AiResultSource.error);
        expect(outcome.data, isNull);
        expect(outcome.errorMessage, contains('Network unreachable'));
      },
    );
  });

  group('Plan-First digital clock pipeline & ProjectContextSnapshot grounding', () {
    test(
      'planWidgetCreation injects Theme.of(context) rule when hasAppColors == false and returns structured AiExecutionPlan',
      () async {
        late Map<String, dynamic> capturedRequestBody;
        late Uri capturedUri;

        final mockClient = _MockHttpClient((request) async {
          capturedUri = request.url;
          capturedRequestBody = jsonDecode(request.body) as Map<String, dynamic>;

          final planJson = {
            'goalSummary':
                'Relógio digital em tempo real com alternância de estilo ao toque.',
            'widgetName': 'DigitalClockWidget',
            'architectureType': 'statefulWidgetClass',
            'stateFields': [
              'DateTime _now',
              'Timer? _timer',
              'int _styleIndex',
            ],
            'interactions': [
              'onTap increments _styleIndex across 4 digital clock themes',
            ],
            'requiredImports': [
              'dart:async',
              'package:flutter/material.dart',
            ],
            'requiredPackages': [],
            'placementStrategy': 'separateWidgetFile',
            'targetFilePath': 'lib/features/home/home_screen.dart',
            'extractedWidgetFilePath':
                'lib/features/home/widgets/digital_clock_widget.dart',
            'visualAnchorDescription':
                'Inserido no topo da Column, imediatamente abaixo de Text(\'Welcome\')',
            'insertionAnchorHint': 'after_text:Welcome',
          };

          return http.Response(
            jsonEncode(_geminiTextResponse(jsonEncode(planJson))),
            200,
          );
        });

        final outcome = await GeminiAiService.planWidgetWithOutcome(
          prompt:
              'Um relogio digital muito bonito que troca de estilo quando eu clico nele',
          userPlacementHint: 'no topo abaixo do Welcome',
          preset: PresetType.cleanLite,
          routeNode: sampleRoute,
          projectContext: snapshotWithoutAppColors,
          apiKey: 'AIzaTestKey',
          client: mockClient,
        );

        expect(capturedUri.toString(), contains('gemini-2.5-flash:generateContent'));
        final genConfig =
            capturedRequestBody['generationConfig'] as Map<String, dynamic>;
        expect(genConfig['responseMimeType'], 'application/json');
        expect(genConfig['temperature'], 0.25);

        final rawPromptSent = jsonEncode(capturedRequestBody['contents']);
        expect(rawPromptSent, contains('hasAppColors == false'));
        expect(rawPromptSent, contains('Theme.of(context).colorScheme'));
        expect(rawPromptSent, contains('Theme.of(context).textTheme'));
        expect(rawPromptSent, contains('no topo abaixo do Welcome'));
        expect(rawPromptSent, contains("Text('Welcome')"));

        expect(outcome.isSuccess, isTrue);
        expect(outcome.source, AiResultSource.liveAi);
        expect(outcome.modelUsed, 'gemini-2.5-flash');

        final plan = outcome.data!;
        expect(plan.widgetName, 'DigitalClockWidget');
        expect(plan.architectureType, 'statefulWidgetClass');
        expect(plan.requiredImports, contains('dart:async'));
        expect(plan.stateFields, contains('Timer? _timer'));
        expect(plan.stateFields, contains('int _styleIndex'));
        expect(plan.visualAnchorDescription, contains('Welcome'));
        expect(plan.insertionAnchorHint, 'after_text:Welcome');
        expect(plan.placementStrategy, AiPlanPlacementStrategy.separateWidgetFile);
      },
    );

    test(
      'generatePlannedWidgetVariationsWithOutcome runs Plan -> StatefulWidget variations with plan attached',
      () async {
        var callCount = 0;
        final capturedBodies = <String>[];

        const clockCode = '''
import 'dart:async';
import 'package:flutter/material.dart';

class DigitalClockWidget extends StatefulWidget {
  const DigitalClockWidget({super.key});

  @override
  State<DigitalClockWidget> createState() => _DigitalClockWidgetState();
}

class _DigitalClockWidgetState extends State<DigitalClockWidget> {
  DateTime _now = DateTime.now();
  Timer? _timer;
  int _styleIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final ss = _now.second.toString().padLeft(2, '0');
    return GestureDetector(
      onTap: () => setState(() => _styleIndex = (_styleIndex + 1) % 3),
      child: Card(
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('\$hh:\$mm:\$ss', style: Theme.of(context).textTheme.headlineMedium),
        ),
      ),
    );
  }
}
''';

        final mockClient = _MockHttpClient((request) async {
          callCount++;
          capturedBodies.add(request.body);

          if (callCount == 1) {
            return http.Response(
              jsonEncode(
                _geminiTextResponse(
                  jsonEncode({
                    'goalSummary': 'Relógio digital em tempo real com 3 estilos',
                    'widgetName': 'DigitalClockWidget',
                    'architectureType': 'statefulWidgetClass',
                    'stateFields': ['DateTime _now', 'Timer? _timer', 'int _styleIndex'],
                    'interactions': ['onTap cycles styles'],
                    'requiredImports': ['dart:async', 'package:flutter/material.dart'],
                    'requiredPackages': [],
                    'placementStrategy': 'separateWidgetFile',
                    'targetFilePath': 'lib/features/home/home_screen.dart',
                    'extractedWidgetFilePath':
                        'lib/features/home/widgets/digital_clock_widget.dart',
                    'visualAnchorDescription': 'No topo abaixo do Welcome',
                    'insertionAnchorHint': 'after_text:Welcome',
                  }),
                ),
              ),
              200,
            );
          }

          return http.Response(
            jsonEncode(
              _geminiTextResponse(
                jsonEncode([
                  {
                    'id': 'clock_var_1',
                    'title': 'Minimal Material Clock',
                    'styleTag': 'Material 3 Surface',
                    'description': 'Relógio digital minimalista usando ColorScheme.',
                    'techApproach': 'StatefulWidget + Timer.periodic + GestureDetector',
                    'requiredImports': ['dart:async', 'package:flutter/material.dart'],
                    'extractedWidgetCode': clockCode,
                    'callSiteSnippet': 'const DigitalClockWidget()',
                    'dartCode': clockCode,
                  },
                  {
                    'id': 'clock_var_2',
                    'title': 'Neon Accent Clock',
                    'styleTag': 'Primary Container Accent',
                    'description': 'Relógio digital com borda de destaque e toggle de tema.',
                    'techApproach': 'StatefulWidget + Timer.periodic + AnimatedContainer',
                    'requiredImports': ['dart:async', 'package:flutter/material.dart'],
                    'extractedWidgetCode': clockCode,
                    'callSiteSnippet': 'const DigitalClockWidget()',
                    'dartCode': clockCode,
                  },
                  {
                    'id': 'clock_var_3',
                    'title': 'Compact Pill Clock',
                    'styleTag': 'Compact Pill',
                    'description': 'Relógio em pílula compacta com segundos.',
                    'techApproach': 'StatefulWidget + Timer.periodic + InkWell',
                    'requiredImports': ['dart:async', 'package:flutter/material.dart'],
                    'extractedWidgetCode': clockCode,
                    'callSiteSnippet': 'const DigitalClockWidget()',
                    'dartCode': clockCode,
                  },
                ]),
              ),
            ),
            200,
          );
        });

        final outcome =
            await GeminiAiService.generatePlannedWidgetVariationsWithOutcome(
          prompt:
              'Um relogio digital muito bonito que troca de estilo quando eu clico nele',
          userPlacementHint: 'no topo abaixo do Welcome',
          preset: PresetType.cleanLite,
          routeNode: sampleRoute,
          projectContext: snapshotWithoutAppColors,
          apiKey: 'AIzaTestKey',
          client: mockClient,
        );

        expect(callCount, 2);
        expect(capturedBodies[0], contains('Theme.of(context).colorScheme'));
        expect(capturedBodies[1], contains('DigitalClockWidget'));
        expect(capturedBodies[1], contains('Theme.of(context).colorScheme'));

        expect(outcome.isSuccess, isTrue);
        expect(outcome.source, AiResultSource.liveAi);
        expect(outcome.modelUsed, 'gemini-2.5-flash');
        expect(outcome.plan, isNotNull);
        expect(outcome.plan!.widgetName, 'DigitalClockWidget');
        expect(outcome.plan!.visualAnchorDescription, contains('Welcome'));

        final variations = outcome.data!;
        expect(variations.length, 3);
        for (final variation in variations) {
          expect(variation.plan, equals(outcome.plan));
          expect(variation.requiredImports, contains('dart:async'));
          expect(variation.extractedWidgetCode, contains('class DigitalClockWidget extends StatefulWidget'));
          expect(variation.extractedWidgetCode, contains('Timer.periodic'));
          expect(variation.callSiteSnippet, 'const DigitalClockWidget()');
          expect(variation.title, isNot(contains('Relogio Digital Muito')));
        }
      },
    );

    test(
      'generateWidgetFromPlan returns liveAi WidgetVariation and respects preferredModel',
      () async {
        late Uri capturedUri;
        const plan = AiExecutionPlan(
          goalSummary: 'Relógio digital interativo',
          widgetName: 'DigitalClockWidget',
          architectureType: 'statefulWidgetClass',
          stateFields: ['DateTime _now', 'Timer? _timer', 'int _styleIndex'],
          interactions: ['onTap cycles themes'],
          requiredImports: ['dart:async', 'package:flutter/material.dart'],
          visualAnchorDescription: 'Logo abaixo do Welcome',
          insertionAnchorHint: 'after_text:Welcome',
        );

        final mockClient = _MockHttpClient((request) async {
          capturedUri = request.url;
          return http.Response(
            jsonEncode(
              _geminiTextResponse(
                jsonEncode({
                  'id': 'single_clock_1',
                  'title': 'Digital Clock Pro',
                  'styleTag': 'Adaptive Theme Clock',
                  'description': 'Implementação completa com Timer e troca de estilo.',
                  'techApproach': 'StatefulWidget + Timer.periodic',
                  'extractedWidgetCode':
                      'class DigitalClockWidget extends StatefulWidget { const DigitalClockWidget({super.key}); @override State<DigitalClockWidget> createState() => _DigitalClockWidgetState(); }',
                  'callSiteSnippet': 'const DigitalClockWidget()',
                  'dartCode':
                      'class DigitalClockWidget extends StatefulWidget { const DigitalClockWidget({super.key}); @override State<DigitalClockWidget> createState() => _DigitalClockWidgetState(); }',
                }),
              ),
            ),
            200,
          );
        });

        final outcome = await GeminiAiService.generateWidgetFromPlan(
          plan: plan,
          originalPrompt: 'Relógio digital',
          userPlacementHint: 'no topo abaixo do Welcome',
          preset: PresetType.cleanLite,
          projectContext: snapshotWithoutAppColors,
          apiKey: 'AIzaTestKey',
          preferredModel: 'gemini-2.5-pro',
          client: mockClient,
        );

        expect(capturedUri.toString(), contains('gemini-2.5-pro:generateContent'));
        expect(outcome.isSuccess, isTrue);
        expect(outcome.modelUsed, 'gemini-2.5-pro');
        expect(outcome.data?.plan, equals(plan));
        expect(outcome.data?.requiredImports, contains('dart:async'));
        expect(outcome.data?.callSiteSnippet, 'const DigitalClockWidget()');
      },
    );

    test(
      'generateScreenWithOutcome injects ProjectContextSnapshot rules and extracts Dart code',
      () async {
        late String capturedBody;
        final mockClient = _MockHttpClient((request) async {
          capturedBody = request.body;
          return http.Response(
            jsonEncode(
              _geminiTextResponse('''
```dart
import 'package:flutter/material.dart';

class SettingsOverviewScreen extends StatelessWidget {
  const SettingsOverviewScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}
```
'''),
            ),
            200,
          );
        });

        final outcome = await GeminiAiService.generateScreenWithOutcome(
          prompt: 'Tela de configurações do usuário',
          userPlacementHint: 'Centralizado com seções Material 3',
          preset: PresetType.cleanLite,
          routeNode: sampleRoute,
          projectContext: snapshotWithoutAppColors,
          existingRoutes: const ['/home', '/settings'],
          apiKey: 'AIzaTestKey',
          client: mockClient,
        );

        expect(capturedBody, contains('hasAppColors == false'));
        expect(capturedBody, contains('Theme.of(context).colorScheme'));
        expect(capturedBody, contains('hasGoRouter == false'));
        expect(capturedBody, contains('/settings'));

        expect(outcome.isSuccess, isTrue);
        expect(outcome.source, AiResultSource.liveAi);
        expect(outcome.modelUsed, 'gemini-2.5-flash');
        expect(outcome.data, contains('class SettingsOverviewScreen'));
        expect(outcome.data, isNot(contains('```')));
      },
    );
  });

  group('WidgetVariation extended fields compatibility', () {
    test('supports requiredImports, extractedWidgetCode, callSiteSnippet, and plan roundtrip', () {
      const plan = AiExecutionPlan(
        goalSummary: 'Clock widget',
        widgetName: 'DigitalClockWidget',
        requiredImports: ['dart:async'],
      );
      const variation = WidgetVariation(
        id: 'v1',
        title: 'Clock',
        styleTag: 'Material',
        description: 'Live clock',
        dartCode: 'const DigitalClockWidget()',
        techApproach: 'StatefulWidget',
        icon: Icons.access_time_rounded,
        requiredImports: ['dart:async', 'package:flutter/material.dart'],
        extractedWidgetCode: 'class DigitalClockWidget extends StatefulWidget {}',
        callSiteSnippet: 'const DigitalClockWidget()',
        plan: plan,
      );

      final roundtrip = WidgetVariation.fromJson(
        variation.toJson(),
        icon: Icons.access_time_rounded,
      );
      expect(roundtrip, equals(variation));
      expect(roundtrip.hashCode, equals(variation.hashCode));

      final cleared = variation.copyWith(
        extractedWidgetCode: null,
        callSiteSnippet: null,
        plan: null,
      );
      expect(cleared.extractedWidgetCode, isNull);
      expect(cleared.callSiteSnippet, isNull);
      expect(cleared.plan, isNull);
    });
  });
}
