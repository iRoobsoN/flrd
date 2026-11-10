/// Centralized configuration for all monetization, billing, and donation endpoints in FLRD.
class MonetizationConfig {
  const MonetizationConfig._();

  /// Lemon Squeezy direct checkout URL for FLRD Pro license/subscription.
  static const String lemonSqueezyProCheckoutUrl =
      'https://flrd.lemonsqueezy.com/buy/flrd-pro';

  /// Lemon Squeezy storefront URL for FLRD templates and plugins.
  static const String lemonSqueezyStoreUrl =
      'https://flrd.lemonsqueezy.com';

  /// Direct Pix key for Brazilian donations.
  static const String pixKey = 'robson.dv14@gmail.com';

  /// PayPal donation URL for international contributors.
  static const String payPalUrl =
      'https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=robson.dv14@gmail.com&currency_code=USD';

  /// GitHub Sponsors profile link for Robson David.
  static const String githubSponsorsUrl =
      'https://github.com/sponsors/iRoobsoN';

  /// Marketplace developer portal for creators selling templates/plugins.
  static const String marketplaceSellerPortalUrl =
      'https://flrd.dev/sellers';

  /// Free Google AI Studio API key creation URL.
  static const String googleAiStudioUrl =
      'https://aistudio.google.com/app/apikey';
}
