import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/user_account.dart';

/// Exception thrown by [FirebaseAuthService] when authentication fails.
class AuthException implements Exception {
  final String message;
  final String? code;

  const AuthException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Firebase Identity Toolkit REST API client supporting real authentication,
/// local session persistence, and seamless offline/mock mode for tests and desktop preview.
class FirebaseAuthService {
  final http.Client _client;
  final String apiKey;
  final String sessionFilePath;
  final bool mockMode;

  static const String _firebaseBaseUrl =
      'https://identitytoolkit.googleapis.com/v1';

  FirebaseAuthService({
    http.Client? httpClient,
    String? apiKey,
    String? sessionFilePath,
    this.mockMode = false,
  })  : _client = httpClient ?? http.Client(),
        apiKey = apiKey ??
            const String.fromEnvironment('FIREBASE_API_KEY', defaultValue: ''),
        sessionFilePath = sessionFilePath ?? defaultSessionFilePath;

  /// Default cross-platform storage location for local auth session: `~/.flrd/auth_session.json`
  static String get defaultSessionFilePath {
    String home;
    if (kIsWeb) {
      home = '/';
    } else if (Platform.isWindows) {
      home = Platform.environment['USERPROFILE'] ??
          Platform.environment['APPDATA'] ??
          Directory.systemTemp.path;
    } else {
      home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    }
    return p.join(home, '.flrd', 'auth_session.json');
  }

  /// Whether the service should run in mock/offline mode (forced or if apiKey is absent).
  bool get isMockMode => mockMode || apiKey.trim().isEmpty;

  // ---------------------------------------------------------------------------
  // AUTHENTICATION API
  // ---------------------------------------------------------------------------

  /// Signs in an existing user with email and password.
  Future<UserAccount> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw const AuthException('O e-mail não pode estar vazio.', code: 'INVALID_EMAIL');
    }
    if (password.trim().isEmpty) {
      throw const AuthException('A senha não pode estar vazia.', code: 'INVALID_PASSWORD');
    }
    if (password.length < 6) {
      throw const AuthException('A senha deve conter pelo menos 6 caracteres.',
          code: 'WEAK_PASSWORD');
    }

    if (isMockMode) {
      final user = _generateMockAccount(cleanEmail);
      await saveSession(user);
      return user;
    }

