import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flrd/features/hub/presentation/hub_screen.dart';
import 'package:flrd/features/projects/presentation/widgets/import_project_dialog.dart';

void main() {
  group('ImportProjectDialog Tests', () {
    testWidgets('Renders ImportProjectDialog with path input and shortcut chips',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ImportProjectDialog(),
            ),
          ),
        ),
      );

      // Verify header and description
      expect(find.text('Importar Projeto Existente'), findsOneWidget);
      expect(find.text('Caminho do Projeto'), findsOneWidget);
      expect(find.text('Atalhos rápidos:'), findsOneWidget);

      // Verify shortcut chips exist
      expect(find.text('C:/Projects'), findsWidgets);
      expect(find.text('Desktop'), findsOneWidget);
      expect(find.text('FLRD Workspace'), findsOneWidget);

      // Verify action buttons
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Analisar e Importar'), findsOneWidget);

      // Tap on Desktop shortcut chip
      await tester.tap(find.text('Desktop'));
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text.contains('Desktop'), isTrue);
    });

    testWidgets('HubScreen renders Importar Projeto button and triggers dialog',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find and scroll to the import button
      final importButton = find.text('Import Project');
      await tester.scrollUntilVisible(
        importButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(importButton, findsOneWidget);

      // Tap the import button
      await tester.tap(importButton);
      await tester.pumpAndSettle();

      // Verify that dialog appeared
      expect(find.byType(ImportProjectDialog), findsOneWidget);
      expect(find.text('Importar Projeto Existente'), findsOneWidget);
    });
  });
}
