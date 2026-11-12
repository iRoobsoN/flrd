import 'package:flutter/foundation.dart';

/// Subscription tiers available in the FLRD ecosystem.
enum SubscriptionTier {
  community,
  starter,
  studioPro;

  /// Human-readable plan title.
  String get label {
    switch (this) {
      case SubscriptionTier.community:
        return 'Community Free';
      case SubscriptionTier.starter:
        return 'FLRD Starter';
      case SubscriptionTier.studioPro:
        return 'FLRD Studio Pro';
    }
  }

  /// Visual badge label for UI chips and dialogs.
  String get badgeLabel {
    switch (this) {
      case SubscriptionTier.community:
        return '🌱 Community Free';
      case SubscriptionTier.starter:
        return '⚡ FLRD Starter';
      case SubscriptionTier.studioPro:
        return '⭐ FLRD Studio Pro';
    }
  }

  /// Whether this tier includes paid Pro privileges.
  bool get isPro => this == SubscriptionTier.studioPro || this == SubscriptionTier.starter;

  /// Whether this tier is a paid subscription.
  bool get isSubscribed => this != SubscriptionTier.community;

  /// Safely parses string representations into [SubscriptionTier].
  static SubscriptionTier fromString(String? value) {
    if (value == null) return SubscriptionTier.community;
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (normalized.contains('studiopro') || normalized == 'pro') {
      return SubscriptionTier.studioPro;
    }
    if (normalized.contains('starter')) {
      return SubscriptionTier.starter;
    }
    return SubscriptionTier.community;
  }
}

/// Represents an authenticated user account with associated subscription plan and AI credits.
@immutable
class UserAccount {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? idToken;
  final String? refreshToken;
  final SubscriptionTier subscriptionTier;
  final int aiCreditsRemaining;
  final int aiCreditsTotal;
  final bool? _isProOverride;
  final bool? _isSubscribedOverride;

  const UserAccount({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.idToken,
    this.refreshToken,
    this.subscriptionTier = SubscriptionTier.community,
    this.aiCreditsRemaining = 10,
    this.aiCreditsTotal = 10,
    bool? isPro,
    bool? isSubscribed,
  })  : _isProOverride = isPro,
        _isSubscribedOverride = isSubscribed;

  /// Whether the user has an active Pro or Starter subscription tier.
  bool get isPro => _isProOverride ?? subscriptionTier.isPro;

  /// Whether the user has any active paid subscription.
  bool get isSubscribed => _isSubscribedOverride ?? subscriptionTier.isSubscribed;

  /// Human-friendly display name fallback to email user part.
  String get effectiveName {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      return displayName!.trim();
    }
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return 'FLRD Developer';
  }

  /// Initials derived from display name or email for user avatar badge.
  String get initials {
    final name = effectiveName.trim();
    if (name.isEmpty) return 'U';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  UserAccount copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? idToken,
    String? refreshToken,
    SubscriptionTier? subscriptionTier,
    int? aiCreditsRemaining,
    int? aiCreditsTotal,
    bool? isPro,
    bool? isSubscribed,
  }) {
    return UserAccount(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      idToken: idToken ?? this.idToken,
      refreshToken: refreshToken ?? this.refreshToken,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      aiCreditsRemaining: aiCreditsRemaining ?? this.aiCreditsRemaining,
      aiCreditsTotal: aiCreditsTotal ?? this.aiCreditsTotal,
      isPro: isPro ?? _isProOverride,
      isSubscribed: isSubscribed ?? _isSubscribedOverride,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'idToken': idToken,
        'refreshToken': refreshToken,
        'subscriptionTier': subscriptionTier.name,
        'aiCreditsRemaining': aiCreditsRemaining,
        'aiCreditsTotal': aiCreditsTotal,
        'isPro': isPro,
        'isSubscribed': isSubscribed,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      uid: json['uid'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      idToken: json['idToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      subscriptionTier: SubscriptionTier.fromString(json['subscriptionTier'] as String?),
      aiCreditsRemaining: json['aiCreditsRemaining'] as int? ?? 10,
      aiCreditsTotal: json['aiCreditsTotal'] as int? ?? 10,
      isPro: json['isPro'] as bool?,
      isSubscribed: json['isSubscribed'] as bool?,
    );
  }

  /// Realistic mock Pro account for development, offline testing, and preview.
  factory UserAccount.mockPro({
    String uid = 'flrd_mock_pro_uid_99',
    String email = 'pro@flrd.dev',
    String displayName = 'Robson Pro Dev',
  }) {
    return UserAccount(
      uid: uid,
      email: email,
      displayName: displayName,
      subscriptionTier: SubscriptionTier.studioPro,
      aiCreditsRemaining: 185,
      aiCreditsTotal: 200,
      idToken: 'mock_jwt_token_pro',
      refreshToken: 'mock_refresh_token_pro',
    );
  }

  /// Realistic mock Starter account for development, offline testing, and preview.
  factory UserAccount.mockStarter({
    String uid = 'flrd_mock_starter_uid_55',
    String email = 'starter@flrd.dev',
    String displayName = 'Starter Builder',
  }) {
    return UserAccount(
      uid: uid,
      email: email,
      displayName: displayName,
      subscriptionTier: SubscriptionTier.starter,
      aiCreditsRemaining: 45,
      aiCreditsTotal: 50,
      idToken: 'mock_jwt_token_starter',
      refreshToken: 'mock_refresh_token_starter',
    );
  }

  /// Realistic mock Community account for development, offline testing, and preview.
  factory UserAccount.mockCommunity({
    String uid = 'flrd_mock_comm_uid_11',
    String email = 'community@flrd.dev',
    String displayName = 'Community Hacker',
  }) {
    return UserAccount(
      uid: uid,
      email: email,
      displayName: displayName,
      subscriptionTier: SubscriptionTier.community,
      aiCreditsRemaining: 5,
      aiCreditsTotal: 10,
      idToken: 'mock_jwt_token_community',
      refreshToken: 'mock_refresh_token_community',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAccount &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          email == other.email &&
          displayName == other.displayName &&
          photoUrl == other.photoUrl &&
          idToken == other.idToken &&
          refreshToken == other.refreshToken &&
          subscriptionTier == other.subscriptionTier &&
          aiCreditsRemaining == other.aiCreditsRemaining &&
          aiCreditsTotal == other.aiCreditsTotal &&
          isPro == other.isPro &&
          isSubscribed == other.isSubscribed;

  @override
  int get hashCode =>
      uid.hashCode ^
      email.hashCode ^
      displayName.hashCode ^
      photoUrl.hashCode ^
      idToken.hashCode ^
      refreshToken.hashCode ^
      subscriptionTier.hashCode ^
      aiCreditsRemaining.hashCode ^
      aiCreditsTotal.hashCode ^
      isPro.hashCode ^
      isSubscribed.hashCode;

  @override
  String toString() =>
      'UserAccount(uid: $uid, email: $email, tier: ${subscriptionTier.name}, credits: $aiCreditsRemaining/$aiCreditsTotal, isPro: $isPro)';
}
