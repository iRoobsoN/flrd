import 'dart:math' as math;

import 'package:flrd/core/theme/app_colors.dart';
import 'package:flrd/core/theme/app_theme.dart';
import 'package:flrd/core/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _relativeLuminance(Color c) {
  double linearize(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * linearize(c.r) +
      0.7152 * linearize(c.g) +
      0.0722 * linearize(c.b);
}

double _contrastRatio(Color a, Color b) {
  final l1 = _relativeLuminance(a);
  final l2 = _relativeLuminance(b);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

ThemeData _testDarkTheme() => ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: AppTheme.darkColorScheme,
      snackBarTheme: AppTheme.darkSnackBarTheme,
    );

void main() {
  group('AppTheme SnackBar Contrast', () {
    test('darkTheme tokens guarantee high-contrast inverseSurface and snackBarTheme', () {
      expect(AppTheme.darkColorScheme.inverseSurface, AppColors.surfaceSelected);
      expect(AppTheme.darkColorScheme.onInverseSurface, AppColors.textPrimary);
      expect(AppTheme.darkSnackBarTheme.backgroundColor, AppColors.surfaceSelected);
      expect(AppTheme.darkSnackBarTheme.contentTextStyle?.color, AppColors.textPrimary);

      final themeRatio = _contrastRatio(
        AppTheme.darkColorScheme.onInverseSurface,
        AppTheme.darkColorScheme.inverseSurface,
      );
      expect(themeRatio, greaterThan(10.0));

      final toastCardRatio = _contrastRatio(
        AppColors.textPrimary,
        const Color(0xFF131B2E),
      );
      expect(toastCardRatio, greaterThan(13.0));
    });

    testWidgets('plain SnackBar without explicit style inherits high-contrast text color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _testDarkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.surfaceCard,
                      content: Text('Mensagem legível padrão'),
                    ),
                  );
                },
                child: const Text('Show Raw SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Raw SnackBar'));
      await tester.pumpAndSettle();

      final snackBarTheme = Theme.of(tester.element(find.text('Mensagem legível padrão'))).snackBarTheme;
      expect(snackBarTheme.contentTextStyle?.color, AppColors.textPrimary);

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == 'Mensagem legível padrão',
          ),
        ),
      );
      expect(richText.text.style?.color, AppColors.textPrimary);
    });
  });

  group('AppToast Desktop Notification', () {
    testWidgets('renders high-contrast card in Scaffold and closes via button', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: _testDarkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => AppToast.warning(
                      context,
                      'Aviso legível para desktop',
                    ),
                    child: const Text('Trigger Warning'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Warning'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byKey(const ValueKey('app_toast_card')), findsOneWidget);
      expect(find.text('Aviso legível para desktop'), findsOneWidget);

      final textWidget = tester.widget<Text>(find.text('Aviso legível para desktop'));
      expect(textWidget.style?.color, AppColors.textPrimary);

      final cardContainer = tester.widget<Container>(
        find.byKey(const ValueKey('app_toast_card')),
      );
      final decoration = cardContainer.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF131B2E));

      // Card width is constrained on wide PC screens instead of spanning 1440px.
      final cardSize = tester.getSize(find.byKey(const ValueKey('app_toast_card')));
      expect(cardSize.width, lessThanOrEqualTo(560));

      // Dismiss manually via close button.
      await tester.tap(find.byKey(const ValueKey('app_toast_close_button')));
      await tester.pumpAndSettle();
      expect(find.text('Aviso legível para desktop'), findsNothing);
    });

    testWidgets('promotes toast above modal barrier when triggered inside showDialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: _testDarkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => Dialog(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Modal Aberto'),
                          ElevatedButton(
                            onPressed: () => AppToast.success(
                              dialogContext,
                              'Ação concluída dentro do modal!',
                              duration: const Duration(seconds: 2),
                            ),
                            child: const Text('Disparar Aviso'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('Abrir Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal'));
      await tester.pumpAndSettle();
      expect(find.text('Modal Aberto'), findsOneWidget);

      await tester.tap(find.text('Disparar Aviso'));
      await tester.pump();

      expect(find.byKey(const ValueKey('app_toast_card')), findsOneWidget);
      expect(find.text('Ação concluída dentro do modal!'), findsOneWidget);

      // Clicking close button dismisses toast without closing the underlying modal.
      await tester.tap(find.byKey(const ValueKey('app_toast_close_button')));
      await tester.pump();

      expect(find.text('Ação concluída dentro do modal!'), findsNothing);
      expect(find.text('Modal Aberto'), findsOneWidget);
    });
  });
}
