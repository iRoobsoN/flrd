import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../localization/language_provider.dart';
import '../theme/app_colors.dart';
import '../../features/settings/presentation/settings_and_billing_dialog.dart';

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

    Widget titleContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (showBackButton) ...[
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
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
          // Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  strings.engineStatus,
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
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
          Expanded(
            child: kIsWeb ? titleContent : DragToMoveArea(child: titleContent),
          ),
          if (trailing != null) trailing!,
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
          if (!kIsWeb) ...[
            _WindowActionButton(
              icon: Icons.remove_rounded,
              onTap: () => windowManager.minimize(),
            ),
            _WindowActionButton(
              icon: Icons.crop_square_rounded,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
            ),
            _WindowActionButton(
              icon: Icons.close_rounded,
              isClose: true,
              onTap: () => windowManager.close(),
            ),
          ],
        ],
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
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
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
