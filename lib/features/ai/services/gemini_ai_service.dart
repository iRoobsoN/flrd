import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../wizard/models/project_config.dart';
import '../../studio/domain/screen_material.dart';
import '../../studio/domain/widget_variation.dart';
import '../../studio/models/route_node.dart';

/// Encapsulates the output of a generated screen operation.
class GeneratedScreenResult {
  final String code;
  final String filePath;
  final String absolutePath;

  const GeneratedScreenResult({
    required this.code,
    required this.filePath,
    required this.absolutePath,
  });

  @override
  String toString() =>
      'GeneratedScreenResult(filePath: $filePath, absolutePath: $absolutePath, codeLength: ${code.length})';
}

/// Service providing AI-powered Flutter screen synthesis using Google Gemini 1.5 Flash
/// with offline architectural fallback synthesis.
class GeminiAiService {
  GeminiAiService._();

  /// Generates a complete Flutter screen widget file using Gemini 1.5 Flash or
  /// an architectural synthesis fallback when offline or lacking an API key.
  ///
  /// Extracts compilable Dart code, writes the file to the target project directory,
  /// and returns a [GeneratedScreenResult].
  static Future<GeneratedScreenResult> generateScreen({
    required String projectPath,
    required String screenClassName,
    required String routePath,
    required String prompt,
    required PresetType preset,
    List<RouteNode>? existingRoutes,
    List<ScreenMaterialItem>? materials,
    String? apiKey,
    http.Client? httpClient,
  }) async {
    String rawCode = '';

    final hasApiKey = apiKey != null &&
        apiKey.trim().isNotEmpty &&
        apiKey.trim() != 'null' &&
        apiKey.trim() != 'undefined';
    if (hasApiKey) {
      final client = httpClient ?? http.Client();
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey.trim()}',
        );

        var routeContext = '';
        if (existingRoutes != null && existingRoutes.isNotEmpty) {
          final routesSummary = existingRoutes
              .map((r) => '${r.title} (${r.path})')
              .join(', ');
          routeContext = ' Known app navigation routes for context.go / context.push: $routesSummary.';
        }

        final systemPrompt =
            'You are an expert Flutter engineer. Output ONLY valid, compilable Dart code within ```dart codeblock. Screen class name: $screenClassName. Route: $routePath.$routeContext Preset: $preset. Use AppColors tokens and standard Flutter Material 3 widgets.';

