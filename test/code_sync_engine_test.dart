import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/widgets/device_screen_emulator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1200, 950),
  }) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    );
  }

  const sampleSplashAuthCode = '''
import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF090D16);
  static const Color surface = Color(0xFF111726);
  static const Color surfaceCard = Color(0xFF141B2D);
  static const Color border = Color(0x1FFFFFFF);
  static const Color primary = Color(0xFF6366F1);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
}

class SplashAuthGuard extends StatelessWidget {
  const SplashAuthGuard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Splash & AuthGuard',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.widgets_rounded, color: AppColors.primary, size: 48),
              SizedBox(height: 16),
              Text(
                'Splash & AuthGuard Screen',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Tela gerada pelo FLRD Studio.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''';

  const sampleComplexFormCode = '''
import 'package:flutter/material.dart';

class FormDemoScreen extends StatelessWidget {
  const FormDemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('Account Setup'),
        backgroundColor: Color(0xFF1E293B),
      ),
      body: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              labelText: 'Full Name',
              hintText: 'Enter your name',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          TextField(
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Secret Password',
              prefixIcon: Icon(Icons.lock),
            ),
          ),
          ElevatedButton(
            onPressed: () {},
            child: Text('Create Account'),
          ),
          OutlinedButton(
            onPressed: () {},
            child: Text('Cancel Registration'),
          ),
          TextButton(
            onPressed: () {},
            child: Text('Help & FAQ'),
          ),
        ],
      ),
    );
  }
}
''';

  group('DeviceScreenEmulator - Dynamic Code-Driven Rendering', () {
    const node = RouteNode(
      id: 'root',
      path: '/',
      title: 'Splash & AuthGuard',
      subtitle: 'Redirection via GoRouter',
      icon: Icons.alt_route_rounded,
      position: Offset.zero,
      filePath: 'lib/router.dart',
    );

    testWidgets(
        'Renders exact AppBar title and container text matching Dart code instead of archetype mock',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: node,
            sourceCode: sampleSplashAuthCode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Matches AppBar title from sourceCode
      expect(find.text('Splash & AuthGuard'), findsOneWidget);

      // 2. Matches Container body text from sourceCode
      expect(find.text('Splash & AuthGuard Screen'), findsOneWidget);
      expect(find.text('Tela gerada pelo FLRD Studio.'), findsOneWidget);

      // 3. Matches Icon from sourceCode
      expect(find.byIcon(Icons.widgets_rounded), findsWidgets);

      // 4. Does NOT render unrelated archetype mock content!
      expect(find.text('FLRD Studio'), findsNothing);
      expect(find.text('GoRouter AuthGuard Pipeline'), findsNothing);
      expect(find.text('Simulate Launch Transition'), findsNothing);
    });

    testWidgets(
        'Extracts buttons (ElevatedButton, OutlinedButton, TextButton), inputs (TextField), and cards',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: node,
            sourceCode: sampleComplexFormCode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar
      expect(find.text('Account Setup'), findsOneWidget);

      // Inputs
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Secret Password'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));

      // Buttons
      expect(find.widgetWithText(ElevatedButton, 'Create Account'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel Registration'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Help & FAQ'), findsOneWidget);
    });

    testWidgets(
        'Toggle pill [⚡ Code Live Sync] / [🎨 Archetype Mock] switches between code view and archetype mock',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: node,
            sourceCode: sampleSplashAuthCode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both toggle options are present
      expect(find.text('⚡ Code Live Sync'), findsOneWidget);
      expect(find.text('🎨 Archetype Mock'), findsOneWidget);

      // Defaults to Code Live Sync: rendered from code
      expect(find.text('Splash & AuthGuard Screen'), findsOneWidget);
      expect(find.text('FLRD Studio'), findsNothing);

      // Tap Archetype Mock toggle
      await tester.tap(find.text('🎨 Archetype Mock'));
      await tester.pumpAndSettle();

      // Now renders Archetype Mock!
      expect(find.text('FLRD Studio'), findsOneWidget);
      expect(find.text('GoRouter AuthGuard Pipeline'), findsOneWidget);
      expect(find.text('Simulate Launch Transition'), findsOneWidget);

      // Tap back to Code Live Sync
      await tester.tap(find.text('⚡ Code Live Sync'));
      await tester.pumpAndSettle();

      // Renders from code again
      expect(find.text('Splash & AuthGuard Screen'), findsOneWidget);
      expect(find.text('FLRD Studio'), findsNothing);
    });

    testWidgets(
        'Preserves phone chassis, Dark/Light toggle, scale presets, and Pixel/iPhone frames',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          tester,
          const DeviceScreenEmulator(
            node: node,
            sourceCode: sampleSplashAuthCode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Phone chassis and Status bar
      expect(find.text('9:41'), findsOneWidget);
      expect(find.text('5G'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);

      // 2. Dark/Light toggle
      expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.dark_mode_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);

      // 3. Scale presets
      expect(find.text('Fit'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // 4. Pixel 8 frame switch
      await tester.tap(find.text('iPhone 15 Pro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pixel 8').last);
      await tester.pumpAndSettle();

      // Pixel 8 features
      expect(find.text('94%'), findsOneWidget);
      expect(find.byIcon(Icons.signal_cellular_4_bar_rounded), findsOneWidget);

      // Code rendering still intact in Pixel 8!
      expect(find.text('Splash & AuthGuard Screen'), findsOneWidget);
    });
  });

  group('DartCodeScreenParser - Unit Tests', () {
    test('extracts Scaffold background, AppBar, icons, text, container, and color tokens', () {
      final parsed = DartCodeScreenParser.parse(sampleSplashAuthCode, isDarkMode: true);

      expect(parsed.scaffoldBackgroundColor, const Color(0xFF090D16));
      expect(parsed.appBar, isNotNull);
      expect(parsed.appBar!.title, 'Splash & AuthGuard');
      expect(parsed.appBar!.backgroundColor, const Color(0xFF111726));
      expect(parsed.isCentered, isTrue);

      expect(parsed.mainCard, isNotNull);
      expect(parsed.mainCard!.backgroundColor, const Color(0xFF141B2D));
      expect(parsed.mainCard!.borderRadius, 16.0);
      expect(parsed.mainCard!.children.length, greaterThanOrEqualTo(3));

      final iconNode = parsed.mainCard!.children.whereType<ParsedIconNode>().first;
      expect(iconNode.icon, Icons.widgets_rounded);
      expect(iconNode.size, 48.0);

      final textNodes = parsed.mainCard!.children.whereType<ParsedTextNode>().toList();
      expect(textNodes.any((t) => t.text == 'Splash & AuthGuard Screen'), isTrue);
      expect(textNodes.any((t) => t.text == 'Tela gerada pelo FLRD Studio.'), isTrue);
    });

    test('extracts buttons and textfields with labels and prefix icons', () {
      final parsed = DartCodeScreenParser.parse(sampleComplexFormCode, isDarkMode: true);

      expect(parsed.appBar!.title, 'Account Setup');
      expect(parsed.appBar!.backgroundColor, const Color(0xFF1E293B));

      final inputs = parsed.bodyWidgets.whereType<ParsedInputNode>().toList();
      expect(inputs.length, 2);
      expect(inputs[0].labelText, 'Full Name');
      expect(inputs[0].prefixIcon, Icons.person_rounded);
      expect(inputs[1].labelText, 'Secret Password');
      expect(inputs[1].prefixIcon, Icons.lock_rounded);
      expect(inputs[1].obscureText, isTrue);

      final buttons = parsed.bodyWidgets.whereType<ParsedButtonNode>().toList();
      expect(buttons.length, 3);
      expect(buttons[0].label, 'Create Account');
      expect(buttons[0].type, ParsedButtonType.elevated);
      expect(buttons[1].label, 'Cancel Registration');
      expect(buttons[1].type, ParsedButtonType.outlined);
      expect(buttons[2].label, 'Help & FAQ');
      expect(buttons[2].type, ParsedButtonType.text);
    });
  });
}
