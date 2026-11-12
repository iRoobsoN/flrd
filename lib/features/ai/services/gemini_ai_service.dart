import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../wizard/models/project_config.dart';
import '../../studio/domain/screen_material.dart';
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
            Text('$displayTitle ação executada com sucesso!'),
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