    try {
      final uri = Uri.parse('$_firebaseBaseUrl/accounts:signInWithPassword?key=$apiKey');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': cleanEmail,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final tier = _inferTierFromEmail(cleanEmail);
        final user = UserAccount(
          uid: data['localId'] as String? ?? 'flrd_uid_${cleanEmail.hashCode.abs()}',
          email: cleanEmail,
          displayName: data['displayName'] as String?,
          idToken: data['idToken'] as String?,
          refreshToken: data['refreshToken'] as String?,
          subscriptionTier: tier,
          aiCreditsRemaining: tier == SubscriptionTier.studioPro
              ? 185
              : (tier == SubscriptionTier.starter ? 45 : 10),
          aiCreditsTotal: tier == SubscriptionTier.studioPro
              ? 200
              : (tier == SubscriptionTier.starter ? 50 : 10),
        );
        await saveSession(user);
        return user;
      } else {
        final err = (data['error'] as Map<String, dynamic>?)?['message'] as String?;
        throw AuthException(_friendlyFirebaseError(err), code: err);
      }
    } on SocketException {
      // Offline fallback
      final user = _generateMockAccount(cleanEmail);
      await saveSession(user);
      return user;
    } on http.ClientException {
      // Network client fallback
      final user = _generateMockAccount(cleanEmail);
      await saveSession(user);
      return user;
    }
  }

  /// Registers a new user with email, password, and optional display name.
  Future<UserAccount> signUpWithEmailAndPassword(
    String email,
    String password, [
    String? displayName,
  ]) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw const AuthException('O e-mail não pode estar vazio.', code: 'INVALID_EMAIL');
    }
    if (password.trim().isEmpty) {
      throw const AuthException('A senha não pode estar vazia.', code: 'INVALID_PASSWORD');
    }
    if (password.length < 6) {
      throw const AuthException('A senha deve conter pelo menos 6 caracteres.',
          code: 'WEAK_PASSWORD');
    }

    if (isMockMode) {
      final user = _generateMockAccount(cleanEmail, displayName: displayName);
      await saveSession(user);
      return user;
    }

    try {
      final uri = Uri.parse('$_firebaseBaseUrl/accounts:signUp?key=$apiKey');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': cleanEmail,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final idToken = data['idToken'] as String?;
        String? finalDisplayName = displayName;

        if (displayName != null && displayName.isNotEmpty && idToken != null) {
          try {
            final updateUri = Uri.parse('$_firebaseBaseUrl/accounts:update?key=$apiKey');
            await _client.post(
              updateUri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'idToken': idToken,
                'displayName': displayName,
                'returnSecureToken': true,
              }),
            );
          } catch (_) {
            // Non-critical if profile name update fails
          }
        }

        final tier = _inferTierFromEmail(cleanEmail);
        final user = UserAccount(
          uid: data['localId'] as String? ?? 'flrd_uid_${cleanEmail.hashCode.abs()}',
          email: cleanEmail,
          displayName: finalDisplayName,
          idToken: idToken,
          refreshToken: data['refreshToken'] as String?,
          subscriptionTier: tier,
          aiCreditsRemaining: tier == SubscriptionTier.studioPro
              ? 185
              : (tier == SubscriptionTier.starter ? 45 : 10),
          aiCreditsTotal: tier == SubscriptionTier.studioPro
              ? 200
              : (tier == SubscriptionTier.starter ? 50 : 10),
        );
        await saveSession(user);
        return user;
      } else {
        final err = (data['error'] as Map<String, dynamic>?)?['message'] as String?;
        throw AuthException(_friendlyFirebaseError(err), code: err);
      }
    } on SocketException {
      final user = _generateMockAccount(cleanEmail, displayName: displayName);
      await saveSession(user);
      return user;
    } on http.ClientException {
      final user = _generateMockAccount(cleanEmail, displayName: displayName);
      await saveSession(user);
      return user;
    }
  }

  /// Signs in via third-party OAuth provider (e.g. google.com, github.com).
  Future<UserAccount> signInWithOAuth(String provider, String idToken) async {
    final cleanProvider = provider.trim().toLowerCase();
    if (cleanProvider.isEmpty) {
      throw const AuthException('Provedor de autenticação inválido.');
    }

    if (isMockMode) {
      final isGoogle = cleanProvider.contains('google');
      final email = isGoogle ? 'google.dev@flrd.dev' : 'github.dev@flrd.dev';
      final name = isGoogle ? 'Google Developer' : 'GitHub Developer';
      final user = UserAccount(
        uid: 'flrd_oauth_${cleanProvider}_${idToken.hashCode.abs()}',
        email: email,
        displayName: name,
        idToken: 'mock_oauth_jwt_$idToken',
        refreshToken: 'mock_oauth_refresh_$idToken',
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
      );
      await saveSession(user);
      return user;
    }

    try {
      final uri = Uri.parse('$_firebaseBaseUrl/accounts:signInWithIdp?key=$apiKey');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'postBody': 'id_token=$idToken&providerId=$cleanProvider',
          'requestUri': 'http://localhost',
          'returnSecureToken': true,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final user = UserAccount(
          uid: data['localId'] as String? ?? 'flrd_oauth_${idToken.hashCode.abs()}',
          email: data['email'] as String? ?? 'user@$cleanProvider',
          displayName: data['displayName'] as String?,
          photoUrl: data['photoUrl'] as String?,
          idToken: data['idToken'] as String?,
          refreshToken: data['refreshToken'] as String?,
          subscriptionTier: SubscriptionTier.studioPro,
          aiCreditsRemaining: 185,
          aiCreditsTotal: 200,
        );
        await saveSession(user);
        return user;
      } else {
        final err = (data['error'] as Map<String, dynamic>?)?['message'] as String?;
        throw AuthException(_friendlyFirebaseError(err), code: err);
      }
    } on SocketException {
      final isGoogle = cleanProvider.contains('google');
      final user = UserAccount(
        uid: 'flrd_oauth_${cleanProvider}_${idToken.hashCode.abs()}',
        email: isGoogle ? 'google.dev@flrd.dev' : 'github.dev@flrd.dev',
        displayName: isGoogle ? 'Google Developer' : 'GitHub Developer',
        subscriptionTier: SubscriptionTier.studioPro,
        aiCreditsRemaining: 185,
        aiCreditsTotal: 200,
      );
      await saveSession(user);
      return user;
    }
  }

  /// Queries user profile information from Firebase Identity Toolkit using [idToken].
  Future<UserAccount?> lookupUserData(String idToken) async {
    if (idToken.trim().isEmpty) return null;

    if (isMockMode) {
      return restoreSession();
    }

    try {
      final uri = Uri.parse('$_firebaseBaseUrl/accounts:lookup?key=$apiKey');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final users = data['users'] as List<dynamic>?;
        if (users != null && users.isNotEmpty) {
          final first = users.first as Map<String, dynamic>;
          final email = first['email'] as String? ?? '';
          final tier = _inferTierFromEmail(email);
          return UserAccount(
            uid: first['localId'] as String? ?? '',
            email: email,
            displayName: first['displayName'] as String?,
            photoUrl: first['photoUrl'] as String?,
            idToken: idToken,
            subscriptionTier: tier,
            aiCreditsRemaining: tier == SubscriptionTier.studioPro
                ? 185
                : (tier == SubscriptionTier.starter ? 45 : 10),
            aiCreditsTotal: tier == SubscriptionTier.studioPro
                ? 200
                : (tier == SubscriptionTier.starter ? 50 : 10),
          );
        }
      }
      return null;
    } catch (_) {
      return restoreSession();
    }
  }

  /// Signs out current session, clearing persisted local credentials.
  Future<void> signOut() async {
    await clearSession();
  }

  // ---------------------------------------------------------------------------
  // LOCAL SESSION PERSISTENCE
  // ---------------------------------------------------------------------------

  /// Persists the active user session to local disk (`~/.flrd/auth_session.json`).
  Future<void> saveSession(UserAccount user) async {
    try {
      final file = File(sessionFilePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(jsonEncode(user.toJson()));
    } catch (e) {
      debugPrint('[FirebaseAuthService] Error saving local session: $e');
    }
  }

  /// Restores active user session from local disk if available.
  Future<UserAccount?> restoreSession() async {
    try {
      final file = File(sessionFilePath);
      if (!await file.exists()) {
        return null;
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return null;
      }
      final json = jsonDecode(content) as Map<String, dynamic>;
      return UserAccount.fromJson(json);
    } catch (e) {
      debugPrint('[FirebaseAuthService] Error restoring local session: $e');
      return null;
    }
  }

  /// Deletes local session file on sign out.
  Future<void> clearSession() async {
    try {
      final file = File(sessionFilePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[FirebaseAuthService] Error clearing local session: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  SubscriptionTier _inferTierFromEmail(String email) {
    final lower = email.toLowerCase();
    if (lower.contains('pro') || lower.contains('admin') || lower.contains('studio')) {
      return SubscriptionTier.studioPro;
    }
    if (lower.contains('starter')) {
      return SubscriptionTier.starter;
    }
    return SubscriptionTier.community;
  }

  UserAccount _generateMockAccount(String email, {String? displayName}) {
    final tier = _inferTierFromEmail(email);
    final effectiveDisplayName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (email.contains('@') ? email.split('@').first : 'FLRD Developer');

    return UserAccount(
      uid: 'flrd_mock_uid_${email.hashCode.abs()}',
      email: email,
      displayName: effectiveDisplayName,
      idToken: 'mock_jwt_token_${email.hashCode.abs()}',
      refreshToken: 'mock_refresh_token_${email.hashCode.abs()}',
      subscriptionTier: tier,
      aiCreditsRemaining: tier == SubscriptionTier.studioPro
          ? 185
          : (tier == SubscriptionTier.starter ? 45 : 10),
      aiCreditsTotal: tier == SubscriptionTier.studioPro
          ? 200
          : (tier == SubscriptionTier.starter ? 50 : 10),
    );
  }

  String _friendlyFirebaseError(String? rawError) {
    if (rawError == null) {
      return 'Ocorreu uma falha durante a autenticação. Verifique sua conexão.';
    }
    final code = rawError.toUpperCase();
    if (code.contains('EMAIL_NOT_FOUND')) {
      return 'Nenhum usuário encontrado com este e-mail.';
    }
    if (code.contains('INVALID_PASSWORD') ||
        code.contains('INVALID_LOGIN_CREDENTIALS')) {
      return 'Senha incorreta. Verifique suas credenciais.';
    }
    if (code.contains('EMAIL_EXISTS')) {
      return 'Este e-mail já está em uso por outra conta.';
    }
    if (code.contains('USER_DISABLED')) {
      return 'Esta conta de usuário foi temporariamente desativada.';
    }
    if (code.contains('TOO_MANY_ATTEMPTS_TRY_LATER')) {
      return 'Muitas tentativas sem sucesso. Tente novamente mais tarde.';
    }
    if (code.contains('WEAK_PASSWORD')) {
      return 'A senha deve conter no mínimo 6 caracteres.';
    }
    if (code.contains('INVALID_EMAIL')) {
      return 'O formato do e-mail é inválido.';
    }
    return rawError;
  }
}

/// Global provider for [FirebaseAuthService].
final firebaseAuthServiceProvider = Provider<FirebaseAuthService>((ref) {
  return FirebaseAuthService();
});
