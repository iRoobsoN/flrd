import 'package:flutter/foundation.dart';

const _planSentinel = Object();

/// Origin / execution status of an AI generation or diagnosis request.
enum AiResultSource {
  liveAi,
  offlineFallback,
  unconfiguredKey,
  error,
}

/// Strategy describing where generated Flutter UI code should be placed.
enum AiPlanPlacementStrategy {
  separateWidgetFile,
  inlineInScreen,
  customPath,
}

/// Typed outcome wrapping an AI result together with provenance and plan metadata.
@immutable
class AiGenerationOutcome<T> {
  final T? data;
  final AiResultSource source;
  final String? modelUsed;
  final String? errorMessage;
  final AiExecutionPlan? plan;

  const AiGenerationOutcome({
    this.data,
    required this.source,
    this.modelUsed,
    this.errorMessage,
    this.plan,
  });

  /// Returns true only when [source] is [AiResultSource.liveAi] and [data] is present.
  bool get isSuccess => source == AiResultSource.liveAi && data != null;

  /// Returns true when offline deterministic synthesis provided [data].
  bool get isOfflineFallback =>
      source == AiResultSource.offlineFallback && data != null;

  /// Returns true whenever non-null [data] is available regardless of source.
  bool get hasData => data != null;

  AiGenerationOutcome<T> copyWith({
    Object? data = _planSentinel,
    AiResultSource? source,
    Object? modelUsed = _planSentinel,
    Object? errorMessage = _planSentinel,
    Object? plan = _planSentinel,
  }) {
    return AiGenerationOutcome<T>(
      data: identical(data, _planSentinel) ? this.data : data as T?,
      source: source ?? this.source,
      modelUsed: identical(modelUsed, _planSentinel)
          ? this.modelUsed
          : modelUsed as String?,
      errorMessage: identical(errorMessage, _planSentinel)
          ? this.errorMessage
          : errorMessage as String?,
      plan: identical(plan, _planSentinel)
          ? this.plan
          : plan as AiExecutionPlan?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AiGenerationOutcome<T> &&
        other.data == data &&
        other.source == source &&
        other.modelUsed == modelUsed &&
        other.errorMessage == errorMessage &&
        other.plan == plan;
  }

  @override
  int get hashCode =>
      Object.hash(data, source, modelUsed, errorMessage, plan);

  @override
  String toString() =>
      'AiGenerationOutcome<$T>(source: ${source.name}, modelUsed: $modelUsed, hasData: $hasData, errorMessage: $errorMessage)';
}

/// Structured Plan-First execution blueprint produced before generating or patching Dart code.
@immutable
class AiExecutionPlan {
  static const List<String> supportedArchitectureTypes = [
    'statefulWidgetClass',
    'statelessSnippet',
    'fullScreen',
    'codePatch',
  ];

  static const Set<String> _reservedIdentifierNames = {
    'Widget',
    'State',
    'BuildContext',
    'Object',
    'Function',
    'Null',
    'Dynamic',
    'Type',
  };

  static const Map<String, String> _diacriticFoldMap = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
    'ý': 'y',
    'ÿ': 'y',
    'Á': 'A',
    'À': 'A',
    'Â': 'A',
    'Ã': 'A',
    'Ä': 'A',
    'Å': 'A',
    'É': 'E',
    'È': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Í': 'I',
    'Ì': 'I',
    'Î': 'I',
    'Ï': 'I',
    'Ó': 'O',
    'Ò': 'O',
    'Ô': 'O',
    'Õ': 'O',
    'Ö': 'O',
    'Ú': 'U',
    'Ù': 'U',
    'Û': 'U',
    'Ü': 'U',
    'Ç': 'C',
    'Ñ': 'N',
    'Ý': 'Y',
  };

  final String goalSummary;
  final String widgetName;
  final String architectureType;
  final List<String> stateFields;
  final List<String> interactions;
  final List<String> requiredImports;
  final List<String> requiredPackages;
  final AiPlanPlacementStrategy placementStrategy;
  final String? targetFilePath;
  final String? extractedWidgetFilePath;
  final String visualAnchorDescription;
  final String insertionAnchorHint;

  const AiExecutionPlan({
    required this.goalSummary,
    required this.widgetName,
    this.architectureType = 'statefulWidgetClass',
    this.stateFields = const [],
    this.interactions = const [],
    this.requiredImports = const [],
    this.requiredPackages = const [],
    this.placementStrategy = AiPlanPlacementStrategy.separateWidgetFile,
    this.targetFilePath,
    this.extractedWidgetFilePath,
    this.visualAnchorDescription = '',
    this.insertionAnchorHint = 'bottom_of_column',
  });

  /// Returns [widgetName] guaranteed to be a valid Dart PascalCase identifier.
  String get sanitizedWidgetName => sanitizeWidgetName(widgetName);

