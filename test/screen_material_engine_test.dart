import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main() {
  group('ScreenMaterial domain model & palette', () {
    test('availableMaterialPalette contains all supported material types', () {
      expect(availableMaterialPalette.isNotEmpty, isTrue);
      expect(availableMaterialPalette.length, 12);

      final types = availableMaterialPalette.map((m) => m.type).toSet();
      expect(types.contains(ScreenMaterialType.appBar), isTrue);
      expect(types.contains(ScreenMaterialType.headerText), isTrue);
      expect(types.contains(ScreenMaterialType.subtitleText), isTrue);
      expect(types.contains(ScreenMaterialType.textInput), isTrue);
      expect(types.contains(ScreenMaterialType.passwordInput), isTrue);
      expect(types.contains(ScreenMaterialType.primaryButton), isTrue);
      expect(types.contains(ScreenMaterialType.secondaryButton), isTrue);
      expect(types.contains(ScreenMaterialType.socialButton), isTrue);
      expect(types.contains(ScreenMaterialType.containerCard), isTrue);
      expect(types.contains(ScreenMaterialType.icon), isTrue);
      expect(types.contains(ScreenMaterialType.switchTile), isTrue);
      expect(types.contains(ScreenMaterialType.checkboxTile), isTrue);
    });

    test('ScreenMaterialType properties are defined', () {
      for (final type in ScreenMaterialType.values) {
        expect(type.displayName.isNotEmpty, isTrue);
        expect(type.shortChipLabel.isNotEmpty, isTrue);
        expect(type.defaultIcon, isNotNull);
        expect(type.accentColor, isNotNull);
      }
    });

    test('ScreenMaterialItem createInstance produces unique ID', () {
      final template = availableMaterialPalette.first;
      final instance1 = template.createInstance();
      final instance2 = template.createInstance();

      expect(instance1.id, isNot(equals(template.id)));
      expect(instance1.id, isNot(equals(instance2.id)));
      expect(instance1.type, template.type);
      expect(instance1.label, template.label);
    });
  });

  group('ScreenMaterialCodeUpdater & ScreenMaterialParser', () {
    const sampleDartCode = '''
import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF090D16);
  static const Color primary = Color(0xFF6366F1);
}

class TestLoginScreen extends StatelessWidget {
  const TestLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrar na Conta'),
        leading: const Icon(Icons.arrow_back),
      ),
      body: Column(
        children: [
          Text(
            'Bem-vindo de volta!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            'Digite suas credenciais',
            style: TextStyle(fontSize: 14),
          ),
          TextField(
            decoration: InputDecoration(
              labelText: 'Seu E-mail',
              hintText: 'user@email.com',
              prefixIcon: Icon(Icons.email),
            ),
          ),
          TextField(
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Sua Senha',
              prefixIcon: Icon(Icons.lock),
            ),
          ),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Fazer Login'),
          ),
          OutlinedButton(
            onPressed: () {},
            child: const Text('Criar Nova Conta'),
          ),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.g_mobiledata),
            label: const Text('Entrar com Google'),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black,
            ),
            child: const Text('Info Card'),
          ),
          Icon(Icons.star),
          SwitchListTile(
            title: const Text('Salvar sessão'),
            value: true,
            onChanged: (v) {},
          ),
          CheckboxListTile(
            title: const Text('Li e aceito os termos'),
            value: true,
            onChanged: (v) {},
          ),
        ],
      ),
    );
  }
}
''';

    test('extractMaterialsFromCode parses all widgets in order', () {
      final materials = ScreenMaterialParser.extractMaterialsFromCode(
        sampleDartCode,
        'TestLoginScreen',
      );

      expect(materials.length, 12);
      expect(materials[0].type, ScreenMaterialType.appBar);
      expect(materials[0].label, 'Entrar na Conta');

      expect(materials[1].type, ScreenMaterialType.headerText);
      expect(materials[1].label, 'Bem-vindo de volta!');

      expect(materials[2].type, ScreenMaterialType.subtitleText);
      expect(materials[2].label, 'Digite suas credenciais');

      expect(materials[3].type, ScreenMaterialType.textInput);
      expect(materials[3].label, 'Seu E-mail');
      expect(materials[3].hint, 'user@email.com');

      expect(materials[4].type, ScreenMaterialType.passwordInput);
      expect(materials[4].label, 'Sua Senha');
      expect(materials[4].isPassword, isTrue);

      expect(materials[5].type, ScreenMaterialType.primaryButton);
      expect(materials[5].label, 'Fazer Login');

      expect(materials[6].type, ScreenMaterialType.secondaryButton);
      expect(materials[6].label, 'Criar Nova Conta');

      expect(materials[7].type, ScreenMaterialType.socialButton);
      expect(materials[7].label, 'Entrar com Google');

      expect(materials[8].type, ScreenMaterialType.containerCard);

      expect(materials[9].type, ScreenMaterialType.icon);

      expect(materials[10].type, ScreenMaterialType.switchTile);

      expect(materials[11].type, ScreenMaterialType.checkboxTile);
    });

    test('buildDartCodeFromMaterials generates valid Flutter code and roundtrips', () {
      final initialMaterials = [
        const ScreenMaterialItem(
          id: 'appBar_0',
          type: ScreenMaterialType.appBar,
          label: 'Checkout',
        ),
        const ScreenMaterialItem(
          id: 'header_1',
          type: ScreenMaterialType.headerText,
          label: 'Pagamento Seguro',
        ),
        const ScreenMaterialItem(
          id: 'btn_2',
          type: ScreenMaterialType.primaryButton,
          label: 'Pagar Agora',
        ),
      ];

      final generatedCode = ScreenMaterialCodeUpdater.buildDartCodeFromMaterials(
        screenClassName: 'CheckoutScreen',
        routePath: '/checkout',
        materials: initialMaterials,
        isProtected: true,
      );

      expect(generatedCode, contains('class CheckoutScreen extends StatefulWidget'));
      expect(generatedCode, contains('class AppColors'));
      expect(generatedCode, contains('Pagamento Seguro'));
      expect(generatedCode, contains('Pagar Agora'));

      final reParsed = ScreenMaterialParser.extractMaterialsFromCode(generatedCode);
      expect(reParsed.length, 3);
      expect(reParsed[0].type, ScreenMaterialType.appBar);
      expect(reParsed[0].label, 'Checkout');
      expect(reParsed[1].type, ScreenMaterialType.headerText);
      expect(reParsed[1].label, 'Pagamento Seguro');
      expect(reParsed[2].type, ScreenMaterialType.primaryButton);
      expect(reParsed[2].label, 'Pagar Agora');
    });

    test('addMaterialToCode appends or inserts new material', () {
      final baseCode = ScreenMaterialCodeUpdater.buildDartCodeFromMaterials(
        screenClassName: 'MyProfileScreen',
        routePath: '/profile',
        materials: [
          const ScreenMaterialItem(
            id: 'appBar_0',
            type: ScreenMaterialType.appBar,
            label: 'Meu Perfil',
          ),
        ],
      );

      final withInput = ScreenMaterialCodeUpdater.addMaterialToCode(
        currentCode: baseCode,
        newMaterial: const ScreenMaterialItem(
          id: 'input_1',
          type: ScreenMaterialType.textInput,
          label: 'Nome Completo',
          hint: 'João Silva',
        ),
      );

      final materials = ScreenMaterialParser.extractMaterialsFromCode(withInput);
      expect(materials.length, 2);
      expect(materials[0].type, ScreenMaterialType.appBar);
      expect(materials[1].type, ScreenMaterialType.textInput);
      expect(materials[1].label, 'Nome Completo');
    });

    test('removeMaterialFromCode removes material by id', () {
      final baseCode = ScreenMaterialCodeUpdater.buildDartCodeFromMaterials(
        screenClassName: 'SettingsScreen',
        routePath: '/settings',
        materials: [
          const ScreenMaterialItem(
            id: 'appBar_0',
            type: ScreenMaterialType.appBar,
            label: 'Configurações',
          ),
          const ScreenMaterialItem(
            id: 'switch_1',
            type: ScreenMaterialType.switchTile,
            label: 'Modo Escuro',
          ),
          const ScreenMaterialItem(
            id: 'btn_2',
            type: ScreenMaterialType.primaryButton,
            label: 'Salvar',
          ),
        ],
      );

      final withoutSwitch = ScreenMaterialCodeUpdater.removeMaterialFromCode(
        currentCode: baseCode,
        materialId: 'switchTile_1',
      );

      final materials = ScreenMaterialParser.extractMaterialsFromCode(withoutSwitch);
      expect(materials.length, 2);
      expect(materials.any((m) => m.type == ScreenMaterialType.switchTile), isFalse);
      expect(materials[0].type, ScreenMaterialType.appBar);
      expect(materials[1].type, ScreenMaterialType.primaryButton);
    });

    test('reorderMaterialsInCode swaps order of materials', () {
      final baseCode = ScreenMaterialCodeUpdater.buildDartCodeFromMaterials(
        screenClassName: 'DemoScreen',
        routePath: '/demo',
        materials: [
          const ScreenMaterialItem(
            id: 'head_0',
            type: ScreenMaterialType.headerText,
            label: 'Topo',
          ),
          const ScreenMaterialItem(
            id: 'sub_1',
            type: ScreenMaterialType.subtitleText,
            label: 'Meio',
          ),
          const ScreenMaterialItem(
            id: 'btn_2',
            type: ScreenMaterialType.primaryButton,
            label: 'Fim',
          ),
        ],
      );

      // Move Fim (index 2) to Top (index 0)
      final reordered = ScreenMaterialCodeUpdater.reorderMaterialsInCode(
        currentCode: baseCode,
        oldIndex: 2,
        newIndex: 0,
      );

      final materials = ScreenMaterialParser.extractMaterialsFromCode(reordered);
      expect(materials.length, 3);
      expect(materials[0].type, ScreenMaterialType.primaryButton);
      expect(materials[0].label, 'Fim');
      expect(materials[1].type, ScreenMaterialType.headerText);
      expect(materials[1].label, 'Topo');
      expect(materials[2].type, ScreenMaterialType.subtitleText);
      expect(materials[2].label, 'Meio');
    });

    test('generateAiEnhancePrompt builds detailed actionable prompt', () {
      const node = RouteNode(
        id: 'checkout',
        path: '/checkout',
        title: 'Finalizar Pedido',
        subtitle: 'Revisão de itens e pagamento',
        icon: Icons.shopping_bag_rounded,
        position: Offset.zero,
        filePath: 'lib/screens/checkout.dart',
        isProtected: true,
        requiredPermissions: [DevicePermission.camera, DevicePermission.notifications],
      );

      final materials = [
        const ScreenMaterialItem(
          id: '1',
          type: ScreenMaterialType.appBar,
          label: 'Revisão do Pedido',
        ),
        const ScreenMaterialItem(
          id: '2',
          type: ScreenMaterialType.headerText,
          label: 'Total a Pagar',
        ),
        const ScreenMaterialItem(
          id: '3',
          type: ScreenMaterialType.primaryButton,
          label: 'Confirmar Pagamento',
        ),
      ];

      final prompt = ScreenMaterialCodeUpdater.generateAiEnhancePrompt(node, materials);
      expect(prompt, contains('/checkout'));
      expect(prompt, contains('Finalizar Pedido'));
      expect(prompt, contains('AuthGuard ativado'));
      expect(prompt, contains('Camera'));
      expect(prompt, contains('Revisão do Pedido'));
      expect(prompt, contains('Total a Pagar'));
      expect(prompt, contains('Confirmar Pagamento'));
      expect(prompt, contains('Obsidian Glass'));
    });
  });
}
