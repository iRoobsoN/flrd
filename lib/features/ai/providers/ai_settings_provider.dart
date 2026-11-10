import 'package:flutter_riverpod/flutter_riverpod.dart';

const Object _sentinel = Object();

/// Immutable state containing AI generation preferences and credentials.
class AiSettingsState {
  final String? apiKey;
  final bool isProActive;

  const AiSettingsState({
    this.apiKey,
    this.isProActive = false,
  });

  /// Returns true if an API key is configured and not blank.
  bool get hasApiKey => apiKey != null && apiKey!.trim().isNotEmpty;

  AiSettingsState copyWith({
    Object? apiKey = _sentinel,
    bool? isProActive,
  }) {
    return AiSettingsState(
      apiKey: identical(apiKey, _sentinel) ? this.apiKey : (apiKey as String?),
      isProActive: isProActive ?? this.isProActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiSettingsState &&
          runtimeType == other.runtimeType &&
          apiKey == other.apiKey &&
          isProActive == other.isProActive;

  @override
  int get hashCode => apiKey.hashCode ^ isProActive.hashCode;

  @override
  String toString() =>
      'AiSettingsState(apiKey: ${apiKey != null && apiKey!.isNotEmpty ? '***' : 'null'}, isProActive: $isProActive)';
}

/// Riverpod notifier managing AI settings such as Gemini BYOK API keys and Pro status.
class AiSettingsNotifier extends StateNotifier<AiSettingsState> {
  AiSettingsNotifier([super.initialState = const AiSettingsState()]);

  /// Updates or clears the Google Gemini API key.
  void setApiKey(String? key) {
    final trimmed = key?.trim();
    state = state.copyWith(apiKey: (trimmed != null && trimmed.isNotEmpty) ? trimmed : null);
  }

  /// Sets whether FLRD Pro features are active.
  void setProActive(bool active) {
    state = state.copyWith(isProActive: active);
  }

  /// Toggles the FLRD Pro subscription active status.
  void toggleProActive() {
    state = state.copyWith(isProActive: !state.isProActive);
  }

  /// Clears any configured API key.
  void clearApiKey() {
    state = state.copyWith(apiKey: null);
  }
}

/// Global provider for managing AI settings across the application.
final aiSettingsProvider =
    StateNotifierProvider<AiSettingsNotifier, AiSettingsState>((ref) {
  return AiSettingsNotifier();
});
