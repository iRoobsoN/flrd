import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/monetization_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../ai/providers/ai_settings_provider.dart';
import '../../auth/presentation/user_account_dialog.dart';
import '../../auth/providers/auth_provider.dart';

/// Modal dialog providing centralized settings for Gemini AI API keys,
/// FLRD subscription & billing via Stripe, and open-source donation options.
class SettingsAndBillingDialog extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const SettingsAndBillingDialog({
    super.key,
    this.initialTabIndex = 0,
  });

  /// Displays the settings and billing dialog modal.
  static Future<void> show(BuildContext context, {int initialTabIndex = 0}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => SettingsAndBillingDialog(initialTabIndex: initialTabIndex),
    );
  }

  @override
  ConsumerState<SettingsAndBillingDialog> createState() =>
      _SettingsAndBillingDialogState();
}

class _SettingsAndBillingDialogState
    extends ConsumerState<SettingsAndBillingDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _apiKeyController;
  bool _obscureApiKey = true;
  bool _isAnnualBilling = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );

    final aiSettings = ref.read(aiSettingsProvider);
    final currentApiKey = aiSettings.apiKey ?? '';
    _apiKeyController = TextEditingController(text: currentApiKey);
    _isAnnualBilling = aiSettings.isAnnualBilling;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        AppToast.error(context, 'Não foi possível abrir o link: $url');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Erro ao abrir link: $e');
    }
  }

  void _copyPixKey(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: MonetizationConfig.pixKey));
    AppToast.success(
      context,
      'Chave Pix copiada com sucesso: ${MonetizationConfig.pixKey}',
      duration: const Duration(seconds: 3),
    );
  }

  void _saveApiKey() {
    final key = _apiKeyController.text.trim();
    ref.read(aiSettingsProvider.notifier).setApiKey(key.isEmpty ? null : key);
    AppToast.success(
      context,
      key.isEmpty
          ? 'API key removed. Using standard synthetic generator.'
          : 'Gemini API Key saved successfully!',
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiSettings = ref.watch(aiSettingsProvider);

    return Dialog(
      backgroundColor: AppColors.backgroundSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 680,
          maxHeight: 640,
          minWidth: 540,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dialog Header
            _buildHeader(context),
            const Divider(height: 1, color: AppColors.borderSubtle),

            // Tab Bar
            _buildTabBar(),
            const Divider(height: 1, color: AppColors.borderSubtle),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAiTab(context, aiSettings),
                  _buildPlanAndBillingTab(context, aiSettings),
                  _buildSupportTab(context),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.borderSubtle),

            // Dialog Footer Actions
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.settings_suggest_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings & Billing',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Manage AI keys, FLRD subscriptions, and project sponsorships',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
            splashRadius: 18,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.secondary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.secondary,
        indicatorWeight: 2,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
        tabs: const [
          Tab(
            icon: Icon(Icons.psychology_rounded, size: 16),
            text: 'Artificial Intelligence (AI)',
          ),
          Tab(
            icon: Icon(Icons.workspace_premium_rounded, size: 16),
            text: 'Plan & Billing',
          ),
          Tab(
            icon: Icon(Icons.favorite_rounded, size: 16),
            text: 'Support Project',
          ),
        ],
      ),
    );
  }

  Widget _buildAiTab(BuildContext context, AiSettingsState aiSettings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Informational Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.secondary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bring Your Own Key (BYOK) — Google Gemini',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Enter your personal Google Gemini API key to synthesize complex Flutter screens directly on your machine with zero latency.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Key Status Pill
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: aiSettings.hasApiKey
                                  ? AppColors.success.withOpacity(0.15)
                                  : AppColors.warning.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: aiSettings.hasApiKey
                                    ? AppColors.success.withOpacity(0.4)
                                    : AppColors.warning.withOpacity(0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  aiSettings.hasApiKey
                                      ? Icons.check_circle_rounded
                                      : Icons.info_outline_rounded,
                                  size: 13,
                                  color: aiSettings.hasApiKey
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    aiSettings.hasApiKey
                                        ? 'API Key Configured & Ready'
                                        : 'No active key (Offline fallback mode)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: aiSettings.hasApiKey
                                          ? AppColors.success
                                          : AppColors.warning,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Google Gemini API Key Input
          const Text(
            'Gemini API Key (Google AI Studio)',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'AIzaSy...',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surfaceCard,
              prefixIcon: const Icon(Icons.vpn_key_rounded, size: 16, color: AppColors.secondary),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _obscureApiKey ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                    tooltip: _obscureApiKey ? 'Show Key' : 'Hide Key',
                  ),
                  if (_apiKeyController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textMuted),
                      onPressed: () {
                        setState(() {
                          _apiKeyController.clear();
                        });
                        ref.read(aiSettingsProvider.notifier).clearApiKey();
                      },
                      tooltip: 'Clear',
                    ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.secondary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Action row: Save Button & Link to Google AI Studio
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _saveApiKey,
                icon: const Icon(Icons.save_rounded, size: 15),
                label: const Text('Save API Key', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _openUrl(MonetizationConfig.googleAiStudioUrl),
                icon: const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.secondary),
                label: const Text('Get Free Key at Google AI Studio', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Helper callout
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 15, color: AppColors.textMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your API key is securely stored locally on your device and never shared with third-party servers.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingTogglePill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: AppColors.primary) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSyncStatusCard(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (user != null && user.isPro)
              ? AppColors.secondary.withOpacity(0.3)
              : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: user != null
                  ? (user.isPro
                      ? AppColors.secondary.withOpacity(0.18)
                      : AppColors.primary.withOpacity(0.18))
                  : AppColors.surfaceCard,
              shape: BoxShape.circle,
            ),
            child: Icon(
              user != null ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: user != null
                  ? (user.isPro ? AppColors.secondary : AppColors.primary)
                  : AppColors.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user != null ? user.email : 'Conta Não Conectada',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (user != null && user.isPro)
                            ? AppColors.secondary.withOpacity(0.18)
                            : AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (user != null && user.isPro)
                              ? AppColors.secondary.withOpacity(0.3)
                              : AppColors.borderSubtle,
                        ),
                      ),
                      child: Text(
                        user != null ? user.subscriptionTier.badgeLabel : 'Modo Offline',
                        style: TextStyle(
                          color: (user != null && user.isPro)
                              ? AppColors.secondary
                              : AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  user != null
                      ? 'Sincronização em Nuvem Multi-Dispositivo Ativa • ${user.aiCreditsRemaining}/${user.aiCreditsTotal} créditos IA'
                      : 'Conecte sua conta FLRD para sincronizar licenças e projetos em múltiplos dispositivos.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => UserAccountDialog.show(context),
            icon: Icon(
              user != null ? Icons.account_circle_rounded : Icons.login_rounded,
              size: 14,
              color: AppColors.secondary,
            ),
            label: Text(
              user != null ? 'Gerenciar Conta' : 'Conectar Conta',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanAndBillingTab(BuildContext context, AiSettingsState aiSettings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Authenticated User & Multi-Device Cloud Sync Card
          _buildAccountSyncStatusCard(context),

          // Billing Period Switcher (Annual vs Monthly)
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBillingTogglePill(
                    label: 'Annual (2 months free 🎁)',
                    isSelected: _isAnnualBilling,
                    onTap: () {
                      setState(() => _isAnnualBilling = true);
                      ref.read(aiSettingsProvider.notifier).setAnnualBilling(true);
                    },
                  ),
                  _buildBillingTogglePill(
                    label: 'Monthly',
                    isSelected: !_isAnnualBilling,
                    onTap: () {
                      setState(() => _isAnnualBilling = false);
                      ref.read(aiSettingsProvider.notifier).setAnnualBilling(false);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Tier 1: FLRD Starter
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FLRD Starter',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'For indie hackers & agile creators',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isAnnualBilling ? r'$149 / year' : r'$15 / month',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Scaffold clean-architecture Flutter apps with turnkey AI generation ready to go.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 14),
                _buildBenefitItem('Unlimited app scaffolding (Riverpod SaaS, BLoC, SQLite)'),
                const SizedBox(height: 6),
                _buildBenefitItem('Managed AI included (100 screens/month with zero config)'),
                const SizedBox(height: 6),
                _buildBenefitItem('App Studio with interactive route flowchart'),
                const SizedBox(height: 6),
                _buildBenefitItem('Dart code editor with real-time syntax highlighting'),
                const SizedBox(height: 6),
                _buildBenefitItem('Native permissions injector for Android & iOS'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceHover,
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _openUrl(
                    _isAnnualBilling
                        ? MonetizationConfig.stripeStarterAnnualCheckoutUrl
                        : MonetizationConfig.stripeStarterMonthlyCheckoutUrl,
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.primary),
                  label: Text(
                    _isAnnualBilling ? 'Subscribe Starter Annual (\$149/year)' : 'Subscribe Starter Monthly (\$15/month)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tier 2: FLRD Studio Pro (Highlight Card)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.secondary.withOpacity(0.4), width: 1.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.secondary.withOpacity(0.08),
                  AppColors.surfaceCard,
                  AppColors.backgroundSecondary,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.diamond_rounded, color: AppColors.secondary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'FLRD Studio Pro',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
                                ),
                                child: const Text(
                                  'MOST POPULAR',
                                  style: TextStyle(
                                    color: AppColors.secondary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            'For teams, agencies & pro creators',
                            style: TextStyle(color: AppColors.secondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isAnnualBilling ? r'$299 / year' : r'$35 / month',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Full firepower: reverse engineer existing apps, bring your own AI keys with zero limits, and sell templates in the Marketplace.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 14),
                _buildBenefitItem('All Starter features included'),
                const SizedBox(height: 6),
                _buildBenefitItem('📂 Reverse Engineering: import and map any legacy app in Studio'),
                const SizedBox(height: 6),
                _buildBenefitItem('🚀 Unlimited BYOK: use your own AI key with no screen limits'),
                const SizedBox(height: 6),
                _buildBenefitItem('💎 Marketplace Seller: publish templates and earn 75% creator payout'),
                const SizedBox(height: 6),
                _buildBenefitItem('🧠 Batch Screen Generation (interconnected multi-screen flows)'),
                const SizedBox(height: 6),
                _buildBenefitItem('⭐ Priority VIP Core Support with early access'),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 2,
                  ),
                  onPressed: () => _openUrl(
                    _isAnnualBilling
                        ? MonetizationConfig.stripeProAnnualCheckoutUrl
                        : MonetizationConfig.stripeProMonthlyCheckoutUrl,
                  ),
                  icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                  label: Text(
                    _isAnnualBilling ? 'Subscribe Studio Pro Annual (\$299/year)' : 'Subscribe Studio Pro Monthly (\$35/month)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Pro status toggle card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                Icon(
                  aiSettings.isProActive ? Icons.verified_rounded : Icons.lock_outline_rounded,
                  color: aiSettings.isProActive ? AppColors.success : AppColors.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        aiSettings.isProActive
                            ? 'License Status: FLRD Pro Active'
                            : (aiSettings.selectedPlan == 'starter'
                                ? 'License Status: FLRD Starter Active'
                                : 'License Status: FLRD Community'),
                        style: TextStyle(
                          color: (aiSettings.isProActive || aiSettings.selectedPlan == 'starter')
                              ? AppColors.success
                              : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        aiSettings.isProActive
                            ? 'Reverse Engineering, BYOK, and Marketplace unlocked!'
                            : 'Subscribe to a plan to unlock all advanced capabilities.',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(aiSettingsProvider.notifier).toggleProActive();
                    AppToast.info(
                      context,
                      !aiSettings.isProActive
                          ? 'FLRD Pro license activated!'
                          : 'Reverted to Community edition.',
                      duration: const Duration(seconds: 2),
                    );
                  },
                  child: Text(
                    aiSettings.isProActive ? 'Deactivate Pro' : 'Activate License',
                    style: const TextStyle(fontSize: 11, color: AppColors.secondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(String text) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 15,
          color: AppColors.secondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSupportTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Open source description
          const Text(
            'Apoie o Desenvolvimento Independente',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'O FLRD é um projeto independente de código aberto desenvolvido por Robson David (@iRoobsoN) para acelerar a criação de aplicações Flutter profissionais. '
            'Seu apoio financia o desenvolvimento de novos templates, presets arquiteturais e melhorias contínuas.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),

          // Pix Card (Brasil)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PIX (Brasil)',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success.withOpacity(0.2),
                        foregroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _copyPixKey(context),
                      icon: const Icon(Icons.copy_rounded, size: 13),
                      label: const Text(
                        'Copiar Chave',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const SelectableText(
                  MonetizationConfig.pixKey,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // PayPal Card (Global)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openUrl(MonetizationConfig.payPalUrl),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.payment_rounded,
                    color: AppColors.secondary,
                    size: 22,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PayPal (Global)',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Apoie internacionalmente com cartão de crédito via PayPal.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // GitHub Sponsors Card
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openUrl(MonetizationConfig.githubSponsorsUrl),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.volunteer_activism_rounded,
                    color: Colors.pinkAccent,
                    size: 22,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GitHub Sponsors (@iRoobsoN)',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Apoio mensal recorrente através da plataforma oficial do GitHub.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () => _openUrl('https://github.com/iRoobsoN/flrd'),
            icon: const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
            label: const Text('Star on GitHub', style: TextStyle(fontSize: 11)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
