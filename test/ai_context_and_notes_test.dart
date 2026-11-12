import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/features/auth/domain/user_account.dart';
import 'package:flrd/features/auth/providers/auth_provider.dart';
import 'package:flrd/features/auth/services/firebase_auth_service.dart';
import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/settings/presentation/settings_and_billing_dialog.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/widgets/ai_screen_generator_dialog.dart';
import 'package:flrd/features/studio/presentation/widgets/screen_materials_builder.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late RegisteredProject dummyProject;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flrd_ai_context_notes_test_');
    dummyProject = RegisteredProject(
      id: 'proj_ai_context_notes',
      name: 'AI Context & Notes App',
      orgId: 'com.flrd.ainotes',
      path: tempDir.path,
      preset: PresetType.saas,
      navigationStyle: NavigationStyle.tabs,
      permissions: const {},
      lastModified: DateTime.now(),
      routeCount: 3,
    );
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  const testNode = RouteNode(
    id: 'checkout',
    title: 'CheckoutScreen',
    subtitle: 'Finalização do Pedido',
    path: '/checkout',
    filePath: 'lib/features/checkout/checkout_screen.dart',
    position: Offset(150, 150),
    isProtected: true,
    icon: Icons.shopping_cart_checkout_rounded,
  );

  final List<RouteNode> existingRoutes = const [
    RouteNode(
      id: 'home',
      title: 'HomeScreen',
      subtitle: 'Feed Principal',
      path: '/home',
      filePath: 'lib/features/home/home_screen.dart',
      icon: Icons.home_rounded,
      position: Offset(50, 50),
      isProtected: false,
    ),
    RouteNode(
      id: 'profile',
      title: 'ProfileScreen',
      subtitle: 'Configurações de Conta',
      path: '/profile',
      filePath: 'lib/features/profile/profile_screen.dart',
      icon: Icons.person_rounded,
      position: Offset(250, 50),
      isProtected: true,
    ),
  ];

  const sampleDartCode = '''
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: const Icon(Icons.arrow_back),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Cupom de Desconto',
                hintText: 'PROMO2026',
              ),
            ),
            ElevatedButton(
              onPressed: () {},
              child: const Text('Finalizar Compra'),
            ),
          ],
        ),
      ),
    );
  }
}
''';

  group('1. ScreenMaterialItem.note Serialization and Persistence', () {
    test('Constructor, copyWith, equality and toJson/fromJson preserve note', () {
      const itemWithNote = ScreenMaterialItem(
        id: 'mat_test_btn',
        type: ScreenMaterialType.primaryButton,
        label: 'Finalizar Pagamento',
        hint: 'Clique para pagar',
        note: 'Botão pulsante com gradiente Obsidian e modal de confirmação biométrica',
      );

      expect(itemWithNote.note, 'Botão pulsante com gradiente Obsidian e modal de confirmação biométrica');
      expect(itemWithNote.displayName, 'Finalizar Pagamento');

      // Test copyWith updating note
      final updatedNote = itemWithNote.copyWith(
        note: 'Nota atualizada com haptic feedback',
      );
      expect(updatedNote.note, 'Nota atualizada com haptic feedback');
      expect(updatedNote.id, itemWithNote.id);

      // Test copyWith without modifying note
      final untouched = itemWithNote.copyWith(label: 'Pagar Agora');
      expect(untouched.note, itemWithNote.note);
      expect(untouched.label, 'Pagar Agora');

      // Test serialization to JSON
      final json = itemWithNote.toJson();
      expect(json['note'], 'Botão pulsante com gradiente Obsidian e modal de confirmação biométrica');
      expect(json['label'], 'Finalizar Pagamento');
      expect(json['type'], 'primaryButton');

      // Test deserialization from JSON
      final deserialized = ScreenMaterialItem.fromJson(json);
      expect(deserialized.id, itemWithNote.id);
      expect(deserialized.type, itemWithNote.type);
      expect(deserialized.label, itemWithNote.label);
      expect(deserialized.note, itemWithNote.note);
      expect(deserialized, equals(itemWithNote));
    });

    test('ScreenMaterialCodeUpdater and Parser roundtrip component notes in Dart code', () {
      const newMaterial = ScreenMaterialItem(
        id: 'mat_security_badge',
        type: ScreenMaterialType.containerCard,
        label: 'Selo de Segurança SSL',
        hint: 'Card com ícone de cadeado e texto de segurança',
        note: 'Efeito de blur glassmorphism 20px com borda translúcida neon',
      );

      final updatedCode = ScreenMaterialCodeUpdater.addMaterialToCode(
        currentCode: sampleDartCode,
        newMaterial: newMaterial,
        screenClassName: 'CheckoutScreen',
        routePath: '/checkout',
        routeTitle: 'CheckoutScreen',
      );

      // Verify that code contains the note comment
      expect(updatedCode, contains('/// Note: Efeito de blur glassmorphism 20px com borda translúcida neon'));

      // Extract materials back from code and verify note is recovered
      final extractedMaterials = ScreenMaterialParser.extractMaterialsFromCode(
        updatedCode,
        'CheckoutScreen',
      );

      final foundBadge = extractedMaterials.firstWhere(
        (m) => m.label.contains('Selo de Segurança SSL') || m.type == ScreenMaterialType.containerCard,
      );
      expect(foundBadge.note, contains('Efeito de blur glassmorphism'));

      // Update material note in code using helper
      final reUpdatedCode = ScreenMaterialCodeUpdater.updateMaterialNoteInCode(
        currentCode: updatedCode,
        materialId: foundBadge.id,
        note: 'Nota modificada: Suporte a Apple Pay e Google Pay',
        screenClassName: 'CheckoutScreen',
        routePath: '/checkout',
        routeTitle: 'CheckoutScreen',
      );

      expect(reUpdatedCode, contains('/// Note: Nota modificada: Suporte a Apple Pay e Google Pay'));

      final finalExtracted = ScreenMaterialParser.extractMaterialsFromCode(
        reUpdatedCode,
        'CheckoutScreen',
      );
      final updatedBadge = finalExtracted.firstWhere(
        (m) => m.id == foundBadge.id || m.label.contains('Selo de Segurança SSL'),
      );
      expect(updatedBadge.note, 'Nota modificada: Suporte a Apple Pay e Google Pay');
    });
  });

  group('2. generateAiEnhancePrompt Navigation Graph and Component Notes', () {
    test('generateAiEnhancePrompt includes app routes and individual component notes', () {
      final materials = [
        const ScreenMaterialItem(
          id: 'mat_app_bar',
          type: ScreenMaterialType.appBar,
          label: 'Pagamento Seguro',
          note: 'Barra transparente com botão voltar customizado',
        ),
        const ScreenMaterialItem(
          id: 'mat_pix_btn',
          type: ScreenMaterialType.primaryButton,
          label: 'Gerar QR Code Pix',
          note: 'Gera Pix dinâmico com countdown de 15 minutos e botão copiar código',
        ),
        const ScreenMaterialItem(
          id: 'mat_subtitle',
          type: ScreenMaterialType.subtitleText,
          label: 'Total a pagar: R\$ 249,90',
        ),
      ];

      final prompt = ScreenMaterialCodeUpdater.generateAiEnhancePrompt(
        testNode,
        materials,
        existingRoutes: existingRoutes,
        preset: PresetType.saas,
      );

      // Assert basic route and architecture context
      expect(prompt, contains('/checkout'));
      expect(prompt, contains('CheckoutScreen'));
      expect(prompt, contains('Finalização do Pedido'));
      expect(prompt, contains('SaaS'));
      expect(prompt, contains('AuthGuard ativado'));

      // Assert navigation graph injection
      expect(prompt, contains('### App Navigation Graph & Available Routes:'));
      expect(prompt, contains('HomeScreen ("/home")'));
      expect(prompt, contains('ProfileScreen ("/profile") [Protegida]'));
      expect(prompt, contains('context.go() ou context.push()'));

      // Assert user notes per component injection
      expect(prompt, contains('### User Component Notes & Behavioral Prompts:'));
      expect(prompt, contains("- Component: Pagamento Seguro -> User Note: 'Barra transparente com botão voltar customizado'"));
      expect(prompt, contains("- Component: Gerar QR Code Pix -> User Note: 'Gera Pix dinâmico com countdown de 15 minutos e botão copiar código'"));

      // Subtitle without note should not appear in User Component Notes section
      expect(prompt, isNot(contains("- Component: Total a pagar: R\$ 249,90 -> User Note:")));
    });
  });

  group('3. generateWidgetSpecificPrompt Focused Single Component', () {
    test('generateWidgetSpecificPrompt produces focused snippet prompt without full scaffold', () {
      const targetMaterial = ScreenMaterialItem(
        id: 'mat_card_metrics',
        type: ScreenMaterialType.containerCard,
        label: 'Card de Resumo Financeiro',
        note: 'Gráfico em linha mini sparkline animado com percentual de crescimento em verde neon',
      );

      final prompt = ScreenMaterialCodeUpdater.generateWidgetSpecificPrompt(
        targetMaterial,
        routeNode: testNode,
        existingRoutes: existingRoutes,
        preset: PresetType.saas,
      );

      expect(prompt, contains('Gere um widget Flutter completo, reativo e elegante'));
      expect(prompt, contains('Card de Resumo Financeiro'));
      expect(prompt, contains('Glass Card'));
      expect(prompt, contains('Contexto da Tela: Rota "/checkout" (CheckoutScreen)'));
      expect(prompt, contains('Arquitetura do Projeto: SaaS'));
      expect(prompt, contains('### Instrução Comportamental do Usuário (Nota Específica):'));
      expect(prompt, contains('Gráfico em linha mini sparkline animado com percentual de crescimento em verde neon'));
      expect(prompt, contains('Requisitos do Widget:'));
      expect(prompt, contains('Obsidian Glass Design System'));
      expect(prompt, contains('Auto-contido: Deve ser um widget pronto para ser embutido'));
    });
  });

  group('4. AiScreenGeneratorDialog Plan Status, Credits, and Single-Widget Mode', () {
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

    testWidgets('Displays current plan and available credits for Pro Cloud', (tester) async {
      const proUser = UserAccount(
        uid: 'user_pro_verifier',
        email: 'verifier@flrd.dev',
        displayName: 'Verifier Pro',
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
      );

      final sessionFile =
          '${tempDir.path}${Platform.pathSeparator}session_verifier_${DateTime.now().microsecondsSinceEpoch}.json';
      final mockAuthService = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AiScreenGeneratorDialog.show(context, dummyProject),
              child: const Text('Open Generator'),
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

      await tester.tap(find.text('Open Generator'));
      await tester.pumpAndSettle();

      expect(find.text('⭐ FLRD Studio Pro'), findsOneWidget);
      expect(find.text('⚡ 185 / 200 Créditos Disponíveis'), findsOneWidget);
      expect(find.text('⚡ Gerenciar Plano / Inscrição'), findsOneWidget);
    });

    testWidgets('Shows "Gerenciar Plano / Inscrição" button opening settings', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AiScreenGeneratorDialog.show(context, dummyProject),
              child: const Text('Open Generator'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Generator'));
      await tester.pumpAndSettle();

      final manageBtn = find.text('⚡ Gerenciar Plano / Inscrição');
      expect(manageBtn, findsOneWidget);
      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsAndBillingDialog), findsOneWidget);
    });

    testWidgets('Consumes 1 credit on Pro Cloud generation', (tester) async {
      const proUser = UserAccount(
        uid: 'user_pro_charge',
        email: 'charge@flrd.dev',
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
      );

      final sessionFile =
          '${tempDir.path}${Platform.pathSeparator}session_charge_${DateTime.now().microsecondsSinceEpoch}.json';
      final mockAuthService = FirebaseAuthService(
        sessionFilePath: sessionFile,
        mockMode: true,
      );

      late AuthNotifier authNotifier;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AiScreenGeneratorDialog.show(context, dummyProject),
              child: const Text('Open Generator'),
            ),
          ),
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
        ),
      );

      await tester.tap(find.text('Open Generator'));
      await tester.pumpAndSettle();

      expect(authNotifier.state.creditsRemaining, equals(185));

      final generateBtn = find.text('Gerar e Injetar Tela');
      await tester.ensureVisible(generateBtn);
      await tester.tap(generateBtn);
      await tester.pump();

      expect(authNotifier.state.creditsRemaining, equals(184));
    });

    testWidgets('Supports single-widget generation mode (targetMaterial)', (tester) async {
      const material = ScreenMaterialItem(
        id: 'mat_single_widget',
        type: ScreenMaterialType.switchTile,
        label: 'Notificações Push',
        note: 'Switch com som suave ao alternar e salvamento local no SharedPreferences',
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AiScreenGeneratorDialog.show(
                context,
                dummyProject,
                targetMaterial: material,
              ),
              child: const Text('Open Widget Generator'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Widget Generator'));
      await tester.pumpAndSettle();

      // Verify title switches to target material name
      expect(find.text('Refinar Widget com IA: Notificações Push'), findsOneWidget);

      // Verify action button changes to widget refinement
      expect(find.text('✨ Refinar e Injetar Widget'), findsOneWidget);

      // Verify prompt contains note and target material
      final textField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && (w.maxLines == 4),
        ),
      );
      expect(textField.controller?.text, contains('Notificações Push'));
      expect(textField.controller?.text, contains('SharedPreferences'));
    });
  });

  group('5. ScreenMaterialsBuilder Note Workflow & Focused AI Refinement', () {
    testWidgets('Adding, editing, and clearing a note on a material', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ScreenMaterialsBuilder(
                    node: testNode,
                    project: dummyProject,
                    currentCode: currentCode,
                    onCodeChanged: (newCode) => setState(() => currentCode = newCode),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial note button exists
      final noteButton = find.byKey(const ValueKey('material_note_button_0'));
      expect(noteButton, findsOneWidget);

      // 2. Open note dialog
      await tester.tap(noteButton);
      await tester.pumpAndSettle();

      expect(find.text('Anotação / Prompt do Widget'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('material_note_text_field')),
        'Campo com máscara de cupom e validação assíncrona',
      );
      await tester.pumpAndSettle();

      // 3. Save note
      await tester.tap(find.byKey(const ValueKey('material_note_dialog_save')));
      await tester.pumpAndSettle();

      // 4. Assert note card and text
      expect(find.byKey(const ValueKey('material_note_card_0')), findsOneWidget);
      expect(find.text('"Campo com máscara de cupom e validação assíncrona"'), findsOneWidget);

      // 5. Assert Refine AI button is visible
      expect(find.byKey(const ValueKey('material_ai_refine_0')), findsOneWidget);

      // 6. Edit note
      await tester.tap(find.byKey(const ValueKey('material_note_edit_0')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('material_note_text_field')),
        'Nota editada com foco automático',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('material_note_dialog_save')));
      await tester.pumpAndSettle();

      expect(find.text('"Nota editada com foco automático"'), findsOneWidget);

      // 7. Clear note
      await tester.tap(find.byKey(const ValueKey('material_note_clear_0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('material_note_card_0')), findsNothing);
      expect(find.byKey(const ValueKey('material_note_button_0')), findsOneWidget);
    });

    testWidgets('Clicking [✨ Refinar este Widget com IA] triggers focused dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String currentCode = sampleDartCode;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScreenMaterialsBuilder(
                  node: testNode,
                  project: dummyProject,
                  currentCode: currentCode,
                  onCodeChanged: (newCode) => currentCode = newCode,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Add a note to the material to expose [✨ Refinar este Widget com IA]
      await tester.tap(find.byKey(const ValueKey('material_note_button_0')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('material_note_text_field')),
        'Botão com shimmer e gradiente roxo',
      );
      await tester.tap(find.byKey(const ValueKey('material_note_dialog_save')));
      await tester.pumpAndSettle();

      // Tap [✨ Refinar este Widget com IA]
      final refineBtn = find.byKey(const ValueKey('material_ai_refine_0'));
      expect(refineBtn, findsOneWidget);
      await tester.tap(refineBtn);
      await tester.pumpAndSettle();

      // Verify that AiScreenGeneratorDialog opens in widget mode
      expect(find.byType(AiScreenGeneratorDialog), findsOneWidget);
      expect(find.textContaining('Refinar Widget com IA:'), findsOneWidget);
      expect(find.text('✨ Refinar e Injetar Widget'), findsOneWidget);
    });
  });
}
