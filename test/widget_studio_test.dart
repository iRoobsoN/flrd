import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flrd/features/ai/services/gemini_ai_service.dart';
import 'package:flrd/features/studio/domain/screen_material.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testNode = RouteNode(
    id: 'profile_dashboard',
    title: 'ProfileDashboardScreen',
    subtitle: 'Painel do Usuário',
    path: '/profile',
    filePath: 'lib/features/profile/profile_screen.dart',
    position: Offset(100, 100),
    isProtected: false,
    icon: Icons.person_outline_rounded,
  );

  const sampleScreenCode = '''import 'package:flutter/material.dart';

class ProfileDashboardScreen extends StatelessWidget {
  const ProfileDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Área Pessoal'),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
''';

  group('WidgetVariation Model Tests', () {
    test('creation, field access, equality, hashCode and copyWith', () {
      const variation1 = WidgetVariation(
        id: 'var_test_1',
        title: 'Glassmorphism Profile Card',
        styleTag: 'Glassmorphism Oval',
        description: 'Card translúcido com CircleAvatar em glow border.',
        dartCode: 'Container(child: CircleAvatar())',
        icon: Icons.account_circle_rounded,
        techApproach: 'CircleAvatar + Glow + Row',
      );

      const variation2 = WidgetVariation(
        id: 'var_test_1',
        title: 'Glassmorphism Profile Card',
        styleTag: 'Glassmorphism Oval',
        description: 'Card translúcido com CircleAvatar em glow border.',
        dartCode: 'Container(child: CircleAvatar())',
        icon: Icons.account_circle_rounded,
        techApproach: 'CircleAvatar + Glow + Row',
      );

      expect(variation1.id, 'var_test_1');
      expect(variation1.title, 'Glassmorphism Profile Card');
      expect(variation1.styleTag, 'Glassmorphism Oval');
      expect(variation1.description, contains('CircleAvatar em glow'));
      expect(variation1.dartCode, contains('CircleAvatar'));
      expect(variation1.icon, Icons.account_circle_rounded);
      expect(variation1.techApproach, 'CircleAvatar + Glow + Row');

      // Equality and hashcode
      expect(variation1, equals(variation2));
      expect(variation1.hashCode, equals(variation2.hashCode));

      // copyWith
      final updated = variation1.copyWith(
        title: 'Updated Title',
        styleTag: 'Updated Tag',
      );
      expect(updated.title, 'Updated Title');
      expect(updated.styleTag, 'Updated Tag');
      expect(updated.id, variation1.id);
      expect(updated.techApproach, variation1.techApproach);
      expect(updated == variation1, isFalse);

      // Serialization
      final jsonMap = variation1.toJson();
      expect(jsonMap['id'], 'var_test_1');
      expect(jsonMap['styleTag'], 'Glassmorphism Oval');
      expect(jsonMap['techApproach'], 'CircleAvatar + Glow + Row');

      final fromJson = WidgetVariation.fromJson(jsonMap, icon: Icons.account_circle_rounded);
      expect(fromJson, equals(variation1));

      // toString
      expect(variation1.toString(), contains('var_test_1'));
      expect(variation1.toString(), contains('Glassmorphism Oval'));
    });
  });

  group('GeminiAiService.synthesizeWidgetVariations Tests', () {
    test('generates 3 distinct variations for profile/photo/welcome prompt', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'caixinha com foto de perfil e bem vindo',
        preset: PresetType.cleanLite,
        routeNode: testNode,
      );

      expect(variations.length, 3);

      // Variation 1: Glassmorphism / CircleAvatar / oval glow
      final var1 = variations[0];
      expect(var1.styleTag, contains('Glassmorphism'));
      expect(var1.techApproach, contains('CircleAvatar'));
      expect(var1.techApproach, contains('Glow'));
      expect(var1.dartCode, contains('CircleAvatar'));
      expect(var1.dartCode, contains('BoxDecoration'));
      expect(var1.dartCode, contains('BoxShadow'));

      // Variation 2: Bento Grid / ClipRRect / status indicator
      final var2 = variations[1];
      expect(var2.styleTag, contains('Bento Grid'));
      expect(var2.techApproach, contains('ClipRRect'));
      expect(var2.techApproach, contains('Bento Grid'));
      expect(var2.dartCode, contains('ClipRRect'));
      expect(var2.dartCode, contains('Online agora'));

      // Variation 3: Hero Banner / Gradient / Action button
      final var3 = variations[2];
      expect(var3.styleTag, contains('Hero Banner'));
      expect(var3.techApproach, contains('Gradient'));
      expect(var3.techApproach, contains('Action Button'));
      expect(var3.dartCode, contains('LinearGradient'));
      expect(var3.dartCode, contains('ElevatedButton'));
    });

    test('generates 3 distinct variations for payment prompts', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'Seletor de Pagamento Pix com QR Code',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations[0].styleTag, contains('Glassmorphism'));
      expect(variations[0].dartCode, contains('Icons.pix_rounded'));

      expect(variations[1].styleTag, contains('Bento Grid'));
      expect(variations[1].dartCode, contains('QR Code'));

      expect(variations[2].styleTag, contains('Hero'));
      expect(variations[2].dartCode, contains('LinearGradient'));
      expect(variations[2].dartCode, contains('ElevatedButton'));
    });

    test('generates 3 distinct variations for metrics prompts', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'Métricas de faturamento e lucro líquido',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations[0].styleTag, contains('Glassmorphism'));
      expect(variations[0].dartCode, contains('Lucro Líquido'));

      expect(variations[1].styleTag, contains('Bento Grid'));
      expect(variations[1].dartCode, contains('Performance'));

      expect(variations[2].styleTag, contains('Hero'));
      expect(variations[2].dartCode, contains('Faturamento Total Acumulado'));
    });

    test('generates 3 distinct variations for search/filter prompts', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'Busca inteligente com filtros e categorias',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations[0].dartCode, contains('TextField'));
      expect(variations[1].dartCode, contains('Filtros Populares'));
      expect(variations[2].dartCode, contains('LinearGradient'));
    });

    test('generates 3 distinct fallback variations for other prompts', () {
      final variations = GeminiAiService.synthesizeWidgetVariations(
        prompt: 'Widget personalizado de notificações push',
        preset: PresetType.cleanLite,
      );

      expect(variations.length, 3);
      expect(variations[0].styleTag, contains('Glassmorphism'));
      expect(variations[1].styleTag, contains('Bento Grid'));
      expect(variations[2].styleTag, contains('Hero'));
    });
  });

  group('GeminiAiService.generateWidgetVariations API & Fallback Tests', () {
    test('returns variations from simulated API response when apiKey is provided', () async {
      final mockClient = _MockHttpClient((request) async {
        expect(request.url.toString(), contains('generativelanguage.googleapis.com'));
        expect(request.url.queryParameters['key'], 'valid_api_key_test');

        final apiResponse = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode([
                      {
                        'id': 'api_var_1',
                        'title': 'AI Custom Glass Card',
                        'styleTag': 'Glassmorphism Oval',
                        'description': 'AI generated glassmorphism card for user profile.',
                        'techApproach': 'CircleAvatar + Glow + Row',
                        'dartCode': 'Container(child: const CircleAvatar(radius: 24))'
                      },
                      {
                        'id': 'api_var_2',
                        'title': 'AI Custom Bento Tile',
                        'styleTag': 'Bento Grid Profile',
                        'description': 'AI generated bento profile tile with stats.',
                        'techApproach': 'ClipRRect + Bento Grid',
                        'dartCode': 'Container(child: ClipRRect(child: Text("Bento Stat")))'
                      },
                      {
                        'id': 'api_var_3',
                        'title': 'AI Custom Hero Banner',
                        'styleTag': 'Hero Banner',
                        'description': 'AI generated hero action banner with gradient.',
                        'techApproach': 'Gradient Container + Action Button',
                        'dartCode': 'Container(child: ElevatedButton(onPressed: null, child: Text("Go")))'
                      }
                    ])
                  }
                ]
              }
            }
          ]
        };

        return http.Response(jsonEncode(apiResponse), 200, headers: {'content-type': 'application/json'});
      });

      final results = await GeminiAiService.generateWidgetVariations(
        prompt: 'caixinha com foto de perfil e bem vindo',
        preset: PresetType.cleanLite,
        apiKey: 'valid_api_key_test',
        httpClient: mockClient,
      );

      expect(results.length, 3);
      expect(results[0].id, 'api_var_1');
      expect(results[0].title, 'AI Custom Glass Card');
      expect(results[1].id, 'api_var_2');
      expect(results[1].title, 'AI Custom Bento Tile');
      expect(results[2].id, 'api_var_3');
      expect(results[2].title, 'AI Custom Hero Banner');
    });

    test('falls back cleanly to synthesizeWidgetVariations when apiKey is null or empty', () async {
      final resultsNullKey = await GeminiAiService.generateWidgetVariations(
        prompt: 'caixinha com foto de perfil e bem vindo',
        preset: PresetType.cleanLite,
        apiKey: null,
      );

      expect(resultsNullKey.length, 3);
      expect(resultsNullKey[0].styleTag, contains('Glassmorphism'));
      expect(resultsNullKey[0].techApproach, contains('CircleAvatar'));

      final resultsEmptyKey = await GeminiAiService.generateWidgetVariations(
        prompt: 'caixinha com foto de perfil e bem vindo',
        preset: PresetType.cleanLite,
        apiKey: '   ',
      );

      expect(resultsEmptyKey.length, 3);
      expect(resultsEmptyKey[0].styleTag, contains('Glassmorphism'));
    });

    test('falls back cleanly to synthesizeWidgetVariations on network error or server 500', () async {
      final errorClient = _MockHttpClient((request) async {
        throw const SocketException('Network is unreachable');
      });

      final resultsOnError = await GeminiAiService.generateWidgetVariations(
        prompt: 'caixinha com foto de perfil e bem vindo',
        preset: PresetType.cleanLite,
        apiKey: 'failing_key_123',
        httpClient: errorClient,
      );

      expect(resultsOnError.length, 3);
      expect(resultsOnError[0].styleTag, contains('Glassmorphism'));
      expect(resultsOnError[1].styleTag, contains('Bento Grid'));
      expect(resultsOnError[2].styleTag, contains('Hero Banner'));

      final server500Client = _MockHttpClient((request) async {
        return http.Response('{"error": "Internal Server Error"}', 500);
      });

      final resultsOn500 = await GeminiAiService.generateWidgetVariations(
        prompt: 'caixinha com foto de perfil e bem vindo',
        preset: PresetType.cleanLite,
        apiKey: 'server_error_key',
        httpClient: server500Client,
      );

      expect(resultsOn500.length, 3);
      expect(resultsOn500[0].styleTag, contains('Glassmorphism'));
    });
  });

  group('ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode Tests', () {
    test('inserts widget snippet into children: [...] of a screen and returns valid compilable Dart code', () {
      const snippet = '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF141B2D),
    borderRadius: BorderRadius.circular(16),
  ),
  child: const Text('Widget Injetado'),
)''';

      final updatedCode = ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode(
        sampleScreenCode,
        snippet,
      );

      expect(updatedCode, contains('Widget Injetado'));
      expect(updatedCode, contains('children: ['));
      // Verify children list still terminates properly
      expect(updatedCode, contains('],\n          )'));
      // Verify earlier child still exists and has comma
      expect(updatedCode, contains('const SizedBox(height: 16),'));
      // Verify structure is complete
      expect(updatedCode, contains('class ProfileDashboardScreen extends StatelessWidget'));
      expect(updatedCode, contains('Widget build(BuildContext context)'));
    });

    test('inserts widget snippet into screen without trailing comma inside children list', () {
      const codeWithoutTrailingComma = '''import 'package:flutter/material.dart';

class SimpleScreen extends StatelessWidget {
  const SimpleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Primeiro Item')
        ],
      ),
    );
  }
}
''';

      const snippet = 'const Text(\'Segundo Item\')';
      final updated = ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode(
        codeWithoutTrailingComma,
        snippet,
      );

      expect(updated, contains('Primeiro Item'));
      expect(updated, contains('Segundo Item'));
      expect(updated, contains('children: ['));
      expect(updated, contains('],'));
    });

    test('generates full compilable scaffold when screen code is empty', () {
      const snippet = 'const Text(\'Widget em tela nova\')';
      final generated = ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode(
        '',
        snippet,
      );

      expect(generated, contains('class GeneratedScreen extends StatelessWidget'));
      expect(generated, contains('Scaffold('));
      expect(generated, contains('children: ['));
      expect(generated, contains('Widget em tela nova'));
    });

    test('returns original code unmodified if snippet is empty or whitespace', () {
      final unchanged = ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode(
        sampleScreenCode,
        '   \n\t  ',
      );
      expect(unchanged, equals(sampleScreenCode));
    });
  });
}
