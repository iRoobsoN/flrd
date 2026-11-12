import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Visual severity for desktop notifications displayed across FLRD.
enum AppToastType { info, success, warning, error }

/// High-contrast desktop notification helper.
///
/// Renders an Obsidian Glass toast card with explicit `#F8FAFC` text over a
/// dark `#131B2E` surface and a semantic accent stripe so messages never blend
/// with their background. Uses [ScaffoldMessenger] on standard routes (keeping
/// full [SnackBar] widget compatibility) and promotes to the root [Overlay]
/// when triggered from inside an active modal dialog so notifications appear
/// cleanly above the modal barrier.
class AppToast {
  AppToast._();

  static OverlayEntry? _activeOverlayEntry;

  static void show(
    BuildContext context, {
    required String message,
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    final route = ModalRoute.of(context);
    final ancestorScaffoldContext =
        context.findAncestorStateOfType<ScaffoldState>()?.context;
    final scaffoldBelongsToCurrentRoute = ancestorScaffoldContext != null &&
        ModalRoute.of(ancestorScaffoldContext) == route;
    final isInsideActiveModal =
        route is PopupRoute && route.isCurrent && !scaffoldBelongsToCurrentRoute;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!isInsideActiveModal && messenger != null) {
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          behavior: SnackBarBehavior.floating,
          duration: duration,
          content: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _AppToastCard(
                message: message,
                type: type,
                onDismiss: () => messenger.hideCurrentSnackBar(),
              ),
            ),
          ),
        ),
      );
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) {
      _dismissActiveOverlay();
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (overlayContext) => _AutoDismissOverlayToast(
          duration: duration,
          onDismiss: () {
            if (_activeOverlayEntry == entry) {
              _dismissActiveOverlay();
            }
          },
          child: _AppToastCard(
            message: message,
            type: type,
            onDismiss: () {
              if (_activeOverlayEntry == entry) {
                _dismissActiveOverlay();
              }
            },
          ),
        ),
      );
      _activeOverlayEntry = entry;
      overlay.insert(entry);
    }
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      type: AppToastType.success,
      duration: duration,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    show(
      context,
      message: message,
      type: AppToastType.error,
      duration: duration,
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      type: AppToastType.warning,
      duration: duration,
    );
  }

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      type: AppToastType.info,
      duration: duration,
    );
  }

  static void _dismissActiveOverlay() {
    final entry = _activeOverlayEntry;
    _activeOverlayEntry = null;
    if (entry != null) {
      try {
        if (entry.mounted) {
          entry.remove();
        }
      } catch (_) {}
    }
  }
}

class _AppToastCard extends StatelessWidget {
  const _AppToastCard({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  final String message;
  final AppToastType type;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (Color accent, IconData icon) = switch (type) {
      AppToastType.success => (AppColors.success, Icons.check_circle_rounded),
      AppToastType.error => (AppColors.danger, Icons.error_outline_rounded),
      AppToastType.warning => (AppColors.warning, Icons.warning_amber_rounded),
      AppToastType.info => (AppColors.secondary, Icons.info_outline_rounded),
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('app_toast_card'),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent.withValues(alpha: 0.65),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.16),
              blurRadius: 12,
              spreadRadius: -2,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: accent, size: 17),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        key: const ValueKey('app_toast_close_button'),
                        onTap: onDismiss,
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoDismissOverlayToast extends StatefulWidget {
  const _AutoDismissOverlayToast({
    required this.duration,
    required this.onDismiss,
    required this.child,
  });

  final Duration duration;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_AutoDismissOverlayToast> createState() =>
      _AutoDismissOverlayToastState();
}

class _AutoDismissOverlayToastState extends State<_AutoDismissOverlayToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          widget.onDismiss();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 24,
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
