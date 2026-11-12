import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../localization/language_provider.dart';
import '../localization/language_selector_widget.dart';
import '../services/flutter_sdk_service.dart';
import '../theme/app_colors.dart';
import '../widgets/flutter_doctor_dialog.dart';
import '../../features/settings/presentation/settings_and_billing_dialog.dart';
import '../../features/auth/domain/user_account.dart';
import '../../features/auth/presentation/user_account_dialog.dart';
import '../../features/auth/providers/auth_provider.dart';

class CustomTitleBar extends ConsumerWidget {
  final bool showBackButton;
  final VoidCallback? onBack;
  final Widget? trailing;

  const CustomTitleBar({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final sdkStatus = ref.watch(flutterSdkProvider);
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    Widget titleContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBackButton) ...[
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onBack ??
                    () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).maybePop();
                      }
                    },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_back_rounded,
                        size: 14,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        strings.backToHub,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Brand Icon & Name
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'FLRD',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'v0.2.1',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Dynamic Flutter SDK Status Pill
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Tooltip(
                message: sdkStatus.isInstalled
                    ? 'Flutter SDK active (${sdkStatus.version ?? "Ready"}). Click to run FLRD Doctor.'
                    : 'Flutter SDK missing in PATH. Click to run FLRD Doctor.',
                child: InkWell(
                  onTap: () => FlutterDoctorDialog.show(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: sdkStatus.isInstalled
                          ? AppColors.success.withOpacity(0.12)
                          : (sdkStatus.isChecking
                              ? AppColors.secondary.withOpacity(0.12)
                              : AppColors.warning.withOpacity(0.15)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sdkStatus.isInstalled
                            ? AppColors.success.withOpacity(0.3)
                            : (sdkStatus.isChecking
                                ? AppColors.secondary.withOpacity(0.3)
                                : AppColors.warning.withOpacity(0.4)),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: sdkStatus.isInstalled
                                ? AppColors.success
                                : (sdkStatus.isChecking
                                    ? AppColors.secondary
                                    : AppColors.warning),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(
                            sdkStatus.isChecking
                                ? strings.flutterSdkChecking
                                : (sdkStatus.isInstalled
                                    ? (sdkStatus.version != null
                                        ? 'Flutter ${sdkStatus.version}'
                                        : strings.engineStatus)
                                    : strings.flutterSdkMissing),
                            style: TextStyle(
                              color: sdkStatus.isInstalled
                                  ? AppColors.success
                                  : (sdkStatus.isChecking
                                      ? AppColors.secondary
                                      : AppColors.warning),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      height: 42,
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Flexible(
            child: titleContent,
          ),
          Expanded(
            child: isDesktop
                ? const DragToMoveArea(child: SizedBox.expand())
                : const SizedBox.expand(),
          ),
          trailing ??
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: LanguageSelectorWidget(compact: true),
              ),
          _buildUserAccountPill(context, ref),
          IconButton(
            tooltip: strings.settingsAndBilling,
            icon: const Icon(
              Icons.settings_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
            splashRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => SettingsAndBillingDialog.show(context),
          ),
          const SizedBox(width: 4),
          if (isDesktop) ...[
            _WindowActionButton(
              icon: Icons.remove_rounded,
              onTap: () async {
                try {
                  await windowManager.minimize();
                } catch (e) {
                  debugPrint('WindowManager minimize failed: $e');
                }
              },
            ),
            _WindowActionButton(
              icon: Icons.crop_square_rounded,
              onTap: () async {
                try {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                } catch (e) {
                  debugPrint('WindowManager maximize toggle failed: $e');
                }
              },
            ),
            _WindowActionButton(
              icon: Icons.close_rounded,
              isClose: true,
              onTap: () async {
                try {
                  await windowManager.close();
                } catch (e) {
                  debugPrint('WindowManager close failed: $e');
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUserAccountPill(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    if (user == null) {
      // Unauthenticated state: [👤 Entrar] pill
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Tooltip(
          message: 'Entrar ou Criar Conta FLRD',
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => UserAccountDialog.show(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 13,
                    color: AppColors.secondary,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Entrar',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Authenticated state: shows user avatar/initials + active tier badge (e.g. ⭐ PRO)
    final tier = user.subscriptionTier;
    final isPro = user.isPro;
    final tierBadgeText = switch (tier) {
      SubscriptionTier.studioPro => '⭐ PRO',
      SubscriptionTier.starter => '⚡ STARTER',
      SubscriptionTier.community => '🌱 FREE',
    };

    final badgeColor = isPro ? AppColors.secondary : AppColors.success;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: '${user.effectiveName} (${tier.label}) - Clique para ver o perfil',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => UserAccountDialog.show(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPro
                    ? AppColors.secondary.withOpacity(0.4)
                    : AppColors.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    user.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tierBadgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowActionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;

  const _WindowActionButton({
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_WindowActionButton> createState() => _WindowActionButtonState();
}

class _WindowActionButtonState extends State<_WindowActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 44,
          height: 42,
          color: _isHovered
              ? (widget.isClose ? AppColors.danger : AppColors.surfaceHover)
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 15,
            color: _isHovered && widget.isClose
                ? Colors.white
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
