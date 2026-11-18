import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

const Object _sentinel = Object();

/// Immutable state containing AI generation preferences, model selection,
/// plan selection, and credentials.
class AiSettingsState {
  static const String geminiFlashModel = 'gemini-2.5-flash';
  static const String geminiProModel = 'gemini-2.5-pro';
  static const String defaultModel = geminiFlashModel;
  static const List<String> supportedModels = [
    geminiFlashModel,
    geminiProModel,
  ];

  final String? apiKey;
  final bool isProActive;
  final bool isAnnualBilling;
  final String selectedPlan;
  final String selectedModel;

  const AiSettingsState({
    this.apiKey,
    this.isProActive = false,
    this.isAnnualBilling = true,
    this.selectedPlan = 'community',
    this.selectedModel = defaultModel,
  });

  /// Normalizes [model] to a supported Gemini model ID, falling back to
  /// [defaultModel] when null, empty, or unrecognized.
  static String normalizeModel(String? model) {
    final trimmed = model?.trim();
    if (trimmed != null && supportedModels.contains(trimmed)) {
      return trimmed;
    }
    return defaultModel;
  }

  /// Returns true if an API key is configured and not blank.
  bool get hasApiKey => apiKey != null && apiKey!.trim().isNotEmpty;

  AiSettingsState copyWith({
    Object? apiKey = _sentinel,
    bool? isProActive,
    bool? isAnnualBilling,
    String? selectedPlan,
    String? selectedModel,
  }) {
    return AiSettingsState(
      apiKey: identical(apiKey, _sentinel) ? this.apiKey : (apiKey as String?),
      isProActive: isProActive ?? this.isProActive,
      isAnnualBilling: isAnnualBilling ?? this.isAnnualBilling,
      selectedPlan: selectedPlan ?? this.selectedPlan,
      selectedModel: selectedModel ?? this.selectedModel,
    );
  }

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'isProActive': isProActive,
        'isAnnualBilling': isAnnualBilling,
        'selectedPlan': selectedPlan,
        'selectedModel': selectedModel,
      };

  factory AiSettingsState.fromJson(Map<String, dynamic> json) {
    final rawKey = json['apiKey'];
    final trimmedKey = rawKey is String ? rawKey.trim() : null;
    final apiKey =
        (trimmedKey != null && trimmedKey.isNotEmpty) ? trimmedKey : null;

    final isProActive =
        json['isProActive'] is bool ? json['isProActive'] as bool : false;
    final isAnnualBilling = json['isAnnualBilling'] is bool
        ? json['isAnnualBilling'] as bool
        : true;

    final rawPlan = json['selectedPlan'];
    final trimmedPlan = rawPlan is String ? rawPlan.trim() : null;
    final selectedPlan = (trimmedPlan != null && trimmedPlan.isNotEmpty)
        ? trimmedPlan
        : (isProActive ? 'studioPro' : 'community');

    final rawModel = json['selectedModel'];
    final selectedModel = normalizeModel(rawModel is String ? rawModel : null);

    return AiSettingsState(
      apiKey: apiKey,
      isProActive: isProActive,
      isAnnualBilling: isAnnualBilling,
      selectedPlan: selectedPlan,
      selectedModel: selectedModel,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiSettingsState &&
          runtimeType == other.runtimeType &&
          apiKey == other.apiKey &&
          isProActive == other.isProActive &&
          isAnnualBilling == other.isAnnualBilling &&
          selectedPlan == other.selectedPlan &&
          selectedModel == other.selectedModel;

  @override
  int get hashCode => Object.hash(
        apiKey,
        isProActive,
        isAnnualBilling,
        selectedPlan,
        selectedModel,
      );

  @override
  String toString() =>
      'AiSettingsState(apiKey: ${apiKey != null && apiKey!.isNotEmpty ? '***' : 'null'}, isProActive: $isProActive, isAnnualBilling: $isAnnualBilling, selectedPlan: $selectedPlan, selectedModel: $selectedModel)';
}

/// Cross-platform disk persistence service for [AiSettingsState], storing
/// configuration atomically at `~/.flrd/ai_settings.json`.
class AiSettingsStorageService {
  final String settingsFilePath;
  static int _tempWriteCounter = 0;

  AiSettingsStorageService({String? settingsFilePath})
      : settingsFilePath = settingsFilePath ?? defaultSettingsFilePath;

  /// Default cross-platform storage location: `~/.flrd/ai_settings.json`.
  static String get defaultSettingsFilePath => resolveSettingsFilePath();

  /// Resolves the storage path matching FLRD's `~/.flrd/` convention
  /// (`USERPROFILE` on Windows, `HOME` on POSIX).
  static String resolveSettingsFilePath({
    Map<String, String>? environment,
    bool? isWindows,
    bool? isWeb,
  }) {
    final runningOnWeb = isWeb ?? kIsWeb;
    if (runningOnWeb) {
      return p.posix.join('/', '.flrd', 'ai_settings.json');
    }

    final env = environment ?? Platform.environment;
    final windows = isWindows ?? Platform.isWindows;

    String? nonEmptyEnv(String key) {
      final value = env[key]?.trim();
      return (value != null && value.isNotEmpty) ? value : null;
    }

    final String home;
    if (windows) {
      home = nonEmptyEnv('USERPROFILE') ??
          nonEmptyEnv('HOME') ??
          nonEmptyEnv('APPDATA') ??
          Directory.systemTemp.path;
    } else {
      home = nonEmptyEnv('HOME') ??
          nonEmptyEnv('USERPROFILE') ??
          Directory.systemTemp.path;
    }

    if (isWindows == null) {
      return p.join(home, '.flrd', 'ai_settings.json');
    }
    final pathContext = windows ? p.windows : p.posix;
    return pathContext.join(home, '.flrd', 'ai_settings.json');
  }

  /// Returns true when disk persistence should be enabled by default for the
  /// global [aiSettingsProvider] (disabled automatically under `flutter test`
  /// and web targets to keep tests isolated).
  static bool isDiskPersistenceAllowedByDefault() {
    if (kIsWeb) return false;
    try {
      return !Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  /// Loads persisted settings synchronously from [settingsFilePath].
  /// Returns `null` when the file is absent, blank, or malformed.
  AiSettingsState? loadSync() {
    if (kIsWeb) return null;
    try {
      final file = File(settingsFilePath);
      if (!file.existsSync()) {
        return null;
      }
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return AiSettingsState.fromJson(decoded);
      }
      if (decoded is Map) {
        return AiSettingsState.fromJson(Map<String, dynamic>.from(decoded));
      }
      return null;
    } catch (e) {
      debugPrint('[AiSettingsStorageService] Error loading AI settings: $e');
      return null;
    }
  }

  /// Atomically writes [state] to [settingsFilePath] by flushing a sibling
  /// temporary file and renaming it into place.
  void saveSync(AiSettingsState state) {
    if (kIsWeb) return;
    File? tempFile;
    try {
      final targetFile = File(settingsFilePath);
      final parentDir = targetFile.parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      _tempWriteCounter++;
      final tempPath =
          '${targetFile.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}.$_tempWriteCounter';
      tempFile = File(tempPath);

      final encoded = const JsonEncoder.withIndent('  ').convert(state.toJson());
      tempFile.writeAsStringSync(encoded, flush: true);
      tempFile.renameSync(targetFile.path);
      tempFile = null;
    } catch (e) {
      debugPrint('[AiSettingsStorageService] Error saving AI settings: $e');
    } finally {
      if (tempFile != null) {
        try {
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
          }
        } catch (_) {}
      }
    }
  }
}

/// Riverpod notifier managing AI settings such as Gemini BYOK API keys,
/// model preference, plan persistence, and Pro status.
class AiSettingsNotifier extends StateNotifier<AiSettingsState> {
  final AiSettingsStorageService? _storage;
  final bool _enablePersistence;

  /// Backwards-compatible in-memory constructor so existing tests and overrides
  /// do not mutate `~/.flrd/ai_settings.json` unless persistence is requested.
  AiSettingsNotifier([super.initialState = const AiSettingsState()])
      : _storage = null,
        _enablePersistence = false;

  /// Creates an isolated in-memory [AiSettingsNotifier] with persistence off.
  AiSettingsNotifier.inMemory([super.initialState = const AiSettingsState()])
      : _storage = null,
        _enablePersistence = false;

  /// Creates a disk-backed [AiSettingsNotifier] that loads on startup and
  /// atomically persists updates to [settingsFilePath] (or `~/.flrd/ai_settings.json`).
  AiSettingsNotifier.persistent({
    AiSettingsState initialState = const AiSettingsState(),
    String? settingsFilePath,
    AiSettingsStorageService? storage,
    bool enablePersistence = true,
  })  : _storage = enablePersistence
            ? (storage ??
                AiSettingsStorageService(settingsFilePath: settingsFilePath))
            : null,
        _enablePersistence = enablePersistence,
        super(initialState) {
    _loadFromDisk();
  }

  /// Whether disk persistence is active for this notifier instance.
  bool get isPersistenceEnabled => _enablePersistence && _storage != null;

  /// Target file path when persistence is enabled, or `null` when in-memory.
  String? get settingsFilePath => _storage?.settingsFilePath;

  void _loadFromDisk() {
    if (!isPersistenceEnabled) return;
    final loaded = _storage!.loadSync();
    if (loaded != null) {
      state = loaded;
    }
  }

  void _persist() {
    if (!isPersistenceEnabled) return;
    _storage!.saveSync(state);
  }

  /// Updates or clears the Google Gemini API key.
  void setApiKey(String? key) {
    final trimmed = key?.trim();
    state = state.copyWith(
      apiKey: (trimmed != null && trimmed.isNotEmpty) ? trimmed : null,
    );
    _persist();
  }

  /// Selects the active Gemini model (`'gemini-2.5-flash'` or `'gemini-2.5-pro'`).
  void setSelectedModel(String model) {
    state = state.copyWith(
      selectedModel: AiSettingsState.normalizeModel(model),
    );
    _persist();
  }

  /// Sets whether FLRD Pro features are active.
  void setProActive(bool active, {String? plan}) {
    state = state.copyWith(
      isProActive: active,
      selectedPlan: plan ?? (active ? 'studioPro' : 'community'),
    );
    _persist();
  }

  /// Toggles the FLRD Pro subscription active status.
  void toggleProActive() {
    final next = !state.isProActive;
    state = state.copyWith(
      isProActive: next,
      selectedPlan: next ? 'studioPro' : 'community',
    );
    _persist();
  }

  /// Persists preferred billing cycle (annual vs monthly).
  void setAnnualBilling(bool isAnnual) {
    state = state.copyWith(isAnnualBilling: isAnnual);
    _persist();
  }

  /// Sets the active subscription plan tier ('community', 'starter', 'studioPro').
  void setSelectedPlan(String plan) {
    final normalized = plan.toLowerCase();
    final isPro = normalized == 'pro' ||
        normalized == 'studiopro' ||
        normalized == 'starter';
    state = state.copyWith(
      selectedPlan: plan,
      isProActive: isPro,
    );
    _persist();
  }

  /// Clears any configured API key.
  void clearApiKey() {
    state = state.copyWith(apiKey: null);
    _persist();
  }
}

/// Global provider for managing AI settings across the application.
final aiSettingsProvider =
    StateNotifierProvider<AiSettingsNotifier, AiSettingsState>((ref) {
  if (AiSettingsStorageService.isDiskPersistenceAllowedByDefault()) {
    return AiSettingsNotifier.persistent();
  }
  return AiSettingsNotifier.inMemory();
});