        final requestPayload = {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'text': '$systemPrompt\n\nUser Request / Screen Requirements:\n$prompt',
                }
              ]
            }
          ],
          'system_instruction': {
            'parts': [
              {'text': systemPrompt}
            ]
          }
        };

        final response = await client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(requestPayload),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> &&
              decoded['candidates'] is List &&
              (decoded['candidates'] as List).isNotEmpty) {
            final candidate = (decoded['candidates'] as List).first;
            if (candidate is Map<String, dynamic> &&
                candidate['content'] is Map<String, dynamic>) {
              final content = candidate['content'] as Map<String, dynamic>;
              if (content['parts'] is List && (content['parts'] as List).isNotEmpty) {
                final part = (content['parts'] as List).first;
                if (part is Map<String, dynamic> && part['text'] is String) {
                  rawCode = part['text'] as String;
                }
              }
            }
          }
        }
      } catch (_) {
        // Fall back to offline code synthesis if Gemini API call fails (network drop, timeout, or auth issue)
        rawCode = '';
      } finally {
        if (httpClient == null) {
          client.close();
        }
      }
    }

    // Fallback to architectural code synthesis generator if API key is absent, offline, or call failed
    if (rawCode.trim().isEmpty) {
      rawCode = synthesizeScreenCode(
        screenClassName: screenClassName,
        routePath: routePath,
        prompt: prompt,
        preset: preset,
        existingRoutes: existingRoutes,
        materials: materials,
      );
    }

    var cleanDartCode = extractDartCode(rawCode);
    if (cleanDartCode.trim().isEmpty) {
      cleanDartCode = synthesizeScreenCode(
        screenClassName: screenClassName,
        routePath: routePath,
        prompt: prompt,
        preset: preset,
        existingRoutes: existingRoutes,
        materials: materials,
      );
    }

    var featureFolder = screenClassName.toLowerCase().replaceAll('screen', '');
    if (featureFolder.isEmpty) {
      featureFolder = screenClassName.toLowerCase();
    }

    final relativeFilePath =
        'lib/features/$featureFolder/presentation/${screenClassName.toLowerCase()}.dart';
    final targetFile = File(p.join(projectPath, relativeFilePath));

    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsString(cleanDartCode);

    return GeneratedScreenResult(
      code: cleanDartCode,
      filePath: relativeFilePath,
      absolutePath: targetFile.absolute.path,
    );
  }

  /// Extracts clean Dart code from markdown code fences (e.g. ```dart ... ```).
  static String extractDartCode(String raw) {
    final trimmed = raw.trim();
    final codeBlockRegex =
        RegExp(r'```(?:dart)?\s*([\s\S]*?)```', multiLine: true);
    final match = codeBlockRegex.firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return trimmed;
  }

  /// Parses JSON variations from Gemini response, handling markdown fences and partial JSON.
  static List<WidgetVariation>? _parseVariationsJson(String rawText) {
    if (rawText.trim().isEmpty) return null;
    try {
      String text = rawText.trim();
      if (text.startsWith('```')) {
        final firstNewline = text.indexOf('\n');
        if (firstNewline != -1) {
          text = text.substring(firstNewline + 1);
        }
        final lastFence = text.lastIndexOf('```');
        if (lastFence != -1) {
          text = text.substring(0, lastFence);
        }
      }
      text = text.trim();

      final startIndex = text.indexOf('[');
      final endIndex = text.lastIndexOf(']');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        text = text.substring(startIndex, endIndex + 1);
      } else if (startIndex != -1) {
        final lastObj = text.lastIndexOf('}');
        if (lastObj > startIndex) {
          text = '${text.substring(startIndex, lastObj + 1)}]';
        }
      }

      // Remove trailing commas before closing braces/brackets
      text = text.replaceAll(RegExp(r',\s*([\]}])'), r'$1');

      final decoded = jsonDecode(text);
      if (decoded is List && decoded.isNotEmpty) {
        final results = <WidgetVariation>[];
        for (int i = 0; i < decoded.length; i++) {
          final item = decoded[i];
          if (item is Map<String, dynamic>) {
            results.add(WidgetVariation(
              id: item['id']?.toString() ?? 'var_${i + 1}',
              title: item['title']?.toString() ?? 'Variação ${i + 1}',
              styleTag: item['styleTag']?.toString() ??
                  (i == 0
                      ? 'Glassmorphism Card'
                      : i == 1
                          ? 'Bento Grid Tile'
                          : 'Hero Action Banner'),
              description: item['description']?.toString() ?? '',
              dartCode: extractDartCode(item['dartCode']?.toString() ?? ''),
              techApproach: item['techApproach']?.toString() ??
                  (i == 0
                      ? 'Glassmorphism Card'
                      : i == 1
                          ? 'Bento Grid'
                          : 'Hero Action Banner'),
              icon: i == 0
                  ? Icons.auto_awesome_rounded
                  : i == 1
                      ? Icons.grid_view_rounded
                      : Icons.view_carousel_rounded,
            ));
          }
        }
        if (results.length >= 2) {
          return results;
        }
      }
    } catch (e) {
      debugPrint('GeminiAiService: Error parsing widget variations JSON: $e');
    }
    return null;
  }

  /// Generates 3 distinct widget variations using Gemini 1.5 Flash API (when apiKey provided)
  /// or falls back to diverse architectural synthesis.
  static Future<List<WidgetVariation>> generateWidgetVariations({
    required String prompt,
    required PresetType preset,
    RouteNode? routeNode,
    String? apiKey,
    http.Client? httpClient,
  }) async {
    final hasApiKey = apiKey != null &&
        apiKey.trim().isNotEmpty &&
        apiKey.trim() != 'null' &&
        apiKey.trim() != 'undefined';

    if (hasApiKey) {
      final client = httpClient ?? http.Client();
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey.trim()}',
        );

        final routeContext = routeNode != null
            ? ' Target screen: "${routeNode.title}" (${routeNode.path}).'
            : '';

        final systemPrompt =
            'You are an expert Flutter engineer and UI/UX designer. '
            'Given the user widget prompt, generate exactly 3 REAL, DIVERSE, PRODUCTION-GRADE Flutter widget variations in JSON format tailored to the user prompt.\n'
            'Each variation must use a distinct visual design, layout architecture, and Flutter widget composition:\n'
            '- Variation 1: Glassmorphism style (subtle borders, translucent background, refined typography, glow effects).\n'
            '- Variation 2: Bento Grid / Modern Card style (clean rounded container, pill badges, structured stats, compact layout).\n'
            '- Variation 3: Hero Action Banner style (vibrant gradients, prominent focal point, interactive action button).\n'
            'CRITICAL ANIMATION REQUIREMENT: If the user prompt asks for animations, physics, bouncing ball, pulses, bounce, or dynamic movement, you MUST output animated Flutter code (using AnimationController, CurvedAnimation, TweenAnimationBuilder, or StatefulBuilder with curves like Curves.bounceOut, Curves.elasticOut).\n'
            'Output ONLY a valid JSON array of 3 objects with keys: "id", "title", "styleTag", "description", "techApproach", "dartCode".\n'
            'Each "dartCode" MUST be a complete, self-contained, compilable Flutter widget snippet (e.g. Container(...), TweenAnimationBuilder(...), StatefulBuilder(...)). Do NOT wrap in markdown other than optional ```json.';

        final requestPayload = {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'text':
                      '$systemPrompt\n\nUser Widget Prompt: "$prompt"\nPreset: ${preset.name}.$routeContext',
                }
              ]
            }
          ],
          'system_instruction': {
            'parts': [
              {'text': systemPrompt}
            ]
          }
        };

        final response = await client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(requestPayload),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> &&
              decoded['candidates'] is List &&
              (decoded['candidates'] as List).isNotEmpty) {
            final candidate = (decoded['candidates'] as List).first;
            if (candidate is Map<String, dynamic> &&
                candidate['content'] is Map<String, dynamic>) {
              final content = candidate['content'] as Map<String, dynamic>;
              if (content['parts'] is List && (content['parts'] as List).isNotEmpty) {
                final part = (content['parts'] as List).first;
                if (part is Map<String, dynamic> && part['text'] is String) {
                  final text = part['text'] as String;
                  final parsedVariations = _parseVariationsJson(text);
                  if (parsedVariations != null && parsedVariations.isNotEmpty) {
                    return parsedVariations;
                  }
                }
              }
            }
          }
        }
      } catch (_) {
        // Fall back to architectural synthesis
      } finally {
        if (httpClient == null) {
          client.close();
        }
      }
    }

    return synthesizeWidgetVariations(
      prompt: prompt,
      preset: preset,
      routeNode: routeNode,
    );
  }

  /// Synthesizes 3 distinct visual and structural widget variations offline.
  static List<WidgetVariation> synthesizeWidgetVariations({
    required String prompt,
    required PresetType preset,
    RouteNode? routeNode,
  }) {
    final lower = prompt.toLowerCase();

    final isProfile = lower.contains('perfil') ||
        lower.contains('profile') ||
        lower.contains('foto') ||
        lower.contains('avatar') ||
        lower.contains('usuário') ||
        lower.contains('usuario') ||
        lower.contains('user') ||
        lower.contains('bem vindo') ||
        lower.contains('bem-vindo') ||
        lower.contains('boas-vindas') ||
        lower.contains('logado');

    final isPayment = lower.contains('pix') ||
        lower.contains('pagamento') ||
        lower.contains('payment') ||
        lower.contains('cartão') ||
        lower.contains('cartao') ||
        (lower.contains('fatura') && !lower.contains('faturamento')) ||
        lower.contains('cobrança') ||
        lower.contains('cobranca');

    final isMetrics = lower.contains('métrica') ||
        lower.contains('metrica') ||
        lower.contains('lucro') ||
        lower.contains('vendas') ||
        lower.contains('analytics') ||
        lower.contains('faturamento') ||
        lower.contains('renda') ||
        lower.contains('dashboard');

    final isSearch = lower.contains('busca') ||
        lower.contains('search') ||
        lower.contains('filtro') ||
        lower.contains('pesquisa') ||
        lower.contains('procurar');

    final isCounter = lower.contains('contador') ||
        lower.contains('counter') ||
        lower.contains('increment') ||
        lower.contains('contar');

    final isBounce = lower.contains('bola') ||
        lower.contains('pingando') ||
        lower.contains('quicando') ||
        lower.contains('bounce') ||
        lower.contains('animad') ||
        lower.contains('física') ||
        lower.contains('fisica') ||
        lower.contains('pular') ||
        lower.contains('pulando');

    // -------------------------------------------------------------------------
    // 1. BOUNCING PHYSICS BALL & ANIMATIONS
    // -------------------------------------------------------------------------
    if (isBounce) {
      return [
        const WidgetVariation(
          id: 'var_bounce_physics_1',
          title: 'Bouncing Physics Ball',
          styleTag: 'Physics Animation',
          description:
              'Bola que fica pingando com física vertical Curves.bounceOut e sombra sincronizada no chão.',
          techApproach: 'CurvedAnimation(curve: Curves.bounceOut) + Ground Shadow',
          icon: Icons.sports_soccer_rounded,
          dartCode: '''TweenAnimationBuilder<double>(
  tween: Tween<double>(begin: 0.0, end: 1.0),
  duration: const Duration(milliseconds: 1400),
  curve: Curves.bounceOut,
  builder: (context, value, child) {
    final double ballY = (1.0 - value) * -90.0;
    final double shadowScale = 0.4 + (value * 0.6);
    final double shadowOpacity = (0.2 + (value * 0.6)).clamp(0.0, 1.0);
    return Container(
      height: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2D).withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.2),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  bottom: 12,
                  child: Container(
                    width: 56 * shadowScale,
                    height: 12 * shadowScale,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(shadowOpacity),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(shadowOpacity * 0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 24 - ballY,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFF818CF8), Color(0xFF4F46E5), Color(0xFF312E81)],
                        center: Alignment(-0.3, -0.4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.55),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.sports_soccer_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Física de Salto Real • Curves.bounceOut',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  },
)''',
        ),
        const WidgetVariation(
          id: 'var_bounce_pulse_2',
          title: 'Glowing Pulse Sphere',
          styleTag: 'Neon Pulse Sphere',
          description:
              'Esfera com escala animada contínua, aura neon luminosa e visual futurista.',
          techApproach: 'TweenAnimationBuilder + Scale & Neon Aura',
          icon: Icons.blur_on_rounded,
          dartCode: '''TweenAnimationBuilder<double>(
  tween: Tween<double>(begin: 0.85, end: 1.15),
  duration: const Duration(milliseconds: 900),
  curve: Curves.easeInOut,
  builder: (context, scale, child) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: scale,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF38BDF8), Color(0xFF0284C7), Color(0xFF0F172A)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withOpacity(0.65),
                    blurRadius: 26 * scale,
                    spreadRadius: 4 * scale,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.blur_on_rounded, color: Colors.white, size: 34),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Esfera de Pulso Neon',
            style: TextStyle(color: Color(0xFFF8FAFC), fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Escala pulsante contínua com aura holográfica',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
          ),
        ],
      ),
    );
  },
)''',
        ),
        const WidgetVariation(
          id: 'var_bounce_spring_3',
          title: 'Interactive Spring Ball',
          styleTag: 'Interactive Spring Ball',
          description:
              'Bola interativa que dispara salto elástico Curves.elasticOut ao toque do usuário.',
          techApproach: 'Tap-to-Bounce + Curves.elasticOut Physics',
          icon: Icons.touch_app_rounded,
          dartCode: '''StatefulBuilder(
  builder: (context, setState) {
    bool isBouncing = false;
    return GestureDetector(
      onTap: () => setState(() => isBouncing = !isBouncing),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(isBouncing),
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 750),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          final double offsetY = -35.0 * (1.0 - value);
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF818CF8).withOpacity(0.4)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Transform.translate(
                  offset: Offset(0, offsetY),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFF43F5E), Color(0xFFBE123C)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF43F5E).withOpacity(0.5),
                          blurRadius: 14,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.touch_app_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Spring Ball Interativo',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Toque no card para ativar o efeito elástico',
                        style: TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Toque Aqui',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  },
)''',
        ),
      ];
    }

    if (isProfile) {
      return [
        const WidgetVariation(
          id: 'var_profile_glass',
          title: 'Glassmorphism Profile Card',
          styleTag: 'Glassmorphism Oval',
          description:
              'Card translúcido com CircleAvatar em glow border, saudação e status badge.',
          techApproach: 'CircleAvatar + Glow + Row',
          icon: Icons.account_circle_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF141B2D).withOpacity(0.85),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.35), width: 1.5),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF6366F1).withOpacity(0.2),
        blurRadius: 18,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  child: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF38BDF8)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.45),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const CircleAvatar(
          radius: 26,
          backgroundColor: Color(0xFF090D16),
          child: Icon(Icons.person_rounded, size: 28, color: Color(0xFFF8FAFC)),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Olá, Alex!',
                  style: TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Bem-vindo de volta ao seu painel',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
      IconButton(
        onPressed: () {},
        icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF94A3B8), size: 20),
      ),
    ],
  ),
)''',
        ),
        const WidgetVariation(
          id: 'var_profile_bento',
          title: 'Bento Grid Profile Tile',
          styleTag: 'Bento Grid Profile',
          description:
              'Tile modular com ClipRRect, moldura oval, indicador online e stat pill.',
          techApproach: 'ClipRRect + Bento Grid',
          icon: Icons.grid_view_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF111726),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0x1FFFFFFF)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 48,
                      height: 48,
                      color: const Color(0xFF1E293B),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        size: 26,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF111726), width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Usuário Conectado',
                    style: TextStyle(
                      color: Color(0xFFF8FAFC),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Online agora',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF38BDF8)),
                SizedBox(width: 4),
                Text(
                  'Nível 12',
                  style: TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF141B2D),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Projetos: 14', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            Text('Tarefas: 38', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            Text('Pontos: 1.250', style: TextStyle(color: Color(0xFFF8FAFC), fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ],
  ),
)''',
        ),
        const WidgetVariation(
          id: 'var_profile_hero',
          title: 'Hero Banner Boas-Vindas',
          styleTag: 'Hero Banner',
          description:
              'Banner com gradiente de destaque, moldura de avatar realçada e botão de ação.',
          techApproach: 'Gradient Container + Action Button',
          icon: Icons.view_carousel_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF06B6D4)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF4F46E5).withOpacity(0.35),
        blurRadius: 18,
        offset: const Offset(0, 5),
      ),
    ],
  ),
  child: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.3),
        ),
        child: const CircleAvatar(
          radius: 26,
          backgroundColor: Colors.white,
          child: Icon(Icons.person_rounded, size: 30, color: Color(0xFF4F46E5)),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Bem-vindo de volta!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Pronto para criar novidades hoje?',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF4F46E5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          elevation: 0,
        ),
        child: const Text('Acessar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    ],
  ),
)''',
        ),
      ];
    }

    if (isPayment) {
      return [
        const WidgetVariation(
          id: 'var_payment_1',
          title: 'Pix Copia-e-Cola Card',
          styleTag: 'Glassmorphism Card',
          description:
              'Card translúcido com chave Pix Copia e Cola, badge instantâneo e taxa zero.',
          techApproach: 'CircleAvatar + Glow + Row',
          icon: Icons.pix_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF141B2D).withOpacity(0.9),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
  ),
  child: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.pix_rounded, color: Color(0xFF10B981), size: 28),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Pagamento via Pix', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 15)),
            SizedBox(height: 2),
            Text('Chave: contato@flrd.dev', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          ],
        ),
      ),
      IconButton(
        onPressed: () {},
        icon: const Icon(Icons.copy_rounded, color: Color(0xFF10B981), size: 20),
      ),
    ],
  ),
)''',
        ),
        const WidgetVariation(
          id: 'var_payment_2',
          title: 'Cartão de Crédito Radio Tile',
          styleTag: 'Hero Credit Card Tile',
          description:
              'Tile de seleção de cartão com bandeira, número mascarado e radio button selecionado.',
          techApproach: 'RadioListTile + Chip EMV Badge',
          icon: Icons.credit_card_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF141B2D).withOpacity(0.9),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF6366F1).withOpacity(0.15),
        blurRadius: 14,
        offset: const Offset(0, 3),
      ),
    ],
  ),
  child: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.credit_card_rounded, color: Colors.white, size: 24),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Mastercard •••• 4289', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 14.5)),
            SizedBox(height: 2),
            Text('Expira em 08/29 • Débito e Crédito', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
          ],
        ),
      ),
      Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF6366F1),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      ),
    ],
  ),
)''',
        ),
        const WidgetVariation(
          id: 'var_payment_3',
          title: 'Bento Payment Method Grid',
          styleTag: 'Bento Grid Tile',
          description:
              'Grid modular Bento Grid com opções Pix, Cartão e Boleto organizados visualmente.',
          techApproach: 'ClipRRect + Bento Grid',
          icon: Icons.grid_view_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF111726),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0x1FFFFFFF)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Métodos de Pagamento',
        style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 14),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
              ),
              child: Column(
                children: const [
                  Icon(Icons.pix_rounded, color: Color(0xFF10B981), size: 24),
                  SizedBox(height: 6),
                  Text('Pix (0%)', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF141B2D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
              ),
              child: Column(
                children: const [
                  Icon(Icons.credit_card_rounded, color: Color(0xFF818CF8), size: 24),
                  SizedBox(height: 6),
                  Text('Cartão', style: TextStyle(color: Color(0xFFF8FAFC), fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF141B2D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF64748B).withOpacity(0.3)),
              ),
              child: Column(
                children: const [
                  Icon(Icons.receipt_long_rounded, color: Color(0xFF94A3B8), size: 24),
                  SizedBox(height: 6),
                  Text('Boleto', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  ),
)''',
        ),
      ];
    }

    if (isMetrics) {
      String metricTitle = 'Faturamento & Lucro';
      if (lower.contains('faturamento') && lower.contains('mensal') && lower.contains('lucro')) {
        metricTitle = 'Faturamento Mensal & Lucro';
      } else if (lower.contains('faturamento') && lower.contains('lucro')) {
        metricTitle = 'Faturamento & Lucro';
      } else if (lower.contains('faturamento')) {
        metricTitle = 'Faturamento Mensal';
      } else if (lower.contains('lucro')) {
        metricTitle = 'Lucro Líquido';
      } else if (lower.contains('financeiro')) {
        metricTitle = 'Painel Financeiro';
      }

      return [
        WidgetVariation(
          id: 'var_metrics_1',
          title: '$metricTitle KPI Card',
          styleTag: 'Glassmorphism KPI',
          description:
              'Card translúcido KPI com indicador de crescimento percentual e sparkline.',
          techApproach: 'CircleAvatar + Glow + Row',
          icon: Icons.trending_up_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF141B2D).withOpacity(0.9),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
  ),
  child: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.insights_rounded, color: Color(0xFF38BDF8), size: 26),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('$metricTitle', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            SizedBox(height: 2),
            Text('R\$ 48.920,00', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.arrow_upward_rounded, color: Color(0xFF10B981), size: 13),
            SizedBox(width: 3),
            Text('+24.8%', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ],
  ),
)''',
        ),
        WidgetVariation(
          id: 'var_metrics_2',
          title: '$metricTitle Bento Tile',
          styleTag: 'Bento Grid Tile',
          description:
              'Grid Bento com 3 métricas-chave divididas em blocos modulares de alta legibilidade.',
          techApproach: 'ClipRRect + Bento Grid',
          icon: Icons.bar_chart_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF111726),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0x1FFFFFFF)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Text('$metricTitle', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 14)),
          Icon(Icons.more_horiz_rounded, color: Color(0xFF64748B), size: 18),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF141B2D), borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Vendas', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  SizedBox(height: 3),
                  Text('1.420', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF141B2D), borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Margem', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  SizedBox(height: 3),
                  Text('38.2%', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF141B2D), borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Lucro', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  SizedBox(height: 3),
                  Text('R\$ 18k', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  ),
)''',
        ),
        WidgetVariation(
          id: 'var_metrics_3',
          title: 'Hero $metricTitle Banner',
          styleTag: 'Hero Action Banner',
          description:
              'Banner hero consolidado com gradiente e botão direto para download de relatórios.',
          techApproach: 'Gradient Container + Action Button',
          icon: Icons.insights_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
  ),
  child: Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Faturamento Total Acumulado', style: TextStyle(color: Colors.white70, fontSize: 12)),
            SizedBox(height: 4),
            Text('R\$ 284.150,00', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
      ),
      ElevatedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.file_download_outlined, size: 16),
        label: const Text('Exportar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          elevation: 0,
        ),
      ),
    ],
  ),
)''',
        ),
      ];
    }

    if (isSearch) {
      return [
        const WidgetVariation(
          id: 'var_search_1',
          title: 'Barra de Busca Glassmorphism',
          styleTag: 'Glassmorphism Card',
          description:
              'Barra de pesquisa em vidro escuro com ícone integrado e filtro rápido.',
          techApproach: 'TextField + Glass Container',
          icon: Icons.search_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
  decoration: BoxDecoration(
    color: const Color(0xFF141B2D).withOpacity(0.85),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
  ),
  child: Row(
    children: const [
      Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 22),
      SizedBox(width: 10),
      Expanded(
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Pesquise por nome, tag ou categoria...',
            hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            border: InputBorder.none,
            isDense: true,
          ),
          style: TextStyle(color: Color(0xFFF8FAFC), fontSize: 13),
        ),
      ),
      Icon(Icons.mic_none_rounded, color: Color(0xFF94A3B8), size: 20),
    ],
  ),
)''',
        ),
        const WidgetVariation(
          id: 'var_search_2',
          title: 'Bento Grid Filtros & Busca',
          styleTag: 'Bento Grid Tile',
          description:
              'Grid modular com chips de categorias e contador de itens encontrados.',
          techApproach: 'ClipRRect + Bento Grid',
          icon: Icons.tune_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: const Color(0xFF111726),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0x1FFFFFFF)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Text('Filtros Populares', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 13)),
          Text('128 resultados', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        ],
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(8)),
              child: const Text('Todos', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFF141B2D), borderRadius: BorderRadius.circular(8)),
              child: const Text('Recentes', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFF141B2D), borderRadius: BorderRadius.circular(8)),
              child: const Text('Favoritos', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            ),
          ],
        ),
      ),
    ],
  ),
)''',
        ),
        const WidgetVariation(
          id: 'var_search_3',
          title: 'Hero Search Action Banner',
          styleTag: 'Hero Action Banner',
          description:
              'Header dinâmico com campo amplo de busca, gradiente de destaque e tags de filtro.',
          techApproach: 'Gradient Container + Action Button',
          icon: Icons.filter_list_rounded,
          dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
    ),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.35)),
  ),
  child: Row(
    children: [
      Expanded(
        child: Row(
          children: const [
            Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 22),
            SizedBox(width: 10),
            Text('Buscar no sistema...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF38BDF8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('Filtrar', style: TextStyle(color: Color(0xFF090D16), fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    ],
  ),
)''',
        ),
      ];
    }

    // -------------------------------------------------------------------------
    // 6. INTERACTIVE COUNTER WIDGETS
    // -------------------------------------------------------------------------
    if (isCounter) {
      return [
        const WidgetVariation(
          id: 'var_counter_1',
          title: 'Stepper Counter Glassmorphism',
          styleTag: 'Glassmorphism Stepper',
          description:
              'Contador interativo com botões de incremento/decremento e indicador de quantidade.',
          techApproach: 'StatefulBuilder + Stepper Controls',
          icon: Icons.exposure_rounded,
          dartCode: '''StatefulBuilder(
  builder: (context, setState) {
    int counter = 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2D).withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.18),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: const [
              Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 22),
              SizedBox(width: 10),
              Text(
                'Quantidade:',
                style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() { if (counter > 0) counter--; }),
                icon: const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFF94A3B8), size: 22),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
                ),
                child: Text(
                  '\$counter',
                  style: const TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => counter++),
                icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF10B981), size: 22),
              ),
            ],
          ),
        ],
      ),
    );
  },
)''',
        ),
        const WidgetVariation(
          id: 'var_counter_2',
          title: 'Bento Goal Counter Tile',
          styleTag: 'Bento Grid Goal Counter',
          description:
              'Tile modular com meta numérica, barra de progresso calculada e botões de atalho (+1, +5).',
          techApproach: 'StatefulBuilder + Progress Bar',
          icon: Icons.sports_score_rounded,
          dartCode: '''StatefulBuilder(
  builder: (context, setState) {
    int count = 15;
    const int target = 50;
    final double progress = (count / target).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Meta Diária', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 14)),
              Text('\$count de \$target', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => count = (count + 1).clamp(0, target)),
                child: const Text('+1'),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: () => setState(() => count = (count + 5).clamp(0, target)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: const Color(0xFF090D16),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('+5', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  },
)''',
        ),
        const WidgetVariation(
          id: 'var_counter_3',
          title: 'Hero Interactive Counter Banner',
          styleTag: 'Hero Action Counter',
          description:
              'Banner de destaque com contador em tempo real, gradiente dinâmico e controle de zerar.',
          techApproach: 'StatefulBuilder + Hero Banner',
          icon: Icons.view_carousel_rounded,
          dartCode: '''StatefulBuilder(
  builder: (context, setState) {
    int total = 42;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '\$total',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Contador de Ações', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                SizedBox(height: 2),
                Text('Clique em adicionar para somar', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => setState(() => total++),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF4F46E5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              elevation: 0,
            ),
            child: const Text('+ Somar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  },
)''',
        ),
      ];
    }

    // -------------------------------------------------------------------------
    // 7. CUSTOM KEYWORD-AWARE PROMPT SYNTHESIS
    // -------------------------------------------------------------------------
    final stopWords = {
      'um', 'uma', 'uns', 'umas', 'o', 'a', 'os', 'as', 'de', 'do', 'da', 'dos', 'das',
      'com', 'para', 'em', 'no', 'na', 'nos', 'nas', 'por', 'sem', 'sobre', 'e', 'ou',
      'que', 'se', 'seu', 'sua', 'meu', 'minha', 'card', 'widget', 'tela', 'caixa', 'caixinha',
    };
    final words = prompt
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^a-zA-Z0-9áéíóúÁÉÍÓÚãõÃÕâêîôûÂÊÎÔÛçÇ]'), ''))
        .where((w) => w.length > 2 && !stopWords.contains(w.toLowerCase()))
        .toList();

    String smartTitle = prompt.length > 24 ? '${prompt.substring(0, 24)}...' : prompt;
    if (words.isNotEmpty) {
      smartTitle = words.take(3).map((w) {
        if (w.isEmpty) return '';
        return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
      }).join(' ');
    }

    return [
      WidgetVariation(
        id: 'var_custom_1',
        title: '$smartTitle Glass Card',
        styleTag: 'Glassmorphism Card',
        description: 'Card translúcido com borda sutil neon e layout refinado para $smartTitle.',
        techApproach: 'CircleAvatar + Glow + Row',
        icon: Icons.auto_awesome_rounded,
        dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF141B2D).withOpacity(0.85),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
  ),
  child: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF38BDF8), size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('$smartTitle', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 15)),
            SizedBox(height: 2),
            Text('Componente customizado com IA', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          ],
        ),
      ),
    ],
  ),
)''',
      ),
      WidgetVariation(
        id: 'var_custom_2',
        title: '$smartTitle Bento Tile',
        styleTag: 'Bento Grid Tile',
        description: 'Layout modular Bento Grid com bordas arredondadas e organização compacta.',
        techApproach: 'ClipRRect + Bento Grid',
        icon: Icons.grid_view_rounded,
        dartCode: '''Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF111726),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0x1FFFFFFF)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: const [
      Text('$smartTitle', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold, fontSize: 14)),
      SizedBox(height: 6),
      Text('Visual modular, responsivo e contextual.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
    ],
  ),
)''',
      ),
      WidgetVariation(
        id: 'var_custom_3',
        title: '$smartTitle Hero Banner',
        styleTag: 'Hero Action Banner',
        description: 'Banner imersivo com gradiente de alta energia e botão de ação interativo.',
        techApproach: 'Gradient Container + Action Button',
        icon: Icons.view_carousel_rounded,
        dartCode: '''Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
    ),
    borderRadius: BorderRadius.circular(18),
  ),
  child: Row(
    children: [
      Expanded(
        child: Text('$smartTitle', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF4F46E5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          elevation: 0,
        ),
        child: const Text('Executar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    ],
  ),
)''',
      ),
    ];
  }


  /// Generates clean, architectural, compilable Dart code adhering to the FLRD Obsidian Glass design
  /// system and the selected project architecture preset.
  static String synthesizeScreenCode({
    required String screenClassName,
    required String routePath,
    required String prompt,
    required PresetType preset,
    List<RouteNode>? existingRoutes,
    List<ScreenMaterialItem>? materials,
  }) {
    final featureName = screenClassName.replaceAll('Screen', '');
    final displayTitle = featureName.isEmpty ? 'Custom' : featureName;
    final routesComment = (existingRoutes != null && existingRoutes.isNotEmpty)
        ? '\n/// App Navigation Routes: ${existingRoutes.map((r) => "${r.title} (${r.path})").join(", ")}'
        : '';

    // Format multi-line prompts so every line starts with '/// ', ensuring valid Dart doc comments
    final formattedPromptComment = prompt
        .split('\n')
        .map((line) {
          final trimmed = line.trimRight();
          return trimmed.isEmpty ? '///' : '/// $trimmed';
        })
        .join('\n');

    final cleanDescription = _extractCleanDescription(prompt, displayTitle);
    final escapedCleanDesc = _escape(cleanDescription);

    // Resolve effective materials from argument or parse from prompt
    final effectiveMaterials = (materials != null && materials.isNotEmpty)
        ? materials
        : _parseMaterialsFromPrompt(prompt);

    final materialsDirectives = effectiveMaterials
        .map((m) => '${m.label} ${m.hint ?? ""} ${m.note ?? ""}')
        .join(' ');
    final fullDirectiveContext = '$prompt $materialsDirectives'.toLowerCase();

    // Directive checks:
    // a) Title cycling / random dynamic title
    final hasDynamicTitle = fullDirectiveContext.contains('trocando de nome') ||
        fullDirectiveContext.contains('troca de nome') ||
        fullDirectiveContext.contains('trocar de nome') ||
        fullDirectiveContext.contains('trocar nome') ||
        fullDirectiveContext.contains('mudar nome') ||
        fullDirectiveContext.contains('aleatoriamente') ||
        fullDirectiveContext.contains('random') ||
        (fullDirectiveContext.contains('troca') && !fullDirectiveContext.contains('cor')) ||
        (fullDirectiveContext.contains('nome') &&
            (fullDirectiveContext.contains('troca') ||
                fullDirectiveContext.contains('alternar') ||
                fullDirectiveContext.contains('ciclo') ||
                fullDirectiveContext.contains('aleat') ||
                fullDirectiveContext.contains('appbar') ||
                fullDirectiveContext.contains('título') ||
                fullDirectiveContext.contains('titulo'))) ||
        effectiveMaterials.any((m) =>
            m.note != null &&
            (m.note!.toLowerCase().contains('nome') ||
                m.note!.toLowerCase().contains('troca') ||
                m.note!.toLowerCase().contains('random') ||
                m.note!.toLowerCase().contains('aleatoriamente')));

    // b) Centered alignment
    final isCentered = fullDirectiveContext.contains('centralizado') ||
        fullDirectiveContext.contains('centralizar') ||
        fullDirectiveContext.contains('meio da tela') ||
        fullDirectiveContext.contains('center') ||
        fullDirectiveContext.contains('central');

    // c) Color toggle
    final hasColorToggle = fullDirectiveContext.contains('trocar de cor') ||
        fullDirectiveContext.contains('troque de cor') ||
        fullDirectiveContext.contains('mudar de cor') ||
        fullDirectiveContext.contains('muda de cor') ||
        fullDirectiveContext.contains('troca de cor') ||
        fullDirectiveContext.contains('cor') ||
        fullDirectiveContext.contains('azul');

    // d) Filter body materials
    final bodyMaterials = effectiveMaterials
        .where((m) => m.type != ScreenMaterialType.appBar)
        .toList();

    final materialCardsCode = bodyMaterials
        .map((m) => _buildObsidianCardForMaterial(
              m,
              isCentered: isCentered,
              hasColorToggle: hasColorToggle,
            ))
        .where((code) => code.trim().isNotEmpty)
        .join('\n              const SizedBox(height: 16),\n              ');

    final materialsSection = materialCardsCode.isNotEmpty
        ? '''const SizedBox(height: 20),
              // Obsidian Materials
              $materialCardsCode,'''
        : '';

    final appBarWidget = hasDynamicTitle
        ? '''appBar: AppBar(
        title: InkWell(
          onTap: () {
            setState(() {
              _titleIndex = (_titleIndex + 1) % _titles.length;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _titles[_titleIndex],
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.shuffle_rounded,
                  size: 16,
                  color: AppColors.secondary,
                ),
              ],
            ),
          ),
        ),
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),'''
        : '''appBar: AppBar(
        title: const Text(
          '$displayTitle',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),''';

    final headerCardCode = isCentered
        ? '''Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A6366F1),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: AppColors.secondary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                '$displayTitle Module',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Route: $routePath',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(child: Text(
                        '$escapedCleanDesc',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )'''
        : '''Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A6366F1),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: AppColors.secondary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '$displayTitle Module',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Route: $routePath',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$escapedCleanDesc',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              )''';

    final interactiveCardCode = isCentered
        ? '''Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Center(child: Text(
                        'Ações e Controles',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ${hasColorToggle ? '_buttonColor' : 'AppColors.primary'},
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isLoading ? null : _handlePrimaryAction,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textPrimary,
                                ),
                              )
                            : const Icon(Icons.bolt_rounded),
                        label: Text(
                          _isLoading ? 'Processando...' : 'Executar $displayTitle',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              )'''
        : '''Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ações e Controles',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ${hasColorToggle ? '_buttonColor' : 'AppColors.primary'},
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isLoading ? null : _handlePrimaryAction,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textPrimary,
                              ),
                            )
                          : const Icon(Icons.bolt_rounded),
                      label: Text(
                        _isLoading ? 'Processando...' : 'Executar $displayTitle',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )''';

    return '''import 'package:flutter/material.dart';

