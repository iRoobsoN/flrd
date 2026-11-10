import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../controllers/wizard_controller.dart';

class NativeConfigTab extends ConsumerWidget {
  const NativeConfigTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardProvider);
    final notifier = ref.read(wizardProvider.notifier);
    final config = state.config;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Native Platform Setup',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Configure Gradle and Xcode deployment targets effortlessly without touching fragile config scripts.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 32),

          // Android Section
          _SectionContainer(
            title: 'ANDROID GRADLE PROPERTIES',
            icon: Icons.android_rounded,
            iconColor: AppColors.success,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Minimum SDK Version (minSdkVersion)',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'SDK 24+ is recommended for modern camera, biometrics, and security features.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  DropdownButton<int>(
                    value: config.androidMinSdk,
                    dropdownColor: AppColors.surfaceCard,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: 21, child: Text('SDK 21 (Android 5.0 Lollipop)')),
                      DropdownMenuItem(value: 24, child: Text('SDK 24 (Android 7.0 Nougat - Recommended)')),
                      DropdownMenuItem(value: 26, child: Text('SDK 26 (Android 8.0 Oreo)')),
                      DropdownMenuItem(value: 33, child: Text('SDK 33 (Android 13 Tiramisu)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        notifier.updateConfig((c) => c.copyWith(androidMinSdk: val));
                      }
                    },
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enable MultiDex Support',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Prevents 64k method limit crashes when compiling heavy packages like Firebase or ML.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  Switch(
                    value: config.enableMultiDex,
                    onChanged: (val) => notifier.updateConfig((c) => c.copyWith(enableMultiDex: val)),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // iOS Section
          _SectionContainer(
            title: 'IOS DEPLOYMENT TARGET',
            icon: Icons.apple_rounded,
            iconColor: AppColors.textPrimary,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'iOS Minimum Deployment Target',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'iOS 15.0+ covers 98%+ of active iOS devices and allows modern SwiftUI/Swift APIs.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  DropdownButton<String>(
                    value: config.iosTarget,
                    dropdownColor: AppColors.surfaceCard,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: '14.0', child: Text('iOS 14.0')),
                      DropdownMenuItem(value: '15.0', child: Text('iOS 15.0 (Recommended)')),
                      DropdownMenuItem(value: '16.0', child: Text('iOS 16.0')),
                      DropdownMenuItem(value: '17.0', child: Text('iOS 17.0')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        notifier.updateConfig((c) => c.copyWith(iosTarget: val));
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionContainer extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _SectionContainer({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
