import 'package:process_run/process_run.dart';
import '../../wizard/models/project_config.dart';
import '../injectors/android_manifest_injector.dart';
import '../injectors/ios_plist_injector.dart';
import '../presets/saas_preset.dart';
import '../presets/clean_lite_preset.dart';
import '../services/permission_service_template.dart';

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
      onLog('🎨 Step 4/5: Synthesizing architecture presets & GoRouter guards...');
      
      // Synthesize permission helper if permissions are enabled
      if (config.permissions.isNotEmpty) {
        await PermissionServiceTemplate.synthesize(targetPath, config.permissions);
      }

      // Synthesize preset files
      switch (config.preset) {
        case PresetType.saas:
          await SaasPreset.synthesize(targetPath, config);
          break;
        case PresetType.cleanLite:
          await CleanLitePreset.synthesize(targetPath, config);
          break;
        default:
          await SaasPreset.synthesize(targetPath, config);
          break;
      }
      onLog('✅ Full architectural preset with auth guards applied.');

      onLog('🎉 Step 5/5: FLRD scaffolding complete! Opening project...');
      return true;
    } catch (e) {
      onLog('❌ Unexpected error: $e');
      return false;
    }
  }
}
