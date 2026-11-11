import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../wizard/models/project_config.dart';

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

        final systemPrompt =
            'You are an expert Flutter engineer. Output ONLY valid, compilable Dart code within ```dart codeblock. Screen class name: $screenClassName. Route: $routePath. Preset: $preset. Use AppColors tokens and standard Flutter Material 3 widgets.';

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
      );
    }

    var cleanDartCode = extractDartCode(rawCode);
    if (cleanDartCode.trim().isEmpty) {
      cleanDartCode = synthesizeScreenCode(
        screenClassName: screenClassName,
        routePath: routePath,
        prompt: prompt,
        preset: preset,
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
  }) {
    final featureName = screenClassName.replaceAll('Screen', '');
    final displayTitle = featureName.isEmpty ? 'Custom' : featureName;

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
/// Preset: ${preset.name} (${preset.tagline})
/// Description: $prompt
class $screenClassName extends StatefulWidget {
  const $screenClassName({super.key});

  @override
  State<$screenClassName> createState() => _${screenClassName}State();
}

class _${screenClassName}State extends State<$screenClassName> {
  bool _isLoading = false;

  void _handlePrimaryAction() async {
    setState(() => _isLoading = true);
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
      appBar: AppBar(
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Container(
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
                      '$prompt',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Interactive Card
              Container(
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
                        backgroundColor: AppColors.primary,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''';
  }
}
