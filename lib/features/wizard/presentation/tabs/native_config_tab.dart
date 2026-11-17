import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors.dart';
import '../../models/project_config.dart';
import '../controllers/wizard_controller.dart';
import '../widgets/dependencies_review_panel.dart';

class NativeConfigTab extends ConsumerWidget {
  const NativeConfigTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardProvider);
    final notifier = ref.read(wizardProvider.notifier);
    final config = state.config;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Etapa 6 • Android, iOS & Revisão Final',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Defina as versões mínimas de compatibilidade para Android e iOS e confira o resumo completo antes de criar o projeto.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),

          // Android Section
          _SectionContainer(
            title: 'PROPRIEDADES DO ANDROID (GRADLE)',
            icon: Icons.android_rounded,
            iconColor: AppColors.success,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Versão Mínima do Android (minSdkVersion)',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'SDK 24+ (Android 7.0) é recomendado para suporte moderno a câmera, biometria e segurança.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: config.androidMinSdk,
                    dropdownColor: AppColors.surfaceCard,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: 21, child: Text('SDK 21 (Android 5.0 Lollipop)')),
                      DropdownMenuItem(value: 24, child: Text('SDK 24 (Android 7.0 - Recomendado)')),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Habilitar suporte MultiDex',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Evita erro de limite de métodos ao usar pacotes maiores como Supabase, Google Maps ou Firebase.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
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
          const SizedBox(height: 20),

          // iOS Section
          _SectionContainer(
            title: 'ALVO DE COMPATIBILIDADE IOS',
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
                          'Versão Mínima do iOS (Deployment Target)',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'iOS 15.0+ atende mais de 98% dos iPhones ativos e garante compatibilidade com bibliotecas atuais.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: config.iosTarget,
                    dropdownColor: AppColors.surfaceCard,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: '14.0', child: Text('iOS 14.0')),
                      DropdownMenuItem(value: '15.0', child: Text('iOS 15.0 (Recomendado)')),
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
          const SizedBox(height: 20),

          // Resumo final completo do app antes da geração
          _WizardSummaryCard(config: config),
          const SizedBox(height: 20),

          // Opções Avançadas opcionais: revisar/desmarcar/incluir dependências antes de criar
          const AdvancedDependenciesSection(),
        ],
      ),
    );
  }
}

class _WizardSummaryCard extends StatelessWidget {
  final ProjectConfig config;

  const _WizardSummaryCard({required this.config});

  @override
  Widget build(BuildContext context) {
    final fullPath = config.outputPath.trim().isEmpty
        ? 'Pasta não selecionada'
        : p.join(config.outputPath.trim(), config.projectName).replaceAll('\\', '/');
    final permList = config.permissions.isEmpty
        ? 'Nenhuma selecionada'
        : config.permissions.map((perm) => perm.name).join(', ');
    final depsCount = config.resolvedPackagesToInstall.length;

    return _SectionContainer(
      title: 'RESUMO FINAL DO APP (PRONTO PARA CRIAR)',
      icon: Icons.fact_check_rounded,
      iconColor: AppColors.secondary,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            _SummaryRow(label: 'Projeto', value: '${config.projectName} (${config.orgId})'),
            _SummaryRow(label: 'Pasta no disco', value: fullPath),
            _SummaryRow(
              label: 'Preset',
              value: '${config.preset.name} — ${config.preset.friendlySubtitle}',
            ),
            _SummaryRow(label: 'Navegação', value: config.navigationStyle.ptLabel),
            _SummaryRow(
              label: 'Tema',
              value:
                  '#${config.seedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()} • ${config.enableDarkTheme ? "Claro + Escuro" : "Somente Claro"}',
            ),
            _SummaryRow(label: 'Permissões', value: permList),
            _SummaryRow(
              label: 'Alvos Nativos',
              value: 'Android SDK ${config.androidMinSdk}+ • iOS ${config.iosTarget}+',
            ),
            _SummaryRow(
              label: 'Dependências',
              value:
                  '$depsCount pacote(s)${config.hasCustomDependencies ? " • revisado" : " (padrão do preset)"}',
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
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
