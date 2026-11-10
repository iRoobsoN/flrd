import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/project_config.dart';
import '../controllers/wizard_controller.dart';

class PermissionsTab extends ConsumerWidget {
  const PermissionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardProvider);
    final notifier = ref.read(wizardProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Smart Permission Wizard',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Automatically injects AndroidManifest tags, App Store-proof Info.plist keys, and a clean PermissionService.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),

          ...DevicePermission.values.map((perm) {
            final isEnabled = state.config.permissions.contains(perm);
            return _PermissionTile(
              permission: perm,
              isEnabled: isEnabled,
              onToggle: (enabled) {
                notifier.updateConfig((c) {
                  final newSet = Set<DevicePermission>.from(c.permissions);
                  if (enabled) {
                    newSet.add(perm);
                  } else {
                    newSet.remove(perm);
                  }
                  return c.copyWith(permissions: newSet);
                });
              },
            );
          }),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final DevicePermission permission;
  final bool isEnabled;
  final ValueChanged<bool> onToggle;

  const _PermissionTile({
    required this.permission,
    required this.isEnabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isEnabled ? AppColors.surfaceSelected : AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled ? AppColors.primary.withOpacity(0.5) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isEnabled ? AppColors.primary.withOpacity(0.2) : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  permission.icon,
                  color: isEnabled ? AppColors.secondary : AppColors.textMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      permission.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      permission.description,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: onToggle,
                activeColor: AppColors.primary,
                activeTrackColor: AppColors.primaryGlow,
                inactiveThumbColor: AppColors.textMuted,
                inactiveTrackColor: AppColors.surface,
              ),
            ],
          ),
          if (isEnabled) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.android_rounded, size: 14, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text(
                        permission.androidTag,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.apple_rounded, size: 14, color: AppColors.textPrimary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${permission.iosKey}: "${permission.iosDefaultReason}"',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
