import 'dart:math';
import 'package:flutter/material.dart';
import '../models/route_node.dart';
import '../../wizard/models/project_config.dart';

// =============================================================================
// SCREEN MATERIAL TYPES & MODELS
// =============================================================================

/// Supported visual and functional component types for Screen Materials.
enum ScreenMaterialType {
  appBar,
  textInput,
  passwordInput,
  primaryButton,
  secondaryButton,
  socialButton,
  headerText,
  subtitleText,
  containerCard,
  icon,
  switchTile,
  checkboxTile;

  String get displayName {
    switch (this) {
      case ScreenMaterialType.appBar:
        return 'Barra Superior (AppBar)';
      case ScreenMaterialType.textInput:
        return 'Campo de Texto';
      case ScreenMaterialType.passwordInput:
        return 'Campo de Senha';
      case ScreenMaterialType.primaryButton:
        return 'Botão Primário';
      case ScreenMaterialType.secondaryButton:
        return 'Botão Secundário';
      case ScreenMaterialType.socialButton:
        return 'Login Social';
      case ScreenMaterialType.headerText:
        return 'Título (Header)';
      case ScreenMaterialType.subtitleText:
        return 'Subtítulo';
      case ScreenMaterialType.containerCard:
        return 'Glass Card';
      case ScreenMaterialType.icon:
        return 'Ícone';
      case ScreenMaterialType.switchTile:
        return 'Interruptor (Switch)';
      case ScreenMaterialType.checkboxTile:
        return 'Termos (Checkbox)';
    }
  }

  IconData get defaultIcon {
    switch (this) {
      case ScreenMaterialType.appBar:
        return Icons.web_asset_rounded;
      case ScreenMaterialType.textInput:
        return Icons.edit_note_rounded;
      case ScreenMaterialType.passwordInput:
        return Icons.lock_rounded;
      case ScreenMaterialType.primaryButton:
        return Icons.smart_button_rounded;
      case ScreenMaterialType.secondaryButton:
        return Icons.crop_16_9_rounded;
      case ScreenMaterialType.socialButton:
        return Icons.g_mobiledata_rounded;
      case ScreenMaterialType.headerText:
        return Icons.title_rounded;
      case ScreenMaterialType.subtitleText:
        return Icons.subtitles_rounded;
      case ScreenMaterialType.containerCard:
        return Icons.dashboard_customize_rounded;
      case ScreenMaterialType.icon:
        return Icons.stars_rounded;
      case ScreenMaterialType.switchTile:
        return Icons.toggle_on_rounded;
      case ScreenMaterialType.checkboxTile:
        return Icons.check_box_rounded;
    }
  }

  Color get accentColor {
    switch (this) {
      case ScreenMaterialType.appBar:
        return const Color(0xFF6366F1); // Indigo
      case ScreenMaterialType.textInput:
        return const Color(0xFF38BDF8); // Sky blue
      case ScreenMaterialType.passwordInput:
        return const Color(0xFFF59E0B); // Amber
      case ScreenMaterialType.primaryButton:
        return const Color(0xFF10B981); // Emerald
      case ScreenMaterialType.secondaryButton:
        return const Color(0xFF94A3B8); // Slate
      case ScreenMaterialType.socialButton:
        return const Color(0xFFEA4335); // Google red
      case ScreenMaterialType.headerText:
        return const Color(0xFFA855F7); // Purple
      case ScreenMaterialType.subtitleText:
        return const Color(0xFF64748B); // Muted slate
      case ScreenMaterialType.containerCard:
        return const Color(0xFF06B6D4); // Cyan
      case ScreenMaterialType.icon:
        return const Color(0xFFEAB308); // Yellow
      case ScreenMaterialType.switchTile:
        return const Color(0xFF14B8A6); // Teal
      case ScreenMaterialType.checkboxTile:
        return const Color(0xFF8B5CF6); // Violet
    }
  }

  String get shortChipLabel {
    switch (this) {
      case ScreenMaterialType.appBar:
        return 'AppBar';
      case ScreenMaterialType.textInput:
        return 'Input';
      case ScreenMaterialType.passwordInput:
        return 'Senha';
      case ScreenMaterialType.primaryButton:
        return 'Botão';
      case ScreenMaterialType.secondaryButton:
        return 'Outlined';
      case ScreenMaterialType.socialButton:
        return 'Social';
      case ScreenMaterialType.headerText:
        return 'Título';
      case ScreenMaterialType.subtitleText:
        return 'Subtítulo';
      case ScreenMaterialType.containerCard:
        return 'Card';
      case ScreenMaterialType.icon:
        return 'Ícone';
      case ScreenMaterialType.switchTile:
        return 'Switch';
      case ScreenMaterialType.checkboxTile:
        return 'Termos';
    }
  }
}

const _materialSentinel = Object();

/// A discrete component or visual material added to a screen.
class ScreenMaterialItem {
  final String id;
  final ScreenMaterialType type;
  final String label;
  final String? hint;
  final String? note;
  final IconData? icon;
  final String? iconName;
  final IconData? leadingIcon;
  final String? leadingIconName;
  final List<IconData> actionIcons;
  final List<String> actionIconNames;
  final bool isPassword;
  final dynamic initialValue;
  final Map<String, dynamic> properties;

  const ScreenMaterialItem({
    required this.id,
    required this.type,
    required this.label,
    this.hint,
    this.note,
    this.icon,
    this.iconName,
    this.leadingIcon,
    this.leadingIconName,
    this.actionIcons = const [],
    this.actionIconNames = const [],
    this.isPassword = false,
    this.initialValue,
    this.properties = const {},
  });

  /// Human-readable display name, preferring label if defined or fallback to type displayName.
  String get displayName => label.isNotEmpty ? label : type.displayName;

  ScreenMaterialItem copyWith({
    String? id,
    ScreenMaterialType? type,
    String? label,
    String? hint,
    Object? note = _materialSentinel,
    IconData? icon,
    String? iconName,
    IconData? leadingIcon,
    String? leadingIconName,
    List<IconData>? actionIcons,
    List<String>? actionIconNames,
    bool? isPassword,
    dynamic initialValue,
    Map<String, dynamic>? properties,
  }) {
    return ScreenMaterialItem(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      hint: hint ?? this.hint,
      note: identical(note, _materialSentinel) ? this.note : (note as String?),
      icon: icon ?? this.icon,
      iconName: iconName ?? this.iconName,
      leadingIcon: leadingIcon ?? this.leadingIcon,
      leadingIconName: leadingIconName ?? this.leadingIconName,
      actionIcons: actionIcons ?? this.actionIcons,
      actionIconNames: actionIconNames ?? this.actionIconNames,
      isPassword: isPassword ?? this.isPassword,
      initialValue: initialValue ?? this.initialValue,
      properties: properties ?? this.properties,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'label': label,
      'hint': hint,
      'note': note,
      'iconName': iconName,
      'leadingIconName': leadingIconName,
      'actionIconNames': actionIconNames,
      'isPassword': isPassword,
      'initialValue': initialValue,
      'properties': properties,
    };
  }

  factory ScreenMaterialItem.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'containerCard';
    final type = ScreenMaterialType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => ScreenMaterialType.containerCard,
    );
    final iconName = json['iconName'] as String?;
    final leadingIconName = json['leadingIconName'] as String?;
    final actionIconNames = (json['actionIconNames'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    return ScreenMaterialItem(
      id: json['id'] as String? ?? '',
      type: type,
      label: json['label'] as String? ?? '',
      hint: json['hint'] as String?,
      note: json['note'] as String?,
      icon: iconName != null ? ScreenMaterialCodeUpdater.resolveIcon(iconName) : null,
      iconName: iconName,
      leadingIcon: leadingIconName != null
          ? ScreenMaterialCodeUpdater.resolveIcon(leadingIconName)
          : null,
      leadingIconName: leadingIconName,
      actionIcons: actionIconNames
          .map((name) => ScreenMaterialCodeUpdater.resolveIcon(name))
          .toList(),
      actionIconNames: actionIconNames,
      isPassword: json['isPassword'] as bool? ?? false,
      initialValue: json['initialValue'],
      properties: json['properties'] != null
          ? Map<String, dynamic>.from(json['properties'] as Map)
          : const {},
    );
  }

  /// Instantiates a new copy with a unique runtime ID suitable for insertion into a screen stack.
  ScreenMaterialItem createInstance() {
    final rand = Random().nextInt(10000);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return copyWith(id: 'mat_${type.name}_${timestamp}_$rand');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScreenMaterialItem &&
        other.id == id &&
        other.type == type &&
        other.label == label &&
        other.hint == hint &&
        other.note == note &&
        other.isPassword == isPassword;
  }

  @override
  int get hashCode => Object.hash(id, type, label, hint, note, isPassword);

  @override
  String toString() => 'ScreenMaterialItem($id, ${type.name}, "$label", note: "$note")';
}

// =============================================================================
// CATALOG OF AVAILABLE MATERIALS (PALETTE)
// =============================================================================

/// Pre-configured catalog of components users can click or drag-and-drop into their screen.
final List<ScreenMaterialItem> availableMaterialPalette = [
  const ScreenMaterialItem(
    id: 'palette_app_bar',
    type: ScreenMaterialType.appBar,
    label: 'Barra Superior',
    hint: 'AppBar com título e ações',
    note: null,
    leadingIcon: Icons.arrow_back_rounded,
    leadingIconName: 'arrow_back_rounded',
    actionIcons: [Icons.notifications_outlined, Icons.more_vert_rounded],
    actionIconNames: ['notifications_outlined', 'more_vert_rounded'],
  ),
  const ScreenMaterialItem(
    id: 'palette_header_text',
    type: ScreenMaterialType.headerText,
    label: 'Título de Destaque',
    hint: 'Tipografia grande para o topo da tela',
    note: null,
  ),
  const ScreenMaterialItem(
    id: 'palette_subtitle_text',
    type: ScreenMaterialType.subtitleText,
    label: 'Subtítulo explicativo',
    hint: 'Texto descritivo em tom atenuado',
    note: null,
  ),
  const ScreenMaterialItem(
    id: 'palette_text_input',
    type: ScreenMaterialType.textInput,
    label: 'Campo de Texto',
    hint: 'Digite aqui...',
    note: null,
    icon: Icons.edit_note_rounded,
    iconName: 'edit_note_rounded',
  ),
  const ScreenMaterialItem(
    id: 'palette_password_input',
    type: ScreenMaterialType.passwordInput,
    label: 'Senha de Acesso',
    hint: '••••••••',
    note: null,
    icon: Icons.lock_outline_rounded,
    iconName: 'lock_outline_rounded',
    isPassword: true,
  ),
  const ScreenMaterialItem(
    id: 'palette_primary_button',
    type: ScreenMaterialType.primaryButton,
    label: 'Ação Principal',
    hint: 'Botão elevado de destaque',
    note: null,
    icon: Icons.arrow_forward_rounded,
    iconName: 'arrow_forward_rounded',
  ),
  const ScreenMaterialItem(
    id: 'palette_secondary_button',
    type: ScreenMaterialType.secondaryButton,
    label: 'Ação Secundária',
    hint: 'Botão outlined com borda sutil',
    note: null,
  ),
  const ScreenMaterialItem(
    id: 'palette_social_button',
    type: ScreenMaterialType.socialButton,
    label: 'Continuar com Google',
    hint: 'Autenticação rápida com provedor externo',
    note: null,
    icon: Icons.g_mobiledata_rounded,
    iconName: 'g_mobiledata_rounded',
  ),
  const ScreenMaterialItem(
    id: 'palette_container_card',
    type: ScreenMaterialType.containerCard,
    label: 'Container Obsidian Card',
    hint: 'Card com fundo de vidro translúcido',
    note: null,
  ),
  const ScreenMaterialItem(
    id: 'palette_icon',
    type: ScreenMaterialType.icon,
    label: 'Ícone Ilustrativo',
    hint: 'Glifo vetorial para ilustração da tela',
    note: null,
    icon: Icons.stars_rounded,
    iconName: 'stars_rounded',
  ),
  const ScreenMaterialItem(
    id: 'palette_switch_tile',
    type: ScreenMaterialType.switchTile,
    label: 'Lembrar configurações',
    hint: 'Interruptor on/off booleano',
    note: null,
    initialValue: true,
  ),
  const ScreenMaterialItem(
    id: 'palette_checkbox_tile',
    type: ScreenMaterialType.checkboxTile,
    label: 'Aceito os Termos de Serviço',
    hint: 'Caixa de seleção de termos e políticas',
    note: null,
    initialValue: true,
  ),
];

// =============================================================================
// SCREEN MATERIAL CODE UPDATER & SYNCHRONIZER
// =============================================================================

/// Engine responsible for extracting materials from Flutter source code,
/// generating clean Flutter Dart code from material stacks, and synchronizing
/// additions, deletions, reorders, and AI prompts.
class ScreenMaterialCodeUpdater {
  static const Map<String, IconData> _namedIcons = {
    'arrow_back': Icons.arrow_back,
    'arrow_back_rounded': Icons.arrow_back_rounded,
    'arrow_forward': Icons.arrow_forward,
    'arrow_forward_rounded': Icons.arrow_forward_rounded,
    'notifications': Icons.notifications,
    'notifications_outlined': Icons.notifications_outlined,
    'notifications_rounded': Icons.notifications_rounded,
    'more_vert': Icons.more_vert,
    'more_vert_rounded': Icons.more_vert_rounded,
    'edit': Icons.edit,
    'edit_note': Icons.edit_note,
    'edit_note_rounded': Icons.edit_note_rounded,
    'lock': Icons.lock,
    'lock_outline': Icons.lock_outline,
    'lock_outline_rounded': Icons.lock_outline_rounded,
    'lock_rounded': Icons.lock_rounded,
    'email': Icons.email,
    'email_outlined': Icons.email_outlined,
    'email_rounded': Icons.email_rounded,
    'person': Icons.person,
    'person_outline': Icons.person_outline,
    'person_rounded': Icons.person_rounded,
    'smart_button': Icons.smart_button,
    'smart_button_rounded': Icons.smart_button_rounded,
    'crop_16_9': Icons.crop_16_9,
    'crop_16_9_rounded': Icons.crop_16_9_rounded,
    'g_mobiledata': Icons.g_mobiledata,
    'g_mobiledata_rounded': Icons.g_mobiledata_rounded,
    'apple': Icons.apple,
    'star': Icons.star,
    'star_rounded': Icons.star_rounded,
    'stars_rounded': Icons.stars_rounded,
    'favorite': Icons.favorite,
    'favorite_rounded': Icons.favorite_rounded,
    'settings': Icons.settings,
    'settings_rounded': Icons.settings_rounded,
    'home': Icons.home,
    'home_rounded': Icons.home_rounded,
    'dashboard': Icons.dashboard,
    'dashboard_rounded': Icons.dashboard_rounded,
    'dashboard_customize_rounded': Icons.dashboard_customize_rounded,
    'toggle_on': Icons.toggle_on,
    'toggle_on_rounded': Icons.toggle_on_rounded,
    'check_box': Icons.check_box,
    'check_box_rounded': Icons.check_box_rounded,
    'title': Icons.title,
    'title_rounded': Icons.title_rounded,
    'subtitles': Icons.subtitles,
    'subtitles_rounded': Icons.subtitles_rounded,
    'web_asset': Icons.web_asset,
    'web_asset_rounded': Icons.web_asset_rounded,
    'search': Icons.search,
    'search_rounded': Icons.search_rounded,
    'check': Icons.check,
    'check_circle': Icons.check_circle,
    'close': Icons.close,
    'visibility': Icons.visibility,
    'visibility_off': Icons.visibility_off,
  };

