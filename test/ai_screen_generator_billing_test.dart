import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:flrd/features/ai/providers/ai_settings_provider.dart';
import 'package:flrd/features/auth/domain/user_account.dart';
import 'package:flrd/features/auth/providers/auth_provider.dart';
import 'package:flrd/features/auth/services/firebase_auth_service.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/settings/presentation/settings_and_billing_dialog.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/presentation/widgets/ai_screen_generator_dialog.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

class _MockGeminiClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  _MockGeminiClient(this.handler);

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

Map<String, dynamic> _geminiResponse(String text) => {
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

Future<void> _pumpThroughRealAsync(
  WidgetTester tester, {
  int maxSteps = 100,
}) async {
  await tester.pump();
  for (var i = 0; i < maxSteps; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;
  late RegisteredProject testProject;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flrd_billing_ui_test_');
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: billing_demo_app
version: 1.0.0+1
environment:
  sdk: ">=3.2.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
    testProject = RegisteredProject(
      id: 'proj_test',
      name: 'billing_demo_app',
      orgId: 'org_test',
      path: tempDir.path,
      preset: PresetType.saas,
      navigationStyle: NavigationStyle.tabs,
      permissions: const {},
      lastModified: DateTime.now(),
      routeCount: 1,
    );
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildTestApp({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  group('AiScreenGeneratorDialog - Plan Status & Honest BYOK Gemini 2.5 Header', () {
    testWidgets('Displays ⭐ FLRD Studio Pro and honest BYOK status without FLRD Pro Cloud',
        (tester) async {
      const proUser = UserAccount(
        uid: 'user_pro_123',
        email: 'pro@flrd.dev',
        displayName: 'Pro Developer',
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
      );

      final sessionFile =
          '${tempDir.path}${Platform.pathSeparator}session_${DateTime.now().microsecondsSinceEpoch}.json';
      final mockAuthService = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(context, testProject);
              },
              child: const Text('Open Dialog'),
            ),
          ),
          overrides: [
            firebaseAuthServiceProvider.overrideWithValue(mockAuthService),
            authProvider.overrideWith((ref) {
              final notifier = AuthNotifier(
                authService: mockAuthService,
                ref: ref,
                autoRestore: false,
              );
              notifier.updateUser(proUser);
              return notifier;
            }),
          ],
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Plan Badge & Manage Plan action remain intact
      expect(find.text('⭐ FLRD Studio Pro'), findsOneWidget);
      expect(find.text('⚡ Gerenciar Plano / Inscrição'), findsOneWidget);

      // Honest BYOK status without fake FLRD Pro Cloud mode
      expect(find.text('Cota Ilimitada / BYOK Livre'), findsOneWidget);
      expect(find.text('🔑 Chave Gemini (BYOK) necessária'), findsOneWidget);
      expect(find.text('⚡ FLRD Pro Cloud'), findsNothing);
      expect(find.text('Gemini 2.5 Flash'), findsOneWidget);
      expect(find.text('Gemini 2.5 Pro'), findsOneWidget);
    });

    testWidgets('Tapping [⚡ Gerenciar Plano / Inscrição] opens SettingsAndBillingDialog',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(context, testProject);
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final manageBtn = find.text('⚡ Gerenciar Plano / Inscrição');
      expect(manageBtn, findsOneWidget);
      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsAndBillingDialog), findsOneWidget);
    });

    testWidgets('Displays ⚡ FLRD Starter badge and honest BYOK status for starter subscriber',
        (tester) async {
      const starterUser = UserAccount(
        uid: 'user_starter_456',
        email: 'starter@flrd.dev',
        subscriptionTier: SubscriptionTier.starter,
        aiCreditsRemaining: 45,
        aiCreditsTotal: 50,
      );

      final sessionFile =
          '${tempDir.path}${Platform.pathSeparator}session_${DateTime.now().microsecondsSinceEpoch}.json';
      final mockAuthService = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(context, testProject);
              },
              child: const Text('Open Dialog'),
            ),
          ),
          overrides: [
            firebaseAuthServiceProvider.overrideWithValue(mockAuthService),
            authProvider.overrideWith((ref) {
              final notifier = AuthNotifier(
                authService: mockAuthService,
                ref: ref,
                autoRestore: false,
              );
              notifier.updateUser(starterUser);
              return notifier;
            }),
          ],
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('⚡ FLRD Starter'), findsOneWidget);
      expect(find.text('Cota Ilimitada / BYOK Livre'), findsOneWidget);
      expect(find.text('⚡ FLRD Pro Cloud'), findsNothing);
    });

    testWidgets('Supports inline Gemini BYOK key save and Gemini 2.5 Flash/Pro model toggle',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    AiScreenGeneratorDialog.show(context, testProject);
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Cota Ilimitada / BYOK Livre'), findsOneWidget);
      expect(find.text('🔑 Chave Gemini (BYOK) necessária'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('dialog_api_key_input')),
        'AIzaBillingTestKey777',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('dialog_api_key_save_button')),
      );
      await tester.tap(find.byKey(const ValueKey('dialog_api_key_save_button')));
      await tester.pumpAndSettle();

      expect(container.read(aiSettingsProvider).apiKey, 'AIzaBillingTestKey777');
      expect(find.text('⚡ BYOK Ativo · Gemini 2.5 Flash'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('dialog_model_pro')));
      await tester.pumpAndSettle();

      expect(
        container.read(aiSettingsProvider).selectedModel,
        AiSettingsState.geminiProModel,
      );
      expect(find.text('⚡ BYOK Ativo · Gemini 2.5 Pro'), findsOneWidget);
    });
  });

  group('AiScreenGeneratorDialog - Focused Widget-Only Generation Mode', () {
    testWidgets('Switches to widget refinement title, prompt, and button',
        (tester) async {
      const material = ScreenMaterialItem(
        id: 'mat_test_input',
        type: ScreenMaterialType.textInput,
        label: 'E-mail Corporativo',
        hint: 'seu.nome@empresa.com',
        note: 'Validar formato de e-mail e aplicar borda neon ao focar',
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AiScreenGeneratorDialog.show(
                  context,
                  testProject,
                  targetMaterial: material,
                );
              },
              child: const Text('Refine Material'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Refine Material'));
      await tester.pumpAndSettle();

      expect(
        find.text('Refinar Widget com IA: E-mail Corporativo'),
        findsOneWidget,
      );
      expect(find.text('✨ Refinar e Injetar Widget'), findsOneWidget);

      final textField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && (w.maxLines == 4),
        ),
      );
      expect(textField.controller?.text, contains('E-mail Corporativo'));
      expect(textField.controller?.text, contains('Validar formato de e-mail'));
    });

    testWidgets(
        'Refining widget (targetMaterial != null) runs Plan -> generateWidgetFromPlan -> DartWidgetInjectorService -> verify without duplicate Scaffold or RouteNode',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const initialLoginCode = '''import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar')),
      body: Column(
        children: const [
          Text('Welcome'),
          ElevatedButton(onPressed: null, child: Text('Entrar')),
        ],
      ),
    );
  }
}
''';
      final loginFile = File(
        p.join(tempDir.path, 'lib/features/auth/presentation/login_screen.dart'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(initialLoginCode);

      var geminiRequests = 0;
      final mockClient = _MockGeminiClient((request) async {
        geminiRequests++;
        if (geminiRequests == 1) {
          return http.Response(
            jsonEncode(
              _geminiResponse(
                jsonEncode({
                  'goalSummary': 'Input corporativo com validação e borda neon.',
                  'widgetName': 'CorporateEmailInput',
                  'architectureType': 'statefulWidgetClass',
                  'stateFields': ['TextEditingController _controller', 'bool _isValid'],
                  'interactions': ['onChanged valida formato de e-mail'],
                  'requiredImports': ['package:flutter/material.dart'],
                  'requiredPackages': [],
                  'placementStrategy': 'separateWidgetFile',
                  'targetFilePath': 'lib/features/auth/presentation/login_screen.dart',
                  'extractedWidgetFilePath':
                      'lib/features/auth/widgets/corporate_email_input.dart',
                  'visualAnchorDescription': 'Logo abaixo do texto Welcome',
                  'insertionAnchorHint': 'after_text:Welcome',
                }),
              ),
            ),
            200,
          );
        }

        return http.Response(
          jsonEncode(
            _geminiResponse(
              jsonEncode({
                'id': 'refined_email_1',
                'title': 'Corporate Email Input',
                'styleTag': 'Neon Input',
                'description': 'Campo com validação em tempo real.',
                'techApproach': 'StatefulWidget + TextEditingController',
                'requiredImports': ['package:flutter/material.dart'],
                'extractedWidgetCode': '''import 'package:flutter/material.dart';

class CorporateEmailInput extends StatefulWidget {
  const CorporateEmailInput({super.key});

  @override
  State<CorporateEmailInput> createState() => _CorporateEmailInputState();
}

class _CorporateEmailInputState extends State<CorporateEmailInput> {
  final TextEditingController _controller = TextEditingController();
  bool _isValid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (v) => setState(() => _isValid = v.contains('@')),
      decoration: InputDecoration(
        labelText: 'E-mail Corporativo',
        suffixIcon: Icon(_isValid ? Icons.check_circle : Icons.email_outlined),
      ),
    );
  }
}''',
                'callSiteSnippet': 'const CorporateEmailInput()',
                'dartCode': 'const CorporateEmailInput()',
              }),
            ),
          ),
          200,
        );
      });

      final verifyCalls = <List<String>>[];
      Future<ProcessResult> mockRunner(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        verifyCalls.add(List<String>.from(args));
        return ProcessResult(1, 0, 'No issues found!\n', '');
      }

      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.inMemory(
              const AiSettingsState(apiKey: 'AIzaRefineTestKey'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final initialNodeCount = container.read(studioProvider).nodes.length;
      String updatedCode = initialLoginCode;

      const material = ScreenMaterialItem(
        id: 'mat_test_input',
        type: ScreenMaterialType.textInput,
        label: 'E-mail Corporativo',
        note: 'Validar formato de e-mail',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    AiScreenGeneratorDialog.show(
                      context,
                      testProject,
                      initialRoutePath: '/auth/login',
                      initialScreenTitle: 'LoginScreen',
                      targetMaterial: material,
                      targetScreenFilePath:
                          'lib/features/auth/presentation/login_screen.dart',
                      currentScreenCode: updatedCode,
                      onCodeChanged: (code) => updatedCode = code,
                      aiHttpClient: mockClient,
                      verificationProcessRunner: mockRunner,
                    );
                  },
                  child: const Text('Refine Material'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Refine Material'));
      await tester.pumpAndSettle();

      final refineBtn = find.byKey(const Key('generate_screen_button'));
      await tester.ensureVisible(refineBtn);
      await tester.tap(refineBtn);
      await _pumpThroughRealAsync(tester);

      expect(geminiRequests, equals(2));
      expect(verifyCalls, hasLength(1));
      expect(verifyCalls.single, contains('analyze'));
      expect(container.read(studioProvider).nodes.length, equals(initialNodeCount));

      final diskScreen = loginFile.readAsStringSync();
      expect(diskScreen, contains('const CorporateEmailInput()'));
      expect(RegExp(r'\bScaffold\s*\(').allMatches(diskScreen).length, equals(1));
      expect(updatedCode, equals(diskScreen));

      final widgetFile = File(
        p.join(tempDir.path, 'lib/features/auth/widgets/corporate_email_input.dart'),
      );
      expect(widgetFile.existsSync(), isTrue);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('AiScreenGeneratorDialog - Honest BYOK Behavior & Credit Preservation', () {
    testWidgets('Consumes 0 credits and shows error when BYOK API key is missing',
        (tester) async {
      const proUser = UserAccount(
        uid: 'user_pro_credit',
        email: 'credit@flrd.dev',
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
      );

      final sessionFile =
          '${tempDir.path}${Platform.pathSeparator}session_${DateTime.now().microsecondsSinceEpoch}.json';
      final mockAuthService = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      late AuthNotifier authNotifier;
      final container = ProviderContainer(
        overrides: [
          firebaseAuthServiceProvider.overrideWithValue(mockAuthService),
          authProvider.overrideWith((ref) {
            authNotifier = AuthNotifier(
              authService: mockAuthService,
              ref: ref,
              autoRestore: false,
            );
            authNotifier.updateUser(proUser);
            return authNotifier;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    AiScreenGeneratorDialog.show(context, testProject);
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final initialNodes = container.read(studioProvider).nodes.length;
      expect(authNotifier.state.creditsRemaining, equals(185));

      final generateBtn = find.byKey(const Key('generate_screen_button'));
      await tester.ensureVisible(generateBtn);
      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      expect(authNotifier.state.creditsRemaining, equals(185));
      expect(find.byKey(const ValueKey('dialog_ai_error_banner')), findsOneWidget);
      expect(
        find.textContaining('Chave Gemini (BYOK) necessária'),
        findsAtLeastNWidgets(2),
      );
      expect(container.read(studioProvider).nodes.length, equals(initialNodes));
      expect(
        File(p.join(tempDir.path, 'lib/features/payment/presentation/paymentscreen.dart'))
            .existsSync(),
        isFalse,
      );
    });

    testWidgets(
        'Plan-First New Screen with BYOK + mock HTTP + analyzer runs Preview -> Backup -> Verify -> Add RouteNode with 0 credits consumed',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const proUser = UserAccount(
        uid: 'user_pro_byok',
        email: 'byok@flrd.dev',
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
      );

      final sessionFile =
          '${tempDir.path}${Platform.pathSeparator}session_${DateTime.now().microsecondsSinceEpoch}.json';
      final mockAuthService = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      const generatedCode = '''import 'package:flutter/material.dart';

class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Live BYOK Payment Screen')),
    );
  }
}
''';

      final mockClient = _MockGeminiClient((request) async {
        expect(request.url.toString(), contains('gemini-2.5-flash'));
        return http.Response(
          jsonEncode(_geminiResponse('```dart\n$generatedCode\n```')),
          200,
        );
      });

      final verifyCalls = <List<String>>[];
      Future<ProcessResult> mockRunner(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        verifyCalls.add(List<String>.from(args));
        return ProcessResult(1, 0, 'No issues found!\n', '');
      }

      late AuthNotifier authNotifier;
      final container = ProviderContainer(
        overrides: [
          firebaseAuthServiceProvider.overrideWithValue(mockAuthService),
          authProvider.overrideWith((ref) {
            authNotifier = AuthNotifier(
              authService: mockAuthService,
              ref: ref,
              autoRestore: false,
            );
            authNotifier.updateUser(proUser);
            return authNotifier;
          }),
          aiSettingsProvider.overrideWith(
            (ref) => AiSettingsNotifier.inMemory(
              const AiSettingsState(apiKey: 'AIzaLiveBillingByokKey'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    AiScreenGeneratorDialog.show(
                      context,
                      testProject,
                      aiHttpClient: mockClient,
                      verificationProcessRunner: mockRunner,
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final initialNodes = container.read(studioProvider).nodes.length;

      // Step 1: Plan & Preview
      final generateBtn = find.byKey(const Key('generate_screen_button'));
      await tester.ensureVisible(generateBtn);
      await tester.tap(generateBtn);
      await _pumpThroughRealAsync(tester);

      expect(find.byKey(const ValueKey('dialog_plan_preview_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('dialog_screen_code_preview')), findsOneWidget);
      expect(find.textContaining('Live BYOK Payment Screen'), findsOneWidget);
      expect(authNotifier.state.creditsRemaining, equals(185));

      // Step 2: Save, Backup, Verify & Inject RouteNode
      final applyBtn = find.byKey(const Key('dialog_apply_and_verify_screen_button'));
      await tester.ensureVisible(applyBtn);
      await tester.tap(applyBtn);
      await _pumpThroughRealAsync(tester);

      expect(verifyCalls, hasLength(1));
      expect(verifyCalls.single, contains('analyze'));
      expect(authNotifier.state.creditsRemaining, equals(185));
      expect(container.read(studioProvider).nodes.length, equals(initialNodes + 1));

      final writtenFile = File(
        p.join(tempDir.path, 'lib/features/payment/presentation/paymentscreen.dart'),
      );
      expect(writtenFile.existsSync(), isTrue);
      expect(writtenFile.readAsStringSync(), contains('Live BYOK Payment Screen'));
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
