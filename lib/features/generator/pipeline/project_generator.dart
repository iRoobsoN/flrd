import 'dart:io';
import 'package:process_run/process_run.dart';
import '../../wizard/models/project_config.dart';
import '../injectors/android_manifest_injector.dart';
import '../injectors/ios_plist_injector.dart';

class ProjectGenerator {
  final ProjectConfig config;
  final void Function(String message) onLog;

  ProjectGenerator({
    required this.config,
    required this.onLog,
  });

  Future<bool> execute() async {
    final targetPath = '${config.outputPath}/${config.projectName}';

    try {
      // Step 1: Base Flutter Scaffold
      onLog('🚀 Step 1/5: Running flutter create via host SDK...');
      final createRes = await runExecutableArguments(
        'flutter',
        [
          'create',
          '--org',
          config.orgId,
          '--project-name',
          config.projectName,
          targetPath,
        ],
      );

      if (createRes.exitCode != 0) {
        onLog('❌ flutter create failed: ${createRes.stderr}');
        return false;
      }
      onLog('✅ Base Flutter project generated successfully.');

      // Step 2: Injecting Native Permissions
      if (config.permissions.isNotEmpty) {
        onLog('🛡️ Step 2/5: Injecting native permissions (AndroidManifest & Info.plist)...');
        await AndroidManifestInjector.injectPermissions(
          projectRoot: targetPath,
          permissions: config.permissions,
        );
        await IosPlistInjector.injectPermissions(
          projectRoot: targetPath,
          permissions: config.permissions,
        );
        onLog('✅ Native permissions safely injected.');
      }

      // Step 3: Resolving Dynamic Dependencies
      onLog('📦 Step 3/5: Resolving dynamic packages from pub.dev...');
      final packagesToAdd = <String>['go_router', 'google_fonts'];
      
      switch (config.preset) {
        case PresetType.saas:
          packagesToAdd.addAll(['flutter_riverpod', 'supabase_flutter']);
          break;
        case PresetType.cleanLite:
          packagesToAdd.addAll(['flutter_bloc', 'dio', 'get_it']);
          break;
        case PresetType.offline:
          packagesToAdd.addAll(['provider', 'shared_preferences']);
          break;
      }

      if (config.permissions.isNotEmpty) {
        packagesToAdd.add('permission_handler');
      }

      await runExecutableArguments(
        'flutter',
        ['pub', 'add', ...packagesToAdd],
        workingDirectory: targetPath,
      );
      onLog('✅ Dependencies resolved and added.');

      // Step 4: Synthesize Lib & Theme
      onLog('🎨 Step 4/5: Synthesizing navigation shell & smart contrast theme...');
      await _writeCustomMain(targetPath);
      onLog('✅ Custom templates applied.');

      onLog('🎉 Step 5/5: FLRD scaffolding complete! Opening project...');
      return true;
    } catch (e) {
      onLog('❌ Unexpected error: $e');
      return false;
    }
  }

  Future<void> _writeCustomMain(String targetPath) async {
    final mainFile = File('$targetPath/lib/main.dart');
    final code = '''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void main() {
  runApp(const MyApp());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '${config.projectName}',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(${config.seedColor.value}),
          brightness: Brightness.${config.enableDarkTheme ? 'dark' : 'light'},
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${config.projectName}'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt_rounded, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Scaffolded with FLRD ⚡',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Preset: ${config.preset.name}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
''';
    await mainFile.writeAsString(code);
  }
}