  /// Public helper resolving material icon names to Material Icons.
  static IconData resolveIcon(String name) => _resolveIcon(name);

  static IconData _resolveIcon(String name) {
    final clean = name.toLowerCase().trim();
    if (_namedIcons.containsKey(clean)) return _namedIcons[clean]!;
    final stripped = clean
        .replaceAll('_rounded', '')
        .replaceAll('_outlined', '')
        .replaceAll('_sharp', '');
    if (_namedIcons.containsKey(stripped)) return _namedIcons[stripped]!;
    return Icons.star_rounded;
  }

  static String? _extractPrecedingNote(String code, int matchStart) {
    final prefixStart = max(0, matchStart - 250);
    final prefix = code.substring(prefixStart, matchStart);
    final noteMatches = RegExp(r'///\s*Note:\s*([^\r\n]+)').allMatches(prefix);
    if (noteMatches.isEmpty) return null;

    final lastMatch = noteMatches.last;
    final between = prefix.substring(lastMatch.end);
    // Do not let an earlier sibling widget's note bleed across statements/list elements.
    if (between.contains(';') || between.contains(']') || between.contains('}')) {
      return null;
    }
    if (RegExp(
      r'\b(?:Text|TextField|TextFormField|ElevatedButton|OutlinedButton|TextButton|SwitchListTile|Switch|CheckboxListTile|Checkbox|Card|Container|Icon|AppBar|SizedBox)\s*\(',
    ).hasMatch(between)) {
      return null;
    }
    return lastMatch.group(1)?.trim();
  }

  static String _iconName(IconData? icon, [String? fallback]) {
    if (fallback != null && fallback.isNotEmpty) return fallback;
    if (icon == null) return 'star_rounded';
    for (final entry in _namedIcons.entries) {
      if (entry.value.codePoint == icon.codePoint) {
        return entry.key;
      }
    }
    return 'star_rounded';
  }

  static int _findMatchingParen(String text, int openParenIndex) {
    return DartSyntaxScanner.findMatchingDelimiter(text, openParenIndex);
  }

