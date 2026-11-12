/// Centralized configuration for all monetization, billing, and donation endpoints in FLRD.
class MonetizationConfig {
  const MonetizationConfig._();

  /// Stripe direct checkout URL for FLRD Starter monthly subscription ($15/mo).
  static const String stripeStarterMonthlyCheckoutUrl =
      'https://buy.stripe.com/test_5kQ14n7BZ0SAcBZbDs0Jq02';

  /// Stripe direct checkout URL for FLRD Starter annual subscription ($149/yr).
  static const String stripeStarterAnnualCheckoutUrl =
      'https://buy.stripe.com/test_14A3cvf4rgRy8lJ8rg0Jq03';

  /// Stripe direct checkout URL for FLRD Studio Pro monthly subscription ($35/mo).
  static const String stripeProMonthlyCheckoutUrl =
      'https://buy.stripe.com/test_fZu5kDcWj7gY8lJ36W0Jq04';

  /// Stripe direct checkout URL for FLRD Studio Pro annual subscription ($299/yr).
  static const String stripeProAnnualCheckoutUrl =
      'https://buy.stripe.com/test_7sYcN56xV6cU6dB5f40Jq05';

  /// Stripe Customer Billing Portal URL for subscription management and invoice history.
  static const String stripeCustomerPortalUrl =
      'https://billing.stripe.com/p/login/test_flrd_portal';

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