  /// Converts an arbitrary raw identifier or phrase into a valid Dart PascalCase class name.
  static String sanitizeWidgetName(
    String raw, {
    String fallback = 'GeneratedWidget',
  }) {
    final safeFallback = _ensureValidFallback(fallback);
    final folded = _foldDiacritics(raw.trim());
    if (folded.isEmpty) return safeFallback;

    // Replace non-alphanumeric separators with spaces and split camelCase/PascalCase bounds.
    final separated = folded
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z])([A-Z][a-z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        );

    final tokens = separated
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    if (tokens.isEmpty) return safeFallback;

    final buffer = StringBuffer();
    for (final token in tokens) {
      if (token.length == 1) {
        buffer.write(token.toUpperCase());
      } else {
        buffer.write(token[0].toUpperCase());
        buffer.write(token.substring(1).toLowerCase());
      }
    }

    var candidate = buffer.toString();
    if (candidate.isEmpty) return safeFallback;

    // Dart class identifiers cannot begin with a digit.
    if (RegExp(r'^[0-9]').hasMatch(candidate)) {
      candidate = 'Widget$candidate';
    }

    if (candidate == 'Widget') {
      return safeFallback;
    }
    if (_reservedIdentifierNames.contains(candidate)) {
      candidate = 'Custom$candidate';
    }

    if (!RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(candidate)) {
      return safeFallback;
    }
    return candidate;
  }

  static String _ensureValidFallback(String fallback) {
    final cleaned = _foldDiacritics(fallback.trim())
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty || RegExp(r'^[0-9]').hasMatch(cleaned)) {
      return 'GeneratedWidget';
    }
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  static String _foldDiacritics(String input) {
    final out = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      out.write(_diacriticFoldMap[ch] ?? ch);
    }
    return out.toString();
  }

  factory AiExecutionPlan.fromJson(Map<String, dynamic> json) {
    final rawGoal = _coerceString(json['goalSummary'] ?? json['goal_summary']);
    final rawWidgetName =
        _coerceString(json['widgetName'] ?? json['widget_name']);
    final rawArch =
        _coerceString(json['architectureType'] ?? json['architecture_type']);
    final rawPlacement =
        json['placementStrategy'] ?? json['placement_strategy'];

    return AiExecutionPlan(
      goalSummary: rawGoal,
      widgetName: sanitizeWidgetName(rawWidgetName),
      architectureType: _coerceArchitectureType(rawArch),
      stateFields: _coerceStringList(
        json['stateFields'] ?? json['state_fields'],
        splitOnComma: false,
      ),
      interactions: _coerceStringList(
        json['interactions'],
        splitOnComma: false,
      ),
      requiredImports: _coerceStringList(
        json['requiredImports'] ?? json['required_imports'],
        splitOnComma: true,
      ),
      requiredPackages: _coerceStringList(
        json['requiredPackages'] ?? json['required_packages'],
        splitOnComma: true,
      ),
      placementStrategy: _coercePlacementStrategy(rawPlacement),
      targetFilePath: _coerceNullablePath(
        json['targetFilePath'] ?? json['target_file_path'],
      ),
      extractedWidgetFilePath: _coerceNullablePath(
        json['extractedWidgetFilePath'] ?? json['extracted_widget_file_path'],
      ),
      visualAnchorDescription: _coerceString(
        json['visualAnchorDescription'] ?? json['visual_anchor_description'],
      ),
      insertionAnchorHint: _coerceString(
        json['insertionAnchorHint'] ?? json['insertion_anchor_hint'],
        fallback: 'bottom_of_column',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'goalSummary': goalSummary,
      'widgetName': sanitizedWidgetName,
      'architectureType': architectureType,
      'stateFields': List<String>.from(stateFields),
      'interactions': List<String>.from(interactions),
      'requiredImports': List<String>.from(requiredImports),
      'requiredPackages': List<String>.from(requiredPackages),
      'placementStrategy': placementStrategy.name,
      'targetFilePath': targetFilePath,
      'extractedWidgetFilePath': extractedWidgetFilePath,
      'visualAnchorDescription': visualAnchorDescription,
      'insertionAnchorHint': insertionAnchorHint,
    };
  }

  AiExecutionPlan copyWith({
    String? goalSummary,
    String? widgetName,
    String? architectureType,
    List<String>? stateFields,
    List<String>? interactions,
    List<String>? requiredImports,
    List<String>? requiredPackages,
    AiPlanPlacementStrategy? placementStrategy,
    Object? targetFilePath = _planSentinel,
    Object? extractedWidgetFilePath = _planSentinel,
    String? visualAnchorDescription,
    String? insertionAnchorHint,
  }) {
    return AiExecutionPlan(
      goalSummary: goalSummary ?? this.goalSummary,
      widgetName: widgetName ?? this.widgetName,
      architectureType: architectureType ?? this.architectureType,
      stateFields: stateFields != null
          ? List<String>.unmodifiable(stateFields)
          : this.stateFields,
      interactions: interactions != null
          ? List<String>.unmodifiable(interactions)
          : this.interactions,
      requiredImports: requiredImports != null
          ? List<String>.unmodifiable(requiredImports)
          : this.requiredImports,
      requiredPackages: requiredPackages != null
          ? List<String>.unmodifiable(requiredPackages)
          : this.requiredPackages,
      placementStrategy: placementStrategy ?? this.placementStrategy,
      targetFilePath: identical(targetFilePath, _planSentinel)
          ? this.targetFilePath
          : targetFilePath as String?,
      extractedWidgetFilePath: identical(extractedWidgetFilePath, _planSentinel)
          ? this.extractedWidgetFilePath
          : extractedWidgetFilePath as String?,
      visualAnchorDescription:
          visualAnchorDescription ?? this.visualAnchorDescription,
      insertionAnchorHint: insertionAnchorHint ?? this.insertionAnchorHint,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AiExecutionPlan &&
        other.goalSummary == goalSummary &&
        other.widgetName == widgetName &&
        other.architectureType == architectureType &&
        listEquals(other.stateFields, stateFields) &&
        listEquals(other.interactions, interactions) &&
        listEquals(other.requiredImports, requiredImports) &&
        listEquals(other.requiredPackages, requiredPackages) &&
        other.placementStrategy == placementStrategy &&
        other.targetFilePath == targetFilePath &&
        other.extractedWidgetFilePath == extractedWidgetFilePath &&
        other.visualAnchorDescription == visualAnchorDescription &&
        other.insertionAnchorHint == insertionAnchorHint;
  }

  @override
  int get hashCode => Object.hash(
        goalSummary,
        widgetName,
        architectureType,
        Object.hashAll(stateFields),
        Object.hashAll(interactions),
        Object.hashAll(requiredImports),
        Object.hashAll(requiredPackages),
        placementStrategy,
        targetFilePath,
        extractedWidgetFilePath,
        visualAnchorDescription,
        insertionAnchorHint,
      );

  @override
  String toString() =>
      'AiExecutionPlan(widgetName: $widgetName, architectureType: $architectureType, placementStrategy: ${placementStrategy.name}, targetFilePath: $targetFilePath, extractedWidgetFilePath: $extractedWidgetFilePath, insertionAnchorHint: $insertionAnchorHint)';

  static String _coerceString(dynamic raw, {String fallback = ''}) {
    if (raw == null) return fallback;
    final value = raw.toString().trim();
    if (value.isEmpty || value == 'null') return fallback;
    return value;
  }

  static String? _coerceNullablePath(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString().trim().replaceAll('\\', '/');
    if (value.isEmpty || value == 'null') return null;
    return value;
  }

  static List<String> _coerceStringList(
    dynamic raw, {
    required bool splitOnComma,
  }) {
    if (raw == null) return const [];
    if (raw is Iterable) {
      final items = <String>[];
      for (final entry in raw) {
        if (entry == null) continue;
        final text = entry.toString().trim();
        if (text.isNotEmpty && text != 'null') {
          items.add(text);
        }
      }
      return List<String>.unmodifiable(items);
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == 'null') return const [];
      final splitter = splitOnComma ? RegExp(r'[\r\n,;]+') : RegExp(r'[\r\n;]+');
      final items = trimmed
          .split(splitter)
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      return List<String>.unmodifiable(items);
    }
    return const [];
  }

  static String _coerceArchitectureType(String raw) {
    if (raw.isEmpty) return 'statefulWidgetClass';
    final normalized = raw.replaceAll('_', '').toLowerCase();
    switch (normalized) {
      case 'statefulwidgetclass':
      case 'statefulwidget':
      case 'stateful':
        return 'statefulWidgetClass';
      case 'statelesssnippet':
      case 'statelesswidget':
      case 'stateless':
      case 'snippet':
        return 'statelessSnippet';
      case 'fullscreen':
      case 'screen':
        return 'fullScreen';
      case 'codepatch':
      case 'patch':
        return 'codePatch';
      default:
        return 'statefulWidgetClass';
    }
  }

  static AiPlanPlacementStrategy _coercePlacementStrategy(dynamic raw) {
    if (raw is AiPlanPlacementStrategy) return raw;
    if (raw is String) {
      final normalized = raw.trim().replaceAll('_', '').toLowerCase();
      switch (normalized) {
        case 'separatewidgetfile':
        case 'separatefile':
        case 'separate':
          return AiPlanPlacementStrategy.separateWidgetFile;
        case 'inlineinscreen':
        case 'inline':
          return AiPlanPlacementStrategy.inlineInScreen;
        case 'custompath':
        case 'custom':
          return AiPlanPlacementStrategy.customPath;
      }
    }
    return AiPlanPlacementStrategy.separateWidgetFile;
  }
}