  static String _indentSnippet(String snippet, String baseIndent) {
    final lines = snippet.trimRight().split('\n');
    int? minIndent;
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      final match = RegExp(r'^[ \t]*').firstMatch(l);
      final len = match?.group(0)?.length ?? 0;
      if (minIndent == null || len < minIndent) {
        minIndent = len;
      }
    }
    minIndent ??= 0;
    return lines.map((l) {
      if (l.trim().isEmpty) return '';
      final stripped =
          l.length >= minIndent! ? l.substring(minIndent) : l.trimLeft();
      return '$baseIndent$stripped';
    }).join('\n');
  }

  static bool _isRangeConsumed(int pos, List<List<int>> ranges) {
    for (final r in ranges) {
      if (pos >= r[0] && pos < r[1]) return true;
    }
    return false;
  }

  static String _escape(String s) {
    return s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');
  }

  static String _detectClassName(String code, [String? fallback]) {
    final match = RegExp(
      r'class\s+([a-zA-Z0-9_]+)\s+extends\s+(?:StatefulWidget|StatelessWidget|ConsumerWidget|ConsumerStatefulWidget)',
    ).firstMatch(code);
    if (match != null) {
      return match.group(1)!;
    }
    return fallback ?? 'GeneratedScreen';
  }

  static String _detectRoutePath(String code, [String? fallback]) {
    final match = RegExp(r'/// Route:\s*([^\r\n]+)').firstMatch(code);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return fallback ?? '/screen';
  }

  static bool _detectProtected(String code, [bool fallback = false]) {
    if (code.contains('/// Protected: true') ||
        code.contains('AuthGuard') ||
        code.contains('isProtected = true')) {
      return true;
    }
    return fallback;
  }

  // ---------------------------------------------------------------------------
  // 1. EXTRACT MATERIALS FROM CODE
  // ---------------------------------------------------------------------------

  /// Parses Flutter Dart code and extracts the list of visual materials in order.
  static List<ScreenMaterialItem> extractMaterialsFromCode(
    String code, [
    String? routeTitle,
  ]) {
    return _extractMaterialSpans(code, routeTitle)
        .map((m) => m.item)
        .toList();
  }

  static bool _isInScopes(int pos, List<List<int>> scopes) {
    if (scopes.isEmpty) return true;
    for (final s in scopes) {
      if (pos >= s[0] && pos < s[1]) return true;
    }
    return false;
  }

  static List<_ExtractedSnippet> _extractMaterialSpans(
    String code, [
    String? routeTitle,
  ]) {
    if (code.trim().isEmpty) {
      return const [];
    }

    final primaryScopes = DartSyntaxScanner.findPrimaryScreenScopes(
      code,
      preferredClassName: routeTitle,
    );
    final List<_ExtractedSnippet> matches = [];
    final List<List<int>> consumedRanges = [];

    // Pre-consume wrapped custom widget blocks so custom injected widgets are not
    // torn apart into unrelated primitives during extraction/roundtrips.
    for (final block in DartSyntaxScanner.findCustomWidgetMarkerBlocks(code)) {
      consumedRanges.add([block.start, block.end]);
    }

    // A. Parse AppBar
    for (final appBarMatch in RegExp(r'\bAppBar\s*\(').allMatches(code)) {
      if (!_isInScopes(appBarMatch.start, primaryScopes)) continue;
      if (_isRangeConsumed(appBarMatch.start, consumedRanges)) continue;
      final openParen = appBarMatch.end - 1;
      final closeParen = _findMatchingParen(code, openParen);
      final appBarEnd = closeParen != -1 ? closeParen + 1 : code.length;
      final appBarSnippet = closeParen != -1
          ? code.substring(openParen + 1, closeParen)
          : code.substring(openParen + 1);

      String title = routeTitle ?? 'App Bar';
      final titleMatch = RegExp(
        r'''title:\s*(?:const\s+)?Text\s*\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      ).firstMatch(appBarSnippet);
      if (titleMatch != null) {
        title = titleMatch.group(1) ?? titleMatch.group(2) ?? title;
      }

      IconData? leadingIcon;
      String? leadingName;
      final leadingMatch = RegExp(
        r'leading:\s*[^)]*?Icons\.([a-zA-Z0-9_]+)',
      ).firstMatch(appBarSnippet);
      if (leadingMatch != null) {
        leadingName = leadingMatch.group(1);
        leadingIcon = _resolveIcon(leadingName!);
      }

      final List<IconData> actionIcons = [];
      final List<String> actionNames = [];
      final actionBlockMatch = RegExp(
        r'actions:\s*\[(.*?)\]',
        dotAll: true,
      ).firstMatch(appBarSnippet);
      final searchArea = actionBlockMatch != null
          ? actionBlockMatch.group(1)!
          : appBarSnippet;

      for (final m in RegExp(r'Icons\.([a-zA-Z0-9_]+)').allMatches(searchArea)) {
        final name = m.group(1)!;
        if (name != leadingName && !actionNames.contains(name)) {
          actionNames.add(name);
          actionIcons.add(_resolveIcon(name));
        }
      }

      consumedRanges.add([appBarMatch.start, appBarEnd]);

      final note = _extractPrecedingNote(code, appBarMatch.start);
      matches.add(_ExtractedSnippet(
        start: appBarMatch.start,
        end: appBarEnd,
        item: ScreenMaterialItem(
          id: 'appBar_0',
          type: ScreenMaterialType.appBar,
          label: title,
          note: note,
          leadingIcon: leadingIcon ?? Icons.arrow_back_rounded,
          leadingIconName: leadingName ?? 'arrow_back_rounded',
          actionIcons: actionIcons,
          actionIconNames: actionNames,
        ),
      ));
      break;
    }

    // B. Parse Inputs (TextField & TextFormField)
    final inputMatches = RegExp(r'\b(TextField|TextFormField)\s*\(').allMatches(code);
    for (final m in inputMatches) {
      if (!_isInScopes(m.start, primaryScopes)) continue;
      if (_isRangeConsumed(m.start, consumedRanges)) continue;
      final openParen = m.end - 1;
      final closeParen = _findMatchingParen(code, openParen);
      if (closeParen == -1) continue;

      final snippet = code.substring(openParen + 1, closeParen);
      consumedRanges.add([m.start, closeParen + 1]);

      String label = 'Campo de Texto';
      final labelMatch = RegExp(
        r'''labelText:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      ).firstMatch(snippet);
      if (labelMatch != null) {
        label = labelMatch.group(1) ?? labelMatch.group(2) ?? label;
      }

      String? hint;
      final hintMatch = RegExp(
        r'''hintText:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      ).firstMatch(snippet);
      if (hintMatch != null) {
        hint = hintMatch.group(1) ?? hintMatch.group(2);
      }

      IconData? prefixIcon;
      String? prefixName;
      final iconMatch = RegExp(
        r'prefixIcon:\s*[^)]*?Icons\.([a-zA-Z0-9_]+)',
      ).firstMatch(snippet);
      if (iconMatch != null) {
        prefixName = iconMatch.group(1);
        prefixIcon = _resolveIcon(prefixName!);
      }

      final isObscure = RegExp(r'obscureText:\s*([a-zA-Z0-9_]+)').firstMatch(snippet);
      final isPassword = (isObscure != null && isObscure.group(1) != 'false') ||
          label.toLowerCase().contains('senha') ||
          label.toLowerCase().contains('password') ||
          (prefixName != null && prefixName.contains('lock'));

      final note = _extractPrecedingNote(code, m.start);
      matches.add(_ExtractedSnippet(
        start: m.start,
        end: closeParen + 1,
        item: ScreenMaterialItem(
          id: '${isPassword ? "passwordInput" : "textInput"}_${matches.length}',
          type: isPassword
              ? ScreenMaterialType.passwordInput
              : ScreenMaterialType.textInput,
          label: label,
          hint: hint,
          note: note,
          icon: prefixIcon ??
              (isPassword
                  ? Icons.lock_outline_rounded
                  : Icons.edit_note_rounded),
          iconName: prefixName ??
              (isPassword ? 'lock_outline_rounded' : 'edit_note_rounded'),
          isPassword: isPassword,
        ),
      ));
    }

    // C. Parse Buttons (ElevatedButton, OutlinedButton, TextButton)
    final btnMatches = RegExp(
      r'\b(ElevatedButton|OutlinedButton|TextButton)(?:\.icon)?\s*\(',
    ).allMatches(code);
    for (final m in btnMatches) {
      if (!_isInScopes(m.start, primaryScopes)) continue;
      if (_isRangeConsumed(m.start, consumedRanges)) continue;
      final openParen = m.end - 1;
      final closeParen = _findMatchingParen(code, openParen);
      if (closeParen == -1) continue;

      final snippet = code.substring(openParen + 1, closeParen);
      consumedRanges.add([m.start, closeParen + 1]);

      final btnTypeStr = m.group(1)!;

      String label = 'Botão';
      final textMatch = RegExp(
        r'''Text\s*\(\s*(?:const\s+)?(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      ).firstMatch(snippet);
      if (textMatch != null) {
        label = textMatch.group(1) ?? textMatch.group(2) ?? label;
      }

      IconData? icon;
      String? iconName;
      final iconMatch = RegExp(r'Icons\.([a-zA-Z0-9_]+)').firstMatch(snippet);
      if (iconMatch != null) {
        iconName = iconMatch.group(1);
        icon = _resolveIcon(iconName!);
      }

      final lower = label.toLowerCase();
      final isSocial = lower.contains('google') ||
          lower.contains('apple') ||
          lower.contains('facebook') ||
          lower.contains('social') ||
          (iconName != null &&
              (iconName.contains('g_mobiledata') || iconName.contains('apple')));

      ScreenMaterialType matType;
      if (isSocial) {
        matType = ScreenMaterialType.socialButton;
      } else if (btnTypeStr == 'ElevatedButton') {
        matType = ScreenMaterialType.primaryButton;
      } else {
        matType = ScreenMaterialType.secondaryButton;
      }

      final note = _extractPrecedingNote(code, m.start);
      matches.add(_ExtractedSnippet(
        start: m.start,
        end: closeParen + 1,
        item: ScreenMaterialItem(
          id: '${matType.name}_${matches.length}',
          type: matType,
          label: label,
          note: note,
          icon: icon,
          iconName: iconName,
        ),
      ));
    }

    // D. Parse SwitchListTile / Switch
    final switchMatches =
        RegExp(r'\b(SwitchListTile|Switch)\s*\(').allMatches(code);
    for (final m in switchMatches) {
      if (!_isInScopes(m.start, primaryScopes)) continue;
      if (_isRangeConsumed(m.start, consumedRanges)) continue;
      final openParen = m.end - 1;
      final closeParen = _findMatchingParen(code, openParen);
      if (closeParen == -1) continue;

      final snippet = code.substring(openParen + 1, closeParen);
      consumedRanges.add([m.start, closeParen + 1]);

      String label = 'Opção';
      final labelMatch = RegExp(
        r'''title:\s*(?:const\s+)?Text\s*\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      ).firstMatch(snippet);
      if (labelMatch != null) {
        label = labelMatch.group(1) ?? labelMatch.group(2) ?? label;
      }

      final note = _extractPrecedingNote(code, m.start);
      matches.add(_ExtractedSnippet(
        start: m.start,
        end: closeParen + 1,
        item: ScreenMaterialItem(
          id: 'switchTile_${matches.length}',
          type: ScreenMaterialType.switchTile,
          label: label,
          note: note,
          initialValue: true,
        ),
      ));
    }

    // E. Parse CheckboxListTile / Checkbox
    final checkMatches =
        RegExp(r'\b(CheckboxListTile|Checkbox)\s*\(').allMatches(code);
    for (final m in checkMatches) {
      if (!_isInScopes(m.start, primaryScopes)) continue;
      if (_isRangeConsumed(m.start, consumedRanges)) continue;
      final openParen = m.end - 1;
      final closeParen = _findMatchingParen(code, openParen);
      if (closeParen == -1) continue;

      final snippet = code.substring(openParen + 1, closeParen);
      consumedRanges.add([m.start, closeParen + 1]);

      String label = 'Termos e Condições';
      final labelMatch = RegExp(
        r'''title:\s*(?:const\s+)?Text\s*\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      ).firstMatch(snippet);
      if (labelMatch != null) {
        label = labelMatch.group(1) ?? labelMatch.group(2) ?? label;
      }

      final note = _extractPrecedingNote(code, m.start);
      matches.add(_ExtractedSnippet(
        start: m.start,
        end: closeParen + 1,
        item: ScreenMaterialItem(
          id: 'checkboxTile_${matches.length}',
          type: ScreenMaterialType.checkboxTile,
          label: label,
          note: note,
          initialValue: true,
        ),
      ));
    }

    // F. Parse Glass Card Container
    final cardMatches =
        RegExp(r'\b(Card|Container)\s*\(').allMatches(code);
    for (final m in cardMatches) {
      if (!_isInScopes(m.start, primaryScopes)) continue;
      if (_isRangeConsumed(m.start, consumedRanges)) continue;
      final openParen = m.end - 1;
      final closeParen = _findMatchingParen(code, openParen);
      if (closeParen == -1) continue;

      final snippet = code.substring(openParen + 1, closeParen);
      final isCard = m.group(1) == 'Card' ||
          snippet.contains('BoxDecoration') ||
          snippet.contains('surfaceCard');
      if (!isCard) continue;

      consumedRanges.add([m.start, closeParen + 1]);

      String label = 'Glass Card Container';
      final textMatch = RegExp(
        r'''Text\s*\(\s*(?:const\s+)?(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      ).firstMatch(snippet);
      if (textMatch != null) {
        label = textMatch.group(1) ?? textMatch.group(2) ?? label;
      }

      final note = _extractPrecedingNote(code, m.start);
      matches.add(_ExtractedSnippet(
        start: m.start,
        end: closeParen + 1,
        item: ScreenMaterialItem(
          id: 'containerCard_${matches.length}',
          type: ScreenMaterialType.containerCard,
          label: label,
          note: note,
        ),
      ));
    }

    // G. Parse standalone Icons
    final iconMatches =
        RegExp(r'\bIcon\s*\(\s*Icons\.([a-zA-Z0-9_]+)').allMatches(code);
    for (final m in iconMatches) {
      if (!_isInScopes(m.start, primaryScopes)) continue;
      if (_isRangeConsumed(m.start, consumedRanges)) continue;
      final openParen = code.indexOf('(', m.start);
      final closeParen =
          openParen != -1 ? _findMatchingParen(code, openParen) : -1;
      final iconName = m.group(1)!;
      final note = _extractPrecedingNote(code, m.start);
      matches.add(_ExtractedSnippet(
        start: m.start,
        end: closeParen != -1 ? closeParen + 1 : m.end,
        item: ScreenMaterialItem(
          id: 'icon_${matches.length}',
          type: ScreenMaterialType.icon,
          label: 'Ícone ${iconName.replaceAll('_', ' ')}',
          note: note,
          icon: _resolveIcon(iconName),
          iconName: iconName,
        ),
      ));
    }

    // H. Parse standalone Texts (Header / Subtitle)
    final textMatches = RegExp(
      r'''\bText\s*\(\s*(?:const\s+)?(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")(.*?)\)''',
      dotAll: true,
    ).allMatches(code);
    for (final m in textMatches) {
      if (!_isInScopes(m.start, primaryScopes)) continue;
      if (_isRangeConsumed(m.start, consumedRanges)) continue;
      String text = m.group(1) ?? m.group(2) ?? '';
      if (text.contains(r'$displayTitle') && routeTitle != null) {
        text = text.replaceAll(r'$displayTitle', routeTitle);
      }
      if (text.trim().isEmpty) continue;

      final openParen = code.indexOf('(', m.start);
      final closeParen =
          openParen != -1 ? _findMatchingParen(code, openParen) : -1;

      final textParams = m.group(3) ?? '';
      final isLarge =
          RegExp(r'fontSize:\s*(?:1[89]|[2-9][0-9])').hasMatch(textParams);
      final isBold =
          RegExp(r'fontWeight:\s*FontWeight\.(?:bold|w[6-9]00)').hasMatch(textParams);

      final isHeader = isLarge || isBold;

      final note = _extractPrecedingNote(code, m.start);
      matches.add(_ExtractedSnippet(
        start: m.start,
        end: closeParen != -1 ? closeParen + 1 : m.end,
        item: ScreenMaterialItem(
          id: '${isHeader ? "headerText" : "subtitleText"}_${matches.length}',
          type: isHeader
              ? ScreenMaterialType.headerText
              : ScreenMaterialType.subtitleText,
          label: text,
          note: note,
        ),
      ));
    }

    // Sort in order of appearance in source code
    matches.sort((a, b) => a.start.compareTo(b.start));

    // Re-index identifiers deterministically
    final results = <_ExtractedSnippet>[];
    for (int i = 0; i < matches.length; i++) {
      final entry = matches[i];
      results.add(_ExtractedSnippet(
        start: entry.start,
        end: entry.end,
        item: entry.item.copyWith(id: '${entry.item.type.name}_$i'),
      ));
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // 2. BUILD DART CODE FROM MATERIALS
  // ---------------------------------------------------------------------------

  /// Generates idiomatic, compilable Flutter Dart code strictly reflecting the materials list,
  /// optionally preserving [extraImports], [extraClasses], and [preservedCustomWidgets].
  static String buildDartCodeFromMaterials({
    required String screenClassName,
    required String routePath,
    required List<ScreenMaterialItem> materials,
    bool isProtected = false,
    List<String> extraImports = const [],
    List<String> extraClasses = const [],
    List<String> preservedCustomWidgets = const [],
  }) {
    ScreenMaterialItem? appBarItem;
    final bodyMaterials = <ScreenMaterialItem>[];

    for (final m in materials) {
      if (m.type == ScreenMaterialType.appBar && appBarItem == null) {
        appBarItem = m;
      } else {
        bodyMaterials.add(m);
      }
    }

    final bodyWidgetsCode = <String>[];
    for (final custom in preservedCustomWidgets) {
      final trimmed = custom.trim();
      if (trimmed.isNotEmpty) {
        bodyWidgetsCode.add(_indentSnippet(trimmed, '              ').trimLeft());
      }
    }
    for (final item in bodyMaterials) {
      bodyWidgetsCode.add(_generateMaterialWidgetCode(item));
    }

    final importLines = <String>["import 'package:flutter/material.dart';"];
    final seenImportUris = <String>{'package:flutter/material.dart'};
    for (final rawImp in extraImports) {
      final uri = DartSyntaxScanner.normalizeImportUri(rawImp);
      final directive = DartSyntaxScanner.formatImportDirective(rawImp);
      if (uri.isNotEmpty &&
          directive.isNotEmpty &&
          seenImportUris.add(uri)) {
        importLines.add(directive);
      }
    }

    final appBarNote = (appBarItem?.note != null && appBarItem!.note!.trim().isNotEmpty)
        ? '/// Note: ${appBarItem.note!.trim().replaceAll(RegExp(r'[\r\n]+'), ' ')}\n      '
        : '';
    final appBarSection = appBarItem != null
        ? '''${appBarNote}appBar: AppBar(
        title: const Text(
          '${_escape(appBarItem.label)}',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        centerTitle: true,
        ${appBarItem.leadingIcon != null ? "leading: IconButton(icon: const Icon(Icons.${_iconName(appBarItem.leadingIcon, appBarItem.leadingIconName)}), onPressed: () {})," : ""}
        ${appBarItem.actionIcons.isNotEmpty ? """actions: [
          ${appBarItem.actionIcons.map((act) => "IconButton(icon: const Icon(Icons.${_iconName(act)}), onPressed: () {}),").join('\n          ')}
        ],""" : ""}
      ),'''
        : '';

    final trailingClasses = extraClasses
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .join('\n\n');
    final trailingSection = trailingClasses.isNotEmpty ? '\n$trailingClasses\n' : '';

    return '''${importLines.join('\n')}

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

/// Generated by FLRD Screen Material Studio
/// Route: $routePath
/// Protected: $isProtected
class $screenClassName extends StatefulWidget {
  const $screenClassName({super.key});

  @override
  State<$screenClassName> createState() => _${screenClassName}State();
}

class _${screenClassName}State extends State<$screenClassName> {
  bool _obscurePassword = true;
  bool _switchValue = true;
  bool _checkboxValue = true;
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      $appBarSection
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ${bodyWidgetsCode.join('\n              ')}
            ],
          ),
        ),
      ),
    );
  }
}
$trailingSection''';
  }

  static String _generateMaterialWidgetCode(ScreenMaterialItem item) {
    final noteComment = (item.note != null && item.note!.trim().isNotEmpty)
        ? '/// Note: ${item.note!.trim().replaceAll(RegExp(r'[\r\n]+'), ' ')}\n              '
        : '';
    switch (item.type) {
      case ScreenMaterialType.appBar:
        return '';
      case ScreenMaterialType.headerText:
        return '''${noteComment}Text(
                '${_escape(item.label)}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),''';
      case ScreenMaterialType.subtitleText:
        return '''${noteComment}Text(
                '${_escape(item.label)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),''';
      case ScreenMaterialType.textInput:
        final iconSnippet = item.icon != null
            ? "prefixIcon: const Icon(Icons.${_iconName(item.icon, item.iconName)}),"
            : "";
        return '''${noteComment}TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: '${_escape(item.label)}',
                  hintText: '${_escape(item.hint ?? '')}',
                  $iconSnippet
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 16),''';
      case ScreenMaterialType.passwordInput:
        return '''${noteComment}TextField(
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '${_escape(item.label)}',
                  hintText: '${_escape(item.hint ?? '••••••••')}',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 16),''';
      case ScreenMaterialType.primaryButton:
        final iconName = _iconName(item.icon, item.iconName);
        final childSnippet = item.icon != null
            ? "Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.$iconName), SizedBox(width: 8), Text('${_escape(item.label)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))])"
            : "const Text('${_escape(item.label)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))";
        return '''${noteComment}ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: $childSnippet,
              ),
              const SizedBox(height: 16),''';
      case ScreenMaterialType.secondaryButton:
        return '''${noteComment}OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('${_escape(item.label)}', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),''';
      case ScreenMaterialType.socialButton:
        final iconName =
            _iconName(item.icon, item.iconName ?? 'g_mobiledata_rounded');
        return '''${noteComment}OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.$iconName, size: 24, color: AppColors.textPrimary),
                label: const Text('${_escape(item.label)}', style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.border),
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),''';
      case ScreenMaterialType.containerCard:
        return '''${noteComment}Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '${_escape(item.label)}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '${_escape(item.hint ?? "Conteúdo do Card")}',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),''';
      case ScreenMaterialType.icon:
        final iconName = _iconName(item.icon, item.iconName ?? 'stars_rounded');
        return '''${noteComment}Center(
                child: Icon(
                  Icons.$iconName,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),''';
      case ScreenMaterialType.switchTile:
        return '''${noteComment}SwitchListTile(
                title: const Text(
                  '${_escape(item.label)}',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                ),
                value: _switchValue,
                onChanged: (val) => setState(() => _switchValue = val),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),''';
      case ScreenMaterialType.checkboxTile:
        return '''${noteComment}CheckboxListTile(
                title: const Text(
                  '${_escape(item.label)}',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                value: _checkboxValue,
                onChanged: (val) => setState(() => _checkboxValue = val ?? false),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),''';
    }
  }

  // ---------------------------------------------------------------------------
  // 3. MUTATION APIS: ADD, REMOVE, REORDER (SURGICAL AST-PRESERVING)
  // ---------------------------------------------------------------------------

  /// Adds a material item to the screen code deterministically while preserving
  /// existing imports, extra classes, and custom widgets.
  static String addMaterialToCode({
    required String currentCode,
    required ScreenMaterialItem newMaterial,
    int? index,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    if (currentCode.trim().isNotEmpty) {
      final surgical = _tryAddMaterialSurgically(
        currentCode: currentCode,
        newMaterial: newMaterial,
        index: index,
        routeTitle: routeTitle,
      );
      if (surgical != null) {
        return surgical;
      }
    }

    final extras = _extractPreservedExtras(currentCode, routeTitle);
    final materials = List<ScreenMaterialItem>.from(
      extractMaterialsFromCode(currentCode, routeTitle),
    );

    if (newMaterial.type == ScreenMaterialType.appBar && index == null) {
      materials.insert(0, newMaterial);
    } else if (index != null && index >= 0 && index <= materials.length) {
      materials.insert(index, newMaterial);
    } else {
      materials.add(newMaterial);
    }

    return buildDartCodeFromMaterials(
      screenClassName: screenClassName ?? _detectClassName(currentCode),
      routePath: routePath ?? _detectRoutePath(currentCode),
      materials: materials,
      isProtected: isProtected || _detectProtected(currentCode),
      extraImports: extras.extraImports,
      extraClasses: extras.extraClasses,
      preservedCustomWidgets: extras.customWidgets,
    );
  }

  /// Removes a material item from the screen code deterministically while preserving
  /// existing imports, extra classes, and custom widgets.
  static String removeMaterialFromCode({
    required String currentCode,
    required String materialId,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    final resolved = _resolveMaterialSpans(currentCode, routeTitle);
    int? targetIdx;
    final exactIdx = resolved.indexWhere((m) => m.item.id == materialId);
    if (exactIdx != -1) {
      targetIdx = exactIdx;
    } else {
      final intIndex = int.tryParse(materialId);
      if (intIndex != null && intIndex >= 0 && intIndex < resolved.length) {
        targetIdx = intIndex;
      } else {
        final typeIdx = resolved.indexWhere(
          (m) => m.item.type.name.toLowerCase() == materialId.toLowerCase(),
        );
        if (typeIdx != -1) {
          targetIdx = typeIdx;
        }
      }
    }

    if (targetIdx != null) {
      final surgical = _tryRemoveResolvedAtIndex(currentCode, resolved, targetIdx);
      if (surgical != null) {
        return surgical;
      }
    } else if (currentCode.trim().isNotEmpty) {
      return currentCode;
    }

    final extras = _extractPreservedExtras(currentCode, routeTitle);
    final materials = resolved.map((m) => m.item).toList();
    if (targetIdx != null) {
      materials.removeAt(targetIdx);
    }

    return buildDartCodeFromMaterials(
      screenClassName: screenClassName ?? _detectClassName(currentCode),
      routePath: routePath ?? _detectRoutePath(currentCode),
      materials: materials,
      isProtected: isProtected || _detectProtected(currentCode),
      extraImports: extras.extraImports,
      extraClasses: extras.extraClasses,
      preservedCustomWidgets: extras.customWidgets,
    );
  }

  /// Removes a material item at a specific index while preserving
  /// existing imports, extra classes, and custom widgets.
  static String removeMaterialAtIndexInCode({
    required String currentCode,
    required int index,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    final resolved = _resolveMaterialSpans(currentCode, routeTitle);
    if (index < 0 || index >= resolved.length) {
      return currentCode;
    }

    final surgical = _tryRemoveResolvedAtIndex(currentCode, resolved, index);
    if (surgical != null) {
      return surgical;
    }

    final extras = _extractPreservedExtras(currentCode, routeTitle);
    final materials = resolved.map((m) => m.item).toList()..removeAt(index);

    return buildDartCodeFromMaterials(
      screenClassName: screenClassName ?? _detectClassName(currentCode),
      routePath: routePath ?? _detectRoutePath(currentCode),
      materials: materials,
      isProtected: isProtected || _detectProtected(currentCode),
      extraImports: extras.extraImports,
      extraClasses: extras.extraClasses,
      preservedCustomWidgets: extras.customWidgets,
    );
  }

  /// Reorders a material item from `oldIndex` to `newIndex` while preserving
  /// existing imports, extra classes, and custom widgets.
  static String reorderMaterialsInCode({
    required String currentCode,
    required int oldIndex,
    required int newIndex,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    final resolved = _resolveMaterialSpans(currentCode, routeTitle);
    if (oldIndex < 0 || oldIndex >= resolved.length) {
      return currentCode;
    }

    final reordered = List<_ResolvedMaterialSpan>.from(resolved);
    final moved = reordered.removeAt(oldIndex);
    final safeNewIndex = newIndex.clamp(0, reordered.length);
    reordered.insert(safeNewIndex, moved);

    if (oldIndex == safeNewIndex) {
      return currentCode;
    }

    if (moved.isAppBar) {
      // AppBar lives in Scaffold.appBar rather than Column.children, so moving
      // it in the list does not displace body items or drop custom code.
      return currentCode;
    }

    final origBody = resolved.where((m) => !m.isAppBar).toList();
    final newBody = reordered.where((m) => !m.isAppBar).toList();

    final surgical = _tryReorderBodySpans(currentCode, origBody, newBody);
    if (surgical != null) {
      return surgical;
    }

    final extras = _extractPreservedExtras(currentCode, routeTitle);
    final materials = reordered.map((m) => m.item).toList();

    return buildDartCodeFromMaterials(
      screenClassName: screenClassName ?? _detectClassName(currentCode),
      routePath: routePath ?? _detectRoutePath(currentCode),
      materials: materials,
      isProtected: isProtected || _detectProtected(currentCode),
      extraImports: extras.extraImports,
      extraClasses: extras.extraClasses,
      preservedCustomWidgets: extras.customWidgets,
    );
  }

  /// Updates or clears the behavioral note for a material item in the screen code
  /// while preserving existing imports, extra classes, and custom widgets.
  static String updateMaterialNoteInCode({
    required String currentCode,
    required String materialId,
    required String? note,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    final resolved = _resolveMaterialSpans(currentCode, routeTitle);
    int? targetIdx;
    final exactIdx = resolved.indexWhere((m) => m.item.id == materialId);
    if (exactIdx != -1) {
      targetIdx = exactIdx;
    } else {
      final intIndex = int.tryParse(materialId);
      if (intIndex != null && intIndex >= 0 && intIndex < resolved.length) {
        targetIdx = intIndex;
      }
    }

    if (targetIdx != null) {
      final surgical = _tryUpdateNoteSurgically(
        currentCode,
        resolved[targetIdx],
        note,
      );
      if (surgical != null) {
        return surgical;
      }
    }

    final extras = _extractPreservedExtras(currentCode, routeTitle);
    final materials = resolved.map((m) => m.item).toList();
    if (targetIdx != null) {
      materials[targetIdx] = materials[targetIdx].copyWith(note: note);
    }

    return buildDartCodeFromMaterials(
      screenClassName: screenClassName ?? _detectClassName(currentCode),
      routePath: routePath ?? _detectRoutePath(currentCode),
      materials: materials,
      isProtected: isProtected || _detectProtected(currentCode),
      extraImports: extras.extraImports,
      extraClasses: extras.extraClasses,
      preservedCustomWidgets: extras.customWidgets,
    );
  }

  /// Safely inserts a widget snippet into the screen's main `children: [...]` of Column/ListView,
  /// stripping `const` from `children: const [` when needed and formatting indentation cleanly.
  static String insertWidgetSnippetIntoScreenCode(
    String screenCode,
    String widgetSnippet,
  ) {
    final cleanSnippet = widgetSnippet.trim();
    if (cleanSnippet.isEmpty) return screenCode;

    if (screenCode.trim().isEmpty) {
      return '''import 'package:flutter/material.dart';

class GeneratedScreen extends StatelessWidget {
  const GeneratedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              $cleanSnippet,
            ],
          ),
        ),
      ),
    );
  }
}
''';
    }

    final targetList = DartSyntaxScanner.findPrimaryChildrenList(screenCode);
    if (targetList == null) {
      return screenCode;
    }

    var working = screenCode;
    var openBracket = targetList.openBracket;
    var closeBracket = targetList.closeBracket;

    // Strip `const ` from `children: const [` / `children: const <Widget>[` and
    // any enclosing const layout widget when inserting non-const code.
    final stripConst = _stripConstAroundChildrenList(
      working,
      targetList,
      stripParentWidgetConst: !cleanSnippet.startsWith('const '),
    );
    working = stripConst.code;
    openBracket = stripConst.openBracket;
    closeBracket = stripConst.closeBracket;

    final listIndent = _lineIndentAt(working, targetList.matchStart - stripConst.deltaBeforeList);
    final closingLineStart = working.lastIndexOf('\n', closeBracket);
    String parentIndent = listIndent;
    if (closingLineStart != -1) {
      final prefix = working.substring(closingLineStart + 1, closeBracket);
      if (prefix.trim().isEmpty) {
        parentIndent = prefix;
      }
    }
    final childIndent = '$parentIndent  ';

    final inside = working.substring(openBracket + 1, closeBracket);
    final trimmedInside = inside.trim();
    final needsLeadingComma =
        trimmedInside.isNotEmpty && !trimmedInside.endsWith(',');

    final formattedSnippet = _indentSnippet(cleanSnippet, childIndent);

    final buffer = StringBuffer();
    if (trimmedInside.isEmpty) {
      buffer.write(working.substring(0, openBracket + 1));
      buffer.write('\n');
      buffer.write(formattedSnippet);
      buffer.write(',\n');
      buffer.write(parentIndent);
      buffer.write(working.substring(closeBracket));
    } else {
      buffer.write(working.substring(0, closeBracket));
      if (needsLeadingComma) {
        buffer.write(',');
      }
      buffer.write('\n');
      buffer.write(formattedSnippet);
      buffer.write(',\n');
      buffer.write(parentIndent);
      buffer.write(working.substring(closeBracket));
    }

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // SURGICAL AST HELPERS
  // ---------------------------------------------------------------------------

  static ({
    List<String> extraImports,
    List<String> extraClasses,
    List<String> customWidgets,
  }) _extractPreservedExtras(String code, String? routeTitle) {
    if (code.trim().isEmpty) {
      return (
        extraImports: const [],
        extraClasses: const [],
        customWidgets: const [],
      );
    }

    final extraImports = <String>[];
    for (final imp in DartSyntaxScanner.findImportDirectives(code)) {
      if (imp.uri != 'package:flutter/material.dart') {
        extraImports.add(imp.rawStatement);
      }
    }

    final primaryScopes = DartSyntaxScanner.findPrimaryScreenScopes(
      code,
      preferredClassName: routeTitle,
    );
    final decls = DartSyntaxScanner.findTopLevelDeclarations(code);
    final extraClasses = <String>[];
    for (final d in decls) {
      if (d.name == 'AppColors') continue;
      final inPrimary = primaryScopes.any((s) => d.start >= s[0] && d.end <= s[1]);
      if (!inPrimary) {
        extraClasses.add(code.substring(d.start, d.end).trim());
      }
    }

    final customWidgets = <String>[];
    for (final block in DartSyntaxScanner.findCustomWidgetMarkerBlocks(code)) {
      customWidgets.add(code.substring(block.start, block.end).trim());
    }

    return (
      extraImports: extraImports,
      extraClasses: extraClasses,
      customWidgets: customWidgets,
    );
  }

  static List<_ResolvedMaterialSpan> _resolveMaterialSpans(
    String code,
    String? routeTitle,
  ) {
    final extracted = _extractMaterialSpans(code, routeTitle);
    if (extracted.isEmpty) return const [];

    final primaryScopes = DartSyntaxScanner.findPrimaryScreenScopes(
      code,
      preferredClassName: routeTitle,
    );
    final buildMethod = DartSyntaxScanner.findBuildMethod(
      code,
      startOffset: primaryScopes.isNotEmpty ? primaryScopes.first[0] : 0,
      endOffset: primaryScopes.isNotEmpty ? primaryScopes.last[1] : null,
    );

    DartNamedArg? appBarArg;
    final childLists = <({
      DartChildrenListMatch list,
      List<DartSpan> elements,
    })>[];

    if (buildMethod != null) {
      final scaffoldMatch = RegExp(r'\bScaffold\s*\(').firstMatch(
        code.substring(buildMethod.bodyStart, buildMethod.bodyEnd),
      );
      if (scaffoldMatch != null) {
        final openParen =
            buildMethod.bodyStart + scaffoldMatch.end - 1;
        final closeParen = DartSyntaxScanner.findMatchingDelimiter(
          code,
          openParen,
        );
        if (closeParen != -1) {
          for (final arg
              in DartSyntaxScanner.findNamedArguments(code, openParen, closeParen)) {
            if (arg.name == 'appBar') {
              appBarArg = arg;
              break;
            }
          }
        }
      }

      for (final list in DartSyntaxScanner.findAllChildrenLists(
        code,
        startOffset: buildMethod.bodyStart,
        endOffset: buildMethod.bodyEnd,
      )) {
        final elems = DartSyntaxScanner.splitTopLevelElements(
          code,
          list.openBracket,
          list.closeBracket,
        );
        childLists.add((list: list, elements: elems));
      }
    }

    final results = <_ResolvedMaterialSpan>[];
    for (final m in extracted) {
      final isAppBar = m.item.type == ScreenMaterialType.appBar;
      DartChildrenListMatch? ownerList;
      List<DartSpan>? ownerElements;
      int? elemIndex;
      DartSpan? childSpan;
      DartSpan? pairedSpacerSpan;

      if (!isAppBar) {
        for (final entry in childLists) {
          if (m.start > entry.list.openBracket &&
              m.start < entry.list.closeBracket) {
            for (int i = 0; i < entry.elements.length; i++) {
              final el = entry.elements[i];
              if (m.start >= el.fullStart && m.start <= el.codeEnd) {
                ownerList = entry.list;
                ownerElements = entry.elements;
                elemIndex = i;
                childSpan = el;
                if (i + 1 < entry.elements.length &&
                    _isPureSpacerElement(code, entry.elements[i + 1])) {
                  pairedSpacerSpan = entry.elements[i + 1];
                }
                break;
              }
            }
            if (childSpan != null) break;
          }
        }
      }

      results.add(_ResolvedMaterialSpan(
        item: m.item,
        matchStart: m.start,
        matchEnd: m.end,
        isAppBar: isAppBar,
        appBarArg: isAppBar ? appBarArg : null,
        ownerList: ownerList,
        ownerElements: ownerElements,
        elemIndex: elemIndex,
        childSpan: childSpan,
        pairedSpacerSpan: pairedSpacerSpan,
      ));
    }

    return results;
  }

  static bool _isPureSpacerElement(String code, DartSpan elem) {
    final full = code.substring(elem.fullStart, elem.codeEnd).trim();
    if (full.contains('/// Note:') || full.contains('FLRD:CUSTOM_WIDGET')) {
      return false;
    }
    final expr = code.substring(elem.codeStart, elem.codeEnd).trim();
    return RegExp(
      r'^(?:const\s+)?SizedBox\s*\(\s*(?:height|width)\s*:\s*[^,)]+,?\s*\)$',
    ).hasMatch(expr);
  }

  static String? _tryAddMaterialSurgically({
    required String currentCode,
    required ScreenMaterialItem newMaterial,
    required int? index,
    required String? routeTitle,
  }) {
    final primaryScopes = DartSyntaxScanner.findPrimaryScreenScopes(
      currentCode,
      preferredClassName: routeTitle,
    );
    final buildMethod = DartSyntaxScanner.findBuildMethod(
      currentCode,
      startOffset: primaryScopes.isNotEmpty ? primaryScopes.first[0] : 0,
      endOffset: primaryScopes.isNotEmpty ? primaryScopes.last[1] : null,
    );
    if (buildMethod == null) return null;

    if (newMaterial.type == ScreenMaterialType.appBar) {
      final scaffoldMatch = RegExp(r'\bScaffold\s*\(').firstMatch(
        currentCode.substring(buildMethod.bodyStart, buildMethod.bodyEnd),
      );
      if (scaffoldMatch == null) return null;
      final openParen = buildMethod.bodyStart + scaffoldMatch.end - 1;
      final closeParen = DartSyntaxScanner.findMatchingDelimiter(
        currentCode,
        openParen,
      );
      if (closeParen == -1) return null;
      final args = DartSyntaxScanner.findNamedArguments(
        currentCode,
        openParen,
        closeParen,
      );
      if (args.any((a) => a.name == 'appBar')) {
        // Already has an AppBar; avoid duplicating appBar parameter.
        return null;
      }
      final scaffoldIndent = _lineIndentAt(
        currentCode,
        buildMethod.bodyStart + scaffoldMatch.start,
      );
      final argIndent = '$scaffoldIndent  ';
      final appBarNote = (newMaterial.note != null &&
              newMaterial.note!.trim().isNotEmpty)
          ? '$argIndent/// Note: ${newMaterial.note!.trim().replaceAll(RegExp(r'[\r\n]+'), ' ')}\n'
          : '';
      final appBarCode = '''$appBarNote${argIndent}appBar: AppBar(
$argIndent  title: const Text('${_escape(newMaterial.label)}'),
$argIndent  backgroundColor: AppColors.backgroundSecondary,
$argIndent  elevation: 0,
$argIndent  centerTitle: true,
$argIndent),''';
      final insertPos = args.isNotEmpty ? args.first.argStart : openParen + 1;
      final lineStart = currentCode.lastIndexOf('\n', insertPos);
      final at = lineStart != -1 ? lineStart + 1 : openParen + 1;
      return '${currentCode.substring(0, at)}$appBarCode\n${currentCode.substring(at)}';
    }

    final childrenList = DartSyntaxScanner.findPrimaryChildrenList(
      currentCode,
      searchStart: buildMethod.bodyStart,
      searchEnd: buildMethod.bodyEnd,
    );
    if (childrenList == null) return null;

    final strip = _stripConstAroundChildrenList(
      currentCode,
      childrenList,
      stripParentWidgetConst: true,
    );
    final code = strip.code;
    final openBracket = strip.openBracket;
    final closeBracket = strip.closeBracket;

    final listIndent = _lineIndentAt(
      code,
      childrenList.matchStart - strip.deltaBeforeList,
    );
    final childIndent = '$listIndent  ';
    final rawSnippet = _generateMaterialWidgetCode(newMaterial);
    final formatted = _indentSnippet(rawSnippet, childIndent);

    final resolved = _resolveMaterialSpans(code, routeTitle);
    final bodyInTarget = resolved
        .where((m) =>
            !m.isAppBar &&
            m.ownerList != null &&
            m.ownerList!.openBracket == openBracket)
        .toList();

    final hasAppBarBefore = resolved.any((m) => m.isAppBar);
    int? targetBodyIdx;
    if (index != null) {
      targetBodyIdx = hasAppBarBefore ? index - 1 : index;
    }

    if (targetBodyIdx != null &&
        targetBodyIdx >= 0 &&
        targetBodyIdx < bodyInTarget.length) {
      final anchorSpan = bodyInTarget[targetBodyIdx].childSpan!;
      final lineStart = _attachedCommentLineStart(code, anchorSpan.codeStart);
      return '${code.substring(0, lineStart)}$formatted\n${code.substring(lineStart)}';
    }

    final inside = code.substring(openBracket + 1, closeBracket);
    final trimmedInside = inside.trim();
    if (trimmedInside.isEmpty) {
      return '${code.substring(0, openBracket + 1)}\n$formatted\n$listIndent${code.substring(closeBracket)}';
    }

    final needsComma = !trimmedInside.endsWith(',');
    final lastCodeOffset = _lastNonWhitespaceIndex(code, openBracket + 1, closeBracket);
    final insertAfter = lastCodeOffset != -1 ? lastCodeOffset + 1 : closeBracket;
    return '${code.substring(0, insertAfter)}${needsComma ? ',' : ''}\n$formatted${code.substring(insertAfter)}';
  }

  static String? _tryRemoveResolvedAtIndex(
    String code,
    List<_ResolvedMaterialSpan> resolved,
    int targetIdx,
  ) {
    final target = resolved[targetIdx];
    if (target.isAppBar && target.appBarArg != null) {
      final arg = target.appBarArg!;
      final removeStart = _attachedCommentLineStart(code, arg.codeStart);
      var removeEnd = arg.commaIndex != null ? arg.commaIndex! + 1 : arg.codeEnd;
      removeEnd = _consumeTrailingLineBreak(code, removeEnd);
      return code.replaceRange(removeStart, removeEnd, '');
    }

    if (target.childSpan != null &&
        target.ownerElements != null &&
        target.elemIndex != null) {
      final elems = target.ownerElements!;
      final idx = target.elemIndex!;
      final firstEl = elems[idx];
      final lastEl = target.pairedSpacerSpan ?? firstEl;
      final removeStart = _attachedCommentLineStart(code, firstEl.codeStart);

      if (lastEl.commaIndex != null) {
        final removeEnd = _consumeTrailingLineBreak(code, lastEl.commaIndex! + 1);
        return code.replaceRange(removeStart, removeEnd, '');
      }

      // Last element without trailing comma: preserve previous element cleanly.
      var adjustedStart = removeStart;
      if (idx > 0 && elems[idx - 1].commaIndex != null) {
        adjustedStart = elems[idx - 1].commaIndex! + 1;
      }
      final removeEnd = lastEl.codeEnd;
      return code.replaceRange(adjustedStart, removeEnd, '');
    }

    return null;
  }

  static String? _tryReorderBodySpans(
    String code,
    List<_ResolvedMaterialSpan> origBody,
    List<_ResolvedMaterialSpan> newBody,
  ) {
    if (origBody.length != newBody.length) return null;
    if (origBody.length <= 1) return code;

    final firstOpen = origBody.first.ownerList?.openBracket;
    if (firstOpen == null) return null;

    final seenStarts = <int>{};
    final slotRanges = <({int start, int end, String indent, String text})>[];
    for (final m in origBody) {
      if (m.ownerList?.openBracket != firstOpen || m.childSpan == null) {
        return null;
      }
      if (!seenStarts.add(m.childSpan!.codeStart)) {
        return null;
      }
      final slotStart = _attachedCommentLineStart(code, m.childSpan!.codeStart);
      final slotEnd = m.pairedSpacerSpan?.codeEnd ?? m.childSpan!.codeEnd;
      final indent = _lineIndentAt(code, m.childSpan!.codeStart);
      slotRanges.add((
        start: slotStart,
        end: slotEnd,
        indent: indent,
        text: code.substring(slotStart, slotEnd),
      ));
    }

    // Build mapping from origBody item identity to extracted slot text.
    final textById = <String, String>{};
    for (int i = 0; i < origBody.length; i++) {
      textById[origBody[i].item.id] = slotRanges[i].text;
    }

    var updated = code;
    for (int k = origBody.length - 1; k >= 0; k--) {
      final slot = slotRanges[k];
      final replacementText = textById[newBody[k].item.id];
      if (replacementText == null) return null;
      final reindented = _indentSnippet(replacementText, slot.indent);

      // Ensure comma when a slot previously lacked a trailing comma (e.g. last item)
      // and is still followed by closing `]`, or ensure non-last slots have a comma.
      final afterSlot = updated.substring(slot.end).trimLeft();
      final needsComma = !afterSlot.startsWith(',');
      updated = updated.replaceRange(
        slot.start,
        slot.end,
        needsComma ? '$reindented,' : reindented,
      );
    }
    return updated;
  }

  static String? _tryUpdateNoteSurgically(
    String code,
    _ResolvedMaterialSpan target,
    String? note,
  ) {
    final anchorOffset = target.appBarArg?.codeStart ??
        target.childSpan?.codeStart ??
        target.matchStart;
    final cleanNote = (note != null && note.trim().isNotEmpty)
        ? note.trim().replaceAll(RegExp(r'[\r\n]+'), ' ')
        : null;

    final anchorLineStart = _lineStartAt(code, anchorOffset);
    final anchorIndent = _lineIndentAt(code, anchorOffset);
    final existingNoteLine = _findPrecedingNoteLineRange(code, anchorLineStart);

    if (existingNoteLine != null) {
      if (cleanNote == null) {
        return code.replaceRange(existingNoteLine.start, existingNoteLine.end, '');
      }
      return code.replaceRange(
        existingNoteLine.start,
        existingNoteLine.end,
        '${existingNoteLine.indent}/// Note: $cleanNote\n',
      );
    }

    if (cleanNote == null) {
      return code;
    }

    return '${code.substring(0, anchorLineStart)}'
        '$anchorIndent/// Note: $cleanNote\n'
        '${code.substring(anchorLineStart)}';
  }

  static ({int start, int end, String indent})? _findPrecedingNoteLineRange(
    String code,
    int anchorLineStart,
  ) {
    var cursor = anchorLineStart;
    while (cursor > 0) {
      final prevNewline = code.lastIndexOf('\n', cursor - 2);
      final lineStart = prevNewline == -1 ? 0 : prevNewline + 1;
      final line = code.substring(lineStart, cursor);
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        cursor = lineStart;
        continue;
      }
      if (RegExp(r'^///\s*Note:').hasMatch(trimmed)) {
        final indentMatch = RegExp(r'^[ \t]*').firstMatch(line);
        return (
          start: lineStart,
          end: cursor,
          indent: indentMatch?.group(0) ?? '',
        );
      }
      break;
    }
    return null;
  }

  static int _attachedCommentLineStart(String code, int codeStart) {
    var result = _lineStartAt(code, codeStart);
    final noteRange = _findPrecedingNoteLineRange(code, result);
    if (noteRange != null) {
      result = noteRange.start;
    }
    return result;
  }

  static int _lineStartAt(String code, int offset) {
    if (offset <= 0) return 0;
    final nl = code.lastIndexOf('\n', offset - 1);
    return nl == -1 ? 0 : nl + 1;
  }

  static String _lineIndentAt(String code, int offset) {
    final start = _lineStartAt(code, offset);
    final rest = code.substring(start);
    final match = RegExp(r'^[ \t]*').firstMatch(rest);
    return match?.group(0) ?? '';
  }

  static int _consumeTrailingLineBreak(String code, int offset) {
    var i = offset;
    while (i < code.length && (code[i] == ' ' || code[i] == '\t')) {
      i++;
    }
    if (i < code.length && code[i] == '\r') i++;
    if (i < code.length && code[i] == '\n') i++;
    return i;
  }

  static int _lastNonWhitespaceIndex(String code, int start, int end) {
    for (int i = end - 1; i >= start; i--) {
      if (code[i].trim().isNotEmpty) return i;
    }
    return -1;
  }

  static ({
    String code,
    int openBracket,
    int closeBracket,
    int deltaBeforeList,
  }) _stripConstAroundChildrenList(
    String code,
    DartChildrenListMatch listMatch, {
    required bool stripParentWidgetConst,
  }) {
    final edits = <({int start, int end})>[];

    // 1. Strip `const ` from `children: const [` or `children: const <Widget>[`
    if (listMatch.constStart != null && listMatch.constEnd != null) {
      edits.add((start: listMatch.constStart!, end: listMatch.constEnd!));
    }

    // 2. Strip enclosing `const Column(` / `const ListView(` / `const SafeArea(` etc.
    if (stripParentWidgetConst) {
      final beforeList = code.substring(0, listMatch.matchStart);
      final enclosingMatches = RegExp(
        r'\b(const\s+)(?:Column|ListView|Wrap|Flex|Center|SafeArea|Padding|SingleChildScrollView)\s*\(',
      ).allMatches(beforeList);
      for (final m in enclosingMatches) {
        final parenIdx = m.end - 1;
        final closeParen = DartSyntaxScanner.findMatchingDelimiter(code, parenIdx);
        if (closeParen != -1 && closeParen > listMatch.closeBracket) {
          final constEnd = m.start + m.group(1)!.length;
          edits.add((start: m.start, end: constEnd));
        }
      }
    }

    if (edits.isEmpty) {
      return (
        code: code,
        openBracket: listMatch.openBracket,
        closeBracket: listMatch.closeBracket,
        deltaBeforeList: 0,
      );
    }

    edits.sort((a, b) => a.start.compareTo(b.start));
    var working = code;
    var deltaBeforeList = 0;
    var deltaBeforeOpen = 0;
    var deltaBeforeClose = 0;

    for (int i = edits.length - 1; i >= 0; i--) {
      final e = edits[i];
      final len = e.end - e.start;
      working = working.replaceRange(e.start, e.end, '');
      if (e.end <= listMatch.matchStart) deltaBeforeList += len;
      if (e.end <= listMatch.openBracket) deltaBeforeOpen += len;
      if (e.end <= listMatch.closeBracket) deltaBeforeClose += len;
    }

    return (
      code: working,
      openBracket: listMatch.openBracket - deltaBeforeOpen,
      closeBracket: listMatch.closeBracket - deltaBeforeClose,
      deltaBeforeList: deltaBeforeList,
    );
  }

  // ---------------------------------------------------------------------------
  // 4. AI PROMPT GENERATOR
  // ---------------------------------------------------------------------------

  /// Generates a structured, rich prompt for AI Screen Generator (e.g. Gemini)
  /// to organize and elevate the user-assembled visual materials into production code.
  static String generateAiEnhancePrompt(
    RouteNode node,
    List<ScreenMaterialItem> materials, {
    List<RouteNode>? existingRoutes,
    PresetType? preset,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Crie uma tela Flutter profissional e completa para a rota "${node.path}" (${node.title}).',
    );
    buffer.writeln(
      'Descrição do fluxo: ${node.subtitle.isNotEmpty ? node.subtitle : "Fluxo principal da aplicação"}.',
    );
    if (preset != null) {
      buffer.writeln('Preset de Arquitetura: ${preset.name} (${preset.tagline}).');
    }
    if (node.isProtected) {
      buffer.writeln('Esta rota é protegida por autenticação (AuthGuard ativado).');
    }
    if (node.requiredPermissions.isNotEmpty) {
      final perms = node.requiredPermissions.map((p) => p.name).join(', ');
      buffer.writeln('Permissões de hardware necessárias: $perms.');
    }

    if (existingRoutes != null && existingRoutes.isNotEmpty) {
      buffer.writeln('\n### App Navigation Graph & Available Routes:');
      buffer.writeln(
        'A aplicação possui as seguintes rotas cadastradas. Use context.go() ou context.push() para navegar entre elas quando apropriado:',
      );
      for (final r in existingRoutes) {
        final protectedFlag = r.isProtected ? ' [Protegida]' : '';
        buffer.writeln('- ${r.title} ("${r.path}")$protectedFlag: ${r.subtitle.isNotEmpty ? r.subtitle : "Tela do app"}');
      }
    }

    buffer.writeln(
      '\nA tela deve conter e organizar harmonicamente os seguintes materiais e componentes definidos pelo usuário:',
    );

    if (materials.isEmpty) {
      buffer.writeln(
        '- Estruture uma tela moderna de acordo com a proposta da rota.',
      );
    } else {
      for (int i = 0; i < materials.length; i++) {
        final item = materials[i];
        final num = i + 1;
        final noteSuffix = (item.note != null && item.note!.trim().isNotEmpty)
            ? ' (Nota do Usuário: "${item.note!.trim()}")'
            : '';
        switch (item.type) {
          case ScreenMaterialType.appBar:
            buffer.writeln(
              '$num. Barra Superior (AppBar): Título "${item.label}" com botão de retorno e ações.$noteSuffix',
            );
            break;
          case ScreenMaterialType.headerText:
            buffer.writeln(
              '$num. Título de Destaque (Header): "${item.label}" com tipografia proeminente.$noteSuffix',
            );
            break;
          case ScreenMaterialType.subtitleText:
            buffer.writeln(
              '$num. Subtítulo: "${item.label}" com estilo atenuado.$noteSuffix',
            );
            break;
          case ScreenMaterialType.textInput:
            buffer.writeln(
              '$num. Campo de Texto: Label "${item.label}"${item.hint != null ? ', placeholder "${item.hint}"' : ''}.$noteSuffix',
            );
            break;
          case ScreenMaterialType.passwordInput:
            buffer.writeln(
              '$num. Campo de Senha: Label "${item.label}" com ocultação de caracteres e botão de alternar visibilidade.$noteSuffix',
            );
            break;
          case ScreenMaterialType.primaryButton:
            buffer.writeln(
              '$num. Botão Primário: "${item.label}" como chamada principal para ação.$noteSuffix',
            );
            break;
          case ScreenMaterialType.secondaryButton:
            buffer.writeln(
              '$num. Botão Secundário: "${item.label}" em estilo outlined/texto.$noteSuffix',
            );
            break;
          case ScreenMaterialType.socialButton:
            buffer.writeln(
              '$num. Botão Social: "${item.label}" para login rápido.$noteSuffix',
            );
            break;
          case ScreenMaterialType.containerCard:
            buffer.writeln(
              '$num. Glass Container Card: Card "${item.label}" com bordas arredondadas e efeito translúcido.$noteSuffix',
            );
            break;
          case ScreenMaterialType.icon:
            buffer.writeln(
              '$num. Ícone Ilustrativo: Ícone de destaque.$noteSuffix',
            );
            break;
          case ScreenMaterialType.switchTile:
            buffer.writeln(
              '$num. Interruptor (Switch): Toggle para "${item.label}".$noteSuffix',
            );
            break;
          case ScreenMaterialType.checkboxTile:
            buffer.writeln(
              '$num. Termos/Confirmação (Checkbox): Checkbox para "${item.label}".$noteSuffix',
            );
            break;
        }
      }

      final notedItems = materials
          .where((m) => m.note != null && m.note!.trim().isNotEmpty)
          .toList();
      if (notedItems.isNotEmpty) {
        buffer.writeln('\n### User Component Notes & Behavioral Prompts:');
        for (final item in notedItems) {
          buffer.writeln(
            "- Component: ${item.displayName} -> User Note: '${item.note!.trim()}'",
          );
        }
      }
    }

    buffer.writeln('\nDiretrizes de Implementação:');
    buffer.writeln(
      '- Utilize a paleta de cores Obsidian Glass (AppColors: background, surfaceCard, primary, border, textPrimary, textSecondary).',
    );
    buffer.writeln(
      '- Aplique Clean Architecture, validações reativas, feedback com SnackBar e estados de carregamento elegantes.',
    );
    buffer.writeln(
      '- Garanta responsividade e suporte a rolagem (SingleChildScrollView) para evitar RenderFlex overflow.',
    );
    if (existingRoutes != null && existingRoutes.isNotEmpty) {
      buffer.writeln(
        '- Conecte botões e ações de navegação às rotas reais do projeto usando GoRouter (ex: context.go(\'...\') ou context.push(\'...\')).',
      );
    }

    return buffer.toString();
  }

  /// Generates a focused prompt to generate or refine ONLY a specific widget
  /// with reactive state, clean styling, and user behavioral instructions.
  static String generateWidgetSpecificPrompt(
    ScreenMaterialItem material, {
    RouteNode? routeNode,
    List<RouteNode>? existingRoutes,
    PresetType? preset,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Gere um widget Flutter completo, reativo e elegante para o componente "${material.label}" (${material.type.displayName}).',
    );
    if (routeNode != null) {
      buffer.writeln(
        'Contexto da Tela: Rota "${routeNode.path}" (${routeNode.title}) - ${routeNode.subtitle}.',
      );
    }
    if (preset != null) {
      buffer.writeln('Arquitetura do Projeto: ${preset.name} (${preset.tagline}).');
    }

    if (material.note != null && material.note!.trim().isNotEmpty) {
      buffer.writeln('\n### Instrução Comportamental do Usuário (Nota Específica):');
      buffer.writeln('"${material.note!.trim()}"');
      buffer.writeln(
        'Implemente rigorosamente o comportamento, interatividade e animações descritos nesta instrução.',
      );
    }

    if (existingRoutes != null && existingRoutes.isNotEmpty) {
      buffer.writeln('\n### Rotas do App Disponíveis para Ações de Navegação:');
      for (final r in existingRoutes) {
        buffer.writeln('- ${r.title}: "${r.path}"');
      }
    }

    buffer.writeln('\nRequisitos do Widget:');
    buffer.writeln(
      '- Estilo visual: Obsidian Glass Design System (fundo escuro, bordas translúcidas, cores AppColors).',
    );
    buffer.writeln(
      '- Reatividade: Gerencie estado interno (StatefulWidget) se houver interatividade (hover, toggle, validação, loading).',
    );
    buffer.writeln(
      '- Auto-contido: Deve ser um widget pronto para ser embutido ou utilizado como componente reutilizável.',
    );

    return buffer.toString();
  }
}

/// Compatibility alias allowing consumers and tests to import `ScreenMaterialParser`.
class ScreenMaterialParser {
  static IconData resolveIcon(String name) =>
      ScreenMaterialCodeUpdater.resolveIcon(name);

  static List<ScreenMaterialItem> extractMaterialsFromCode(
    String code, [
    String? routeTitle,
  ]) =>
      ScreenMaterialCodeUpdater.extractMaterialsFromCode(code, routeTitle);

  static String buildDartCodeFromMaterials({
    required String screenClassName,
    required String routePath,
    required List<ScreenMaterialItem> materials,
    bool isProtected = false,
    List<String> extraImports = const [],
    List<String> extraClasses = const [],
    List<String> preservedCustomWidgets = const [],
  }) =>
      ScreenMaterialCodeUpdater.buildDartCodeFromMaterials(
        screenClassName: screenClassName,
        routePath: routePath,
        materials: materials,
        isProtected: isProtected,
        extraImports: extraImports,
        extraClasses: extraClasses,
        preservedCustomWidgets: preservedCustomWidgets,
      );

  static String addMaterialToCode({
    required String currentCode,
    required ScreenMaterialItem newMaterial,
    int? index,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) =>
      ScreenMaterialCodeUpdater.addMaterialToCode(
        currentCode: currentCode,
        newMaterial: newMaterial,
        index: index,
        screenClassName: screenClassName,
        routePath: routePath,
        routeTitle: routeTitle,
        isProtected: isProtected,
      );

  static String updateMaterialNoteInCode({
    required String currentCode,
    required String materialId,
    required String? note,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) =>
      ScreenMaterialCodeUpdater.updateMaterialNoteInCode(
        currentCode: currentCode,
        materialId: materialId,
        note: note,
        screenClassName: screenClassName,
        routePath: routePath,
        routeTitle: routeTitle,
        isProtected: isProtected,
      );

  static String removeMaterialFromCode({
    required String currentCode,
    required String materialId,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) =>
      ScreenMaterialCodeUpdater.removeMaterialFromCode(
        currentCode: currentCode,
        materialId: materialId,
        screenClassName: screenClassName,
        routePath: routePath,
        routeTitle: routeTitle,
        isProtected: isProtected,
      );

  static String removeMaterialAtIndexInCode({
    required String currentCode,
    required int index,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) =>
      ScreenMaterialCodeUpdater.removeMaterialAtIndexInCode(
        currentCode: currentCode,
        index: index,
        screenClassName: screenClassName,
        routePath: routePath,
        routeTitle: routeTitle,
        isProtected: isProtected,
      );

  static String reorderMaterialsInCode({
    required String currentCode,
    required int oldIndex,
    required int newIndex,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) =>
      ScreenMaterialCodeUpdater.reorderMaterialsInCode(
        currentCode: currentCode,
        oldIndex: oldIndex,
        newIndex: newIndex,
        screenClassName: screenClassName,
        routePath: routePath,
        routeTitle: routeTitle,
        isProtected: isProtected,
      );

  static String generateAiEnhancePrompt(
    RouteNode node,
    List<ScreenMaterialItem> materials, {
    List<RouteNode>? existingRoutes,
    PresetType? preset,
  }) =>
      ScreenMaterialCodeUpdater.generateAiEnhancePrompt(
        node,
        materials,
        existingRoutes: existingRoutes,
        preset: preset,
      );

  static String generateWidgetSpecificPrompt(
    ScreenMaterialItem material, {
    RouteNode? routeNode,
    List<RouteNode>? existingRoutes,
    PresetType? preset,
  }) =>
      ScreenMaterialCodeUpdater.generateWidgetSpecificPrompt(
        material,
        routeNode: routeNode,
        existingRoutes: existingRoutes,
        preset: preset,
      );

  static String insertWidgetSnippetIntoScreenCode(
    String screenCode,
    String widgetSnippet,
  ) =>
      ScreenMaterialCodeUpdater.insertWidgetSnippetIntoScreenCode(
        screenCode,
        widgetSnippet,
      );
}

class _ExtractedSnippet {
  final int start;
  final int end;
  final ScreenMaterialItem item;

  _ExtractedSnippet({
    required this.start,
    required this.end,
    required this.item,
  });
}

class _ResolvedMaterialSpan {
  final ScreenMaterialItem item;
  final int matchStart;
  final int matchEnd;
  final bool isAppBar;
  final DartNamedArg? appBarArg;
  final DartChildrenListMatch? ownerList;
  final List<DartSpan>? ownerElements;
  final int? elemIndex;
  final DartSpan? childSpan;
  final DartSpan? pairedSpacerSpan;

  const _ResolvedMaterialSpan({
    required this.item,
    required this.matchStart,
    required this.matchEnd,
    required this.isAppBar,
    this.appBarArg,
    this.ownerList,
    this.ownerElements,
    this.elemIndex,
    this.childSpan,
    this.pairedSpacerSpan,
  });
}

// =============================================================================
// SHARED DART SYNTAX SCANNER (AST-LITE HELPERS)
// =============================================================================

/// Metadata for a top-level class/enum/mixin/extension declaration.
class DartTopLevelDecl {
  final int start;
  final int end;
  final int bodyOpenBrace;
  final int bodyCloseBrace;
  final String kind;
  final String name;
  final String? superclass;

  const DartTopLevelDecl({
    required this.start,
    required this.end,
    required this.bodyOpenBrace,
    required this.bodyCloseBrace,
    required this.kind,
    required this.name,
    this.superclass,
  });
}

/// Span of a comma-separated Dart expression (e.g. a widget inside `children: [...]`).
class DartSpan {
  final int fullStart;
  final int codeStart;
  final int codeEnd;
  final int? commaIndex;

  const DartSpan({
    required this.fullStart,
    required this.codeStart,
    required this.codeEnd,
    this.commaIndex,
  });
}

/// Metadata for a named constructor argument (e.g. `body:`, `appBar:`, `child:`).
class DartNamedArg {
  final String name;
  final int argStart;
  final int codeStart;
  final int valueStart;
  final int codeEnd;
  final int? commaIndex;

  const DartNamedArg({
    required this.name,
    required this.argStart,
    required this.codeStart,
    required this.valueStart,
    required this.codeEnd,
    this.commaIndex,
  });
}

/// Metadata for a `children: [...]` list literal.
class DartChildrenListMatch {
  final int matchStart;
  final int? constStart;
  final int? constEnd;
  final int openBracket;
  final int closeBracket;

  const DartChildrenListMatch({
    required this.matchStart,
    this.constStart,
    this.constEnd,
    required this.openBracket,
    required this.closeBracket,
  });
}

/// Metadata for an `import '...';` directive.
class DartImportDirective {
  final int start;
  final int end;
  final String uri;
  final String rawStatement;

  const DartImportDirective({
    required this.start,
    required this.end,
    required this.uri,
    required this.rawStatement,
  });
}

/// Metadata for a `// FLRD:CUSTOM_WIDGET_START` wrapped region.
class DartCustomWidgetBlock {
  final int start;
  final int end;

  const DartCustomWidgetBlock({
    required this.start,
    required this.end,
  });
}

enum _ScanFrameKind { root, string, interpolation }

class _ScanFrame {
  final _ScanFrameKind kind;
  final String openChar;
  final String closeChar;
  final String quote;
  final bool raw;
  int depth;

  _ScanFrame.root(this.openChar, this.closeChar)
      : kind = _ScanFrameKind.root,
        quote = '',
        raw = false,
        depth = 1;

  _ScanFrame.string({required this.quote, required this.raw})
      : kind = _ScanFrameKind.string,
        openChar = '',
        closeChar = '',
        depth = 0;

  _ScanFrame.interpolation()
      : kind = _ScanFrameKind.interpolation,
        openChar = '{',
        closeChar = '}',
        quote = '',
        raw = false,
        depth = 1;
}

/// Dart-aware lexical scanner used by both [ScreenMaterialCodeUpdater] and
/// `DartWidgetInjectorService` to avoid naive regex/bracket bugs across strings,
/// interpolations, triple quotes, raw strings, and nested comments.
class DartSyntaxScanner {
  const DartSyntaxScanner._();

  static bool _isIdentChar(int codeUnit) {
    return (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122) ||
        (codeUnit >= 48 && codeUnit <= 57) ||
        codeUnit == 95 ||
        codeUnit == 36;
  }

  /// Attempts to consume a Dart string literal opening at [i].
  static ({int advance, String quote, bool raw})? _matchStringStart(
    String code,
    int i,
  ) {
    if (i < 0 || i >= code.length) return null;
    if (code[i] == 'r' &&
        (i == 0 || !_isIdentChar(code.codeUnitAt(i - 1))) &&
        i + 1 < code.length) {
      final next = code[i + 1];
      if (next == "'" || next == '"') {
        final triple = next * 3;
        if (code.startsWith(triple, i + 1)) {
          return (advance: 4, quote: triple, raw: true);
        }
        return (advance: 2, quote: next, raw: true);
      }
    }
    final ch = code[i];
    if (ch == "'" || ch == '"') {
      final triple = ch * 3;
      if (code.startsWith(triple, i)) {
        return (advance: 3, quote: triple, raw: false);
      }
      return (advance: 1, quote: ch, raw: false);
    }
    return null;
  }

  /// Skips past a `/* ... */` nested block comment starting at [start] (where
  /// `code[start..start+2] == '/*'`). Returns index of the char right after `*/`.
  static int _skipBlockComment(String code, int start) {
    var depth = 1;
    var i = start + 2;
    while (i < code.length && depth > 0) {
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '*') {
        depth++;
        i += 2;
      } else if (i + 1 < code.length && code[i] == '*' && code[i + 1] == '/') {
        depth--;
        i += 2;
      } else {
        i++;
      }
    }
    return i;
  }

  /// Skips past a `// ...` line comment starting at [start]. Returns index of
  /// the newline `\n` (or `code.length`).
  static int _skipLineComment(String code, int start) {
    final nl = code.indexOf('\n', start + 2);
    return nl == -1 ? code.length : nl;
  }

  /// Computes non-code intervals (strings & comments) so regex searches never
  /// falsely match inside literals or comments.
  static List<List<int>> computeIgnoredIntervals(String code) {
    final intervals = <List<int>>[];
    final stack = <_ScanFrame>[];
    var i = 0;

    while (i < code.length) {
      if (stack.isNotEmpty && stack.last.kind == _ScanFrameKind.string) {
        final frame = stack.last;
        if (!frame.raw && code[i] == r'\') {
          i += (i + 1 < code.length) ? 2 : 1;
          continue;
        }
        if (!frame.raw && code.startsWith(r'${', i)) {
          stack.add(_ScanFrame.interpolation());
          i += 2;
          continue;
        }
        if (code.startsWith(frame.quote, i)) {
          i += frame.quote.length;
          stack.removeLast();
          if (intervals.isNotEmpty && stack.isEmpty) {
            intervals.last[1] = i;
          }
          continue;
        }
        i++;
        continue;
      }

      if (code[i] == '/' && i + 1 < code.length && code[i + 1] == '/') {
        final end = _skipLineComment(code, i);
        if (stack.isEmpty) {
          intervals.add([i, end]);
        }
        i = end;
        continue;
      }
      if (code[i] == '/' && i + 1 < code.length && code[i + 1] == '*') {
        final end = _skipBlockComment(code, i);
        if (stack.isEmpty) {
          intervals.add([i, end]);
        }
        i = end;
        continue;
      }

      final strStart = _matchStringStart(code, i);
      if (strStart != null) {
        if (stack.isEmpty) {
          intervals.add([i, code.length]);
        }
        stack.add(_ScanFrame.string(quote: strStart.quote, raw: strStart.raw));
        i += strStart.advance;
        continue;
      }

      if (stack.isNotEmpty && stack.last.kind == _ScanFrameKind.interpolation) {
        if (code[i] == '{') {
          stack.last.depth++;
        } else if (code[i] == '}') {
          stack.last.depth--;
          if (stack.last.depth == 0) {
            stack.removeLast();
          }
        }
      }
      i++;
    }
    return intervals;
  }

  static bool isOffsetIgnored(int offset, List<List<int>> ignoredIntervals) {
    for (final span in ignoredIntervals) {
      if (offset >= span[0] && offset < span[1]) return true;
      if (span[0] > offset) break;
    }
    return false;
  }

  /// Finds matching closing delimiter for `(`, `[`, or `{` at [openIndex].
  static int findMatchingDelimiter(String code, int openIndex) {
    if (openIndex < 0 || openIndex >= code.length) return -1;
    final openChar = code[openIndex];
    final String closeChar;
    if (openChar == '(') {
      closeChar = ')';
    } else if (openChar == '[') {
      closeChar = ']';
    } else if (openChar == '{') {
      closeChar = '}';
    } else {
      return -1;
    }

    final stack = <_ScanFrame>[_ScanFrame.root(openChar, closeChar)];
    var i = openIndex + 1;

    while (i < code.length && stack.isNotEmpty) {
      final top = stack.last;
      if (top.kind == _ScanFrameKind.string) {
        if (!top.raw && code[i] == r'\') {
          i += (i + 1 < code.length) ? 2 : 1;
          continue;
        }
        if (!top.raw && code.startsWith(r'${', i)) {
          stack.add(_ScanFrame.interpolation());
          i += 2;
          continue;
        }
        if (code.startsWith(top.quote, i)) {
          i += top.quote.length;
          stack.removeLast();
          continue;
        }
        i++;
        continue;
      }

      if (code[i] == '/' && i + 1 < code.length && code[i + 1] == '/') {
        i = _skipLineComment(code, i);
        continue;
      }
      if (code[i] == '/' && i + 1 < code.length && code[i + 1] == '*') {
        i = _skipBlockComment(code, i);
        continue;
      }

      final strStart = _matchStringStart(code, i);
      if (strStart != null) {
        stack.add(_ScanFrame.string(quote: strStart.quote, raw: strStart.raw));
        i += strStart.advance;
        continue;
      }

      if (top.kind == _ScanFrameKind.interpolation) {
        if (code[i] == '{') {
          top.depth++;
        } else if (code[i] == '}') {
          top.depth--;
          if (top.depth == 0) {
            stack.removeLast();
          }
        }
        i++;
        continue;
      }

      // Root delimiter tracking
      if (code[i] == top.openChar) {
        top.depth++;
      } else if (code[i] == top.closeChar) {
        top.depth--;
        if (top.depth == 0) {
          return i;
        }
      }
      i++;
    }
    return -1;
  }

  /// Splits top-level comma-separated elements inside `(...)` or `[...]` from
  /// [openIndex] to [closeIndex].
  static List<DartSpan> splitTopLevelElements(
    String code,
    int openIndex,
    int closeIndex,
  ) {
    if (openIndex < 0 || closeIndex <= openIndex || closeIndex >= code.length) {
      return const [];
    }

    final spans = <DartSpan>[];
    final stack = <_ScanFrame>[];
    var parenDepth = 0;
    var bracketDepth = 0;
    var braceDepth = 0;
    var elemRawStart = openIndex + 1;
    var i = openIndex + 1;

    void recordElement(int rawStart, int rawEnd, int? commaIndex) {
      final slice = code.substring(rawStart, rawEnd);
      if (slice.trim().isEmpty) return;
      final parsed = _trimElementBoundaries(code, rawStart, rawEnd);
      if (parsed == null) return;
      spans.add(DartSpan(
        fullStart: parsed.fullStart,
        codeStart: parsed.codeStart,
        codeEnd: parsed.codeEnd,
        commaIndex: commaIndex,
      ));
    }

    while (i < closeIndex) {
      if (stack.isNotEmpty && stack.last.kind == _ScanFrameKind.string) {
        final top = stack.last;
        if (!top.raw && code[i] == r'\') {
          i += (i + 1 < closeIndex) ? 2 : 1;
          continue;
        }
        if (!top.raw && code.startsWith(r'${', i)) {
          stack.add(_ScanFrame.interpolation());
          i += 2;
          continue;
        }
        if (code.startsWith(top.quote, i)) {
          i += top.quote.length;
          stack.removeLast();
          continue;
        }
        i++;
        continue;
      }

      if (code[i] == '/' && i + 1 < closeIndex && code[i + 1] == '/') {
        i = min(closeIndex, _skipLineComment(code, i));
        continue;
      }
      if (code[i] == '/' && i + 1 < closeIndex && code[i + 1] == '*') {
        i = min(closeIndex, _skipBlockComment(code, i));
        continue;
      }

      final strStart = _matchStringStart(code, i);
      if (strStart != null) {
        stack.add(_ScanFrame.string(quote: strStart.quote, raw: strStart.raw));
        i += strStart.advance;
        continue;
      }

      if (stack.isNotEmpty && stack.last.kind == _ScanFrameKind.interpolation) {
        if (code[i] == '{') {
          stack.last.depth++;
        } else if (code[i] == '}') {
          stack.last.depth--;
          if (stack.last.depth == 0) {
            stack.removeLast();
          }
        }
        i++;
        continue;
      }

      final ch = code[i];
      if (ch == '(') {
        parenDepth++;
      } else if (ch == ')') {
        if (parenDepth > 0) parenDepth--;
      } else if (ch == '[') {
        bracketDepth++;
      } else if (ch == ']') {
        if (bracketDepth > 0) bracketDepth--;
      } else if (ch == '{') {
        braceDepth++;
      } else if (ch == '}') {
        if (braceDepth > 0) braceDepth--;
      } else if (ch == ',' &&
          parenDepth == 0 &&
          bracketDepth == 0 &&
          braceDepth == 0) {
        recordElement(elemRawStart, i, i);
        elemRawStart = i + 1;
      }
      i++;
    }

    if (elemRawStart < closeIndex) {
      recordElement(elemRawStart, closeIndex, null);
    }

    return spans;
  }

  static ({int fullStart, int codeStart, int codeEnd})? _trimElementBoundaries(
    String code,
    int rawStart,
    int rawEnd,
  ) {
    var cursor = rawStart;
    var fullStart = -1;

    // Advance past leading whitespace and any closing FLRD marker from a
    // preceding element so the next sibling never adopts it.
    while (cursor < rawEnd) {
      while (cursor < rawEnd && code[cursor].trim().isEmpty) {
        cursor++;
      }
      if (cursor >= rawEnd) break;

      if (cursor + 1 < rawEnd &&
          code[cursor] == '/' &&
          code[cursor + 1] == '/') {
        final lineEnd = min(rawEnd, _skipLineComment(code, cursor));
        final lineText = code.substring(cursor, lineEnd).trim();
        if (lineText.contains('FLRD:CUSTOM_WIDGET_END')) {
          cursor = lineEnd;
          fullStart = -1;
          continue;
        }
        if (fullStart == -1) fullStart = cursor;
        cursor = lineEnd;
        continue;
      }

      if (cursor + 1 < rawEnd &&
          code[cursor] == '/' &&
          code[cursor + 1] == '*') {
        if (fullStart == -1) fullStart = cursor;
        cursor = min(rawEnd, _skipBlockComment(code, cursor));
        continue;
      }

      break;
    }

    if (cursor >= rawEnd) return null;
    final codeStart = cursor;
    if (fullStart == -1) fullStart = codeStart;

    // Trim trailing whitespace and trailing line comments (e.g. CUSTOM_WIDGET_END
    // before closing `]` when the last element had no trailing comma).
    var codeEnd = rawEnd;
    while (codeEnd > codeStart) {
      while (codeEnd > codeStart && code[codeEnd - 1].trim().isEmpty) {
        codeEnd--;
      }
      final lineStart = code.lastIndexOf('\n', max(0, codeEnd - 1));
      final segStart = lineStart == -1 || lineStart < codeStart
          ? codeStart
          : lineStart + 1;
      final tailLine = code.substring(segStart, codeEnd).trim();
      if (tailLine.startsWith('//')) {
        codeEnd = segStart;
        continue;
      }
      break;
    }

    if (codeEnd <= codeStart) return null;
    return (fullStart: fullStart, codeStart: codeStart, codeEnd: codeEnd);
  }

  /// Parses named constructor arguments inside `(openParen..closeParen)`.
  static List<DartNamedArg> findNamedArguments(
    String code,
    int openParen,
    int closeParen,
  ) {
    final spans = splitTopLevelElements(code, openParen, closeParen);
    final args = <DartNamedArg>[];
    for (final span in spans) {
      final slice = code.substring(span.codeStart, span.codeEnd);
      final nameMatch =
          RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*').firstMatch(slice);
      if (nameMatch == null) continue;
      args.add(DartNamedArg(
        name: nameMatch.group(1)!,
        argStart: span.fullStart,
        codeStart: span.codeStart,
        valueStart: span.codeStart + nameMatch.end,
        codeEnd: span.codeEnd,
        commaIndex: span.commaIndex,
      ));
    }
    return args;
  }

  /// Finds all top-level declarations (`class`, `enum`, `mixin`, `extension`).
  static List<DartTopLevelDecl> findTopLevelDeclarations(String code) {
    final ignored = computeIgnoredIntervals(code);
    final decls = <DartTopLevelDecl>[];
    final declRegex = RegExp(
      r'(?:^|\n)[ \t]*(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*(class|enum|mixin|extension)\s+([A-Za-z_][A-Za-z0-9_]*)?[^{;]*\{',
    );

    var cursor = 0;
    for (final m in declRegex.allMatches(code)) {
      if (m.start < cursor) continue;
      final bracePos = m.end - 1;
      if (isOffsetIgnored(bracePos, ignored)) continue;

      final closeBrace = findMatchingDelimiter(code, bracePos);
      if (closeBrace == -1) continue;

      var headerLineStart = m.start;
      if (code[headerLineStart] == '\n') headerLineStart++;
      final declStart = _expandLeadingDocAndAnnotations(code, headerLineStart);

      final header = code.substring(headerLineStart, bracePos);
      final headerWithoutTypeParams = _stripGenericAngleGroups(header);
      final extMatch = RegExp(
        r'\bextends\s+([A-Za-z_][A-Za-z0-9_]*)',
      ).firstMatch(headerWithoutTypeParams);

      decls.add(DartTopLevelDecl(
        start: declStart,
        end: closeBrace + 1,
        bodyOpenBrace: bracePos,
        bodyCloseBrace: closeBrace,
        kind: m.group(1) ?? 'class',
        name: m.group(2) ?? '',
        superclass: extMatch?.group(1),
      ));

      cursor = closeBrace + 1;
    }

    return decls;
  }

  static String _stripGenericAngleGroups(String header) {
    final out = StringBuffer();
    var depth = 0;
    for (var i = 0; i < header.length; i++) {
      final ch = header[i];
      if (ch == '<') {
        depth++;
      } else if (ch == '>' && depth > 0) {
        depth--;
      } else if (depth == 0) {
        out.write(ch);
      }
    }
    return out.toString();
  }

  static int _expandLeadingDocAndAnnotations(String code, int declLineStart) {
    var cursor = declLineStart;
    while (cursor > 0) {
      final prevNl = code.lastIndexOf('\n', cursor - 2);
      final prevLineStart = prevNl == -1 ? 0 : prevNl + 1;
      final line = code.substring(prevLineStart, cursor).trim();
      if (line.startsWith('///') || line.startsWith('@')) {
        cursor = prevLineStart;
        continue;
      }
      break;
    }
    return cursor;
  }

  /// Identifies the source ranges of the primary screen widget class and its
  /// companion `State` class (if stateful), excluding extra helper/widget classes.
  static List<List<int>> findPrimaryScreenScopes(
    String code, {
    String? preferredClassName,
  }) {
    final decls = findTopLevelDeclarations(code);
    if (decls.isEmpty) return const [];

    const widgetBases = {
      'StatefulWidget',
      'StatelessWidget',
      'ConsumerWidget',
      'ConsumerStatefulWidget',
    };

    final widgetDecls = decls
        .where((d) =>
            d.kind == 'class' &&
            d.superclass != null &&
            widgetBases.contains(d.superclass))
        .toList();
    if (widgetDecls.isEmpty) return const [];

    DartTopLevelDecl primary = widgetDecls.first;
    if (preferredClassName != null && preferredClassName.trim().isNotEmpty) {
      final normalizedPref = preferredClassName
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')
          .toLowerCase();
      for (final candidate in widgetDecls) {
        if (candidate.name.toLowerCase() == normalizedPref) {
          primary = candidate;
          break;
        }
      }
    }

    final scopes = <List<int>>[
      [primary.start, primary.end],
    ];

    if (primary.superclass == 'StatefulWidget' ||
        primary.superclass == 'ConsumerStatefulWidget') {
      final primaryBody = code.substring(primary.start, primary.end);
      final stateRefMatch = RegExp(
        r'createState\s*\(\s*\)\s*(?:=>|\{\s*return)\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      ).firstMatch(primaryBody);
      final explicitStateName = stateRefMatch?.group(1);

      for (final d in decls) {
        if (d.kind != 'class') continue;
        if (d.start == primary.start) continue;
        final header = code.substring(d.start, d.bodyOpenBrace);
        final matchesExplicit =
            explicitStateName != null && d.name == explicitStateName;
        final matchesGenericState = RegExp(
          r'extends\s+(?:ConsumerState|State)\s*<\s*' +
              RegExp.escape(primary.name) +
              r'\s*>',
        ).hasMatch(header);
        if (matchesExplicit || matchesGenericState) {
          scopes.add([d.start, d.end]);
          break;
        }
      }
    }

    scopes.sort((a, b) => a[0].compareTo(b[0]));
    return scopes;
  }

  /// Finds the `Widget build(...)` method body in `[startOffset, endOffset]`.
  static ({
    int methodStart,
    int bodyStart,
    int bodyEnd,
    bool isArrow,
  })? findBuildMethod(
    String code, {
    int startOffset = 0,
    int? endOffset,
  }) {
    final limit = min(code.length, endOffset ?? code.length);
    if (startOffset >= limit) return null;

    final ignored = computeIgnoredIntervals(code);
    final buildRegex = RegExp(r'\bWidget\s+build\s*\(');
    for (final m in buildRegex.allMatches(code, startOffset)) {
      if (m.start >= limit) break;
      if (isOffsetIgnored(m.start, ignored)) continue;
      final openParen = m.end - 1;
      final closeParen = findMatchingDelimiter(code, openParen);
      if (closeParen == -1 || closeParen >= limit) continue;

      var cursor = closeParen + 1;
      while (cursor < limit) {
        while (cursor < limit && code[cursor].trim().isEmpty) {
          cursor++;
        }
        if (cursor + 1 < limit && code[cursor] == '/' && code[cursor + 1] == '/') {
          cursor = min(limit, _skipLineComment(code, cursor));
          continue;
        }
        if (cursor + 1 < limit && code[cursor] == '/' && code[cursor + 1] == '*') {
          cursor = min(limit, _skipBlockComment(code, cursor));
          continue;
        }
        break;
      }

      if (cursor >= limit) continue;
      if (code[cursor] == '{') {
        final closeBrace = findMatchingDelimiter(code, cursor);
        if (closeBrace == -1 || closeBrace > limit) continue;
        return (
          methodStart: m.start,
          bodyStart: cursor + 1,
          bodyEnd: closeBrace,
          isArrow: false,
        );
      }

      if (code.startsWith('=>', cursor)) {
        final arrowStart = cursor + 2;
        final semi = _findTopLevelSemicolon(code, arrowStart, limit);
        if (semi == -1) continue;
        return (
          methodStart: m.start,
          bodyStart: arrowStart,
          bodyEnd: semi,
          isArrow: true,
        );
      }
    }
    return null;
  }

  static int _findTopLevelSemicolon(String code, int start, int limit) {
    final stack = <_ScanFrame>[];
    var paren = 0;
    var bracket = 0;
    var brace = 0;
    var i = start;
    while (i < limit) {
      if (stack.isNotEmpty && stack.last.kind == _ScanFrameKind.string) {
        final top = stack.last;
        if (!top.raw && code[i] == r'\') {
          i += (i + 1 < limit) ? 2 : 1;
          continue;
        }
        if (!top.raw && code.startsWith(r'${', i)) {
          stack.add(_ScanFrame.interpolation());
          i += 2;
          continue;
        }
        if (code.startsWith(top.quote, i)) {
          i += top.quote.length;
          stack.removeLast();
          continue;
        }
        i++;
        continue;
      }
      if (code[i] == '/' && i + 1 < limit && code[i + 1] == '/') {
        i = min(limit, _skipLineComment(code, i));
        continue;
      }
      if (code[i] == '/' && i + 1 < limit && code[i + 1] == '*') {
        i = min(limit, _skipBlockComment(code, i));
        continue;
      }
      final strStart = _matchStringStart(code, i);
      if (strStart != null) {
        stack.add(_ScanFrame.string(quote: strStart.quote, raw: strStart.raw));
        i += strStart.advance;
        continue;
      }
      if (stack.isNotEmpty && stack.last.kind == _ScanFrameKind.interpolation) {
        if (code[i] == '{') {
          stack.last.depth++;
        } else if (code[i] == '}') {
          stack.last.depth--;
          if (stack.last.depth == 0) stack.removeLast();
        }
        i++;
        continue;
      }
      if (code[i] == '(') paren++;
      if (code[i] == ')' && paren > 0) paren--;
      if (code[i] == '[') bracket++;
      if (code[i] == ']' && bracket > 0) bracket--;
      if (code[i] == '{') brace++;
      if (code[i] == '}' && brace > 0) brace--;
      if (code[i] == ';' && paren == 0 && bracket == 0 && brace == 0) {
        return i;
      }
      i++;
    }
    return -1;
  }

  /// Finds all `children: [...]` (including `children: const [...]` and
  /// `children: const <Widget>[...]`) lists inside `[startOffset, endOffset]`.
  static List<DartChildrenListMatch> findAllChildrenLists(
    String code, {
    int startOffset = 0,
    int? endOffset,
  }) {
    final limit = min(code.length, endOffset ?? code.length);
    if (startOffset >= limit) return const [];

    final ignored = computeIgnoredIntervals(code);
    final regex = RegExp(r'\bchildren\s*:\s*(const\s+)?(?:<[^>]+>\s*)?\[');
    final matches = <DartChildrenListMatch>[];

    for (final m in regex.allMatches(code, startOffset)) {
      if (m.start >= limit) break;
      if (isOffsetIgnored(m.start, ignored)) continue;
      final openBracket = m.end - 1;
      final closeBracket = findMatchingDelimiter(code, openBracket);
      if (closeBracket == -1 || closeBracket >= limit) continue;

      int? constStart;
      int? constEnd;
      final constGroup = m.group(1);
      if (constGroup != null) {
        constStart = code.indexOf('const', m.start);
        constEnd = constStart + constGroup.length;
      }

      matches.add(DartChildrenListMatch(
        matchStart: m.start,
        constStart: constStart,
        constEnd: constEnd,
        openBracket: openBracket,
        closeBracket: closeBracket,
      ));
    }

    return matches;
  }

  /// Finds the primary `children: [...]` list inside `Scaffold.body` (or first
  /// `Column`/`ListView` inside `build()`).
  static DartChildrenListMatch? findPrimaryChildrenList(
    String code, {
    int? searchStart,
    int? searchEnd,
  }) {
    int start = searchStart ?? 0;
    int end = searchEnd ?? code.length;

    if (searchStart == null && searchEnd == null) {
      final scopes = findPrimaryScreenScopes(code);
      final buildMethod = findBuildMethod(
        code,
        startOffset: scopes.isNotEmpty ? scopes.first[0] : 0,
        endOffset: scopes.isNotEmpty ? scopes.last[1] : null,
      );
      if (buildMethod != null) {
        start = buildMethod.bodyStart;
        end = buildMethod.bodyEnd;
      }
    }

    final lists = findAllChildrenLists(code, startOffset: start, endOffset: end);
    if (lists.isEmpty) return null;

    var bodyStart = start;
    var bodyEnd = end;
    final bodyArg = findScaffoldBodyArg(code, startOffset: start, endOffset: end);
    if (bodyArg != null) {
      bodyStart = bodyArg.valueStart;
      bodyEnd = bodyArg.codeEnd;
    }

    final bodyLists = lists
        .where((l) => l.matchStart >= bodyStart && l.closeBracket <= bodyEnd)
        .toList();
    final pool = bodyLists.isNotEmpty ? bodyLists : lists;

    for (final candidate in pool) {
      final prefix = code.substring(
        max(start, candidate.matchStart - 220),
        candidate.matchStart,
      );
      if (RegExp(r'\b(?:Column|ListView|CustomScrollView|Wrap|Flex)\s*\([^)]*$')
          .hasMatch(prefix)) {
        return candidate;
      }
    }
    return pool.first;
  }

  /// Finds the `body:` argument of the primary `Scaffold(...)` inside `[startOffset, endOffset]`.
  static DartNamedArg? findScaffoldBodyArg(
    String code, {
    int startOffset = 0,
    int? endOffset,
  }) {
    final limit = min(code.length, endOffset ?? code.length);
    final ignored = computeIgnoredIntervals(code);
    for (final m in RegExp(r'\bScaffold\s*\(').allMatches(code, startOffset)) {
      if (m.start >= limit) break;
      if (isOffsetIgnored(m.start, ignored)) continue;
      final openParen = m.end - 1;
      final closeParen = findMatchingDelimiter(code, openParen);
      if (closeParen == -1 || closeParen > limit) continue;
      for (final arg in findNamedArguments(code, openParen, closeParen)) {
        if (arg.name == 'body') return arg;
      }
    }
    return null;
  }

  /// Finds all top-level `import '...';` directives.
  static List<DartImportDirective> findImportDirectives(String code) {
    final ignored = computeIgnoredIntervals(code);
    final result = <DartImportDirective>[];
    final regex = RegExp(
      r'''^\s*import\s+(['"])([^'"]+)\1[^;\r\n]*;''',
      multiLine: true,
    );
    for (final m in regex.allMatches(code)) {
      if (isOffsetIgnored(m.start, ignored)) continue;
      final trimmedStart =
          m.start + m.group(0)!.indexOf('import');
      result.add(DartImportDirective(
        start: trimmedStart,
        end: m.end,
        uri: m.group(2)!.trim(),
        rawStatement: code.substring(trimmedStart, m.end).trim(),
      ));
    }
    return result;
  }

  /// Normalizes either `'dart:async'` or `"import 'dart:async';"` to `'dart:async'`.
  static String normalizeImportUri(String raw) {
    var clean = raw.trim();
    if (clean.isEmpty || clean == 'null') return '';
    final stmtMatch = RegExp(
      r'''^import\s+(['"])([^'"]+)\1.*?;?\s*$''',
    ).firstMatch(clean);
    if (stmtMatch != null) {
      return stmtMatch.group(2)!.trim();
    }
    if ((clean.startsWith("'") && clean.endsWith("'")) ||
        (clean.startsWith('"') && clean.endsWith('"'))) {
      clean = clean.substring(1, clean.length - 1).trim();
    }
    return clean;
  }

  /// Formats any import string or directive into `"import '...';"` form.
  static String formatImportDirective(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == 'null') return '';
    if (trimmed.startsWith('import ') && trimmed.endsWith(';')) {
      return trimmed;
    }
    final uri = normalizeImportUri(trimmed);
    if (uri.isEmpty) return '';
    return "import '$uri';";
  }

  /// Finds all `// FLRD:CUSTOM_WIDGET_START` wrapped custom widget blocks.
  static List<DartCustomWidgetBlock> findCustomWidgetMarkerBlocks(
    String code, {
    int startOffset = 0,
    int? endOffset,
  }) {
    final limit = min(code.length, endOffset ?? code.length);
    final blocks = <DartCustomWidgetBlock>[];
    final startRegex = RegExp(
      r'^[ \t]*//[ \t]*FLRD:CUSTOM_WIDGET_START\b[^\r\n]*',
      multiLine: true,
    );
    final endRegex = RegExp(
      r'^[ \t]*//[ \t]*FLRD:CUSTOM_WIDGET_END\b[^\r\n]*',
      multiLine: true,
    );

    var cursor = startOffset;
    while (cursor < limit) {
      final startMatch = startRegex.firstMatch(code.substring(cursor, limit));
      if (startMatch == null) break;
      final absStart = cursor + startMatch.start;
      final afterStartLine = cursor + startMatch.end;

      final endMatch = endRegex.firstMatch(code.substring(afterStartLine, limit));
      if (endMatch != null) {
        final absEnd = afterStartLine + endMatch.end;
        // Verify there is no unmatched closing `]` / `}` before absEnd.
        final between = code.substring(afterStartLine, afterStartLine + endMatch.start);
        if (!between.contains('\n  }') && !between.contains('\n}')) {
          blocks.add(DartCustomWidgetBlock(start: absStart, end: absEnd));
          cursor = absEnd;
          continue;
        }
      }

      // Single START marker without END: capture the next balanced expression.
      final exprEnd = _findNextExpressionEnd(code, afterStartLine, limit);
      blocks.add(DartCustomWidgetBlock(start: absStart, end: exprEnd));
      cursor = max(afterStartLine + 1, exprEnd);
    }

    return blocks;
  }

  static int _findNextExpressionEnd(String code, int start, int limit) {
    final stack = <_ScanFrame>[];
    var paren = 0;
    var bracket = 0;
    var brace = 0;
    var seenCode = false;
    var i = start;

    while (i < limit) {
      if (stack.isNotEmpty && stack.last.kind == _ScanFrameKind.string) {
        final top = stack.last;
        if (!top.raw && code[i] == r'\') {
          i += (i + 1 < limit) ? 2 : 1;
          continue;
        }
        if (!top.raw && code.startsWith(r'${', i)) {
          stack.add(_ScanFrame.interpolation());
          i += 2;
          continue;
        }
        if (code.startsWith(top.quote, i)) {
          i += top.quote.length;
          stack.removeLast();
          continue;
        }
        i++;
        continue;
      }
      if (code[i] == '/' && i + 1 < limit && code[i + 1] == '/') {
        i = min(limit, _skipLineComment(code, i));
        continue;
      }
      if (code[i] == '/' && i + 1 < limit && code[i + 1] == '*') {
        i = min(limit, _skipBlockComment(code, i));
        continue;
      }
      final strStart = _matchStringStart(code, i);
      if (strStart != null) {
        seenCode = true;
        stack.add(_ScanFrame.string(quote: strStart.quote, raw: strStart.raw));
        i += strStart.advance;
        continue;
      }
      if (stack.isNotEmpty && stack.last.kind == _ScanFrameKind.interpolation) {
        if (code[i] == '{') {
          stack.last.depth++;
        } else if (code[i] == '}') {
          stack.last.depth--;
          if (stack.last.depth == 0) stack.removeLast();
        }
        i++;
        continue;
      }

      final ch = code[i];
      if (ch.trim().isNotEmpty) seenCode = true;
      if (ch == '(') paren++;
      if (ch == ')') {
        if (paren > 0) paren--;
      }
      if (ch == '[') bracket++;
      if (ch == ']') {
        if (bracket > 0) {
          bracket--;
        } else if (seenCode && paren == 0 && brace == 0) {
          return i;
        }
      }
      if (ch == '{') brace++;
      if (ch == '}') {
        if (brace > 0) brace--;
      }
      if ((ch == ',' || ch == ';') &&
          seenCode &&
          paren == 0 &&
          bracket == 0 &&
          brace == 0) {
        return i + 1;
      }
      i++;
    }
    return limit;
  }
}
