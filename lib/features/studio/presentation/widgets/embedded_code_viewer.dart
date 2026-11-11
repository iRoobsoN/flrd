import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/theme/app_colors.dart';
import '../../models/route_node.dart';

/// Custom [TextEditingController] providing real-time Dart syntax highlighting
/// with Obsidian Glass palette accents.
class DartCodeHighlightingController extends TextEditingController {
  DartCodeHighlightingController({super.text});

  static final RegExp _syntaxRegex = RegExp(
    r'(?<comment>//.*$|/\*[\s\S]*?\*/)'
    r'|(?<string>"""[\s\S]*?"""|'
    r"'''[\s\S]*?'''|"
    r'"(?:[^"\\]|\\.)*"|'
    r"'(?:[^'\\]|\\.)*')"
    r'|(?<annotation>@[a-zA-Z_]\w*)'
    r'|(?<keyword>\b(?:abstract|as|assert|async|await|break|case|catch|class|const|continue|covariant|default|deferred|do|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|function|get|hide|if|implements|import|in|interface|is|late|library|mixin|new|null|of|on|operator|part|required|rethrow|return|set|show|static|super|switch|sync|this|throw|true|try|typedef|var|void|while|with|yield)\b)'
    r'|(?<type>\b[A-Z][a-zA-Z0-9_]*\b)'
    r'|(?<number>\b(?:0x[a-fA-F0-9]+|\d+(?:\.\d+)?)\b)',
    multiLine: true,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> spans = [];
    int lastMatchEnd = 0;

    final baseStyle = style ??
        const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
          color: AppColors.textPrimary,
        );

