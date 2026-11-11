import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/window/custom_titlebar.dart';
import 'features/hub/presentation/hub_screen.dart';
import 'features/marketplace/presentation/marketplace_view.dart';
import 'features/projects/providers/projects_provider.dart';
import 'features/settings/presentation/settings_and_billing_dialog.dart';
import 'features/studio/presentation/app_studio_screen.dart';
import 'features/wizard/presentation/wizard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop Window Setup (Windows, macOS, Linux)
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1180, 780),
      minimumSize: Size(980, 640),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'FLRD - Flutter Rapid Deployment',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    const ProviderScope(
      child: FLRDApp(),
    ),
  );
}

class FLRDApp extends ConsumerWidget {
  const FLRDApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget getHomeScreen() {
      if (kIsWeb) {
        final screenParam = Uri.base.queryParameters['screen'] ?? '';
        if (screenParam == 'studio') {
          final projects = ref.watch(projectsProvider).projects;
          final sampleProject = projects.isNotEmpty ? projects.first : null;
          if (sampleProject != null) {
            return AppStudioScreen(project: sampleProject);
          }
        } else if (screenParam == 'marketplace') {
          return const Scaffold(
            body: Column(
              children: [
                CustomTitleBar(),
                Expanded(child: MarketplaceView()),
              ],
            ),
          );
        } else if (screenParam == 'wizard') {
          return const Scaffold(
            body: Column(
              children: [
                CustomTitleBar(showBackButton: true),
                Expanded(child: WizardScreen()),
              ],
            ),
          );
        } else if (screenParam == 'billing') {
          return const _BillingShowcaseWrapper();
        }
      }
      return const HubScreen();
    }

    return MaterialApp(
      title: 'FLRD - Flutter Rapid Deployment',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: getHomeScreen(),
    );
  }
}

class _BillingShowcaseWrapper extends StatefulWidget {
  const _BillingShowcaseWrapper();

  @override
  State<_BillingShowcaseWrapper> createState() => _BillingShowcaseWrapperState();
}

class _BillingShowcaseWrapperState extends State<_BillingShowcaseWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SettingsAndBillingDialog.show(context, initialTabIndex: 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const HubScreen();
  }
}

