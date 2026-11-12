import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/providers/ai_settings_provider.dart';
import '../domain/user_account.dart';
import '../services/firebase_auth_service.dart';

/// Represents the authentication state of the application.
@immutable
class AuthState {
  final UserAccount? user;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
  });

  /// Whether an authenticated user session is active.
  bool get isAuthenticated => user != null;

  /// Whether current active user has a Pro / Starter tier.
  bool get isPro => user?.isPro ?? false;

  /// Active subscription tier (defaults to community when unauthenticated).
  SubscriptionTier get tier =>
      user?.subscriptionTier ?? SubscriptionTier.community;

  /// Remaining AI generation credits for current billing period.
  int get creditsRemaining => user?.aiCreditsRemaining ?? 0;

  /// Total AI generation credits for current plan tier.
  int get creditsTotal => user?.aiCreditsTotal ?? 0;

  AuthState copyWith({
    UserAccount? user,
    bool clearUser = false,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          runtimeType == other.runtimeType &&
          user == other.user &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode =>
      user.hashCode ^ isLoading.hashCode ^ errorMessage.hashCode;

  @override
  String toString() =>
      'AuthState(isAuthenticated: $isAuthenticated, user: ${user?.email}, isLoading: $isLoading, error: $errorMessage)';
}

/// Riverpod StateNotifier managing authentication flows, session lifecycle,
/// and automatic synchronization with [aiSettingsProvider].
class AuthNotifier extends StateNotifier<AuthState> {
  final FirebaseAuthService _authService;
  final Ref _ref;

  AuthNotifier({
    required FirebaseAuthService authService,
    required Ref ref,
    bool autoRestore = true,
  })  : _authService = authService,
        _ref = ref,
        super(const AuthState()) {
    if (autoRestore) {
      restoreSession();
    }
  }

  /// Attempts to restore previously persisted user session on startup.
  Future<void> restoreSession() async {
    try {
      final restored = await _authService.restoreSession();
      if (restored != null) {
        state = state.copyWith(user: restored, clearError: true);
        _syncWithAiSettings(restored);
      }
    } catch (e) {
      debugPrint('[AuthNotifier] Error restoring session: $e');
    }
  }

  /// Authenticates using email and password.
  Future<bool> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _authService.signInWithEmailAndPassword(email, password);
      state = state.copyWith(
        user: user,
        isLoading: false,
        clearError: true,
      );
      _syncWithAiSettings(user);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Falha ao realizar login. Tente novamente.',
      );
      return false;
    }
  }

  /// Registers a new account with email, password, and optional display name.
  Future<bool> signUpWithEmailAndPassword(
    String email,
    String password, [
    String? displayName,
  ]) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _authService.signUpWithEmailAndPassword(
        email,
        password,
        displayName,
      );
      state = state.copyWith(
        user: user,
        isLoading: false,
        clearError: true,
      );
      _syncWithAiSettings(user);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Falha ao criar conta. Tente novamente.',
      );
      return false;
    }
  }

  /// Authenticates via OAuth provider (Google or GitHub).
  Future<bool> signInWithOAuth(String provider, String idToken) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _authService.signInWithOAuth(provider, idToken);
      state = state.copyWith(
        user: user,
        isLoading: false,
        clearError: true,
      );
      _syncWithAiSettings(user);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Falha no login com $provider.',
      );
      return false;
    }
  }

  /// Ends the current user session and clears stored tokens.
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authService.signOut();
    } finally {
      state = const AuthState();
      _syncWithAiSettings(null);
    }
  }

  /// Updates the current user model and persists session changes.
  Future<void> updateUser(UserAccount updatedUser) async {
    state = state.copyWith(user: updatedUser);
    await _authService.saveSession(updatedUser);
    _syncWithAiSettings(updatedUser);
  }

  /// Decrements AI generation credit count and persists session.
  Future<void> consumeAiCredit([int amount = 1]) async {
    final current = state.user;
    if (current == null) return;
    final remaining = (current.aiCreditsRemaining - amount).clamp(0, current.aiCreditsTotal);
    final updated = current.copyWith(aiCreditsRemaining: remaining);
    await updateUser(updated);
  }

  /// Upgrades or modifies current subscription tier.
  Future<void> updateSubscription(SubscriptionTier tier) async {
    final current = state.user;
    if (current == null) return;

    final creditsTotal = tier == SubscriptionTier.studioPro
        ? 200
        : (tier == SubscriptionTier.starter ? 50 : 10);
    final creditsRemaining = tier == SubscriptionTier.studioPro
        ? 185
        : (tier == SubscriptionTier.starter ? 45 : 5);

    final updated = current.copyWith(
      subscriptionTier: tier,
      aiCreditsTotal: creditsTotal,
      aiCreditsRemaining: creditsRemaining,
    );
    await updateUser(updated);
  }

  /// Clears active error message banner.
  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  /// Automatically synchronizes auth state with [aiSettingsProvider]:
  /// - When user logs in with Pro or Starter, calls `setProActive(true)` and sets `selectedPlan`.
  /// - When user logs out or switches to Community, resets plan to 'community' and `isProActive` to false.
  void _syncWithAiSettings(UserAccount? user) {
    try {
      final aiNotifier = _ref.read(aiSettingsProvider.notifier);
      if (user != null && user.isPro) {
        final planName = user.subscriptionTier == SubscriptionTier.starter
            ? 'starter'
            : 'studioPro';
        aiNotifier.setProActive(true, plan: planName);
        aiNotifier.setSelectedPlan(planName);
      } else {
        aiNotifier.setProActive(false, plan: 'community');
        aiNotifier.setSelectedPlan('community');
      }
    } catch (e) {
      debugPrint('[AuthNotifier] Sync with aiSettingsProvider error: $e');
    }
  }
}

/// Global provider for [AuthNotifier] and [AuthState].
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(firebaseAuthServiceProvider);
  return AuthNotifier(authService: authService, ref: ref);
});

/// Convenience provider for listening to the current authenticated [UserAccount].
final currentUserProvider = Provider<UserAccount?>((ref) {
  return ref.watch(authProvider).user;
});

/// Convenience provider for checking authentication status.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});