    for (final RegExpMatch match in _syntaxRegex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      TextStyle matchStyle = baseStyle;
      if (match.namedGroup('comment') != null) {
        matchStyle = matchStyle.copyWith(
          color: const Color(0xFF6A9955), // Forest Comment Green
          fontStyle: FontStyle.italic,
        );
      } else if (match.namedGroup('string') != null) {
        matchStyle = matchStyle.copyWith(
          color: const Color(0xFFCE9178), // Coral String Amber
        );
      } else if (match.namedGroup('annotation') != null) {
        matchStyle = matchStyle.copyWith(
          color: const Color(0xFFFBBF24), // Gold Annotation
          fontWeight: FontWeight.w600,
        );
      } else if (match.namedGroup('keyword') != null) {
        matchStyle = matchStyle.copyWith(
          color: const Color(0xFFC586C0), // Electric Violet Keyword
          fontWeight: FontWeight.bold,
        );
      } else if (match.namedGroup('type') != null) {
        matchStyle = matchStyle.copyWith(
          color: const Color(0xFF4EC9B0), // Cyan/Teal Class Type
          fontWeight: FontWeight.w600,
        );
      } else if (match.namedGroup('number') != null) {
        matchStyle = matchStyle.copyWith(
          color: const Color(0xFFB5CEA8), // Sage Olive Number
        );
      }

      spans.add(TextSpan(
        text: match.group(0),
        style: matchStyle,
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return TextSpan(children: spans, style: baseStyle);
  }
}

/// Obsidian Code Canvas: Embedded Code Viewer with Live Editing,
/// Line Numbers Gutter, Syntax Highlighting, Disk Saving, and Clipboard actions.
class EmbeddedCodeViewer extends ConsumerStatefulWidget {
  final String projectPath;
  final RouteNode node;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;
  final Future<void> Function(String code)? onSave;

  const EmbeddedCodeViewer({
    super.key,
    required this.projectPath,
    required this.node,
    this.isExpanded = false,
    this.onToggleExpand,
    this.onSave,
  });

  /// Writes code back to file on disk using File.writeAsString.
  static Future<File> saveCodeToDisk({
    required String projectPath,
    required RouteNode node,
    required String code,
  }) async {
    final filePath = p.isAbsolute(node.filePath)
        ? p.normalize(node.filePath)
        : p.normalize(p.join(projectPath, node.filePath));
    final file = File(filePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    await file.writeAsString(code, flush: true);
    return file;
  }

  /// Helper to display the code viewer inside an Obsidian Modal Dialog.
  static Future<void> showDialogViewer(
    BuildContext context, {
    required String projectPath,
    required RouteNode node,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: SizedBox(
            width: 1000,
            height: 700,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: EmbeddedCodeViewer(
                projectPath: projectPath,
                node: node,
                isExpanded: true,
                onToggleExpand: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Generates clean, production-grade Flutter template code for a given RouteNode.
  static String generateTemplateCode(RouteNode node) {
    final className = _toPascalCase(node.title);
    final displayTitle = node.title;
    final routePath = node.path;

    return '''import 'package:flutter/material.dart';

/// Obsidian Glass Color Tokens for $className
class AppColors {
  static const Color background = Color(0xFF090D16);
  static const Color backgroundSecondary = Color(0xFF0D121F);
  static const Color surface = Color(0xFF111726);
  static const Color surfaceCard = Color(0xFF141B2D);
  static const Color border = Color(0x1FFFFFFF);
  static const Color primary = Color(0xFF6366F1);
  static const Color secondary = Color(0xFF38BDF8);
  static const Color success = Color(0xFF10B981);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
}

/// Route: $routePath
class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          '$displayTitle',
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
                '$displayTitle Screen',
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
  }

  static String _toPascalCase(String input) {
    final clean = input.replaceAll(RegExp(r'[^a-zA-Z0-9\s_]'), ' ').trim();
    final words = clean.split(RegExp(r'[\s_]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'GeneratedScreen';
    final result = words.map((w) => w[0].toUpperCase() + w.substring(1)).join();
    if (result.endsWith('Screen') || result.endsWith('Page') || result.endsWith('View')) {
      return result;
    }
    return '${result}Screen';
  }

  @override
  ConsumerState<EmbeddedCodeViewer> createState() => _EmbeddedCodeViewerState();
}

class _EmbeddedCodeViewerState extends ConsumerState<EmbeddedCodeViewer> {
  late final DartCodeHighlightingController _codeController;
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _gutterScrollController = ScrollController();

  bool _isLoading = true;
  bool _isTemplate = false;
  bool _isSaving = false;
  bool _isDirty = false;
  int _lineCount = 1;
  int _maxLineLength = 0;

  static const double _fontSize = 12.0;
  static const double _lineHeightMultiplier = 1.5;
  static const double _lineBoxHeight = _fontSize * _lineHeightMultiplier; // 18.0

  String get _resolvedFilePath {
    if (p.isAbsolute(widget.node.filePath)) {
      return p.normalize(widget.node.filePath);
    }
    return p.normalize(p.join(widget.projectPath, widget.node.filePath));
  }

  @override
  void initState() {
    super.initState();
    _codeController = DartCodeHighlightingController();
    _codeController.addListener(_onCodeChanged);

    // Sync vertical scrolling between code viewport and gutter
    _verticalScrollController.addListener(_syncGutterScroll);

    _loadFileContent();
  }

  void _syncGutterScroll() {
    if (_gutterScrollController.hasClients && _verticalScrollController.hasClients) {
      final targetOffset = _verticalScrollController.offset.clamp(
        0.0,
        _gutterScrollController.position.maxScrollExtent,
      );
      if ((_gutterScrollController.offset - targetOffset).abs() > 0.5) {
        _gutterScrollController.jumpTo(targetOffset);
      }
    }
  }

  void _onCodeChanged() {
    if (!_isDirty) {
      setState(() => _isDirty = true);
    }
    _updateLineStats();
  }

  void _updateLineStats() {
    final lines = _codeController.text.split('\n');
    final count = lines.isEmpty ? 1 : lines.length;
    int maxLen = 0;
    for (final l in lines) {
      if (l.length > maxLen) maxLen = l.length;
    }

    if (count != _lineCount || maxLen != _maxLineLength) {
      setState(() {
        _lineCount = count;
        _maxLineLength = maxLen;
      });
    }
  }

  @override
  void didUpdateWidget(covariant EmbeddedCodeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.filePath != widget.node.filePath ||
        oldWidget.projectPath != widget.projectPath ||
        oldWidget.node.id != widget.node.id) {
      _loadFileContent();
    }
  }

  void _loadFileContent() {
    try {
      final file = File(_resolvedFilePath);
      if (file.existsSync()) {
        _codeController.text = file.readAsStringSync();
        _isTemplate = false;
      } else {
        _codeController.text = EmbeddedCodeViewer.generateTemplateCode(widget.node);
        _isTemplate = true;
      }
    } catch (_) {
      _codeController.text = EmbeddedCodeViewer.generateTemplateCode(widget.node);
      _isTemplate = true;
    }
    _isLoading = false;
    _isDirty = false;
    _updateLineStats();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveToDisk() async {
    setState(() => _isSaving = true);
    try {
      if (widget.onSave != null) {
        await widget.onSave!(_codeController.text);
      } else {
        await EmbeddedCodeViewer.saveCodeToDisk(
          projectPath: widget.projectPath,
          node: widget.node,
          code: _codeController.text,
        );
      }

      if (mounted) {
        setState(() {
          _isDirty = false;
          _isTemplate = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surfaceCard,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: AppColors.border),
            ),
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Arquivo salvo com sucesso em ${widget.node.filePath}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surfaceCard,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: AppColors.danger),
            ),
            content: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.danger,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Error saving file to disk: $e',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _copyCodeToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _codeController.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceCard,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.border),
          ),
          content: Row(
            children: const [
              Icon(
                Icons.content_copy_rounded,
                color: AppColors.secondary,
                size: 16,
              ),
              SizedBox(width: 8),
              Text(
                'Code copied to clipboard!',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _verticalScrollController.removeListener(_syncGutterScroll);
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _gutterScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Bar
          _buildTopBar(context),

          // Code Canvas (Gutter + Highlighted Monospace Editor)
          Expanded(
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  )
                : _buildEditorCanvas(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 460;

        final pathTag = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.flutter_dash,
                size: 14,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.node.filePath,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_isDirty) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Alterações não salvas no disco',
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
              if (_isTemplate) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.secondary.withOpacity(0.3),
                    ),
                  ),
                  child: const Text(
                    'Template',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );

        final actionButtons = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Save to Disk" Button
            _buildTopBarButton(
              icon: Icons.save_rounded,
              label: 'Save to Disk',
              color: AppColors.primary,
              isLoading: _isSaving,
              onPressed: _saveToDisk,
            ),
            const SizedBox(width: 6),

            // "Copy Code" Button
            _buildTopBarButton(
              icon: Icons.copy_rounded,
              label: 'Copy Code',
              color: AppColors.textSecondary,
              onPressed: _copyCodeToClipboard,
            ),

            // "Expand" Button
            if (widget.onToggleExpand != null) ...[
              const SizedBox(width: 6),
              _buildTopBarButton(
                icon: widget.isExpanded
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                label: widget.isExpanded ? 'Collapse' : 'Expand',
                color: AppColors.secondary,
                onPressed: widget.onToggleExpand!,
              ),
            ],
          ],
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    pathTag,
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: actionButtons,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: pathTag),
                    const SizedBox(width: 8),
                    actionButtons,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTopBarButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return MouseRegion(
      cursor: isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isLoading ? null : onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorCanvas() {
    final gutterWidth =
        (_lineCount.toString().length * 9.0 + 20.0).clamp(38.0, 70.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final codeViewportWidth =
            math.max(constraints.maxWidth - gutterWidth, 100.0);
        final minContentWidth =
            math.max(_maxLineLength * 7.8 + 40.0, codeViewportWidth);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Line Numbers Gutter
            Container(
              width: gutterWidth,
              decoration: const BoxDecoration(
                color: AppColors.backgroundSecondary,
                border: Border(
                  right: BorderSide(color: AppColors.borderSubtle, width: 1),
                ),
              ),
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent &&
                      _verticalScrollController.hasClients) {
                    final target = (_verticalScrollController.offset +
                            event.scrollDelta.dy)
                        .clamp(
                      0.0,
                      _verticalScrollController.position.maxScrollExtent,
                    );
                    _verticalScrollController.jumpTo(target);
                  }
                },
                child: SingleChildScrollView(
                  controller: _gutterScrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 12, bottom: 12, right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      _lineCount,
                      (index) => SizedBox(
                        height: _lineBoxHeight,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: _fontSize,
                            height: _lineHeightMultiplier,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Code Editor Area with Dual Scrollbars (Vertical + Horizontal)
            Expanded(
              child: Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: minContentWidth,
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        scrollDirection: Axis.vertical,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: TextField(
                            controller: _codeController,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            cursorColor: AppColors.primary,
                            cursorWidth: 2,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: _fontSize,
                              height: _lineHeightMultiplier,
                              color: AppColors.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
