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
    final prefix = code.substring(max(0, matchStart - 250), matchStart);
    final noteMatches = RegExp(r'///\s*Note:\s*([^\r\n]+)').allMatches(prefix);
    if (noteMatches.isNotEmpty) {
      return noteMatches.last.group(1)?.trim();
    }
    return null;
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
    int depth = 0;
    for (int i = openParenIndex; i < text.length; i++) {
      if (text[i] == '(') {
        depth++;
      } else if (text[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
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
    if (code.trim().isEmpty) {
      return const [];
    }

    final List<_ExtractedSnippet> matches = [];
    final List<List<int>> consumedRanges = [];

    // A. Parse AppBar
    final appBarMatch = RegExp(r'\bAppBar\s*\(').firstMatch(code);
    if (appBarMatch != null) {
      final openParen = appBarMatch.end - 1;
      final closeParen = _findMatchingParen(code, openParen);
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

      consumedRanges.add([
        appBarMatch.start,
        closeParen != -1 ? closeParen + 1 : code.length,
      ]);

      final note = _extractPrecedingNote(code, appBarMatch.start);
      matches.add(_ExtractedSnippet(
        start: appBarMatch.start,
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
    }

    // B. Parse Inputs (TextField & TextFormField)
    final inputMatches = RegExp(r'\b(TextField|TextFormField)\s*\(').allMatches(code);
    for (final m in inputMatches) {
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
      if (_isRangeConsumed(m.start, consumedRanges)) continue;
      final iconName = m.group(1)!;
      final note = _extractPrecedingNote(code, m.start);
      matches.add(_ExtractedSnippet(
        start: m.start,
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
      if (_isRangeConsumed(m.start, consumedRanges)) continue;
      String text = m.group(1) ?? m.group(2) ?? '';
      if (text.contains(r'$displayTitle') && routeTitle != null) {
        text = text.replaceAll(r'$displayTitle', routeTitle);
      }
      if (text.trim().isEmpty) continue;

      final textParams = m.group(3) ?? '';
      final isLarge =
          RegExp(r'fontSize:\s*(?:1[89]|[2-9][0-9])').hasMatch(textParams);
      final isBold =
          RegExp(r'fontWeight:\s*FontWeight\.(?:bold|w[6-9]00)').hasMatch(textParams);

      final isHeader = isLarge || isBold;

      final note = _extractPrecedingNote(code, m.start);
      matches.add(_ExtractedSnippet(
        start: m.start,
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
    final results = <ScreenMaterialItem>[];
    for (int i = 0; i < matches.length; i++) {
      final it = matches[i].item;
      results.add(it.copyWith(id: '${it.type.name}_$i'));
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // 2. BUILD DART CODE FROM MATERIALS
  // ---------------------------------------------------------------------------

  /// Generates idiomatic, compilable Flutter Dart code strictly reflecting the materials list.
  static String buildDartCodeFromMaterials({
    required String screenClassName,
    required String routePath,
    required List<ScreenMaterialItem> materials,
    bool isProtected = false,
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
    for (final item in bodyMaterials) {
      bodyWidgetsCode.add(_generateMaterialWidgetCode(item));
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
''';
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
  // 3. MUTATION APIS: ADD, REMOVE, REORDER
  // ---------------------------------------------------------------------------

  /// Adds a material item to the screen code deterministically.
  static String addMaterialToCode({
    required String currentCode,
    required ScreenMaterialItem newMaterial,
    int? index,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    final materials = List<ScreenMaterialItem>.from(
      extractMaterialsFromCode(currentCode, routeTitle),
    );

    if (newMaterial.type == ScreenMaterialType.appBar && index == null) {
      // Place AppBar at top if not explicitly indexed
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
    );
  }

  /// Removes a material item from the screen code deterministically.
  static String removeMaterialFromCode({
    required String currentCode,
    required String materialId,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    final materials = List<ScreenMaterialItem>.from(
      extractMaterialsFromCode(currentCode, routeTitle),
    );

    final idx = materials.indexWhere((m) => m.id == materialId);
    if (idx != -1) {
      materials.removeAt(idx);
    } else {
      final intIndex = int.tryParse(materialId);
      if (intIndex != null && intIndex >= 0 && intIndex < materials.length) {
        materials.removeAt(intIndex);
      } else {
        final typeIdx = materials.indexWhere(
          (m) => m.type.name.toLowerCase() == materialId.toLowerCase(),
        );
        if (typeIdx != -1) {
          materials.removeAt(typeIdx);
        }
      }
    }

    return buildDartCodeFromMaterials(
      screenClassName: screenClassName ?? _detectClassName(currentCode),
      routePath: routePath ?? _detectRoutePath(currentCode),
      materials: materials,
      isProtected: isProtected || _detectProtected(currentCode),
    );
  }

  /// Removes a material item at a specific index.
  static String removeMaterialAtIndexInCode({
    required String currentCode,
    required int index,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    final materials = List<ScreenMaterialItem>.from(
      extractMaterialsFromCode(currentCode, routeTitle),
    );

    if (index >= 0 && index < materials.length) {
      materials.removeAt(index);
    }

    return buildDartCodeFromMaterials(
      screenClassName: screenClassName ?? _detectClassName(currentCode),
      routePath: routePath ?? _detectRoutePath(currentCode),
      materials: materials,
      isProtected: isProtected || _detectProtected(currentCode),
    );
  }

  /// Reorders a material item from `oldIndex` to `newIndex`.
  static String reorderMaterialsInCode({
    required String currentCode,
    required int oldIndex,
    required int newIndex,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    final materials = List<ScreenMaterialItem>.from(
      extractMaterialsFromCode(currentCode, routeTitle),
    );

    if (oldIndex < 0 || oldIndex >= materials.length) {
      return currentCode;
    }

    final item = materials.removeAt(oldIndex);
    final safeNewIndex = newIndex.clamp(0, materials.length);
    materials.insert(safeNewIndex, item);

    return buildDartCodeFromMaterials(
      screenClassName: screenClassName ?? _detectClassName(currentCode),
      routePath: routePath ?? _detectRoutePath(currentCode),
      materials: materials,
      isProtected: isProtected || _detectProtected(currentCode),
    );
  }

  /// Updates or clears the behavioral note for a material item in the screen code.
  static String updateMaterialNoteInCode({
    required String currentCode,
    required String materialId,
    required String? note,
    String? screenClassName,
    String? routePath,
    String? routeTitle,
    bool isProtected = false,
  }) {
    final materials = List<ScreenMaterialItem>.from(
      extractMaterialsFromCode(currentCode, routeTitle),
    );

    final idx = materials.indexWhere((m) => m.id == materialId);
    if (idx != -1) {
      materials[idx] = materials[idx].copyWith(note: note);
    } else {
      final intIndex = int.tryParse(materialId);
      if (intIndex != null && intIndex >= 0 && intIndex < materials.length) {
        materials[intIndex] = materials[intIndex].copyWith(note: note);
      }
    }

    return buildDartCodeFromMaterials(
      screenClassName: screenClassName ?? _detectClassName(currentCode),
      routePath: routePath ?? _detectRoutePath(currentCode),
      materials: materials,
      isProtected: isProtected || _detectProtected(currentCode),
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
  }) =>
      ScreenMaterialCodeUpdater.buildDartCodeFromMaterials(
        screenClassName: screenClassName,
        routePath: routePath,
        materials: materials,
        isProtected: isProtected,
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
}

class _ExtractedSnippet {
  final int start;
  final ScreenMaterialItem item;

  _ExtractedSnippet({
    required this.start,
    required this.item,
  });
}
