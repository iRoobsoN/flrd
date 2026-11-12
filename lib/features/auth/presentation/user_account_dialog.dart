import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/monetization_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../domain/user_account.dart';
import '../providers/auth_provider.dart';

/// Modal dialog styled with Obsidian Glass aesthetics for user authentication,
/// registration, account profile inspection, tier badges, and Stripe billing portal access.
class UserAccountDialog extends ConsumerStatefulWidget {
  final int initialTab;

  const UserAccountDialog({
    super.key,
    this.initialTab = 0,
  });

  /// Displays the User Account dialog modal.
  static Future<void> show(BuildContext context, {int initialTab = 0}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => UserAccountDialog(initialTab: initialTab),
    );
  }

  @override
  ConsumerState<UserAccountDialog> createState() => _UserAccountDialogState();
}

class _UserAccountDialogState extends ConsumerState<UserAccountDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _loginPasswordController = TextEditingController();

  final TextEditingController _signupNameController = TextEditingController();
  final TextEditingController _signupEmailController = TextEditingController();
  final TextEditingController _signupPasswordController = TextEditingController();

  bool _obscureLoginPassword = true;
  bool _obscureSignupPassword = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupNameController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        AppToast.error(context, 'Não foi possível abrir: $url');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Erro ao abrir link: $e');
    }
  }

  Future<void> _handleSignIn() async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;

    if (email.isEmpty || password.isEmpty) {
      AppToast.warning(context, 'Por favor, informe seu email e senha.');
      return;
    }

    final success = await ref
        .read(authProvider.notifier)
        .signInWithEmailAndPassword(email, password);

    if (success && mounted) {
      AppToast.success(
        context,
        'Login efetuado com sucesso!',
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _handleSignUp() async {
    final name = _signupNameController.text.trim();
    final email = _signupEmailController.text.trim();
    final password = _signupPasswordController.text;

    if (email.isEmpty || password.isEmpty) {
      AppToast.warning(
        context,
        'Por favor, informe email e senha para criar a conta.',
      );
      return;
    }

    final success = await ref
        .read(authProvider.notifier)
        .signUpWithEmailAndPassword(email, password, name.isNotEmpty ? name : null);

    if (success && mounted) {
      AppToast.success(
        context,
        'Conta criada com sucesso! Seja bem-vindo ao FLRD.',
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _handleOAuthLogin(String provider) async {
    final success = await ref
        .read(authProvider.notifier)
        .signInWithOAuth(provider, 'mock_${provider}_token');

    if (success && mounted) {
      AppToast.success(
        context,
        'Autenticado com sucesso via $provider!',
        duration: const Duration(seconds: 2),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    return Dialog(
      backgroundColor: AppColors.backgroundSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 520,
          maxHeight: 650,
          minWidth: 420,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dialog Header
            _buildHeader(context, user),
            const Divider(height: 1, color: AppColors.borderSubtle),

            // Dialog Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Error Callout Banner
                    if (authState.errorMessage != null &&
                        authState.errorMessage!.isNotEmpty)
                      _buildErrorBanner(authState.errorMessage!),

                    // Render Logged-in Profile or Auth Tabs
                    if (user != null)
                      _buildLoggedInProfile(user, authState.isLoading)
                    else
                      _buildAuthForm(authState.isLoading),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UserAccount? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              user != null ? Icons.verified_user_rounded : Icons.lock_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user != null ? 'Perfil da Conta FLRD' : 'Autenticação FLRD',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  user != null
                      ? 'Sincronização em nuvem & Gerenciamento de Assinatura'
                      : 'Acesse seus projetos e planos em qualquer dispositivo',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 20),
            tooltip: 'Fechar',
            splashRadius: 18,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.danger.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => ref.read(authProvider.notifier).clearError(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AUTH FORM (UNAUTHENTICATED)
  // ---------------------------------------------------------------------------

  Widget _buildAuthForm(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs: Sign In vs Sign Up
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login_rounded, size: 15),
                      SizedBox(width: 6),
                      Text('🔑 Entrar / Sign In'),
                    ],
                  ),
                ),
              ),
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add_alt_1_rounded, size: 15),
                      SizedBox(width: 6),
                      Text('✨ Criar Conta / Sign Up'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Tab Content via IndexedStack
        IndexedStack(
          index: _tabController.index,
          children: [
            _buildSignInView(isLoading),
            _buildSignUpView(isLoading),
          ],
        ),

        const SizedBox(height: 16),
        // Social Divider
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.borderSubtle)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'ou continue com',
                style: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.8),
                  fontSize: 11,
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.borderSubtle)),
          ],
        ),
        const SizedBox(height: 14),

        // Social Login Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: isLoading ? null : () => _handleOAuthLogin('Google'),
                icon: const Icon(Icons.language_rounded, size: 16, color: AppColors.secondary),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '🌐 Continuar com Google',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: isLoading ? null : () => _handleOAuthLogin('GitHub'),
                icon: const Icon(Icons.code_rounded, size: 16, color: AppColors.textPrimary),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '🐱 Continuar com GitHub',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignInView(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _loginEmailController,
          label: 'E-mail',
          hint: 'exemplo@flrd.dev',
          icon: Icons.alternate_email_rounded,
          enabled: !isLoading,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _loginPasswordController,
          label: 'Senha',
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscureLoginPassword,
          enabled: !isLoading,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureLoginPassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 16,
              color: AppColors.textMuted,
            ),
            onPressed: () => setState(() => _obscureLoginPassword = !_obscureLoginPassword),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: isLoading ? null : _handleSignIn,
          child: isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'Entrar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
        ),
      ],
    );
  }

  Widget _buildSignUpView(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _signupNameController,
          label: 'Nome de Exibição (Opcional)',
          hint: 'Robson Dev',
          icon: Icons.badge_outlined,
          enabled: !isLoading,
        ),
        const SizedBox(height: 10),
        _buildTextField(
          controller: _signupEmailController,
          label: 'E-mail',
          hint: 'dev@flrd.dev',
          icon: Icons.alternate_email_rounded,
          enabled: !isLoading,
        ),
        const SizedBox(height: 10),
        _buildTextField(
          controller: _signupPasswordController,
          label: 'Senha (mínimo 6 caracteres)',
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscureSignupPassword,
          enabled: !isLoading,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureSignupPassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 16,
              color: AppColors.textMuted,
            ),
            onPressed: () => setState(() => _obscureSignupPassword = !_obscureSignupPassword),
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: AppColors.background,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: isLoading ? null : _handleSignUp,
          child: isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                )
              : const Text(
                  'Criar Conta',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    bool enabled = true,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, size: 16, color: AppColors.secondary),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // USER PROFILE CARD (AUTHENTICATED)
  // ---------------------------------------------------------------------------

  Widget _buildLoggedInProfile(UserAccount user, bool isLoading) {
    final progress = user.aiCreditsTotal > 0
        ? (user.aiCreditsRemaining / user.aiCreditsTotal).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // User Profile Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              // Avatar with Initials
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  user.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // User Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.effectiveName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Monospace UID Row with copy
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'UID: ${user.uid}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: user.uid));
                            AppToast.success(
                              context,
                              'UID copiado para a área de transferência!',
                              duration: const Duration(seconds: 2),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.copy_rounded, size: 12, color: AppColors.textMuted),
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
        const SizedBox(height: 14),

        // Active Subscription Badge Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: user.isPro
                ? AppColors.secondary.withOpacity(0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: user.isPro
                  ? AppColors.secondary.withOpacity(0.3)
                  : AppColors.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: user.isPro
                      ? AppColors.secondary.withOpacity(0.2)
                      : AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  user.subscriptionTier == SubscriptionTier.studioPro
                      ? Icons.workspace_premium_rounded
                      : (user.subscriptionTier == SubscriptionTier.starter
                          ? Icons.bolt_rounded
                          : Icons.eco_rounded),
                  color: user.isPro ? AppColors.secondary : AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.subscriptionTier.badgeLabel,
                      style: TextStyle(
                        color: user.isPro ? AppColors.secondary : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.isPro
                          ? 'Sincronização em nuvem ativa em todos os seus computadores.'
                          : 'Plano comunitário com limite padrão de gerações.',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // AI Credits Counter Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Cota de IA',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '⚡ ${user.aiCreditsRemaining} / ${user.aiCreditsTotal} Gerações de IA restantes neste mês',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.surface,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress < 0.2 ? AppColors.danger : AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Actions: Stripe Customer Portal & Sign Out
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceHover,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _openUrl(MonetizationConfig.stripeCustomerPortalUrl),
                icon: const Icon(Icons.manage_accounts_rounded, size: 16, color: AppColors.secondary),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Gerenciar Assinatura (Stripe)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        await ref.read(authProvider.notifier).signOut();
                        if (mounted) {
                          AppToast.info(
                            context,
                            'Sessão encerrada com sucesso.',
                            duration: const Duration(seconds: 2),
                          );
                        }
                      },
                icon: const Icon(Icons.logout_rounded, size: 16, color: AppColors.danger),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Desconectar / Sign Out',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
