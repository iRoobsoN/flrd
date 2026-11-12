import 'package:flutter_riverpod/flutter_riverpod.dart';

const Object _sentinel = Object();

/// Immutable state containing AI generation preferences, plan selection, and credentials.
class AiSettingsState {
  final String? apiKey;
  final bool isProActive;
  final bool isAnnualBilling;
  final String selectedPlan;

  const AiSettingsState({
    this.apiKey,
    this.isProActive = false,
    this.isAnnualBilling = true,
    this.selectedPlan = 'community',
  });

  /// Returns true if an API key is configured and not blank.
  bool get hasApiKey => apiKey != null && apiKey!.trim().isNotEmpty;

  AiSettingsState copyWith({
    Object? apiKey = _sentinel,
    bool? isProActive,
    bool? isAnnualBilling,
    String? selectedPlan,
  }) {
    return AiSettingsState(
      apiKey: identical(apiKey, _sentinel) ? this.apiKey : (apiKey as String?),
      isProActive: isProActive ?? this.isProActive,
      isAnnualBilling: isAnnualBilling ?? this.isAnnualBilling,
      selectedPlan: selectedPlan ?? this.selectedPlan,
    );
  }

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'isProActive': isProActive,
        'isAnnualBilling': isAnnualBilling,
        'selectedPlan': selectedPlan,
      };

  factory AiSettingsState.fromJson(Map<String, dynamic> json) {
    return AiSettingsState(
      apiKey: json['apiKey'] as String?,
      isProActive: json['isProActive'] as bool? ?? false,
      isAnnualBilling: json['isAnnualBilling'] as bool? ?? true,
      selectedPlan: json['selectedPlan'] as String? ??
          ((json['isProActive'] == true) ? 'studioPro' : 'community'),
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
          selectedPlan == other.selectedPlan;

  @override
  int get hashCode =>
      apiKey.hashCode ^
      isProActive.hashCode ^
      isAnnualBilling.hashCode ^
      selectedPlan.hashCode;

  @override
  String toString() =>
      'AiSettingsState(apiKey: ${apiKey != null && apiKey!.isNotEmpty ? '***' : 'null'}, isProActive: $isProActive, isAnnualBilling: $isAnnualBilling, selectedPlan: $selectedPlan)';
}

/// Riverpod notifier managing AI settings such as Gemini BYOK API keys, plan persistence, and Pro status.
class AiSettingsNotifier extends StateNotifier<AiSettingsState> {
  AiSettingsNotifier([super.initialState = const AiSettingsState()]);

  /// Updates or clears the Google Gemini API key.
  void setApiKey(String? key) {
    final trimmed = key?.trim();
    state = state.copyWith(apiKey: (trimmed != null && trimmed.isNotEmpty) ? trimmed : null);
  }

  /// Sets whether FLRD Pro features are active.
  void setProActive(bool active, {String? plan}) {
    state = state.copyWith(
      isProActive: active,
      selectedPlan: plan ?? (active ? 'studioPro' : 'community'),
    );
  }

  /// Toggles the FLRD Pro subscription active status.
  void toggleProActive() {
    final next = !state.isProActive;
    state = state.copyWith(
      isProActive: next,
      selectedPlan: next ? 'studioPro' : 'community',
    );
  }

  /// Persists preferred billing cycle (annual vs monthly).
  void setAnnualBilling(bool isAnnual) {
    state = state.copyWith(isAnnualBilling: isAnnual);
  }

  /// Sets the active subscription plan tier ('community', 'starter', 'studioPro').
  void setSelectedPlan(String plan) {
    final normalized = plan.toLowerCase();
    final isPro = normalized == 'pro' || normalized == 'studiopro' || normalized == 'starter';
    state = state.copyWith(
      selectedPlan: plan,
      isProActive: isPro,
    );
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
