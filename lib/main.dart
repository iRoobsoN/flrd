import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'features/hub/presentation/hub_screen.dart';

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

class FLRDApp extends StatelessWidget {
  const FLRDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FLRD - Flutter Rapid Deployment',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HubScreen(),
    );
  }
}