/// Obsidian Glass Color Tokens for $screenClassName
class AppColors {
  static const Color background = Color(0xFF090D16);
  static const Color backgroundSecondary = Color(0xFF0D121F);
  static const Color surface = Color(0xFF111726);
  static const Color surfaceCard = Color(0xFF141B2D);
  static const Color border = Color(0x1FFFFFFF);
  static const Color primary = Color(0xFF6366F1);
  static const Color secondary = Color(0xFF38BDF8);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color success = Color(0xFF10B981);
}

/// Generated by FLRD AI Screen Studio
/// Route: $routePath
/// Preset: ${preset.name} (${preset.tagline})$routesComment
///
$formattedPromptComment
class $screenClassName extends StatefulWidget {
  const $screenClassName({super.key});

  @override
  State<$screenClassName> createState() => _${screenClassName}State();
}

class _${screenClassName}State extends State<$screenClassName> {
  bool _isLoading = false;
  final TextEditingController _textController = TextEditingController();
  bool _obscurePassword = true;
  bool _switchValue = true;
  bool _checkboxValue = true;
  ${hasColorToggle ? "Color _buttonColor = AppColors.primary;\n  " : ""}${hasDynamicTitle ? """int _titleIndex = 0;
  final List<String> _titles = const [
    '$displayTitle',
    'Explorar',
    'Novidades',
    'Destaques',
  ];
  """ : ""}
  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _handlePrimaryAction() async {
    setState(() {
      _isLoading = true;
      ${hasColorToggle ? "_buttonColor = _buttonColor == AppColors.primary ? AppColors.secondary : AppColors.primary;" : ""}
    });
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: AppColors.success),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '$displayTitle ação executada com sucesso!',
                style: TextStyle(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surfaceCard,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      $appBarWidget
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: ${isCentered ? 'CrossAxisAlignment.center' : 'CrossAxisAlignment.stretch'},
            children: [
              // Header Card
              $headerCardCode,
              $materialsSection
              const SizedBox(height: 20),

              // Interactive Card
              $interactiveCardCode,
            ],
          ),
        ),
      ),
    );
  }
}
''';
  }

  static String _extractCleanDescription(String prompt, String displayTitle) {
    final fluxoRegex =
        RegExp(r'Descrição do fluxo:\s*([^\r\n]+)', caseSensitive: false);
    final match = fluxoRegex.firstMatch(prompt);
    if (match != null) {
      final desc = match.group(1)?.trim();
      if (desc != null && desc.isNotEmpty) {
        return desc;
      }
    }
    final trimmed = prompt.trim();
    if (!trimmed.contains('\n') &&
        !trimmed.contains('###') &&
        !trimmed.toLowerCase().contains('crie uma tela') &&
        trimmed.length <= 120 &&
        trimmed.isNotEmpty) {
      return trimmed;
    }
    return '$displayTitle - Módulo interativo e responsivo';
  }

  static String _escape(String text) {
    return text.replaceAll("'", r"\'").replaceAll(r"$", r"\$");
  }

  static List<ScreenMaterialItem> _parseMaterialsFromPrompt(String prompt) {
    final list = <ScreenMaterialItem>[];
    final lines = prompt.split('\n');
    final regex = RegExp(r'^\s*\d+\.\s+([^:]+):\s*(.+)$');
    for (final line in lines) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final category = match.group(1)!.trim().toLowerCase();
        final details = match.group(2)!.trim();

        String? note;
        final noteMatch = RegExp(
          r'\(Nota do Usu[aá]rio:\s*["“](.+?)["”]\)',
          caseSensitive: false,
        ).firstMatch(details);
        if (noteMatch != null) {
          note = noteMatch.group(1);
        }

        String label = 'Componente';
        final labelMatch = RegExp(
          r'(?:Título|Titulo|Label)?\s*["“](.+?)["”]',
          caseSensitive: false,
        ).firstMatch(details);
        if (labelMatch != null) {
          label = labelMatch.group(1)!;
        }

        String? hint;
        final hintMatch = RegExp(
          r'placeholder\s*["“](.+?)["”]',
          caseSensitive: false,
        ).firstMatch(details);
        if (hintMatch != null) {
          hint = hintMatch.group(1);
        }

        ScreenMaterialType type = ScreenMaterialType.containerCard;
        if (category.contains('appbar') || category.contains('barra superior')) {
          type = ScreenMaterialType.appBar;
        } else if (category.contains('header') ||
            category.contains('destaque') ||
            category.contains('título de destaque')) {
          type = ScreenMaterialType.headerText;
        } else if (category.contains('subtítulo') ||
            category.contains('subtitulo')) {
          type = ScreenMaterialType.subtitleText;
        } else if (category.contains('senha')) {
          type = ScreenMaterialType.passwordInput;
        } else if (category.contains('texto') ||
            category.contains('input') ||
            category.contains('campo')) {
          type = ScreenMaterialType.textInput;
        } else if (category.contains('social')) {
          type = ScreenMaterialType.socialButton;
        } else if (category.contains('secundário') ||
            category.contains('secundario')) {
          type = ScreenMaterialType.secondaryButton;
        } else if (category.contains('botão') || category.contains('botao')) {
          type = ScreenMaterialType.primaryButton;
        } else if (category.contains('switch')) {
          type = ScreenMaterialType.switchTile;
        } else if (category.contains('checkbox')) {
          type = ScreenMaterialType.checkboxTile;
        } else if (category.contains('ícone') || category.contains('icone')) {
          type = ScreenMaterialType.icon;
        } else if (category.contains('card') ||
            category.contains('container')) {
          type = ScreenMaterialType.containerCard;
        }

        list.add(ScreenMaterialItem(
          id: 'parsed_mat_${list.length}',
          type: type,
          label: label,
          hint: hint,
          note: note,
        ));
      }
    }
    return list;
  }

  static String _buildObsidianCardForMaterial(
    ScreenMaterialItem item, {
    required bool isCentered,
    required bool hasColorToggle,
  }) {
    final noteComment = (item.note != null && item.note!.trim().isNotEmpty)
        ? '/// Note: ${_escape(item.note!.trim().replaceAll(RegExp(r"[\r\n]+"), " "))}\n              '
        : '';
    final alignCenter =
        isCentered ? 'CrossAxisAlignment.center' : 'CrossAxisAlignment.start';
    final textAlign = isCentered ? 'TextAlign.center' : 'TextAlign.start';

    switch (item.type) {
      case ScreenMaterialType.appBar:
        return '';
      case ScreenMaterialType.headerText:
        return '''${noteComment}Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: $alignCenter,
                  children: [
                    Text(
                      '${_escape(item.label)}',
                      textAlign: $textAlign,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),''';
      case ScreenMaterialType.subtitleText:
        return '''${noteComment}Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '${_escape(item.label)}',
                  textAlign: $textAlign,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),''';
      case ScreenMaterialType.textInput:
        return '''${noteComment}Container(
                padding: const EdgeInsets.all(18.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_escape(item.label)}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _textController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '${_escape(item.hint ?? "Digite aqui...")}',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.edit_note_rounded, color: AppColors.secondary),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),''';
      case ScreenMaterialType.passwordInput:
        return '''${noteComment}Container(
                padding: const EdgeInsets.all(18.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_escape(item.label)}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '${_escape(item.hint ?? "••••••••")}',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.secondary),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),''';
      case ScreenMaterialType.primaryButton:
        return '''${noteComment}Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ${hasColorToggle ? '_buttonColor' : 'AppColors.primary'},
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: ${isCentered ? 'Center(child: Text(\'${_escape(item.label)}\', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)))' : 'Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.bolt_rounded, size: 18), SizedBox(width: 8), Text(\'${_escape(item.label)}\', style: TextStyle(fontWeight: FontWeight.bold))])'},
                ),
              ),''';
      case ScreenMaterialType.secondaryButton:
        return '''${noteComment}Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: ${isCentered ? 'Center(child: Text(\'${_escape(item.label)}\', textAlign: TextAlign.center))' : 'Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.link_rounded, size: 18), SizedBox(width: 8), Text(\'${_escape(item.label)}\')])'},
                ),
              ),''';
      case ScreenMaterialType.socialButton:
        return '''${noteComment}Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 24, color: AppColors.secondary),
                  label: Text('${_escape(item.label)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),''';
      case ScreenMaterialType.containerCard:
        return '''${noteComment}Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: $alignCenter,
                  children: [
                    Text(
                      '${_escape(item.label)}',
                      textAlign: $textAlign,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_escape(item.hint ?? "Obsidian Card Component")}',
                      textAlign: $textAlign,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),''';
      case ScreenMaterialType.icon:
        return '''${noteComment}Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Center(
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 40,
                    color: AppColors.secondary,
                  ),
                ),
              ),''';
      case ScreenMaterialType.switchTile:
        return '''${noteComment}Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: SwitchListTile(
                  title: Text(
                    '${_escape(item.label)}',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                  ),
                  value: _switchValue,
                  onChanged: (val) => setState(() => _switchValue = val),
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                ),
              ),''';
      case ScreenMaterialType.checkboxTile:
        return '''${noteComment}Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: CheckboxListTile(
                  title: Text(
                    '${_escape(item.label)}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                  value: _checkboxValue,
                  onChanged: (val) => setState(() => _checkboxValue = val ?? false),
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),''';
    }
  }

  /// Generates a standalone, focused Flutter widget code snippet based on a material and note.
  static Future<String> generateWidgetSnippet({
    required ScreenMaterialItem material,
    required PresetType preset,
    RouteNode? routeNode,
    List<RouteNode>? existingRoutes,
    String? apiKey,
    http.Client? httpClient,
  }) async {
    String rawCode = '';

    final prompt = ScreenMaterialCodeUpdater.generateWidgetSpecificPrompt(
      material,
      routeNode: routeNode,
      existingRoutes: existingRoutes,
      preset: preset,
    );

    final hasApiKey = apiKey != null &&
        apiKey.trim().isNotEmpty &&
        apiKey.trim() != 'null' &&
        apiKey.trim() != 'undefined';

    if (hasApiKey) {
      final client = httpClient ?? http.Client();
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey.trim()}',
        );

        final systemPrompt =
            'You are an expert Flutter engineer. Output ONLY a single, focused, standalone, and compilable Flutter widget code snippet within ```dart codeblock based on the requested component and behavioral prompt. Component: ${material.label} (${material.type.displayName}). Preset: $preset. Use AppColors tokens and standard Flutter Material 3 widgets.';

        final requestPayload = {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'text': '$systemPrompt\n\nWidget Requirements:\n$prompt',
                }
              ]
            }
          ],
          'system_instruction': {
            'parts': [
              {'text': systemPrompt}
            ]
          }
        };

        final response = await client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(requestPayload),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> &&
              decoded['candidates'] is List &&
              (decoded['candidates'] as List).isNotEmpty) {
            final candidate = (decoded['candidates'] as List).first;
            if (candidate is Map<String, dynamic> &&
                candidate['content'] is Map<String, dynamic>) {
              final content = candidate['content'] as Map<String, dynamic>;
              if (content['parts'] is List && (content['parts'] as List).isNotEmpty) {
                final part = (content['parts'] as List).first;
                if (part is Map<String, dynamic> && part['text'] is String) {
                  rawCode = part['text'] as String;
                }
              }
            }
          }
        }
      } catch (_) {
        rawCode = '';
      } finally {
        if (httpClient == null) {
          client.close();
        }
      }
    }

    if (rawCode.trim().isEmpty) {
      rawCode = synthesizeWidgetSnippet(
        material: material,
        preset: preset,
        routeNode: routeNode,
        existingRoutes: existingRoutes,
      );
    }

    var cleanDartCode = extractDartCode(rawCode);
    if (cleanDartCode.trim().isEmpty) {
      cleanDartCode = synthesizeWidgetSnippet(
        material: material,
        preset: preset,
        routeNode: routeNode,
        existingRoutes: existingRoutes,
      );
    }

    return cleanDartCode;
  }

  /// Synthesizes a focused, standalone Flutter widget code snippet for offline or fallback usage.
  static String synthesizeWidgetSnippet({
    required ScreenMaterialItem material,
    required PresetType preset,
    RouteNode? routeNode,
    List<RouteNode>? existingRoutes,
  }) {
    final widgetName =
        _pascalCase(material.label.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ''));
    final className = widgetName.isNotEmpty
        ? '${widgetName}Widget'
        : 'Custom${material.type.name}Widget';
    final userNote = material.note?.trim() ?? '';
    final noteComment = userNote.isNotEmpty ? '\n/// User Note: $userNote' : '';
    final routeComment = routeNode != null
        ? '\n/// Target Route: ${routeNode.path} (${routeNode.title})'
        : '';

    return '''import 'package:flutter/material.dart';

/// Obsidian Glass Focused Component: ${material.label} (${material.type.displayName})$routeComment$noteComment
class $className extends StatefulWidget {
  final VoidCallback? onTap;
  const $className({super.key, this.onTap});

  @override
  State<$className> createState() => _${className}State();
}

class _${className}State extends State<$className> {
  bool _isHovered = false;
  bool _isActive = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _isHovered ? const Color(0xFF1E293B) : const Color(0xFF141B2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isHovered ? const Color(0xFF6366F1) : const Color(0x1FFFFFFF),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: InkWell(
        onTap: () {
          setState(() => _isActive = !_isActive);
          widget.onTap?.call();
        },
        onHover: (hovered) => setState(() => _isHovered = hovered),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF38BDF8), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${material.label}',
                    style: const TextStyle(
                      color: Color(0xFFF8FAFC),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ('${material.hint ?? ""}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${material.hint ?? ""}',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            if ('$userNote'.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Custom Note',
                  style: TextStyle(color: Color(0xFF818CF8), fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
''';
  }

  static String _pascalCase(String text) {
    if (text.isEmpty) return '';
    return text.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join();
  }
}
